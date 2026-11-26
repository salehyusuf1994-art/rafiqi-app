"""
نموذج الفصل: التنزيل (مرة واحدة، مع التحقق من البصمة)، واختيار الأسرع على هذا الجهاز
(كرت الشاشة عبر DirectML أو المعالج)، والتشغيل بالدقة الكاملة fp32.
"""
from __future__ import annotations

import hashlib
import json
import os
import queue
import ssl
import threading
import time
import urllib.request

import numpy as np

from . import paths
from .dsp import BINS, FRAMES

MODEL_TAG = 'sep-onnx-v1'
MODEL_NAME = 'bsroformer-vocals-fp32.onnx'
MODEL_URL = f'https://github.com/salehyusuf1994-art/rafiqi-app/releases/download/{MODEL_TAG}/{MODEL_NAME}'
# تُعبّأ من files.json الخاص بالإصدار (بصمة SHA-256 وحجم الملف)
MODEL_SHA256 = '64473bc1d1de94725b7cf71da4c5266f4c41d772efc66571ea8205d2bcba183b'
MODEL_SIZE = 644_675_182


def model_path() -> str:
    return os.path.join(paths.data_dir('model'), f'{MODEL_TAG}-{MODEL_NAME}')


def is_ready() -> bool:
    p = model_path()
    return os.path.isfile(p) and (MODEL_SIZE == 0 or os.path.getsize(p) == MODEL_SIZE) and os.path.isfile(p + '.ok')


def _sha256(path: str, progress=None) -> str:
    h = hashlib.sha256()
    total = max(1, os.path.getsize(path))
    done = 0
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(8 << 20), b''):
            h.update(b)
            done += len(b)
            if progress:
                progress(done / total)
    return h.hexdigest()


def download(progress, cancelled) -> None:
    """ينزّل النموذج (يكمل من حيث توقف إن انقطع)، ثم يتحقق من بصمته قبل اعتماده"""
    dst = model_path()
    part = dst + '.part'
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for old in os.listdir(os.path.dirname(dst)):          # نسخ قديمة من النموذج
        full = os.path.join(os.path.dirname(dst), old)
        if old.endswith('.onnx') and full != dst:
            try:
                os.remove(full)
            except OSError:
                pass
    have = os.path.getsize(part) if os.path.isfile(part) else 0
    req = urllib.request.Request(MODEL_URL, headers={'User-Agent': 'Naqa/1.0'})
    if have:
        req.add_header('Range', f'bytes={have}-')
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=60, context=ctx) as r:
        if have and r.status != 206:          # الخادم لا يدعم الإكمال: من البداية
            have = 0
        total = have + int(r.headers.get('Content-Length') or 0)
        if MODEL_SIZE:
            total = MODEL_SIZE
        with open(part, 'ab' if have else 'wb') as f:
            done = have
            last = 0.0
            while True:
                if cancelled():
                    raise InterruptedError
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
                done += len(b)
                now = time.time()
                if now - last > 0.2:
                    last = now
                    progress('download', done / max(1, total), done, total)
    progress('verify', 0.0, 0, 0)
    got = _sha256(part, lambda v: progress('verify', v, 0, 0))
    if got != MODEL_SHA256:
        os.remove(part)
        raise ValueError('بصمة النموذج لا تطابق — أُلغي الملف. أعد التنزيل.')
    os.replace(part, dst)
    with open(dst + '.ok', 'w') as f:
        f.write(got)


def gpu_names() -> list[str]:
    """أسماء كروت الشاشة (للعرض فقط)"""
    if os.name != 'nt':
        return []
    try:
        import subprocess
        out = subprocess.run(
            ['powershell', '-NoProfile', '-Command',
             '(Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join "|"'],
            capture_output=True, text=True, timeout=15, creationflags=0x08000000)
        return [x.strip() for x in out.stdout.split('|') if x.strip()]
    except Exception:
        return []


class Runner:
    """
    يشغّل النموذج على أسرع وسيلة في هذا الجهاز: كرت الشاشة (DirectML: NVIDIA أو AMD أو Intel)،
    أو المعالج، أو الاثنان معًا على قطع مختلفة في الوقت نفسه إن كان ذلك أسرع.
    إن تعذّر كرت الشاشة أثناء العمل يكمل على المعالج بلا توقف.
    """

    def __init__(self):
        self.mode = 'cpu'                   # 'cpu' | 'dml' | 'hybrid'
        self.sessions = {}                  # 'cpu'/'dml' → جلسة
        self.idle = queue.Queue()
        self.stat_lock = threading.Lock()
        self.seconds = 0.0
        self.calls = 0
        self.fallbacks = 0

    @property
    def workers(self) -> int:
        return max(1, len(self.sessions))

    @staticmethod
    def _make(provider: str, threads: int = 0):
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        so.log_severity_level = 3
        so.add_session_config_entry('session.set_denormal_as_zero', '1')   # يمنع بطء الأرقام الصغيرة جدًا، بلا أثر على الناتج
        if threads:
            so.intra_op_num_threads = threads
        if provider == 'dml':
            so.enable_mem_pattern = False                       # شرط DirectML
            so.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
            prov = ['DmlExecutionProvider', 'CPUExecutionProvider']
        else:
            prov = ['CPUExecutionProvider']
        s = ort.InferenceSession(model_path(), so, providers=prov)
        if provider == 'dml' and 'DmlExecutionProvider' not in s.get_providers():
            raise RuntimeError('DirectML unavailable')
        return s

    @staticmethod
    def _cores() -> int:
        n = os.cpu_count() or 4
        return max(2, n // 2)               # الأنوية الفعلية تقريبًا (بلا الأنوية الافتراضية)

    def _use(self, mode: str, made: dict):
        self.mode = mode
        self.sessions = {k: v for k, v in made.items() if k in (('dml', 'cpu') if mode == 'hybrid' else (mode,))}
        self.idle = queue.Queue()
        for k in self.sessions:
            self.idle.put(k)

    def prepare(self, status=None, force_benchmark=False) -> str:
        """يختار الأسرع (يُقاس مرة واحدة على هذا الجهاز ويُحفظ). يرجع الوضع المختار"""
        prefs = paths.load_settings()
        key = MODEL_TAG
        choice = prefs.get('backend', {}).get(key)
        cores = self._cores()
        if choice and not force_benchmark:
            try:
                made = {}
                if choice in ('cpu', 'hybrid'):
                    made['cpu'] = self._make('cpu', cores)
                if choice in ('dml', 'hybrid'):
                    made['dml'] = self._make('dml')
                self._use(choice, made)
                return choice
            except Exception:
                pass
        if status:
            status('يجهّز النموذج لجهازك ويختار الأسرع (مرة واحدة، دقائق قليلة)…')
        import onnxruntime as ort
        x = np.random.default_rng(0).standard_normal((1, 2 * BINS, FRAMES, 2)).astype(np.float32) * 0.1
        made, times, ref = {}, {}, None
        for prov in ('cpu', 'dml'):
            try:
                s = self._make(prov, cores if prov == 'cpu' else 0)
                cpu_t = times.get('cpu') if isinstance(times.get('cpu'), float) else None
                # كرت ضعيف جدًا (أو بلا كرت حقيقي) لا يعطّل التجهيز: تُوقف المحاولة إن طالت كثيرًا عن المعالج
                limit = max(120.0, 4 * cpu_t) if (prov == 'dml' and cpu_t) else None

                def once():
                    ro = ort.RunOptions()
                    timer = threading.Timer(limit, lambda: setattr(ro, 'terminate', True)) if limit else None
                    if timer:
                        timer.start()
                    try:
                        return s.run(['mask'], {'spec': x}, ro)[0]
                    finally:
                        if timer:
                            timer.cancel()
                once()                                              # تحمية
                t = time.time()
                out = once()
                times[prov] = time.time() - t
                if prov == 'cpu':
                    ref = out
                elif ref is not None:
                    # الجودة لا تنقص: كرت الشاشة يُعتمد فقط إن طابق ناتجه ناتج المعالج
                    err = float(np.max(np.abs(out - ref)) / (np.max(np.abs(ref)) + 1e-9))
                    if not err < 1e-3:
                        times[prov] = f'inexact: {err:.1e}'
                        continue
                made[prov] = s
            except Exception as e:  # noqa: BLE001
                times[prov] = 'slow' if 'terminate' in str(e).lower() else f'fail: {e.__class__.__name__}'
        ok = {k: v for k, v in times.items() if isinstance(v, float)}
        if not ok:
            raise RuntimeError('تعذّر تشغيل النموذج على هذا الجهاز.')
        best = min(ok, key=ok.get)
        rate = 1.0 / ok[best]                                       # قطع في الثانية
        # الاثنان معًا: يُقاس فعليًا وهما يعملان في الوقت نفسه (كرت الشاشة المدمج يشارك المعالج الطاقة والذاكرة)
        if len(ok) == 2 and max(ok.values()) < 4 * min(ok.values()):
            try:
                slow, fast = max(ok, key=ok.get), min(ok, key=ok.get)
                stop = threading.Event()
                res = {}

                def go(k, once):
                    n, t0 = 0, time.time()
                    try:
                        while True:
                            made[k].run(['mask'], {'spec': x})
                            n += 1
                            if once or stop.is_set():
                                break
                    finally:
                        res[k] = (n, time.time() - t0)
                        if once:
                            stop.set()
                th = [threading.Thread(target=go, args=(slow, True)), threading.Thread(target=go, args=(fast, False))]
                [t.start() for t in th]
                [t.join() for t in th]
                hybrid_rate = sum(n / t for n, t in res.values() if n)
                times['hybrid'] = round(1 / hybrid_rate, 2)
                if hybrid_rate > rate * 1.1:
                    best, rate = 'hybrid', hybrid_rate
            except Exception as e:  # noqa: BLE001
                times['hybrid'] = f'fail: {e.__class__.__name__}'
        self._use(best, made)
        prefs.setdefault('backend', {})[key] = best
        prefs.setdefault('benchmark', {})[key] = {k: (round(v, 2) if isinstance(v, float) else v) for k, v in times.items()}
        paths.save_settings(prefs)
        return best

    def __call__(self, inp: np.ndarray) -> np.ndarray:
        k = self.idle.get()
        t = time.time()
        try:
            out = self.sessions[k].run(['mask'], {'spec': inp})[0]
        except Exception:
            if k != 'dml':
                self.idle.put(k)
                raise
            # كرت الشاشة تعذّر أثناء العمل: يكمل على المعالج بلا توقف (لا يُعاد كرت الشاشة للطابور)
            with self.stat_lock:
                self.fallbacks += 1
                self.sessions.pop('dml', None)
                if 'cpu' not in self.sessions:
                    self.sessions['cpu'] = self._make('cpu', self._cores())
                    self.idle.put('cpu')
                self.mode = 'cpu'
            return self(inp)
        with self.stat_lock:
            self.seconds += time.time() - t
            self.calls += 1
        self.idle.put(k)
        return out

    def describe(self) -> str:
        return {'dml': 'كرت الشاشة', 'hybrid': 'المعالج وكرت الشاشة معًا'}.get(self.mode, 'المعالج')

    def summary(self) -> dict:
        prefs = paths.load_settings()
        return {'mode': self.mode, 'benchmark': prefs.get('benchmark', {}).get(MODEL_TAG, {})}


def benchmark_json() -> str:
    return json.dumps(paths.load_settings().get('benchmark', {}), ensure_ascii=False)
