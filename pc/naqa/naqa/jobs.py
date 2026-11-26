"""
فصل المقاطع الطويلة (حتى ٤ ساعات) — نفس طريقة رفيقي (SepLong.swift):
  • كتل ٥ دقائق، مع ٨ ثوانٍ سياق من الجانبين، وتلاشٍ متقاطع نصف ثانية بين الكتل
  • قراءة بالتتابع دون تحميل الملف كله، والناتج الخام يُكتب أولًا بأول
  • حفظ التقدّم بعد كل كتلة: إن انقطع (إغلاق، انطفاء، إيقاف) يكمل من حيث توقف
  • الترميز النهائي مرة واحدة، والفيديو يحتفظ بصورته كما هي ومزامنته مع الصوت
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass

import numpy as np

from . import dsp, media, paths
from .dsp import SR

BLOCK = 5 * 60 * SR
CTX = 8 * SR
XFADE = SR // 2
MAX_SECONDS = 4 * 3600
STALE_DAYS = 7

SUFFIX = {'vocals': 'بدون موسيقى', 'music': 'بدون صوت بشري'}


def jobs_dir() -> str:
    return paths.data_dir('jobs')


def key(src: str, keep: str) -> str:
    st = os.stat(src)
    s = f'{os.path.abspath(src).lower()}|{st.st_size}|{st.st_mtime_ns}|{keep}|bsroformer-fp32'
    return hashlib.sha256(s.encode('utf-8')).hexdigest()[:24]


@dataclass
class State:
    keep: str
    src: str
    written: int = 0
    next_block: int = 0
    audio_start: float = 0.0
    est_total: int = 0


def _load(jd: str):
    try:
        with open(os.path.join(jd, 'state.json'), encoding='utf-8') as f:
            return State(**json.load(f))
    except Exception:
        return None


def _save(jd: str, st: State) -> None:
    p = os.path.join(jd, 'state.json')
    with open(p + '.tmp', 'w', encoding='utf-8') as f:
        json.dump(asdict(st), f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(p + '.tmp', p)


def pending(src: str, keep: str):
    """نسبة فصل غير مكتمل لهذا الملف (أو None)"""
    try:
        st = _load(os.path.join(jobs_dir(), key(src, keep)))
    except OSError:
        return None
    if st and st.written > 0 and st.est_total > 0:
        return min(0.99, st.written / st.est_total)
    return None


def discard(src: str, keep: str) -> None:
    try:
        shutil.rmtree(os.path.join(jobs_dir(), key(src, keep)), ignore_errors=True)
    except OSError:
        pass


def purge_stale(now: float | None = None) -> int:
    """بقايا فصل لم يُكمل منذ ٧ أيام، أو حُذف ملفه الأصلي"""
    now = now or time.time()
    n = 0
    for name in os.listdir(jobs_dir()):
        d = os.path.join(jobs_dir(), name)
        if not os.path.isdir(d):
            continue
        st = _load(d)
        sp = os.path.join(d, 'state.json')
        last = os.path.getmtime(sp) if os.path.isfile(sp) else os.path.getmtime(d)
        if now - last > STALE_DAYS * 86400 or (st and not os.path.isfile(st.src)):
            shutil.rmtree(d, ignore_errors=True)
            n += 1
    return n


def _free_bytes(path: str) -> int:
    try:
        return shutil.disk_usage(path).free
    except OSError:
        return 1 << 62


def _size_text(b: float) -> str:
    return f'{b / 1e9:.1f} جيجا' if b >= 1e9 else f'{b / 1e6:.0f} ميجا'


def run(src: str, keep: str, separate, fmt: str = 'm4a', progress=None, cancelled=None, status=None) -> dict:
    """
    separate(l, r, progress) → (vl, vr): الصوت البشري للنافذة.
    keep: 'vocals' (إزالة الموسيقى) أو 'music' (إزالة الصوت البشري).
    يرجع: {'out', 'resumed', 'seconds', 'duration'}
    """
    t0 = time.time()
    info = media.probe(src)
    dur = info['duration']
    if not dur or dur <= 0:
        raise media.MediaError('تعذّرت قراءة مدة الملف.')
    if dur > MAX_SECONDS + 1:
        raise media.MediaError('المقطع أطول من ٤ ساعات.')
    est = int(dur * SR)
    if est < 4096:
        raise media.MediaError('المقطع قصير جدًا.')

    k = key(src, keep)
    jd = os.path.join(jobs_dir(), k)
    os.makedirs(jd, exist_ok=True)
    st = _load(jd)
    resumed = bool(st and st.written > 0 and st.keep == keep)
    if not resumed:
        st = State(keep=keep, src=os.path.abspath(src), est_total=est, audio_start=info['audio_start'])
        for f in os.listdir(jd):
            os.remove(os.path.join(jd, f))
        _save(jd, st)

    # المساحة: الخام (٨ بايت لكل عيّنة ستيريو) + الناتج
    need = max(0, est - st.written) * 8 + int(dur * 48_000) + 200_000_000
    if _free_bytes(jd) < need:
        raise media.MediaError(f'المساحة لا تكفي للفصل: يحتاج تقريبًا {_size_text(need)}، والمتاح {_size_text(_free_bytes(jd))}.')
    out_dir = os.path.dirname(os.path.abspath(src))
    if _free_bytes(out_dir) < int(dur * 48_000) + 50_000_000 + (info['size'] if info['video'] else 0):
        raise media.MediaError('المساحة في مجلد الملف لا تكفي لحفظ الناتج.')

    raw = os.path.join(jd, 'main.raw')
    if not os.path.isfile(raw):
        open(raw, 'wb').close()
    with open(raw, 'r+b') as h:
        h.truncate(st.written * 8)          # قد يكون الانقطاع في منتصف كتابة
    tail = None
    tp = os.path.join(jd, f'tail-{st.next_block}.npy')
    if resumed and os.path.isfile(tp):
        t = np.load(tp)
        if t.shape == (2, XFADE):
            tail = (t[0], t[1])

    b = st.next_block
    reader = media.Reader(src, max(0, b * BLOCK - CTX), timeline=info['video'])
    blocks_est = max(1, -(-est // BLOCK))
    try:
        with open(raw, 'ab') as hout:
            while True:
                if cancelled and cancelled():
                    raise InterruptedError
                cs = b * BLOCK
                ws = max(0, cs - CTX)
                reader.fill(cs + BLOCK + CTX)
                reader.drop(ws)
                ce = min(cs + BLOCK, reader.end)
                if ce <= cs:
                    break
                we = min(cs + BLOCK + CTX, reader.end)
                wl = reader.l[ws - reader.base:we - reader.base]
                wr = reader.r[ws - reader.base:we - reader.base]
                total = max(blocks_est, b + 1)
                bi = b
                if status:
                    status(bi, total)
                vl, vr = separate(wl, wr, lambda p: progress and progress((bi + p) / total))
                if cancelled and cancelled():
                    raise InterruptedError
                assert vl.shape == wl.shape and vr.shape == wr.shape

                off, ln = cs - ws, ce - cs
                cl = vl[off:off + ln].copy()
                cr = vr[off:off + ln].copy()
                if tail is not None:
                    m = min(XFADE, ln)
                    w = (np.arange(1, m + 1, dtype=np.float32) / np.float32(XFADE + 1))
                    cl[:m] = tail[0][:m] * (1 - w) + cl[:m] * w
                    cr[:m] = tail[1][:m] * (1 - w) + cr[:m] * w
                tail = (vl[off + ln:off + ln + XFADE].copy(), vr[off + ln:off + ln + XFADE].copy()) \
                    if off + ln + XFADE <= vl.shape[0] else None

                # الصوت البشري، أو الموسيقى = الأصل − الصوت البشري
                if keep == 'vocals':
                    ol, orr = cl, cr
                else:
                    ol, orr = wl[off:off + ln] - cl, wr[off:off + ln] - cr
                inter = np.empty(2 * ln, np.float32)
                inter[0::2] = ol
                inter[1::2] = orr
                hout.write(inter.tobytes())
                hout.flush()
                os.fsync(hout.fileno())

                st.written += ln
                st.next_block = b + 1
                if tail is not None:
                    np.save(os.path.join(jd, f'tail-{b + 1}.npy'), np.stack([tail[0], tail[1]]))
                _save(jd, st)
                old = os.path.join(jd, f'tail-{b}.npy')
                if os.path.isfile(old):
                    os.remove(old)
                b += 1
                if reader.eof and ce >= reader.end:
                    break
    finally:
        reader.close()
    if st.written <= 0:
        raise media.MediaError('تعذّرت قراءة الصوت.')

    # الترميز النهائي (مرة واحدة)
    if progress:
        progress(0.995)
    if status:
        status(-1, 0)
    ext = os.path.splitext(src)[1].lower()
    if info['video']:
        out_ext = ext if ext in ('.mp4', '.m4v', '.mov', '.mkv') else '.mp4'
        out = media.output_path(src, SUFFIX[keep], out_ext)
        try:
            media.mux_video(src, raw, out, cancelled)
        except media.MediaError:
            if os.path.isfile(out):
                os.remove(out)
            out = media.output_path(src, SUFFIX[keep], '.mkv')   # حاوية تقبل أي صيغة صورة
            media.mux_video(src, raw, out, cancelled)
    else:
        out = media.output_path(src, SUFFIX[keep], '.' + fmt)
        media.encode_audio(raw, out, fmt, cancelled)
    shutil.rmtree(jd, ignore_errors=True)
    return {'out': out, 'resumed': resumed, 'seconds': time.time() - t0, 'duration': dur}


def make_separator(runner, pool: ThreadPoolExecutor, cancelled, counter: dict):
    """دالة الفصل لنافذة صوت: قطع ٨ ثوانٍ بتداخل الحواف على النموذج"""
    def separate(l, r, p):
        vl, vr, n = dsp.separate(l, r, runner, progress=p, cancelled=cancelled, pool=pool,
                                 workers=getattr(runner, 'workers', 1))
        counter['chunks'] = counter.get('chunks', 0) + n
        return vl, vr
    return separate
