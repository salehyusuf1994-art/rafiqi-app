"""أماكن ملفات الأداة: كلها داخل مجلد المستخدم المحلي (لا شيء يُرفع لأي مكان)"""
from __future__ import annotations

import json
import os
import sys

APP = 'Naqa'


def data_dir(*sub: str) -> str:
    base = os.environ.get('LOCALAPPDATA') or os.path.join(os.path.expanduser('~'), '.local', 'share')
    p = os.path.join(base, APP, *sub)
    os.makedirs(p, exist_ok=True)
    return p


def resource(*parts: str) -> str:
    """ملف مرفق مع الأداة (الواجهة، ffmpeg) — داخل حزمة PyInstaller أو بجانب الكود"""
    base = getattr(sys, '_MEIPASS', None) or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, *parts)


def _settings_file() -> str:
    return os.path.join(data_dir(), 'settings.json')


def load_settings() -> dict:
    try:
        with open(_settings_file(), encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def save_settings(d: dict) -> None:
    tmp = _settings_file() + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, _settings_file())
