"""تشخيص مزامنة الفيديو مع نسخ ffmpeg المختلفة: يجرّب طرق وضع الصوت المفصول ويقيس أول صوت"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from naqa import media  # noqa: E402
from naqa.dsp import SR  # noqa: E402

FF, FP = media.tool('ffmpeg'), media.tool('ffprobe')
print(subprocess.run([FF, '-version'], capture_output=True, text=True).stdout.splitlines()[0])


def onset(path, af='aresample=async=1:first_pts=0'):
    raw = subprocess.run([FF, '-v', 'error', '-i', path, '-af', af, '-ac', '1', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    return float(np.argmax(np.abs(x) > 0.05)) / SR


def streams(path):
    d = json.loads(subprocess.run([FP, '-v', 'error', '-show_entries',
                                   'format=start_time,duration:stream=codec_type,start_time,start_pts,time_base,duration',
                                   '-of', 'json', path], capture_output=True, text=True).stdout)
    return d


tmp = tempfile.mkdtemp()
for vcodec, ext in (('mpeg4', '.mp4'), ('libx264', '.mp4'), ('mpeg4', '.mkv'), ('mpeg4', '.mov')):
    src = os.path.join(tmp, f'src-{vcodec}{ext}')
    r = subprocess.run([FF, '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=25:duration=20',
                        '-itsoffset', '0.75', '-f', 'lavfi', '-i', 'sine=frequency=600:sample_rate=44100:duration=19',
                        '-map', '0:v', '-map', '1:a', '-c:v', vcodec, '-c:a', 'aac', '-b:a', '128k', src],
                       capture_output=True, text=True)
    if r.returncode:
        print('skip', vcodec, ext, r.stderr[-200:])
        continue
    info = media.probe(src)
    on0 = onset(src)
    print(f'\n== {vcodec}{ext}: probe audio_start={info["audio_start"]:.4f} onset={on0:.4f}')
    print('   streams', json.dumps(streams(src)))
    # الصوت كما يقرؤه القارئ
    rd = media.Reader(src)
    rd.fill(SR * 3600)
    a = np.stack([rd.l, rd.r], 1).astype(np.float32)
    rd.close()
    first = float(np.argmax(np.abs(a[:, 0]) > 0.05)) / SR
    print(f'   reader: {len(a) / SR:.3f}s first-sound-in-raw={first:.4f}')
    raw = os.path.join(tmp, 'a.f32')
    a.tofile(raw)
    # طريقة بديلة: الصوت مقروء على خط زمن الملف نفسه من الصفر (صمت قبل بدايته)
    pad = np.frombuffer(subprocess.run([FF, '-v', 'error', '-i', src, '-map', '0:a:0', '-af', 'aresample=async=1:first_pts=0',
                                        '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True).stdout, np.float32)
    rawp = os.path.join(tmp, 'p.f32')
    pad.tofile(rawp)
    outp = os.path.join(tmp, f'o-pad{ext}')
    media.mux_video(src, rawp, outp, 0.0)
    onp = onset(outp)
    print(f'   [pad] raw-first={float(np.argmax(np.abs(pad[0::2]) > 0.05)) / SR:.4f} onset={onp:.4f} diff={1000 * (onp - on0):+.1f}ms')
    for name in ('itsoffset', 'none'):
        out = os.path.join(tmp, f'o-{name}{ext}')
        media.mux_video(src, raw, out, info['audio_start'] if name == 'itsoffset' else 0.0)
        on1 = onset(out)
        print(f'   [{name}] onset={on1:.4f} diff={1000 * (on1 - on0):+.1f}ms streams={json.dumps(streams(out))}')
