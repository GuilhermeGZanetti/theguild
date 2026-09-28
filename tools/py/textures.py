"""Procedural pixel textures: terrain ground types per biome, cliff sides,
water, the prop palettes per region and small sprites (deco, shadows, fx).

Output: assets/textures/*.png
"""
import os
import sys
import math
import json
import colorsys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
T = 48  # texels per ground texture (2 world units at 24 px/unit)

rng = np.random.default_rng(7)


# ------------------------------------------------------------------ noise
def periodic_noise(size, freq, seed):
    """Tileable value noise in [0,1]."""
    r = np.random.default_rng(seed)
    g = r.random((freq, freq))
    xs = np.arange(size) / size * freq
    x0 = np.floor(xs).astype(int)
    fx = xs - x0
    fx = fx * fx * (3 - 2 * fx)
    x1 = (x0 + 1) % freq
    a = g[np.ix_(x0, x0)]
    b = g[np.ix_(x0, x1)]
    c = g[np.ix_(x1, x0)]
    d = g[np.ix_(x1, x1)]
    fy = fx[:, None]
    fxx = fx[None, :]
    top = a * (1 - fxx) + b * fxx
    bot = c * (1 - fxx) + d * fxx
    return top * (1 - fy) + bot * fy


def fbm(size, seed, octaves=((4, 0.5), (8, 0.3), (16, 0.2))):
    n = np.zeros((size, size))
    for i, (f, w) in enumerate(octaves):
        n += periodic_noise(size, f, seed + i * 31) * w
    return n / sum(w for _, w in octaves)


def shade(rgb, k):
    """k<1 darker (hue toward purple), k>1 lighter (toward yellow)."""
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if k < 1:
        h = h + ((0.72 - h + 0.5) % 1 - 0.5) * (1 - k) * 0.5
        s = min(1, s * (1 + (1 - k) * 0.4))
    else:
        h = h + ((0.14 - h + 0.5) % 1 - 0.5) * (k - 1) * 0.5
        s = s * (1 - (k - 1) * 0.4)
    v = min(1, v * k)
    rr, gg, bb = colorsys.hsv_to_rgb(h % 1, max(0, s), v)
    return (int(rr * 255), int(gg * 255), int(bb * 255))


def ramp(base, n=4):
    ks = [0.62, 0.8, 1.0, 1.16][:n] if n == 4 else np.linspace(0.6, 1.2, n)
    return [shade(base, k) for k in ks]


def quantize(v, levels):
    return np.clip((v * levels).astype(int), 0, levels - 1)


def paint(levels_img, colors):
    h, w = levels_img.shape
    out = np.zeros((h, w, 3), dtype=np.uint8)
    for i, c in enumerate(colors):
        out[levels_img == i] = c
    return out


# ------------------------------------------------------------------ ground types
def tex_grass(base, seed, blades=True, flowers=None):
    n = fbm(T, seed)
    lv = quantize(n * 1.1 - 0.05, 3) + 1
    img = paint(lv, ramp(base))
    if blades:
        r = np.random.default_rng(seed)
        for _ in range(70):
            x, y = r.integers(0, T), r.integers(0, T)
            c = ramp(base)[3] if r.random() < 0.6 else ramp(base)[0]
            img[y, x] = c
            img[(y - 1) % T, x] = c if r.random() < 0.5 else img[(y - 1) % T, x]
    if flowers:
        r = np.random.default_rng(seed + 5)
        for _ in range(6):
            x, y = r.integers(0, T), r.integers(0, T)
            img[y, x] = flowers[r.integers(0, len(flowers))]
    return img


def tex_speckle(base, seed, count=60, pebble=None, levels=3, freq=((4, 0.6), (12, 0.4))):
    n = fbm(T, seed, freq)
    lv = quantize(n, levels) + (1 if levels < 4 else 0)
    img = paint(lv, ramp(base))
    r = np.random.default_rng(seed)
    for _ in range(count):
        x, y = r.integers(0, T), r.integers(0, T)
        img[y, x] = ramp(base)[0] if r.random() < 0.5 else ramp(base)[3]
    if pebble:
        for _ in range(8):
            x, y = r.integers(0, T - 1), r.integers(0, T - 1)
            img[y, x] = pebble
            img[y, x + 1] = shade(pebble, 0.8)
    return img


def tex_cobble(base, seed, size=8):
    img = np.zeros((T, T, 3), dtype=np.uint8)
    cols = ramp(base)
    img[:] = cols[0]
    r = np.random.default_rng(seed)
    for by in range(0, T, size):
        off = (size // 2) if (by // size) % 2 else 0
        for bx in range(-size, T, size):
            x0 = bx + off
            c = cols[r.integers(1, 3)]
            for y in range(by + 1, by + size):
                for x in range(x0 + 1, x0 + size):
                    img[y % T, x % T] = c
            for x in range(x0 + 1, x0 + size - 1):
                img[(by + 1) % T, x % T] = cols[3]
    return img


def tex_planks(base, seed):
    img = np.zeros((T, T, 3), dtype=np.uint8)
    cols = ramp(base)
    r = np.random.default_rng(seed)
    pw = 8
    for py in range(0, T, pw):
        c = cols[r.integers(1, 3)]
        img[py:py + pw, :] = c
        img[py, :] = cols[0]
        img[py + 1, :] = cols[3]
        for k in range(3):
            x = r.integers(0, T)
            img[py + 2:py + pw, x] = cols[0]
        for k in range(5):
            x, y = r.integers(0, T), py + r.integers(3, pw)
            img[y % T, x] = cols[0]
    return img


def tex_stonepath(base, seed):
    n = fbm(T, seed, ((6, 0.7), (12, 0.3)))
    cells = quantize(n, 4)
    img = paint(cells, ramp(base))
    # cracks between cells
    edges = (np.roll(cells, 1, 0) != cells) | (np.roll(cells, 1, 1) != cells)
    img[edges] = ramp(base)[0]
    return img


def tex_leaves(base, accents, seed):
    img = tex_speckle(base, seed, count=20)
    r = np.random.default_rng(seed + 3)
    for _ in range(90):
        x, y = r.integers(0, T - 1), r.integers(0, T - 1)
        c = accents[r.integers(0, len(accents))]
        img[y, x] = c
        if r.random() < 0.6:
            img[y, (x + 1) % T] = shade(c, 0.8)
    return img


def tex_water(base, seed):
    n = fbm(T, seed, ((4, 0.5), (8, 0.5)))
    lv = quantize(n, 3)
    return paint(lv, [shade(base, 0.85), base, shade(base, 1.12)])


def tex_void(seed):
    n = fbm(T, seed, ((4, 0.5), (8, 0.5)))
    lv = quantize(n, 3)
    return paint(lv, [(70, 70, 78), (86, 86, 94), (104, 104, 112)])


# ------------------------------------------------------------------ biome palettes
BIOMES = {
    "town": {"grass": (106, 160, 72), "moss": (92, 136, 70), "dirt": (150, 112, 78), "mud": (110, 88, 70), "sand": (214, 186, 138),
             "wetsand": (180, 158, 118), "redsand": (206, 150, 110), "cobble": (146, 140, 134), "stonepath": (160, 150, 136),
             "planks": (156, 110, 68), "ash": (140, 138, 134), "leaves": (120, 150, 70), "void": (80, 80, 88),
             "cliff": (132, 112, 96), "cliff2": (104, 86, 76), "water": (72, 150, 170), "flowers": [(236, 214, 110), (230, 120, 120), (240, 240, 230)]},
    "hush_town": None, "coast": None, "jungle": None, "autumn": None, "desert": None, "hush": None,
}
BIOMES["hush_town"] = dict(BIOMES["town"], grass=(120, 128, 110), cobble=(132, 130, 130), dirt=(130, 118, 108), cliff=(120, 114, 110), water=(110, 120, 126),
                           flowers=[(200, 200, 200)])
BIOMES["coast"] = dict(BIOMES["town"], grass=(128, 170, 84), sand=(230, 204, 150), wetsand=(196, 170, 128), cliff=(150, 136, 120), cliff2=(118, 104, 96),
                       water=(52, 168, 180), flowers=[(250, 240, 220)])
BIOMES["jungle"] = dict(BIOMES["town"], grass=(142, 196, 58), moss=(96, 160, 70), dirt=(144, 104, 66), mud=(104, 90, 64), planks=(170, 120, 70),
                        cliff=(118, 92, 66), cliff2=(90, 72, 56), water=(60, 176, 170), flowers=[(250, 130, 170), (250, 220, 90), (240, 240, 230)])
BIOMES["autumn"] = dict(BIOMES["town"], grass=(150, 160, 70), leaves=(186, 130, 60), dirt=(136, 96, 64), mud=(110, 82, 60), moss=(120, 136, 60),
                        cliff=(126, 96, 72), cliff2=(96, 74, 60), water=(86, 140, 140), flowers=[(230, 96, 50), (250, 190, 70), (200, 60, 40)])
BIOMES["desert"] = dict(BIOMES["town"], sand=(228, 176, 146), redsand=(206, 132, 102), stonepath=(196, 164, 140), grass=(170, 160, 96), dirt=(190, 130, 100),
                        cliff=(196, 126, 96), cliff2=(160, 98, 78), water=(90, 170, 170), flowers=[(240, 220, 200)])
BIOMES["hush"] = dict(BIOMES["town"], ash=(150, 150, 154), stonepath=(126, 126, 132), grass=(128, 132, 124), cobble=(120, 120, 126), dirt=(118, 114, 112),
                      cliff=(108, 108, 114), cliff2=(88, 88, 94), water=(96, 96, 104), flowers=[(230, 200, 120)])

GROUNDS = ["grass", "moss", "leaves", "dirt", "mud", "sand", "wetsand", "redsand", "cobble", "stonepath", "planks", "ash", "void"]


def ground_tex(name, pal, seed):
    b = pal[name]
    if name == "grass":
        return tex_grass(b, seed, flowers=pal["flowers"])
    if name == "moss":
        return tex_grass(b, seed, blades=False)
    if name == "leaves":
        return tex_leaves(pal["grass"] if False else shade(b, 0.9), [pal["flowers"][0], shade(b, 1.1), pal["flowers"][-1]], seed)
    if name in ("dirt", "mud"):
        return tex_speckle(b, seed, 50, pebble=shade(b, 1.25))
    if name in ("sand", "redsand"):
        return tex_speckle(b, seed, 40, levels=3, freq=((3, 0.7), (10, 0.3)))
    if name == "wetsand":
        return tex_speckle(b, seed, 30, pebble=(236, 230, 214))
    if name == "cobble":
        return tex_cobble(b, seed)
    if name == "stonepath":
        return tex_stonepath(b, seed)
    if name == "planks":
        return tex_planks(b, seed)
    if name == "ash":
        return tex_speckle(b, seed, 80)
    if name == "void":
        return tex_void(seed)
    return tex_speckle(b, seed)


def cliff_tex(pal, seed):
    """Strata for tile sides: 48x48 (2 units wide, 2 units tall)."""
    n = fbm(T, seed, ((4, 0.5), (16, 0.5)))
    rows = np.arange(T)[:, None] / T
    strata = (np.sin(rows * 9 * math.pi + n * 3) * 0.5 + 0.5) * 0.6 + n * 0.4
    lv = quantize(strata, 3)
    img = paint(lv, [shade(pal["cliff2"], 0.85), pal["cliff2"], pal["cliff"]])
    r = np.random.default_rng(seed)
    for _ in range(40):
        x, y = r.integers(0, T), r.integers(0, T)
        img[y, x] = shade(pal["cliff"], 1.15)
    return img


def build_ground_atlas():
    """One horizontal strip per biome: [ground0 .. groundN, cliff, water]."""
    meta = {"grounds": GROUNDS, "size": T, "biomes": {}}
    for bi, (biome, pal) in enumerate(BIOMES.items()):
        tiles = [ground_tex(g, pal, 100 + gi * 7 + bi * 101) for gi, g in enumerate(GROUNDS)]
        tiles.append(cliff_tex(pal, 900 + bi))
        tiles.append(tex_water(pal["water"], 700 + bi))
        strip = np.concatenate(tiles, axis=1)
        Image.fromarray(strip, "RGB").save(os.path.join(OUT, f"ground_{biome}.png"))
        meta["biomes"][biome] = {"cliff_index": len(GROUNDS), "water_index": len(GROUNDS) + 1,
                                 "water": pal["water"], "grass": pal["grass"]}
    json.dump(meta, open(os.path.join(OUT, "ground.json"), "w"), indent=1)


# ------------------------------------------------------------------ prop palettes (16 slots)
PROP_SLOTS = ["stone", "stone_dark", "wood", "wood_dark", "leaf", "leaf2", "leaf3", "metal", "cloth", "cloth2", "thatch", "glow",
              "bone", "earth", "moss", "accent"]
PROP_PAL = {
    "town": {"stone": (156, 150, 140), "stone_dark": (112, 106, 106), "wood": (158, 110, 66), "wood_dark": (108, 72, 48), "leaf": (96, 164, 70),
             "leaf2": (66, 124, 62), "leaf3": (236, 120, 96), "metal": (156, 162, 174), "cloth": (186, 76, 64), "cloth2": (226, 206, 160),
             "thatch": (206, 168, 96), "glow": (255, 214, 120), "bone": (234, 226, 204), "earth": (160, 116, 82), "moss": (104, 138, 64),
             "accent": (74, 116, 176)},
}
PROP_PAL["hush_town"] = {k: v for k, v in PROP_PAL["town"].items()}
PROP_PAL["coast"] = dict(PROP_PAL["town"], stone=(128, 136, 140), stone_dark=(88, 94, 104), wood=(186, 156, 116), wood_dark=(132, 104, 80),
                         leaf=(112, 178, 86), leaf2=(74, 138, 76), leaf3=(250, 150, 146), cloth2=(214, 196, 160), accent=(236, 110, 110),
                         moss=(90, 140, 110), earth=(200, 170, 120))
PROP_PAL["jungle"] = dict(PROP_PAL["town"], stone=(136, 146, 124), stone_dark=(96, 106, 90), leaf=(150, 206, 60), leaf2=(84, 158, 64),
                          leaf3=(250, 128, 170), thatch=(196, 150, 80), cloth2=(214, 196, 150), accent=(220, 90, 70), moss=(96, 160, 70),
                          glow=(255, 206, 96))
PROP_PAL["autumn"] = dict(PROP_PAL["town"], stone=(160, 150, 128), stone_dark=(116, 106, 96), leaf=(230, 128, 44), leaf2=(196, 170, 56),
                          leaf3=(200, 66, 44), wood=(128, 86, 56), wood_dark=(92, 62, 46), moss=(126, 140, 56), accent=(196, 64, 52),
                          bone=(236, 226, 206))
PROP_PAL["desert"] = dict(PROP_PAL["town"], stone=(206, 146, 112), stone_dark=(166, 106, 84), wood=(140, 98, 64), wood_dark=(104, 72, 52),
                          leaf=(150, 160, 84), leaf2=(112, 138, 76), leaf3=(236, 120, 96), bone=(240, 230, 206), earth=(210, 130, 96),
                          moss=(160, 150, 90), accent=(80, 128, 170))
PROP_PAL["hush"] = {k: (int(sum(v) / 3 * 0.95), int(sum(v) / 3 * 0.95), int(sum(v) / 3 * 1.02)) for k, v in PROP_PAL["town"].items()}
PROP_PAL["hush"]["glow"] = (236, 206, 130)
PROP_PAL["hush"]["accent"] = (206, 176, 110)
PROP_PAL["hush_town"] = {k: (int(v[0] * 0.55 + sum(v) / 3 * 0.45), int(v[1] * 0.55 + sum(v) / 3 * 0.45), int(v[2] * 0.55 + sum(v) / 3 * 0.45 + 4))
                         for k, v in PROP_PAL["town"].items()}
PROP_PAL["tavern"] = dict(PROP_PAL["town"], wood=(164, 108, 64), wood_dark=(104, 66, 44), cloth=(160, 60, 56), cloth2=(206, 176, 130),
                          accent=(150, 54, 50), stone=(150, 136, 124), glow=(255, 196, 110))


def build_prop_palettes():
    """16 x 4 image per biome: columns = slots, rows = deep/shadow/base/light."""
    for biome, pal in PROP_PAL.items():
        img = np.zeros((4, 16, 3), dtype=np.uint8)
        for i, s in enumerate(PROP_SLOTS):
            for j, c in enumerate(ramp(pal[s])):
                img[j, i] = c
        Image.fromarray(img, "RGB").save(os.path.join(OUT, f"props_{biome}.png"))


# ------------------------------------------------------------------ small sprites
def outline(img, color=(40, 30, 50, 255)):
    a = img[..., 3] > 0
    edge = np.zeros_like(a)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        edge |= np.roll(np.roll(a, dy, 0), dx, 1)
    edge &= ~a
    img[edge] = color
    return img


def deco_sprites():
    """Tiny billboards: tuft, flowers, pebbles, shells, starfish, fern, leaves, mushroom, bones, skull, pages, ash."""
    names = ["tuft", "flowers", "pebbles", "shells", "starfish", "fern", "leaves", "mushroom", "bones", "skull", "pages", "ash"]
    S = 16
    sheet = np.zeros((S, S * len(names), 4), dtype=np.uint8)
    r = np.random.default_rng(3)

    def put(img, x, y, c):
        if 0 <= x < S and 0 <= y < S:
            img[y, x] = (*c, 255)

    for i, n in enumerate(names):
        img = np.zeros((S, S, 4), dtype=np.uint8)
        if n in ("tuft", "fern"):
            for b in range(5 if n == "tuft" else 4):
                x0 = 4 + b * 2
                h = r.integers(4, 9)
                lean = r.integers(-1, 2)
                for k in range(h):
                    put(img, x0 + (lean * k) // 3, 15 - k, (255, 255, 255) if k < h - 1 else (200, 200, 200))
        elif n == "flowers":
            for b in range(3):
                x0, h = 4 + b * 4, r.integers(3, 6)
                for k in range(h):
                    put(img, x0, 15 - k, (180, 180, 180))
                for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, -1), (0, 1)):
                    put(img, x0 + dx, 15 - h + dy, (255, 0, 0) if (dx, dy) != (0, 0) else (255, 255, 0))
        elif n == "pebbles":
            for b in range(3):
                x0, y0 = r.integers(3, 12), r.integers(11, 15)
                put(img, x0, y0, (200, 200, 200))
                put(img, x0 + 1, y0, (160, 160, 160))
        elif n == "shells":
            for b in range(2):
                x0, y0 = r.integers(4, 11), r.integers(11, 14)
                for dx in range(3):
                    put(img, x0 + dx, y0, (255, 230, 220))
                put(img, x0 + 1, y0 - 1, (255, 200, 190))
        elif n == "starfish":
            c = (250, 140, 90)
            for d in range(-2, 3):
                put(img, 8 + d, 12, c)
                put(img, 8, 12 + d, c)
        elif n == "leaves":
            for b in range(5):
                x0, y0 = r.integers(2, 13), r.integers(10, 15)
                put(img, x0, y0, (255, 0, 0))
                put(img, x0 + 1, y0, (200, 0, 0))
        elif n == "mushroom":
            put(img, 8, 14, (230, 220, 200))
            put(img, 8, 13, (230, 220, 200))
            for dx in range(-1, 2):
                put(img, 8 + dx, 12, (255, 0, 0))
            put(img, 8, 11, (255, 0, 0))
        elif n == "bones":
            for dx in range(-3, 4):
                put(img, 8 + dx, 13 + (dx // 3), (240, 232, 214))
            put(img, 5, 12, (240, 232, 214))
            put(img, 11, 15, (240, 232, 214))
        elif n == "skull":
            for dy in range(3):
                for dx in range(4):
                    put(img, 6 + dx, 11 + dy, (240, 232, 214))
            put(img, 7, 12, (50, 40, 50))
            put(img, 9, 12, (50, 40, 50))
        elif n == "pages":
            for dy in range(3):
                for dx in range(4):
                    put(img, 5 + dx, 12 + dy, (240, 236, 224))
            put(img, 6, 13, (120, 120, 130))
            put(img, 7, 13, (120, 120, 130))
        elif n == "ash":
            for b in range(6):
                put(img, r.integers(3, 13), r.integers(10, 15), (170, 170, 176))
        sheet[:, i * S:(i + 1) * S] = img
    Image.fromarray(sheet, "RGBA").save(os.path.join(OUT, "deco.png"))
    json.dump({"names": names, "size": S}, open(os.path.join(OUT, "deco.json"), "w"))


def blob_shadow():
    S = 32
    img = np.zeros((S // 2, S, 4), dtype=np.uint8)
    for y in range(S // 2):
        for x in range(S):
            dx = (x - S / 2 + 0.5) / (S / 2)
            dy = (y - S / 4 + 0.5) / (S / 4)
            d = dx * dx + dy * dy
            if d < 1.0:
                img[y, x] = (40, 30, 60, 110 if d < 0.55 else 70)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "shadow.png"))


def tile_marker():
    """16x16 tile overlay: filled with a 1px border (white; tinted in game)."""
    S = 24
    img = np.zeros((S, S, 4), dtype=np.uint8)
    img[:, :] = (255, 255, 255, 60)
    img[0, :] = img[-1, :] = img[:, 0] = img[:, -1] = (255, 255, 255, 230)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "tile_marker.png"))


def noise_tex():
    n = (fbm(64, 99, ((4, 0.4), (8, 0.3), (16, 0.3))) * 255).astype(np.uint8)
    Image.fromarray(n, "L").save(os.path.join(OUT, "noise.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    build_ground_atlas()
    build_prop_palettes()
    deco_sprites()
    blob_shadow()
    tile_marker()
    noise_tex()
    print("[textures] done")


if __name__ == "__main__":
    main()
