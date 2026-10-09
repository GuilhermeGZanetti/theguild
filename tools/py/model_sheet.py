"""Review sheet for the character models: for each variant, toon renders of
the 4x Blender frames (front-right, front-left, back) beside the final pixel
sprites (four directions and an attack frame) and the portrait, all in the
variant's game palette (first choice of every list in data/races.json).

    blender -b --factory-startup --python tools/blender/units.py -- --out tools/_cache/quick --quick --only <ids>
    python tools/py/model_sheet.py [--src tools/_cache/quick] <id|prefix> ...   -> tools/_cache/preview/models_<name>.png
"""
import os
import sys
import json
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import palette as P  # noqa: E402
import sprites_post as S  # noqa: E402

ROOT = S.ROOT
RACES = json.load(open(os.path.join(ROOT, "data", "races.json"), encoding="utf-8"))
BASE = {"cloth1": (64, 124, 170), "cloth2": (186, 70, 64), "leather": (126, 84, 54), "metal": (176, 184, 196),
        "trim": (226, 184, 74), "wood": (146, 98, 58), "glow": (130, 236, 255), "cape": (84, 128, 72),
        "white": (236, 230, 218), "bandage": (242, 236, 224), "eyes": (38, 28, 48), "feature": (200, 150, 90)}
LOOKS = ("warrior", "rogue", "ranger", "mystic", "tidecaller", "lanternbearer", "graftwarden", "sandreaver", "villager")


def parse(vid):
    parts = vid.split("_")
    race = parts[0]
    look = parts[1] if len(parts) > 1 and parts[1] in LOOKS else "warrior"
    g = parts[2] if len(parts) > 2 and parts[2] in ("m", "f") else "m"
    return race, look, g


ENEMIES = json.load(open(os.path.join(ROOT, "data", "enemies.json"), encoding="utf-8"))


def palette_for(vid, pick=0):
    # an enemy sprite shows in the colours of the first enemy that wears it
    for e in ENEMIES.values():
        if e.get("sprite") == vid:
            pal = dict(BASE)
            pal.update({k: tuple(v) for k, v in e.get("palette", {}).items()})
            return pal
    race, look, g = parse(vid)
    pal = dict(BASE)
    rd = RACES.get(race, RACES["human"])
    for k in ("skin", "skin2", "hair"):
        lst = rd[k]
        pal[k] = tuple(lst[pick % len(lst)])
    for k, v in rd.get("palette", {}).items():
        pal[k] = tuple(v[pick % len(v)])
    for key in (look, look + "_" + g):
        for k, v in rd.get("looks", {}).get(key, {}).items():
            pal[k] = tuple(v[pick % len(v)])
    return pal


def toon(img, pal):
    """Colorize a 4x index render (no outline) in the game ramps."""
    a = np.asarray(img.convert("RGBA"))
    alpha = a[..., 3] > 127
    slot = np.clip(a[..., 0].astype(np.int32) // 16, 0, 14)
    shade = a[..., 1].astype(np.float32) / 255.0
    lvl = np.zeros(shade.shape, dtype=np.int32)
    for t in S.SHADE_T:
        lvl += (shade >= t).astype(np.int32)
    lvl = np.where(slot == S.GLOW, np.maximum(lvl, 2), lvl)
    ramps = np.array([P.ramp(pal.get(n, (255, 0, 255))) for n in P.SLOTS[:15]], dtype=np.uint8)
    out = np.zeros(a.shape, dtype=np.uint8)
    out[..., :3] = ramps[slot, lvl]
    out[..., 3] = np.where(alpha, 255, 0)
    return Image.fromarray(out, "RGBA")


def pix(path, pal, portrait=False):
    enc = S.process_frame(path, portrait=portrait)
    return Image.fromarray(S.colorize(enc, pal), "RGBA")


def main():
    args = sys.argv[1:]
    src = os.path.join(ROOT, "tools", "_cache", "quick")
    if "--src" in args:
        i = args.index("--src")
        src = os.path.join(ROOT, args[i + 1])
        del args[i:i + 2]
    pick = 0
    if "--pick" in args:
        i = args.index("--pick")
        pick = int(args[i + 1])
        del args[i:i + 2]
    have = sorted(d for d in os.listdir(src) if os.path.isfile(os.path.join(src, d, "meta.json")))
    ids = [d for d in have if any(d == a or d.startswith(a) for a in args)] if args else have
    HI, SP, PO = 224, 192, 192
    W = 3 * HI + 5 * SP + PO
    rows = []
    for vid in ids:
        d = os.path.join(src, vid)
        pal = palette_for(vid, pick)
        row = Image.new("RGBA", (W, HI + 14), (196, 192, 180, 255))
        x = 0
        cv = json.load(open(os.path.join(d, "meta.json")))["canvas"] * S.SS
        for di in (0, 1, 2):
            f = os.path.join(d, f"idle_{di}_0.png")
            if os.path.exists(f):
                im = toon(Image.open(f), pal).crop((cv * 3 // 32, 0, cv * 29 // 32, cv * 26 // 32)).resize((HI, HI), Image.LANCZOS)
                row.alpha_composite(im, (x, 0))
            x += HI
        for f in [f"idle_{di}_0.png" for di in range(4)] + ["attack_0_2.png"]:
            fp = os.path.join(d, f)
            if os.path.exists(fp):
                im = pix(fp, pal).resize((SP, SP), Image.NEAREST)
                row.alpha_composite(im, (x, HI - SP))
            x += SP
        fp = os.path.join(d, "portrait.png")
        if os.path.exists(fp):
            bg = Image.new("RGBA", (32, 32), (60, 50, 70, 255))
            bg.alpha_composite(pix(fp, pal, portrait=True))
            row.alpha_composite(bg.resize((PO, PO), Image.NEAREST), (x, HI - PO))
        ImageDraw.Draw(row).text((4, HI), vid, fill=(30, 24, 30, 255))
        rows.append(row)
    if not rows:
        print("nothing to show")
        return
    sheet = Image.new("RGBA", (W, sum(r.height for r in rows)), (196, 192, 180, 255))
    y = 0
    for r in rows:
        sheet.alpha_composite(r, (0, y))
        y += r.height
    name = "_".join(args)[:60] if args else "all"
    out = os.path.join(ROOT, "tools", "_cache", "preview", "models_%s.png" % name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
