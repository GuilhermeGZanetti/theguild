"""Shared paths and helpers for the trailer tools."""
import os
import shutil
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CACHE = os.path.join(ROOT, "tools", "_cache", "trailer")
SHOTS = os.path.join(CACHE, "shots")
OUT = os.path.join(ROOT, "build", "trailer")
GODOT = r"C:\Users\ferna\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe"
FONTS = os.path.join(ROOT, "assets", "fonts")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
FPS = 30
W, H = 1920, 1080


def ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        exe = shutil.which("ffmpeg")
        if exe is None:
            raise SystemExit("ffmpeg not found: pip install imageio-ffmpeg (in .venv) or put ffmpeg on PATH")
        return exe


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)
