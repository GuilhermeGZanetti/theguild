"""Turn Blender 4x index renders into final pixel-art index sheets.

Input : tools/_cache/units/<id>/*.png   (R=slot, G=shade, B=depth, 4x size)
Output: assets/sprites/units/<id>.png            index sheet (rows=dirs, cols=frames)
        assets/sprites/units/<id>_portrait.png   32x32 index portrait
        assets/sprites/units/<id>_portrait_b.png bandaged portrait (players)
        assets/sprites/units/units.json          frame tables for the game
Encoding: R = slot*16 (15 = outline), G = shade*85 (outline: G = inner slot*16), A = 255.
Render input with depth 0 (B = 0) marks priority pixels (eye highlights) that
win the downsample vote even when they cover little of a pixel.
"""
import os
import sys
import json
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import palette as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(ROOT, "tools", "_cache", "units")
OUT = os.path.join(ROOT, "assets", "sprites", "units")
SS = 4

ANIMS = [("idle", 4), ("walk", 4), ("attack", 4), ("cast", 4), ("hit", 2),
         ("dodge", 2), ("downed", 2), ("death", 4)]

EYES, WHITE, GLOW, OUTLINE = 3, 13, 10, 15
# thin / important features win the majority vote more easily
WEIGHTS = np.ones(16, dtype=np.float32)
WEIGHTS[EYES] = 5.0
WEIGHTS[WHITE] = 1.6
WEIGHTS[GLOW] = 1.6
WEIGHTS[7] = 1.3   # metal (blades)
WEIGHTS[8] = 1.4   # trim
WEIGHTS[9] = 1.2   # wood (bows, staves)
WEIGHTS[14] = 1.5  # bandage
SHADE_T = (0.40, 0.60, 0.86)
PRIO_W = 14.0


def downsample(img):
    a = np.asarray(img.convert("RGBA"), dtype=np.uint8)
    H, W = a.shape[:2]
    h, w = H // SS, W // SS
    alpha = a[..., 3] > 127
    slot = (a[..., 0].astype(np.int32)) // 16
    shade = a[..., 1].astype(np.float32) / 255.0
    prio = alpha & (a[..., 2] < 3)
    depth = np.where(prio, 0.5, a[..., 2].astype(np.float32) / 255.0)
    onehot = (slot[..., None] == np.arange(16)[None, None, :]) & alpha[..., None]
    oh = onehot.reshape(h, SS, w, SS, 16).sum(axis=(1, 3)).astype(np.float32)
    ph = (onehot & prio[..., None]).reshape(h, SS, w, SS, 16).sum(axis=(1, 3)).astype(np.float32)
    cov = oh.sum(axis=2)
    sh = (onehot * shade[..., None]).reshape(h, SS, w, SS, 16).sum(axis=(1, 3))
    dp = (onehot * depth[..., None]).reshape(h, SS, w, SS, 16).sum(axis=(1, 3))
    score = oh * WEIGHTS[None, None, :] + ph * PRIO_W
    best = np.argmax(score, axis=2)
    cnt = np.take_along_axis(oh, best[..., None], axis=2)[..., 0]
    s_mean = np.take_along_axis(sh, best[..., None], axis=2)[..., 0] / np.maximum(cnt, 1)
    d_mean = np.take_along_axis(dp, best[..., None], axis=2)[..., 0] / np.maximum(cnt, 1)
    eye_cnt = oh[..., EYES]
    opaque = (cov >= 6) | ((eye_cnt >= 3) & (cov >= 4))
    return opaque, best, s_mean, d_mean


def quantize(opaque, slot, shade, depth, portrait=False):
    lvl = np.zeros(shade.shape, dtype=np.int32)
    for t in SHADE_T:
        lvl += (shade >= t).astype(np.int32)
    # inner lines: darken pixels just behind a nearer, different part
    h, w = slot.shape
    inner = np.zeros_like(opaque)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        ys = slice(max(0, dy), h + min(0, dy))
        yd = slice(max(0, -dy), h + min(0, -dy))
        xs = slice(max(0, dx), w + min(0, dx))
        xd = slice(max(0, -dx), w + min(0, -dx))
        nb_op = np.zeros_like(opaque)
        nb_sl = np.zeros_like(slot)
        nb_dp = np.ones_like(depth)
        nb_op[yd, xd] = opaque[ys, xs]
        nb_sl[yd, xd] = slot[ys, xs]
        nb_dp[yd, xd] = depth[ys, xs]
        inner |= opaque & nb_op & (nb_sl != slot) & (nb_dp < depth - 0.045)
    keep = (slot == EYES) | (slot == GLOW)
    lvl = np.where(inner & ~keep, np.minimum(lvl, 0), lvl)
    lvl = np.where(slot == EYES, np.clip(lvl, 0, 3) if portrait else np.minimum(lvl, 1), lvl)
    lvl = np.where(slot == GLOW, np.maximum(lvl, 2), lvl)
    return lvl


def encode(opaque, slot, lvl):
    h, w = slot.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., 0] = np.where(opaque, slot * 16, 0)
    out[..., 1] = np.where(opaque, lvl * 85, 0)
    out[..., 3] = np.where(opaque, 255, 0)
    # outer outline (4-connected)
    edge = np.zeros_like(opaque)
    src = np.zeros_like(slot)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        ys = slice(max(0, dy), h + min(0, dy))
        yd = slice(max(0, -dy), h + min(0, -dy))
        xs = slice(max(0, dx), w + min(0, dx))
        xd = slice(max(0, -dx), w + min(0, -dx))
        nb = np.zeros_like(opaque)
        nbs = np.zeros_like(slot)
        nb[yd, xd] = opaque[ys, xs]
        nbs[yd, xd] = slot[ys, xs]
        new = nb & ~opaque & ~edge
        src = np.where(new, nbs, src)
        edge |= new
    out[..., 0] = np.where(edge, OUTLINE * 16, out[..., 0])
    out[..., 1] = np.where(edge, src * 16, out[..., 1])
    out[..., 3] = np.where(edge, 255, out[..., 3])
    return out


def process_frame(path, portrait=False):
    img = Image.open(path)
    opaque, slot, shade, depth = downsample(img)
    lvl = quantize(opaque, slot, shade, depth, portrait)
    return encode(opaque, slot, lvl)


def colorize(enc, pal=None):
    pal = pal or P.TEST_PALETTE
    ramps = [P.ramp(pal.get(n, (255, 0, 255))) for n in P.SLOTS[:15]]
    outl = [P.outline_of(pal.get(n, (255, 0, 255))) for n in P.SLOTS[:15]]
    h, w = enc.shape[:2]
    rgb = np.zeros((h, w, 4), dtype=np.uint8)
    slot = enc[..., 0] // 16
    g = enc[..., 1]
    for y in range(h):
        for x in range(w):
            if enc[y, x, 3] == 0:
                continue
            s = slot[y, x]
            if s == OUTLINE:
                c = outl[min(14, g[y, x] // 16)]
            else:
                c = ramps[s][min(3, g[y, x] // 85)]
                if s == GLOW:
                    c = ramps[s][3]
            rgb[y, x] = (c[0], c[1], c[2], 255)
    return rgb


def build(vid, preview=False):
    src = os.path.join(CACHE, vid)
    meta = json.load(open(os.path.join(src, "meta.json")))
    cv = meta["canvas"]
    cols = sum(n for _, n in ANIMS) + (4 if meta.get("bandage") else 0)
    sheet = np.zeros((cv * 4, cv * cols, 4), dtype=np.uint8)
    table = {}
    col = 0
    for anim, n in ANIMS:
        table[anim] = [col, n]
        for f in range(n):
            for d in range(4):
                sheet[d * cv:(d + 1) * cv, col * cv:(col + 1) * cv] = process_frame(os.path.join(src, f"{anim}_{d}_{f}.png"))
            col += 1
    if meta.get("bandage"):
        table["idle_bandage"] = [col, 4]
        for f in range(4):
            for d in range(4):
                sheet[d * cv:(d + 1) * cv, col * cv:(col + 1) * cv] = process_frame(os.path.join(src, f"bandage_idle_{d}_{f}.png"))
            col += 1
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, vid + ".png"))
    port = process_frame(os.path.join(src, "portrait.png"), portrait=True)
    Image.fromarray(port, "RGBA").save(os.path.join(OUT, vid + "_portrait.png"))
    if meta.get("bandage"):
        pb = process_frame(os.path.join(src, "bandage_portrait.png"), portrait=True)
        Image.fromarray(pb, "RGBA").save(os.path.join(OUT, vid + "_portrait_b.png"))
    if preview:
        prev_dir = os.path.join(ROOT, "tools", "_cache", "preview")
        os.makedirs(prev_dir, exist_ok=True)
        # idle/walk/attack/cast of all dirs + portrait
        cut = sheet[:, :cv * 16]
        rgb = colorize(cut)
        im = Image.fromarray(rgb, "RGBA")
        bg = Image.new("RGBA", im.size, (104, 132, 84, 255))
        bg.alpha_composite(im)
        bg = bg.resize((bg.width * 3, bg.height * 3), Image.NEAREST)
        bg.save(os.path.join(prev_dir, vid + "_preview.png"))
        pr = Image.fromarray(colorize(port), "RGBA")
        pbg = Image.new("RGBA", pr.size, (60, 50, 70, 255))
        pbg.alpha_composite(pr)
        pbg.resize((pr.width * 8, pr.height * 8), Image.NEAREST).save(os.path.join(prev_dir, vid + "_portrait.png"))
    return {"canvas": cv, "anchor": meta["anchor"], "anims": table, "bandage": bool(meta.get("bandage"))}


def main():
    args = sys.argv[1:]
    preview = "--preview" in args
    ids = [a for a in args if not a.startswith("--")]
    full = not ids
    if full:
        ids = sorted(d for d in os.listdir(CACHE) if os.path.isfile(os.path.join(CACHE, d, "meta.json")))
    index_path = os.path.join(OUT, "units.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {}
    for vid in ids:
        index[vid] = build(vid, preview)
        print("[post]", vid, flush=True)
    if full:
        # a full build owns the folder: drop units that are no longer rendered
        for vid in sorted(set(index) - set(ids)):
            del index[vid]
            for name in (vid + ".png", vid + "_portrait.png", vid + "_portrait_b.png"):
                for f in (name, name + ".import"):
                    fp = os.path.join(OUT, f)
                    if os.path.exists(fp):
                        os.remove(fp)
            print("[post] removed stale", vid, flush=True)
    json.dump(index, open(index_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
