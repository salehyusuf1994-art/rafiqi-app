"""
«نقاء» — فصل الصوت البشري عن الموسيقى على الكمبيوتر بنموذج BS-RoFormer بالدقة الكاملة.
الواجهة HTML (عربية من اليمين لليسار) داخل نافذة WebView2، والمعالجة كلها على الجهاز.
"""
from __future__ import annotations

import ctypes
import json
import logging
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from . import __version__, jobs, media, model, paths

log = logging.getLogger('naqa')

AR_DIGITS = str.maketrans('0123456789.', '٠١٢٣٤٥٦٧٨٩٫')


def ar(x) -> str:
    return str(x).translate(AR_DIGITS)


def hms(sec: float) -> str:
    s = int(round(sec))
    h, m, s = s // 3600, (s % 3600) // 60, s % 60
    return ar(f'{h}:{m:02d}:{s:02d}' if h else f'{m}:{s:02d}')


def words(sec: float) -> str:
    """مدة بالكلمات: «ساعة و٢٠ دقيقة»، «٤٥ دقيقة»، «أقل من دقيقة»"""
    m = int(round(sec / 60))
    if m < 1:
        return 'أقل من دقيقة'
    h, m = divmod(m, 60)
    parts = []
    if h:
        parts.append('ساعة' if h == 1 else 'ساعتين' if h == 2 else f'{ar(h)} ساعات')
    if m:
        parts.append('دقيقة' if m == 1 else 'دقيقتين' if m == 2 else f'{ar(m)} دقيقة')
    return ' و'.join(parts)


def size_text(b: float) -> str:
    if b >= 1e9:
        return ar(f'{b / 1e9:.1f}') + ' جيجا'
    return ar(f'{b / 1e6:.1f}') + ' ميجا'


class Power:
    """أثناء الفصل: لا ينام الجهاز، والأولوية أقل من برامجك فيبقى الجهاز سريعًا وأنت تعمل"""
    ES_CONTINUOUS, ES_SYSTEM_REQUIRED = 0x80000000, 0x00000001

    @staticmethod
    def busy(on: bool) -> None:
        if os.name != 'nt':
            return
        try:
            k = ctypes.windll.kernel32
            k.SetThreadExecutionState(Power.ES_CONTINUOUS | (Power.ES_SYSTEM_REQUIRED if on else 0))
            k.SetPriorityClass(k.GetCurrentProcess(), 0x4000 if on else 0x20)   # BELOW_NORMAL / NORMAL
        except Exception:
            pass


class Api:
    def __init__(self):
        self._window = None
        self._runner = None
        self._file = None
        self._cancel = threading.Event()
        self._dl_cancel = threading.Event()
        self._busy = False
        self._pool = ThreadPoolExecutor(max_workers=3)
        self._last_out = None

    # ── واجهة ← بايثون ──
    def _js(self, fn: str, *args) -> None:
        if self._window:
            try:
                self._window.evaluate_js(f'ui.{fn}({",".join(json.dumps(a, ensure_ascii=False) for a in args)})')
            except Exception:
                pass

    def init(self):
        prefs = paths.load_settings()
        threading.Thread(target=lambda: log.info('purged %s', jobs.purge_stale()), daemon=True).start()
        if model.is_ready():
            threading.Thread(target=self._prepare_runner, daemon=True).start()
        return {'version': __version__, 'modelReady': model.is_ready(), 'keep': prefs.get('keep', 'vocals'),
                'fmt': prefs.get('fmt', 'm4a'), 'modelSize': size_text(model.MODEL_SIZE) if model.MODEL_SIZE else ''}

    def _prepare_runner(self):
        try:
            r = model.Runner()
            r.prepare(status=lambda s: self._js('modelStatus', 'preparing', s))
            self._runner = r
            self._js('modelStatus', 'ready', r.describe())
        except Exception as e:  # noqa: BLE001
            log.exception('prepare')
            self._js('modelStatus', 'failed', str(e))

    def download_model(self):
        if self._busy:
            return
        self._dl_cancel.clear()

        def work():
            try:
                model.download(lambda phase, v, done, total: self._js(
                    'dl', phase, v, size_text(done) if done else '', size_text(total) if total else ''),
                    self._dl_cancel.is_set)
                self._js('modelStatus', 'preparing', 'يجهّز النموذج لجهازك…')
                self._prepare_runner()
            except InterruptedError:
                self._js('modelStatus', 'missing', 'أُوقف التنزيل. يكمل من حيث توقف عند الضغط مرة ثانية.')
            except Exception as e:  # noqa: BLE001
                log.exception('download')
                self._js('modelStatus', 'missing', f'تعذّر التنزيل: {e}')
        threading.Thread(target=work, daemon=True).start()

    def cancel_download(self):
        self._dl_cancel.set()

    def pick_file(self):
        import webview
        open_kind = webview.FileDialog.OPEN if hasattr(webview, 'FileDialog') else webview.OPEN_DIALOG
        types = ('ملفات الصوت والفيديو (*.mp4;*.mkv;*.mov;*.avi;*.wmv;*.webm;*.flv;*.m4v;*.ts;*.mpg;*.mp3;*.m4a;*.wav;*.flac;*.aac;*.ogg;*.opus;*.wma)',
                 'كل الملفات (*.*)')
        r = self._window.create_file_dialog(open_kind, allow_multiple=False, file_types=types)
        if not r:
            return None
        return self.select(r[0])

    def select(self, path: str):
        if self._busy:
            return {'error': 'انتظر حتى ينتهي الفصل الحالي.'}
        if not path or not os.path.isfile(path):
            return {'error': 'الملف غير موجود.'}
        try:
            info = media.probe(path)
        except media.MediaError as e:
            return {'error': str(e)}
        if info['duration'] > jobs.MAX_SECONDS + 1:
            return {'error': f'المقطع {words(info["duration"])}، والحد الأقصى ٤ ساعات.'}
        self._file = {'path': path, **info}
        prefs = paths.load_settings()
        keep = prefs.get('keep', 'vocals')
        return {'name': os.path.basename(path), 'folder': os.path.dirname(path), 'video': info['video'],
                'duration': hms(info['duration']), 'durationWords': words(info['duration']),
                'size': size_text(os.path.getsize(path)), 'pending': self._pending(keep)}

    def _pending(self, keep):
        if not self._file:
            return None
        p = jobs.pending(self._file['path'], keep)
        return None if p is None else ar(int(p * 100))

    def set_prefs(self, keep: str, fmt: str):
        prefs = paths.load_settings()
        prefs['keep'], prefs['fmt'] = keep, fmt
        paths.save_settings(prefs)
        return self._pending(keep)

    def discard(self, keep: str):
        if self._file and not self._busy:
            jobs.discard(self._file['path'], keep)
        return None

    def start(self, keep: str, fmt: str):
        if self._busy or not self._file:
            return False
        if self._runner is None:
            return False
        self._busy = True
        self._cancel.clear()
        src = self._file['path']
        dur = self._file['duration']
        threading.Thread(target=self._work, args=(src, keep, fmt, dur), daemon=True).start()
        return True

    def _work(self, src, keep, fmt, dur):
        Power.busy(True)
        t0 = time.time()
        counter = {}
        r = self._runner
        r.seconds, r.calls, r.fallbacks = 0.0, 0, 0
        state = {'p': 0.0, 'part': ''}

        def progress(p):
            state['p'] = max(state['p'], p)
            el = time.time() - t0
            eta = ''
            if 0.02 < state['p'] < 0.995 and el > 20:
                eta = words(el * (1 - state['p']) / state['p'])
            self._js('progress', state['p'], ar(int(state['p'] * 100)), eta, state['part'])

        def status(b, total):
            state['part'] = 'يحفظ الناتج…' if b < 0 else (f'الجزء {ar(b + 1)} من {ar(total)}' if total > 1 else '')

        try:
            sep = jobs.make_separator(r, self._pool, self._cancel.is_set, counter)
            res = jobs.run(src, keep, sep, fmt=fmt, progress=progress, cancelled=self._cancel.is_set, status=status)
            chunks = max(1, counter.get('chunks', 1))
            secs = res['seconds']
            rep = f'استغرق الفصل {hms(secs)} ({ar(f"{secs / chunks:.1f}")} ثانية لكل ٨ ثوانٍ من المقطع). '
            rep += f'النموذج وحده {ar(f"{r.seconds / max(1, r.calls):.1f}")} ثانية لكل جزء. يعمل على: {r.describe()}.'
            if r.fallbacks:
                rep += f' تعذّر كرت الشاشة في {ar(r.fallbacks)} من الأجزاء فأكمل على المعالج.'
            if res['resumed']:
                rep += ' أُكمل من حيث توقف سابقًا.'
            self._last_out = res['out']
            self._js('done', {'name': os.path.basename(res['out']), 'path': res['out'],
                              'size': size_text(os.path.getsize(res['out'])), 'report': rep})
            log.info('done %s', rep)
        except InterruptedError:
            self._js('stopped', self._pending(keep) or '')
        except media.MediaError as e:
            self._js('failed', str(e))
        except MemoryError:
            self._js('failed', 'الذاكرة لا تكفي. أغلق بعض البرامج وجرّب مرة ثانية؛ يكمل من حيث توقف.')
        except Exception as e:  # noqa: BLE001
            log.exception('separate')
            self._js('failed', f'تعذّرت المعالجة: {e.__class__.__name__}. يكمل من حيث توقف عند المحاولة مرة ثانية.')
        finally:
            self._busy = False
            Power.busy(False)

    def cancel(self):
        self._cancel.set()

    def open_path(self, path: str):
        if path and os.path.exists(path):
            os.startfile(path) if os.name == 'nt' else subprocess.Popen(['xdg-open', path])

    def show_in_folder(self, path: str):
        if path and os.path.exists(path) and os.name == 'nt':
            subprocess.Popen(['explorer', '/select,', os.path.normpath(path)])

    def closing(self):
        """إغلاق النافذة أثناء الفصل: يُحفظ التقدّم ويكمل لاحقًا من حيث توقف"""
        if self._busy:
            self._cancel.set()
            for _ in range(50):
                if not self._busy:
                    break
                time.sleep(0.1)


def _bind_drop(window, api: Api):
    try:
        from webview.dom import DOMEventHandler
    except Exception:
        return

    def on_drop(e):
        try:
            files = (e.get('dataTransfer') or {}).get('files') or []
            p = files[0].get('pywebviewFullPath') if files else None
            if p:
                window.evaluate_js(f'ui.dropped({json.dumps(p, ensure_ascii=False)})')
        except Exception:
            log.exception('drop')

    doc = window.dom.document
    doc.events.dragenter += DOMEventHandler(lambda e: None, True, True)
    doc.events.dragover += DOMEventHandler(lambda e: None, True, True)
    doc.events.drop += DOMEventHandler(on_drop, True, True)


def _utf8_stdio():
    """النص العربي لا يُسقط البرنامج إن وُجدت نافذة أوامر بترميز قديم (ويندوز cp1252)"""
    for s in (sys.stdout, sys.stderr):
        try:
            if s is not None:
                s.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass


def main():
    _utf8_stdio()
    logging.basicConfig(filename=os.path.join(paths.data_dir(), 'naqa.log'), level=logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s', encoding='utf-8')
    if '--selftest' in sys.argv:
        from . import selftest
        try:
            code = selftest.main(sys.argv)
        except BaseException:  # noqa: BLE001 — لا نافذة خطأ تنتظر أحدًا: يُسجَّل ويخرج برمز فشل
            logging.exception('selftest crashed')
            code = 3
        sys.exit(code)
    import webview
    api = Api()
    window = webview.create_window('نقاء — فصل الصوت البشري عن الموسيقى', url=paths.resource('ui', 'index.html'),
                                   js_api=api, width=1000, height=760, min_size=(820, 640),
                                   background_color='#08090E', text_select=False)
    api._window = window
    window.events.closing += api.closing
    smoke = '--smoke' in sys.argv

    def on_start(w):
        _bind_drop(w, api)
        if smoke:
            time.sleep(4)
            print('NAQA SMOKE OK', flush=True)
            w.destroy()
    webview.start(on_start, window, gui='edgechromium' if os.name == 'nt' else None, debug=False,
                  storage_path=paths.data_dir('webview'))


if __name__ == '__main__':
    main()
