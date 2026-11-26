"""
تحويل الطيف وفصل المقطع على قطع — نفس خوارزمية رفيقي على الجوال حرفيًا (Roformer.swift)،
ومطابق لـ torch.stft / torch.istft في النموذج الأصلي:
  n_fft 2048، hop 441، نافذة Hann دورية، حشو انعكاسي في الطرفين، DC = 0 عند التركيب.
القطعة ٨ ثوانٍ (801 إطار)، والقطع تتداخل عند الحواف فقط بتلاشٍ خطي بطول عُشر القطعة.
"""
from __future__ import annotations

import numpy as np

SR = 44100
NFFT = 2048
HOP = 441
BINS = NFFT // 2 + 1          # 1025
FRAMES = 801
CHUNK = (FRAMES - 1) * HOP    # 352800 = ٨ ثوانٍ
FADE = CHUNK // 10            # تداخل الحواف

WIN = (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(NFFT) / NFFT)).astype(np.float32)  # Hann دورية

# مجموع مربعات النافذة على طول القطعة (قسمة iSTFT)، يُحسب مرة واحدة
_OLA_LEN = NFFT + HOP * (FRAMES - 1)
_ENV = np.zeros(_OLA_LEN, np.float64)
for _t in range(FRAMES):
    _ENV[_t * HOP:_t * HOP + NFFT] += WIN.astype(np.float64) ** 2
_ENV_TRIM = _ENV[NFFT // 2:NFFT // 2 + CHUNK]
_ENV_OK = _ENV_TRIM > 1e-11
_ENV_INV = np.where(_ENV_OK, 1.0 / np.where(_ENV_OK, _ENV_TRIM, 1.0), 0.0).astype(np.float32)


def stft(x: np.ndarray) -> np.ndarray:
    """x: [CHUNK] → طيف مركّب [FRAMES, BINS] (complex64)"""
    p = np.pad(x.astype(np.float32, copy=False), (NFFT // 2, NFFT // 2), mode='reflect')
    frames = np.lib.stride_tricks.sliding_window_view(p, NFFT)[::HOP]
    assert frames.shape[0] == FRAMES
    return np.fft.rfft(frames * WIN, axis=-1).astype(np.complex64, copy=False)


def istft(spec: np.ndarray) -> np.ndarray:
    """spec: [FRAMES, BINS] → [CHUNK] (float32) مثل torch.istft(center=True, length=CHUNK)"""
    frames = np.fft.irfft(spec, n=NFFT, axis=-1).astype(np.float32, copy=False) * WIN
    ola = np.zeros(_OLA_LEN, np.float32)
    for t in range(FRAMES):
        ola[t * HOP:t * HOP + NFFT] += frames[t]
    return ola[NFFT // 2:NFFT // 2 + CHUNK] * _ENV_INV


def model_input(left: np.ndarray, right: np.ndarray):
    """قطعة ستيريو → (دخل النموذج [1, 2050, 801, 2]، طيف القناتين)"""
    xl, xr = stft(left), stft(right)
    inp = np.empty((1, 2 * BINS, FRAMES, 2), np.float32)
    for s, x in ((0, xl), (1, xr)):
        inp[0, s::2, :, 0] = x.real.T
        inp[0, s::2, :, 1] = x.imag.T
    return inp, (xl, xr)


def apply_mask(spec, mask: np.ndarray):
    """Y = X × القناع (DC صفر كما في الأصل) ثم iSTFT → (يسار، يمين)"""
    out = []
    for s, x in enumerate(spec):
        m = mask[0, s::2, :, 0].T + 1j * mask[0, s::2, :, 1].T     # [FRAMES, BINS]
        y = (x * m).astype(np.complex64, copy=False)
        y[:, 0] = 0
        out.append(istft(y))
    return out[0], out[1]


def _chunk_from(src_l, src_r, start: int, length: int, off: int):
    """القطعة من المقطع المحشو بالانعكاس (بلا نسخ المقطع)، والأخيرة تُكمل بالانعكاس أو بالأصفار"""
    n = src_l.shape[0]
    idx = np.arange(start, start + length) - off
    idx = np.abs(idx)
    idx = np.where(idx >= n, 2 * (n - 1) - idx, idx)
    ok = (idx >= 0) & (idx < n)
    pl = np.zeros(CHUNK, np.float32)
    pr = np.zeros(CHUNK, np.float32)
    pl[:length][ok] = src_l[idx[ok]]
    pr[:length][ok] = src_r[idx[ok]]
    if length < CHUNK and length > CHUNK // 2 + 1:
        k = np.arange(length, CHUNK)
        j = 2 * (length - 1) - k
        good = j >= 0
        pl[k[good]] = pl[j[good]]
        pr[k[good]] = pr[j[good]]
    return pl, pr


def separate(left: np.ndarray, right: np.ndarray, run_model, progress=None, cancelled=None, pool=None, workers=1):
    """
    الصوت البشري لمقطع كامل (قناتان float32 بطول n).
    run_model(inp) → mask. pool: ThreadPoolExecutor يجهّز القطع ويشغّلها.
    workers: عدد القطع التي تعمل في الوقت نفسه (أكثر من ١ حين يعمل المعالج وكرت الشاشة معًا).
    الجمع دائمًا بترتيب القطع نفسه، فالناتج واحد مهما كان عدد العمّال.
    يرجع (يسار، يمين، عدد القطع).
    """
    n = left.shape[0]
    step = CHUNK - FADE
    border = CHUNK - step
    padded = n > 2 * border
    off = border if padded else 0
    total_len = n + 2 * off
    win = np.ones(CHUNK, np.float32)
    ramp = np.arange(FADE, dtype=np.float32) / np.float32(FADE - 1)
    win[:FADE] = ramp
    win[CHUNK - FADE:] = ramp[::-1]
    acc_l = np.zeros(total_len, np.float32)
    acc_r = np.zeros(total_len, np.float32)
    cnt = np.zeros(total_len, np.float32)
    starts = list(range(0, total_len, step))

    def prepare(ci):
        s0 = starts[ci]
        length = min(CHUNK, total_len - s0)
        pl, pr = _chunk_from(left, right, s0, length, off)
        inp, spec = model_input(pl, pr)
        return inp, spec, length

    def add(ci, yl, yr, length):
        s0 = starts[ci]
        w = win.copy()
        if s0 == 0:
            w[:FADE] = 1
        if s0 + CHUNK >= total_len:
            w[CHUNK - FADE:] = 1
        acc_l[s0:s0 + length] += yl[:length] * w[:length]
        acc_r[s0:s0 + length] += yr[:length] * w[:length]
        cnt[s0:s0 + length] += w[:length]
        if progress:
            progress((ci + 1) / len(starts))

    if pool and workers > 1:
        def whole(ci):
            if cancelled and cancelled():
                raise InterruptedError
            inp, spec, length = prepare(ci)
            yl, yr = apply_mask(spec, run_model(inp))
            return yl, yr, length

        flight = {}
        nxt = 0
        try:
            for ci in range(len(starts)):
                while nxt < len(starts) and nxt < ci + workers:
                    flight[nxt] = pool.submit(whole, nxt)
                    nxt += 1
                if cancelled and cancelled():
                    raise InterruptedError
                yl, yr, length = flight.pop(ci).result()
                add(ci, yl, yr, length)
        finally:
            for f in flight.values():
                f.cancel()
            for f in flight.values():
                try:
                    f.result()
                except BaseException:  # noqa: BLE001
                    pass
    else:
        nxt = pool.submit(prepare, 0) if pool else None
        for ci in range(len(starts)):
            if cancelled and cancelled():
                raise InterruptedError
            inp, spec, length = nxt.result() if pool else prepare(ci)
            if pool and ci + 1 < len(starts):
                nxt = pool.submit(prepare, ci + 1)
            yl, yr = apply_mask(spec, run_model(inp))
            add(ci, yl, yr, length)
    c = cnt[off:off + n]
    ok = c > 1e-6
    out_l = np.zeros(n, np.float32)
    out_r = np.zeros(n, np.float32)
    out_l[ok] = acc_l[off:off + n][ok] / c[ok]
    out_r[ok] = acc_r[off:off + n][ok] / c[ok]
    return out_l, out_r, len(starts)
