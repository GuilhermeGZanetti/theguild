"""Review sheet for the race models: each variant in its race palette
(first choice of every list in data/races.json), 4 idle directions, an attack
frame and the portrait.

    python tools/py/race_sheet.py [race ...]  -> tools/_cache/preview/races.png
"""
import os
import sys
import json
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sprites_post as S  # noqa: E402

ROOT = S.ROOT
RACES = json.load(open(os.path.join(ROOT, "data", "races.json"), encoding="utf-8"))
LOOKS = {"tidefolk": "tidecaller", "mothkin": "lanternbearer", "barkborn": "graftwarden", "khepri": "sandreaver"}
BASE = {"cloth1": (64, 124, 170), "cloth2": (186, 70, 64), "leather": (126, 84, 54), "metal": (176, 184, 196),
        "trim": (226, 184, 74), "wood": (146, 98, 58), "glow": (130, 236, 255), "cape": (84, 128, 72),
        "white": (236, 230, 218), "bandage": (242, 236, 224), "eyes": (38, 28, 48)}


def palette_for(race, look):
    rd = RACES[race]
    pal = dict(BASE)
    for k in ("skin", "skin2", "hair"):
        pal[k] = tuple(rd[k][0])
    for k, v in rd.get("palette", {}).items():
        pal[k] = tuple(v[0])
    for k, v in rd.get("looks", {}).get(look, {}).items():
        pal[k] = tuple(v[0])
    pal.setdefault("feature", (200, 150, 90))
    return pal


def main():
    races = sys.argv[1:] or ["tidefolk", "mothkin", "barkborn", "khepri"]
    idx = json.load(open(os.path.join(S.OUT, "units.json")))
    rows = []
    for race in races:
        for look in ["warrior", "rogue", "ranger", "mystic", LOOKS[race]]:
            rows.append((race, look, f"{race}_{look}"))
    cv = 64
    sheet = Image.new("RGBA", (6 * cv, len(rows) * (cv + 8)), (200, 196, 184, 255))
    d = ImageDraw.Draw(sheet)
    for r, (race, look, vid) in enumerate(rows):
        if vid not in idx:
            continue
        m = idx[vid]
        pal = palette_for(race, look)
        im = np.asarray(Image.open(os.path.join(S.OUT, vid + ".png")))
        atk = m["anims"]["attack"][0] + 2
        frames = [im[k * cv:(k + 1) * cv, 0:cv] for k in range(4)] + [im[0:cv, atk * cv:(atk + 1) * cv]]
        y0 = r * (cv + 8)
        for k, fr in enumerate(frames):
            sheet.alpha_composite(Image.fromarray(S.colorize(fr, pal), "RGBA"), (k * cv, y0))
        p = Image.fromarray(S.colorize(np.asarray(Image.open(os.path.join(S.OUT, vid + "_portrait.png"))), pal), "RGBA")
        sheet.alpha_composite(p.resize((64, 64), Image.NEAREST), (5 * cv, y0))
        d.text((2, y0 + cv - 2), vid, fill=(40, 30, 40, 255))
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    out = os.path.join(ROOT, "tools", "_cache", "preview", "races_%s.png" % "_".join(races))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
