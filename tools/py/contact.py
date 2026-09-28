"""Contact sheet of every unit (idle dir0, dir1, attack f2 dir1, portrait) for review."""
import os
import sys
import json
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sprites_post as S  # noqa: E402

ROOT = S.ROOT
idx = json.load(open(os.path.join(S.OUT, "units.json")))
ids = sys.argv[1:] or sorted(idx)
cell = 128
cols = 8
rows = (len(ids) + 1) // 2
W = cols * cell // 2 * 1
sheet = Image.new("RGBA", (cell * 4 * 2 // 2 * 2, rows * (cell // 2 + 10)), (98, 124, 80, 255))
sheet = Image.new("RGBA", (8 * 64, rows * 74), (98, 124, 80, 255))
d = ImageDraw.Draw(sheet)
for i, vid in enumerate(ids):
    m = idx[vid]
    cv = m["canvas"]
    im = np.asarray(Image.open(os.path.join(S.OUT, vid + ".png")))
    atk = m["anims"]["attack"][0] + 2
    frames = [im[0:cv, 0:cv], im[cv:2 * cv, 0:cv], im[cv:2 * cv, atk * cv:(atk + 1) * cv]]
    x0 = (i % 2) * 256
    y0 = (i // 2) * 74
    for k, fr in enumerate(frames):
        rgb = Image.fromarray(S.colorize(fr), "RGBA")
        if cv != 64:
            rgb = rgb.crop(((cv - 64) // 2, cv - 64 - (cv - 64) // 4, (cv - 64) // 2 + 64, cv - (cv - 64) // 4)) if cv > 64 else rgb
        sheet.alpha_composite(rgb, (x0 + k * 64, y0))
    p = Image.fromarray(S.colorize(np.asarray(Image.open(os.path.join(S.OUT, vid + "_portrait.png")))), "RGBA")
    sheet.alpha_composite(p.resize((64, 64), Image.NEAREST), (x0 + 192, y0))
    d.text((x0 + 2, y0 + 63), vid, fill=(255, 255, 255, 255))
sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
out = os.path.join(ROOT, "tools", "_cache", "preview", "contact.png")
sheet.save(out)
print(out, sheet.size)
