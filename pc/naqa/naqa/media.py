"""
قراءة الصوت من أي ملف صوت أو فيديو، والترميز النهائي، ودمج الصوت الجديد مع الصورة كما هي — عبر ffmpeg المرفق.
"""
from __future__ import annotations

import json
import os
import subprocess
import threading

import numpy as np

from . import paths
from .dsp import SR

NO_WINDOW = 0x08000000 if os.name == 'nt' else 0

VIDEO_EXT = {'.mp4', '.m4v', '.mov', '.mkv', '.avi', '.wmv', '.flv', '.webm', '.ts', '.mts', '.m2ts', '.mpg', '.mpeg', '.3gp'}
AUDIO_EXT = {'.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.wma', '.aiff', '.aif', '.amr', '.mka'}


def tool(name: str) -> str:
    exe = name + ('.exe' if os.name == 'nt' else '')
    for p in (paths.resource('ffmpeg', exe), paths.resource('ffmpeg', 'bin', exe)):
        if os.path.isfile(p):
            return p
    return name  # من PATH (التطوير والاختبار)


class MediaError(Exception):
    pass


def probe(path: str) -> dict:
    r = subprocess.run([tool('ffprobe'), '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path],
                       capture_output=True, timeout=60, creationflags=NO_WINDOW)
    if r.returncode != 0:
        raise MediaError('تعذّرت قراءة الملف. تأكد أنه ملف صوت أو فيديو سليم.')
    d = json.loads(r.stdout.decode('utf-8', 'replace') or '{}')
    streams = d.get('streams', [])
    a = next((s for s in streams if s.get('codec_type') == 'audio'), None)
    v = next((s for s in streams if s.get('codec_type') == 'video'
              and not (s.get('disposition') or {}).get('attached_pic')), None)
    if a is None:
        raise MediaError('الملف لا يحتوي على صوت.')
    fmt = d.get('format', {})

    def f(x, default=0.0):
        try:
            return float(x)
        except (TypeError, ValueError):
            return default
    dur = f(fmt.get('duration')) or f(a.get('duration'))
    fs = f(fmt.get('start_time'))
    return {
        'duration': dur,
        'video': v is not None,
        'audio_start': max(0.0, f(a.get('start_time'), fs) - fs),   # موضع الصوت من بداية الملف (للمزامنة)
        'audio_codec': a.get('codec_name', ''),
        'video_codec': (v or {}).get('codec_name', ''),
        'size': f(fmt.get('size')),
    }


class Reader:
    """يقرأ الصوت بالتتابع (ستيريو 44.1 كيلوهرتز، float32) من موضع معيّن — دون تحميل الملف كله في الذاكرة"""

    def __init__(self, path: str, start_sample: int = 0):
        self.base = start_sample
        self.l = np.zeros(0, np.float32)
        self.r = np.zeros(0, np.float32)
        self.eof = False
        args = [tool('ffmpeg'), '-nostdin', '-v', 'error']
        if start_sample > 0:
            args += ['-ss', f'{start_sample / SR:.6f}']
        args += ['-i', path, '-map', '0:a:0', '-vn', '-sn', '-dn', '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-']
        self.p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=NO_WINDOW)
        self._err = b''
        threading.Thread(target=self._drain, daemon=True).start()

    def _drain(self):
        try:
            self._err = self.p.stderr.read()[-2000:]
        except Exception:
            pass

    @property
    def end(self) -> int:
        return self.base + self.l.shape[0]

    def fill(self, to: int) -> None:
        need = to - self.end
        parts_l, parts_r = [self.l], [self.r]
        while need > 0 and not self.eof:
            want = min(need, SR * 30) * 8
            buf = b''
            while len(buf) < want:
                b = self.p.stdout.read(want - len(buf))
                if not b:
                    self.eof = True
                    break
                buf += b
            usable = len(buf) // 8 * 8
            if usable:
                x = np.frombuffer(buf[:usable], np.float32).reshape(-1, 2)
                parts_l.append(x[:, 0].copy())
                parts_r.append(x[:, 1].copy())
                need -= x.shape[0]
        if len(parts_l) > 1:
            self.l = np.concatenate(parts_l)
            self.r = np.concatenate(parts_r)
        if self.eof:
            self.p.wait(timeout=30)
            if self.p.returncode not in (0, None) and self.end == self.base:
                raise MediaError('تعذّرت قراءة الصوت من الملف.')

    def drop(self, before: int) -> None:
        k = before - self.base
        if k > 0:
            self.l = self.l[k:].copy()
            self.r = self.r[k:].copy()
            self.base = before

    def close(self) -> None:
        try:
            if self.p.poll() is None:
                self.p.kill()
        except Exception:
            pass


def _run(args, cancelled=None) -> None:
    p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, creationflags=NO_WINDOW)
    err = []
    t = threading.Thread(target=lambda: err.append(p.stderr.read()), daemon=True)
    t.start()
    while p.poll() is None:
        if cancelled and cancelled():
            p.kill()
            raise InterruptedError
        try:
            p.wait(timeout=0.3)
        except subprocess.TimeoutExpired:
            pass
    t.join(timeout=5)
    if p.returncode != 0:
        tail = (err[0] if err else b'').decode('utf-8', 'replace')[-600:]
        raise MediaError('تعذّر حفظ الناتج.\n' + tail)


def encode_audio(raw: str, out: str, fmt: str, cancelled=None) -> None:
    """الصوت الخام (float32 ستيريو) → m4a (AAC 256k) أو wav (بدون ضغط، 24 بت) أو flac (بدون فقد)"""
    args = [tool('ffmpeg'), '-nostdin', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', raw]
    if fmt == 'wav':
        args += ['-c:a', 'pcm_s24le']
    elif fmt == 'flac':
        args += ['-c:a', 'flac', '-sample_fmt', 's32']
    else:
        args += ['-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart']
    _run(args + [out], cancelled)


def mux_video(src: str, raw: str, out: str, audio_start: float, cancelled=None) -> None:
    """الصورة تُنسخ كما هي بلا إعادة ترميز، والصوت الجديد يبدأ من موضع الصوت الأصلي نفسه (مزامنة مطابقة)"""
    args = [tool('ffmpeg'), '-nostdin', '-v', 'error', '-y', '-i', src]
    if audio_start > 0.0005:
        args += ['-itsoffset', f'{audio_start:.6f}']
    args += ['-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', raw,
             '-map', '0:v:0', '-map', '1:a:0', '-map_metadata', '0', '-c:v', 'copy',
             '-c:a', 'aac', '-b:a', '256k']
    if out.lower().endswith(('.mp4', '.m4v', '.mov')):
        args += ['-movflags', '+faststart']
    _run(args + [out], cancelled)


def output_path(src: str, suffix: str, ext: str) -> str:
    """«الاسم - اللاحقة.امتداد» بجانب الملف الأصلي، بلا كتابة فوق ملف موجود"""
    d, name = os.path.split(src)
    stem = os.path.splitext(name)[0]
    p = os.path.join(d, f'{stem} - {suffix}{ext}')
    k = 2
    while os.path.exists(p):
        p = os.path.join(d, f'{stem} - {suffix} ({k}){ext}')
        k += 1
    return p
