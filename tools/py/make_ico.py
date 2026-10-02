"""Build assets/icon.ico (multi-size) from the 64x64-native pixel-art project icon.

Sizes that are integer multiples of the native art (64/128/256) use nearest-neighbor
to keep the pixels crisp; the small sizes (16-48) are filtered so thin lines survive.
Run: .venv/Scripts/python tools/py/make_ico.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/sprites/ui/icon.png"
DST = ROOT / "assets/icon.ico"

src = Image.open(SRC).convert("RGBA")
native = src.resize((64, 64), Image.NEAREST)
frames = []
for size in (256, 128, 64, 48, 32, 24, 16):
    if size % 64 == 0:
        frames.append(native.resize((size, size), Image.NEAREST))
    else:
        frames.append(src.resize((size, size), Image.LANCZOS))
frames[0].save(DST, format="ICO", sizes=[f.size for f in frames], append_images=frames[1:])
print(f"wrote {DST.relative_to(ROOT)} ({DST.stat().st_size} bytes)")
