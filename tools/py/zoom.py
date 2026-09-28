"""Crop + upscale an image region for visual inspection: zoom.py in out x y w h scale"""
import sys
from PIL import Image

src, dst, x, y, w, h, s = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:8])
im = Image.open(src).convert("RGBA").crop((x, y, x + w, y + h))
bg = Image.new("RGBA", im.size, (104, 132, 84, 255))
bg.alpha_composite(im)
bg.resize((w * s, h * s), Image.NEAREST).save(dst)
