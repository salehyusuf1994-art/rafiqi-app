"""
مقارنة فصل مقطع واحد بالنموذج الأصلي بالدقة الكاملة (fp32):
  ١× (مرة واحدة: طريقة رفيقي/نقاء الحالية)، ٢× (أول نسخة)، ٤× (طريقة أصحاب النموذج: num_overlap=4)،
ومقارنة ناتج الجوال (نصف الدقة على كرت الشاشة) بنتيجة ١× رقمًا برقم.
الاستخدام: compare_overlap.py <orig.mp4> <phone.mp4> <model.onnx> <outdir>
السجل لا يطبع أي شيء عن محتوى المقطع (أرقام وأوقات فقط)؛ الملفات تُشفّر قبل الرفع (ci/seal.sh).
"""
import json
import os
import subprocess
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from naqa import dsp  # noqa: E402

SR = dsp.SR
C, F = dsp.CHUNK, dsp.FADE


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-map', '0:a:0', '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).T.copy()


def demix(l, r, run, k):
    """الطريقة الأصلية (demix في Music-Source-Separation-Training): خطوة = القطعة/k، نافذة بحواف متلاشية"""
    step = C // k
    border = C - step
    n = len(l)
    off = border if n > 2 * border else 0
    pl = np.pad(l, (off, off), mode='reflect') if off else l
    pr = np.pad(r, (off, off), mode='reflect') if off else r
    L = len(pl)
    win = np.ones(C, np.float32)
    ramp = np.linspace(0, 1, F, dtype=np.float32)
    win[:F] = ramp
    win[-F:] = ramp[::-1]
    al = np.zeros(L, np.float32)
    ar = np.zeros(L, np.float32)
    cnt = np.zeros(L, np.float32)
    i = 0
    chunks = 0
    while i < L:
        a, b = pl[i:i + C], pr[i:i + C]
        ln = len(a)
        if ln < C:
            mode = 'reflect' if ln > C // 2 + 1 else 'constant'
            a = np.pad(a, (0, C - ln), mode=mode)
            b = np.pad(b, (0, C - ln), mode=mode)
        inp, spec = dsp.model_input(a.astype(np.float32), b.astype(np.float32))
        yl, yr = dsp.apply_mask(spec, run(inp))
        chunks += 1
        w = win.copy()
        if i == 0:
            w[:F] = 1
        if i + step >= L:
            w[-F:] = 1
        al[i:i + ln] += yl[:ln] * w[:ln]
        ar[i:i + ln] += yr[:ln] * w[:ln]
        cnt[i:i + ln] += w[:ln]
        i += step
    c = np.maximum(cnt, 1e-8)
    return np.stack([(al / c)[off:off + n], (ar / c)[off:off + n]]), chunks


def snr(ref, x):
    return float(10 * np.log10(np.sum(ref ** 2) / (np.sum((ref - x) ** 2) + 1e-20) + 1e-20))


def align(ref, x, span=4096):
    a = ref.mean(0)
    b = x.mean(0)
    m = min(len(a), len(b))
    nfft = 1 << int(np.ceil(np.log2(2 * m)))
    cc = np.fft.irfft(np.fft.rfft(a[:m], nfft) * np.conj(np.fft.rfft(b[:m], nfft)), nfft)
    lag = int(np.argmax(np.r_[cc[-span:], cc[:span + 1]])) - span
    return lag


def shift(x, lag, n):
    out = np.zeros((2, n), np.float32)
    if lag >= 0:
        seg = x[:, :max(0, n - lag)]
        out[:, lag:lag + seg.shape[1]] = seg
    else:
        seg = x[:, -lag:-lag + n]
        out[:, :seg.shape[1]] = seg
    return out


def bands(mix, voc):
    res = {}
    for lo, hi in ((20, 100), (100, 200), (200, 400), (400, 1000), (1000, 2000), (2000, 3500), (3500, 8000), (8000, 20000)):
        X = np.abs(np.fft.rfft(mix.mean(0))) ** 2
        V = np.abs(np.fft.rfft(voc.mean(0))) ** 2
        f = np.fft.rfftfreq(mix.shape[1], 1 / SR)
        sel = (f >= lo) & (f < hi)
        res[f'{lo}-{hi}'] = round(float(100 * V[sel].sum() / max(X[sel].sum(), 1e-20)), 1)
    return res


def aac_roundtrip(x, tmp):
    raw = os.path.join(tmp, 'rt.f32')
    m4a = os.path.join(tmp, 'rt.m4a')
    x.T.astype(np.float32).tofile(raw)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', raw, '-c:a', 'aac', '-b:a', '192k', m4a], check=True)
    y = decode(m4a)
    lag = align(x, y)
    return shift(y, lag, x.shape[1])


def mux(orig, x, out, tmp):
    raw = os.path.join(tmp, 'mx.f32')
    x.T.astype(np.float32).tofile(raw)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', orig, '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', raw,
                    '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', out], check=True)


def main():
    orig, phone, model, outdir = sys.argv[1:5]
    os.makedirs(outdir, exist_ok=True)
    tmp = os.path.join(outdir, '.tmp')
    os.makedirs(tmp, exist_ok=True)
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    so.add_session_config_entry('session.set_denormal_as_zero', '1')
    so.log_severity_level = 3
    sess = ort.InferenceSession(model, so, providers=['CPUExecutionProvider'])
    stat = {'chunk_seconds': []}

    def run(inp):
        t = time.time()
        m = sess.run(['mask'], {'spec': inp})[0]
        stat['chunk_seconds'].append(round(time.time() - t, 1))
        print(f'chunk {len(stat["chunk_seconds"])} {stat["chunk_seconds"][-1]}s', flush=True)
        return m

    mix = decode(orig)
    ph = decode(phone)
    l, r = mix[0].copy(), mix[1].copy()
    n = mix.shape[1]
    v1l, v1r, c1 = dsp.separate(l, r, run)
    v1 = np.stack([v1l, v1r])
    v2, c2 = demix(l, r, run, 2)
    v4, c4 = demix(l, r, run, 4)
    stat['chunks'] = {'x1': c1, 'x2': c2, 'x4': c4}

    # ناتج الجوال مقابل ١× بالدقة الكاملة (نفس الطريقة) — والأرضية: كم يغيّر ترميز AAC ‏192k وحده
    lag = align(v1, ph)
    php = shift(ph, lag, n)
    m = min(n, ph.shape[1] + max(0, lag)) - 2048
    v1aac = aac_roundtrip(v1, tmp)
    stat['phone_lag_samples'] = lag
    stat['snr_phone_vs_x1_dB'] = round(snr(v1[:, :m], php[:, :m]), 2)
    stat['snr_aac_floor_dB'] = round(snr(v1[:, :m], v1aac[:, :m]), 2)
    stat['snr_phone_vs_x1_per_second'] = [round(snr(v1[:, s:s + SR], php[:, s:s + SR]), 1) for s in range(0, m - SR + 1, SR)]
    stat['snr_x4_vs_x1_dB'] = round(snr(v4, v1), 2)
    stat['snr_x4_vs_x2_dB'] = round(snr(v4, v2), 2)
    stat['snr_x4_vs_x1_per_second'] = [round(snr(v4[:, s:s + SR], v1[:, s:s + SR]), 1) for s in range(0, n - SR + 1, SR)]
    stat['kept_as_voice_percent_by_band'] = {'phone': bands(mix[:, :m], php[:, :m]), 'x1': bands(mix, v1), 'x2': bands(mix, v2), 'x4': bands(mix, v4)}
    stat['removed_dB'] = {k: round(float(10 * np.log10(np.mean((mix[:, :m] - v[:, :m]) ** 2) / np.mean(mix[:, :m] ** 2))), 2)
                          for k, v in (('phone', php), ('x1', v1), ('x2', v2), ('x4', v4))}

    mux(orig, v1, os.path.join(outdir, '1 - مرة واحدة (مثل الجوال، دقة كاملة).mp4'), tmp)
    mux(orig, v2, os.path.join(outdir, '2 - مرتين (مثل أول نسخة).mp4'), tmp)
    mux(orig, v4, os.path.join(outdir, '3 - أربع مرات (طريقة أصحاب النموذج).mp4'), tmp)
    for k, v in (('x1', v1), ('x2', v2), ('x4', v4)):
        np.save(os.path.join(tmp, f'{k}.npy'), v)
    json.dump(stat, open(os.path.join(outdir, 'stats.json'), 'w'), ensure_ascii=False, indent=1)
    for f in os.listdir(tmp):
        if f.endswith('.f32') or f.endswith('.m4a'):
            os.remove(os.path.join(tmp, f))
    print('done', sum(stat['chunk_seconds']), 's model time', flush=True)


if __name__ == '__main__':
    main()
