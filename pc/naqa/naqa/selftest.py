"""
فحص الأداة على جهاز البناء (بدون واجهة):
  ١) التحويل الطيفي ذهابًا وإيابًا يعيد الإشارة كما هي
  ٢) الفصل على قطع بقناع «هوية» يعيد المقطع كما هو (لا تشويه عند حدود القطع)
  ٣) مقطع ١٢ دقيقة على كتل: الناتج مطابق، والإيقاف ثم الإكمال يعطي نفس الناتج بالضبط
  ٤) فيديو: الصورة كما هي، والصوت يبدأ من موضعه الأصلي (مزامنة)
  ٥) (--model) جودة الفصل الحقيقية على خليط كلام + موسيقى: SDR ونسبة البقايا، وسرعة الجزء
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np

from . import dsp, jobs, media, model
from .dsp import SR

FAIL = []
LOG = os.environ.get('NAQA_TEST_LOG')


def say(*a):
    line = ' '.join(str(x) for x in a)
    print(line, flush=True)
    if LOG:
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(line + '\n')


def check(name, ok, detail=''):
    say(f'NAQA TEST {"PASS" if ok else "FAIL"} {name} {detail}')
    if not ok:
        FAIL.append(name)


def write_wav(path, l, r):
    inter = np.empty(2 * len(l), np.float32)
    inter[0::2], inter[1::2] = l, r
    raw = path + '.raw'
    inter.tofile(raw)
    subprocess.run([media.tool('ffmpeg'), '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', raw,
                    '-c:a', 'pcm_f32le', path], check=True)
    os.remove(raw)


def read_all(path):
    r = media.Reader(path)
    r.fill(1 << 40)
    r.close()
    return r.l, r.r


def identity_model(inp):
    m = np.zeros_like(inp)
    m[..., 0] = 1.0
    return m


def music(n, seed=1):
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    beat = SR // 2
    chords = [(220, 277.2, 329.6), (196, 246.9, 293.7), (174.6, 220, 261.6), (196, 246.9, 311.1)]
    for i in range(0, n, beat * 4):                                   # أوتار
        f = chords[(i // (beat * 4)) % 4]
        seg = slice(i, min(n, i + beat * 4))
        tt = t[seg] - t[i]
        env = np.exp(-tt * 0.9)
        out[seg] += 0.12 * env * sum(np.sin(2 * np.pi * fr * tt) + 0.3 * np.sin(4 * np.pi * fr * tt) for fr in f)
    for i in range(0, n, beat):                                       # طبل + صنج + باص
        tt = np.arange(min(beat, n - i)) / SR
        out[i:i + len(tt)] += 0.5 * np.sin(2 * np.pi * (55 + 60 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 9)
        h = rng.standard_normal(len(tt)) * np.exp(-tt * 60) * 0.06
        out[i:i + len(tt)] += np.diff(np.concatenate([[0], h]))
        out[i:i + len(tt)] += 0.15 * np.sin(2 * np.pi * 82.4 * tt) * np.exp(-tt * 3)
    return out.astype(np.float32)


def speech(n, tmp):
    """كلام حقيقي من محرّك ويندوز للنطق (SAPI)، يتكرر حتى الطول المطلوب"""
    if os.name != 'nt':
        return None
    wav = os.path.join(tmp, 'tts.wav')
    text = ('Welcome to the separation quality test. The quick brown fox jumps over the lazy dog. '
            'Every sentence here is spoken clearly so the model can keep the human voice and remove the music. '
            'We measure how much of the voice stays and how much of the music leaks through.')
    ps = ("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
          f"$s.Rate = 0; $s.SetOutputToWaveFile('{wav}'); $s.Speak('{text}'); $s.Dispose()")
    try:
        subprocess.run(['powershell', '-NoProfile', '-Command', ps], check=True, timeout=120)
        l, _ = read_all(wav)
    except Exception as e:  # noqa: BLE001
        say('NAQA TEST note: no TTS', e)
        return None
    reps = int(np.ceil(n / len(l)))
    v = np.tile(l, reps)[:n] * 0.9
    return v.astype(np.float32)


def sdr(ref, est):
    return 10 * np.log10(np.sum(ref ** 2) / max(1e-12, np.sum((ref - est) ** 2)))


def main(argv) -> int:
    tmp = tempfile.mkdtemp(prefix='naqa-test-')
    os.environ['LOCALAPPDATA'] = os.path.join(tmp, 'appdata')
    pool = ThreadPoolExecutor(2)
    rng = np.random.default_rng(0)
    try:
        # ١) التحويل الطيفي
        x = (rng.standard_normal(dsp.CHUNK) * 0.1).astype(np.float32)
        y = dsp.istft(dsp.stft(x))
        check('stft-roundtrip', np.abs(y - x).max() < 1e-4, f'max={np.abs(y - x).max():.2e}')

        # ٢) القطع بقناع الهوية (الحد ~٤٩ ديسيبل لأن خانة التردد صفر تُصفّر كما في النموذج الأصلي)
        n = SR * 50 + 1234
        t = np.arange(n) / SR
        l = (0.3 * np.sin(2 * np.pi * 440 * t) + 0.05 * rng.standard_normal(n)).astype(np.float32)
        r = (0.3 * np.sin(2 * np.pi * 523 * t) + 0.05 * rng.standard_normal(n)).astype(np.float32)
        l -= l.mean(); r -= r.mean()
        ol, orr, c = dsp.separate(l, r, identity_model, pool=pool)
        check('chunks-identity', sdr(l, ol) > 45 and sdr(r, orr) > 45, f'sdr={sdr(l, ol):.1f}/{sdr(r, orr):.1f} chunks={c}')

        # ٣) ١٢ دقيقة على كتل + الإيقاف والإكمال
        n = SR * 60 * 12 + 777
        t = np.arange(n) / SR
        l = (0.2 * np.sin(2 * np.pi * 330 * t) * (1 + 0.5 * np.sin(2 * np.pi * 0.1 * t))).astype(np.float32)
        r = (0.2 * np.sin(2 * np.pi * 220 * t + 1)).astype(np.float32)
        src = os.path.join(tmp, 'long.wav')
        write_wav(src, l, r)
        ident = lambda a, b, p: (a.copy(), b.copy())  # noqa: E731
        res = jobs.run(src, 'vocals', ident, fmt='wav')
        gl, gr = read_all(res['out'])
        ok = len(gl) == n and np.abs(gl - l).max() < 1e-5 and np.abs(gr - r).max() < 1e-5
        check('blocks-identity', ok, f'len={len(gl)}/{n} err={np.abs(gl[:n] - l[:len(gl)]).max():.2e}')
        res_m = jobs.run(src, 'music', ident, fmt='wav')
        ml, _ = read_all(res_m['out'])
        check('blocks-music-is-rest', np.abs(ml).max() < 1e-5, f'max={np.abs(ml).max():.2e}')
        os.remove(res['out']); os.remove(res_m['out'])

        stop = {'n': 0}

        def cancel_after_two():
            return stop['n'] >= 2

        def counting(a, b, p):
            stop['n'] += 1
            return a.copy(), b.copy()
        try:
            jobs.run(src, 'vocals', counting, fmt='wav', cancelled=cancel_after_two)
            check('resume-interrupt', False, 'did not stop')
        except InterruptedError:
            pend = jobs.pending(src, 'vocals')
            check('resume-interrupt', pend is not None and 0.2 < pend < 0.9, f'pending={pend}')
        res2 = jobs.run(src, 'vocals', ident, fmt='wav')
        rl, rr = read_all(res2['out'])
        check('resume-identical', res2['resumed'] and len(rl) == n and np.abs(rl - l).max() < 1e-5 and np.abs(rr - r).max() < 1e-5,
              f'resumed={res2["resumed"]} len={len(rl)}')

        # ٤) فيديو صوته يبدأ بعد الصورة بـ ٠٫٧٥ ثانية: الصورة تُنسخ كما هي والصوت يبقى في موضعه (ثلاث حاويات)
        for ext, secs in (('.mp4', 95), ('.mkv', 20), ('.mov', 20)):
            vid = make_clip(tmp, 'clip' + ext, secs)
            info0 = media.probe(vid)
            rv = jobs.run(vid, 'vocals', ident)
            info1 = media.probe(rv['out'])
            on0, on1 = onset(vid), onset(rv['out'])
            check('video-sync' + ext, info1['video'] and abs(info1['duration'] - info0['duration']) < 0.2
                  and abs(on1 - on0) < 0.01 and on0 > 0.7,
                  f'dur {info0["duration"]:.2f}/{info1["duration"]:.2f} first sound {on0:.4f}/{on1:.4f} s '
                  f'codec {info1["video_codec"]} out={os.path.basename(rv["out"])}')

        # ٤ب) فيديو أطول من كتلة: يُوقف ثم يكمل → الناتج مطابق لفصل متواصل، والمزامنة سليمة
        vid = make_clip(tmp, 'long.mp4', 400)
        full = jobs.run(vid, 'vocals', ident)
        a_full = decode(full['out'])
        os.replace(full['out'], os.path.join(tmp, 'long-full.mp4'))
        stop['n'] = 0
        try:
            jobs.run(vid, 'vocals', counting, cancelled=cancel_after_two)
            check('video-resume', False, 'did not stop')
        except InterruptedError:
            res = jobs.run(vid, 'vocals', ident)
            a_res = decode(res['out'])
            on0, on1 = onset(vid), onset(res['out'])
            same = a_full.shape == a_res.shape and float(np.abs(a_full - a_res).max()) < 1e-6
            check('video-resume', res['resumed'] and same and abs(on1 - on0) < 0.01,
                  f'resumed={res["resumed"]} identical={same} first sound {on0:.4f}/{on1:.4f} s')

        # ٥) جودة النموذج الحقيقي
        if '--model' in argv:
            quality(tmp, pool)
    finally:
        pool.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)
    say('NAQA TEST RESULT', 'FAIL ' + ','.join(FAIL) if FAIL else 'ALL PASS')
    return 1 if FAIL else 0


def make_clip(tmp, name, secs) -> str:
    """فيديو اختبار صوته (نغمة) يبدأ بعد الصورة بـ ٠٫٧٥ ثانية"""
    vid = os.path.join(tmp, name)
    subprocess.run([media.tool('ffmpeg'), '-v', 'error', '-y',
                    '-f', 'lavfi', '-i', f'testsrc2=size=320x240:rate=25:duration={secs}',
                    '-itsoffset', '0.75', '-f', 'lavfi', '-i', f'sine=frequency=600:sample_rate=44100:duration={secs - 1}',
                    '-map', '0:v', '-map', '1:a', '-c:v', 'mpeg4', '-q:v', '5', '-c:a', 'aac', '-b:a', '128k', vid], check=True)
    return vid


def decode(path) -> np.ndarray:
    raw = subprocess.run([media.tool('ffmpeg'), '-v', 'error', '-i', path, '-map', '0:a:0', '-ac', '2', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def onset(path) -> float:
    """أول صوت مسموع بالثواني من بداية الملف (الصوت موضوع على خط زمن الملف نفسه)"""
    raw = subprocess.run([media.tool('ffmpeg'), '-v', 'error', '-i', path, '-af', 'aresample=async=1:first_pts=0',
                          '-ac', '1', '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    return float(np.argmax(np.abs(x) > 0.05)) / SR


def quality(tmp, pool):
    t0 = time.time()
    if not model.is_ready():
        model.download(lambda *a: None, lambda: False)
    say('NAQA TEST model download+verify seconds', round(time.time() - t0, 1))
    runner = model.Runner()
    backend = runner.prepare(force_benchmark=True)
    say('NAQA TEST backend', backend, runner.summary())
    n = SR * 48
    v = speech(n, tmp)
    if v is None:
        check('model-quality', False, 'no speech source')
        return
    m = music(n)
    vl, vr = v, v * 0.95
    ml, mr = m, np.roll(m, 300) * 0.9
    mix_l, mix_r = vl + ml, vr + mr
    t = time.time()
    el, er, chunks = dsp.separate(mix_l, mix_r, runner, pool=pool)
    secs = time.time() - t
    sdr_v = (sdr(vl, el) + sdr(vr, er)) / 2
    sdr_m = (sdr(ml, mix_l - el) + sdr(mr, mix_r - er)) / 2
    keep_v = 100 * float(np.dot(el, vl) / np.dot(vl, vl))
    leak_m = 100 * float(np.sum((el - vl) ** 2) / np.sum(vl ** 2))
    say(f'NAQA TEST quality sdrV={sdr_v:.2f} sdrM={sdr_m:.2f} keepV={keep_v:.1f}% residual={leak_m:.2f}% '
          f'chunks={chunks} sec/chunk={secs / chunks:.2f} model sec/chunk={runner.seconds / max(1, runner.calls):.2f}')
    check('model-quality', sdr_v > 13 and sdr_m > 20 and keep_v > 90, f'sdrV={sdr_v:.2f} sdrM={sdr_m:.2f}')


if __name__ == '__main__':
    sys.exit(main(sys.argv))
