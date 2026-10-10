"""Faction emblems: hand-placed pixel art for the four factions of Ambral.

Every emblem is a round seal (a bevelled rim around an inset field) with the
faction's sign laid over it. Signs are drawn as letter grids, one per size, where
each letter names a material. Most grids hold only the left half and are mirrored;
the shading (light from the top left), outlines, glow and drop shadows are then
worked out per pixel, so all sizes share one look.

Output (via ui_art.build_emblems): assets/sprites/ui/emblem_<faction>_<size>.png
"""
import math
from PIL import Image

INK = (24, 16, 24, 255)
BAYER = ((0, 2), (3, 1))
RINGS = (16, 32)  # sizes that get automatic ink rings (a faction may override); other grids place their ink by hand


def _c(*cols):
    return [tuple(c) + (255,) for c in cols]


# material keys: ramp (dark -> light), base tone, z (draw order), bevel, inset (lit from below),
# outline (ink ring drawn on lower materials), glow (halo radius on the field), grad (tone steps from
# bottom to top, dithered where the bands meet if dither), shadow (darkened under-right of higher
# materials), clip (only drawn over the field)
def M(ramp, base=2, z=0, bevel=True, inset=False, outline=False, glow=0, grad=0.0, dither=False, shadow=False, clip=False):
    return dict(ramp=ramp, base=base, z=z, bevel=bevel, inset=inset, outline=outline, glow=glow, grad=grad, dither=dither,
                shadow=shadow, clip=clip)


# the scarab's wing cases: a left and a right twin, so the seam between them is shaded
SHELL = M(_c((40, 22, 52), (80, 40, 96), (132, 70, 148), (186, 112, 196), (232, 172, 236)), z=3, outline=True)


# radii of the seal per size: (outer edge of the rim, inner edge of the rim)
SEAL = {12: (4.9, 3.9), 16: (6.7, 5.4), 32: (14.6, 12.1)}

FACTIONS = {
    # ------------------------------------------------------------------ Saltborn Compact
    # a glowing memory-jellyfish in a verdigris porthole
    "saltborn": {
        "mat": {
            "rim": M(_c((24, 56, 62), (38, 92, 92), (64, 140, 128), (112, 190, 164), (184, 232, 200)), z=1),
            "field": M(_c((10, 16, 40), (16, 30, 62), (22, 46, 86), (30, 66, 110), (40, 90, 132)), base=1, inset=True, grad=2.2, dither=True, shadow=True),
            "jelly": M(_c((40, 92, 150), (70, 150, 206), (120, 206, 240), (190, 240, 255), (245, 255, 255)), z=3, glow=2, grad=1.4),
            "pink": M(_c((120, 54, 112), (196, 96, 160), (240, 150, 196), (255, 206, 228)), z=4),
            "tent": M(_c((44, 104, 156), (84, 166, 214), (140, 222, 244), (206, 248, 255)), base=2, z=2, bevel=False),
        },
        "legend": {
            "J": ("jelly", 0), "j": ("jelly", -1), "*": ("jelly", (250, 255, 255, 255)),
            "P": ("pink", 0), "F": ("pink", 0), "A": ("pink", -1), "T": ("tent", 0),
            "r": ("rim", (214, 246, 222, 255)), "q": ("rim", (24, 56, 62, 255)),
            "o": ("field", (120, 200, 228, 255)), "O": ("field", (70, 140, 180, 255)),
        },
        "art": {
            32: [
                "................",
                "................",
                "...............r",
                "...............q",
                "................",
                "................",
                "......r.......JJ",
                "......q.....JJJJ",
                "..........JJJJJJ",
                ".........JJJJJJJ",
                "........J**JJJJJ",
                ".......JJ*JJJJJJ",
                ".......JJJJJJJPP",
                "......JJJJJJJPPP",
                "......JJJJJJJJPP",
                "..r...jjjjjjjjjj",
                "..q...FFFFFFFFFF",
                "......F.FF.FF.FF",
                "........T..T.AA..AA.T..T........",
                "........T..T.AA..AA.T..T........",
                ".......T..T.AA..AA.T..T.........",
                ".......T..T.AA..AA.T..T.........",
                ".......T..T.AA..AA.T..T.........",
                "........T..T.AA..AA.T..T........",
                "........T..T.A...A..T..T........",
                "......r.....T........T...r......",
                "......q.....T........T...q......",
                "................",
                "...............r",
                "...............q",
                "................",
            ],
            16: [
                "........",
                "........",
                "........",
                "......JJ",
                ".....JJJ",
                "....J*JJ",
                "....JJJP",
                "....jjjj",
                "....F.FF",
                ".....T.A",
                ".....T.A",
                "......T.",
                "........",
                "........",
                "........",
                "........",
            ],
            12: [
                "............",
                "............",
                "....JJJJ....",
                "...J*JJJJ...",
                "..JJJPPJJJ..",
                "..jjjjjjjj..",
                "..T.T..T.T..",
                "...T.T..T.T.",
                "..T.T..T.T..",
                "............",
                "............",
                "............",
            ],
        },
        "extra": {32: [(24, 8, "o"), (26, 11, "O"), (8, 8, "O")]},
    },
    # ------------------------------------------------------------------ Lantern Conclave
    # a lit lantern carried on moth wings, under a night sky
    "lantern": {
        "mat": {
            "rim": M(_c((92, 56, 38), (146, 96, 46), (204, 152, 60), (240, 200, 96), (255, 238, 168)), z=1),
            "field": M(_c((14, 10, 34), (24, 18, 54), (36, 28, 78), (50, 40, 102), (66, 54, 126)), base=1, inset=True, grad=1.6, dither=True, shadow=True),
            "wing": M(_c((58, 36, 88), (96, 64, 132), (142, 104, 178), (188, 154, 214), (228, 208, 240)), z=2, outline=True),
            "band": M(_c((140, 108, 96), (196, 166, 136), (234, 214, 180), (252, 240, 214)), base=1, z=2, outline=True),
            "frame": M(_c((50, 30, 28), (96, 60, 40), (156, 106, 54), (212, 164, 78), (244, 214, 130)), z=4, outline=True),
            "light": M(_c((236, 160, 60), (252, 206, 104), (255, 236, 160), (255, 252, 226)), base=1, z=5, bevel=False, glow=3),
            "feeler": M(_c((50, 30, 28), (96, 60, 40), (156, 106, 54), (212, 164, 78)), base=2, z=2, bevel=False),
        },
        "legend": {
            "W": ("wing", 0), "w": ("band", 0), "V": ("wing", -1), "E": ("wing", (44, 24, 56, 255)), "e": ("wing", (246, 204, 110, 255)),
            "G": ("frame", 0), "L": ("light", 0), "l": ("light", 1), "H": ("light", (255, 255, 248, 255)), "a": ("feeler", 0),
            "s": ("field", (200, 196, 236, 255)), "t": ("field", (120, 112, 176, 255)),
        },
        "art": {
            32: [
                "................",
                "..........a.....",
                "...........a....",
                "............a...",
                ".............a..",
                "..ww..........GG",
                ".wwWWww......G..",
                "wwWWWWWWW....G..",
                "wWWEEWWWWW..GGGG",
                "wWEeeEWWWW.GGGGG",
                ".wEeeEWWVW.G####",
                ".wWEEWWVWW.G#HLL",
                "..wWWWVWWW.G#HLl",
                "..wWWVWWWW.G#LLl",
                "...wwWWWWW.G#LLl",
                "....wwwWWW.G#LLL",
                ".......wWW.G#LLL",
                ".....wwWWW.G####",
                "....wWWWWW.GGGGG",
                "....wWEWWW..GGGG",
                "....wWWWWW...GGG",
                ".....wWWWW....GG",
                "......wwWW......",
                ".......ww.......",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ],
            16: [
                "................",
                "................",
                "................",
                "..w....GG....w..",
                ".wWW..GGGG..WWw.",
                ".wWeWGGGGGGWeWw.",
                "..wWWGHLLLGWWw..",
                "...WWGHLlLGWW...",
                "...wWGLLLLGWw...",
                "..wWWGLLLLGWWw..",
                "..wWeGGGGGGeWw..",
                "...ww.GGGG.ww...",
                ".......GG.......",
                "................",
                "................",
                "................",
            ],
            12: [
                "............",
                ".....##.....",
                ".w..#GG#..w.",
                ".WW#GGGG#WW.",
                ".We#GHLG#eW.",
                ".wW#GLlG#Ww.",
                "..W#GLLG#W..",
                "..w#GGGG#w..",
                "....#GG#....",
                ".....##.....",
                "............",
                "............",
            ],
        },
        "shift": {32: (0, 3)},
        "extra": {32: [(9, 25, "s"), (22, 26, "t"), (6, 22, "t")]},
    },
    # ------------------------------------------------------------------ Rootwardens
    # an autumn maple leaf whose stem roots into the Ember Wood
    "rootwardens": {
        "mat": {
            "rim": M(_c((52, 30, 26), (86, 52, 34), (128, 80, 46), (172, 114, 62), (212, 156, 92)), z=1),
            "field": M(_c((26, 14, 18), (42, 24, 26), (62, 34, 30), (86, 46, 34), (112, 60, 38)), base=1, inset=True, grad=1.6, dither=True, shadow=True),
            "leaf": M(_c((112, 30, 30), (170, 56, 34), (214, 100, 42), (242, 154, 60), (255, 206, 112)), z=3, outline=True, grad=1.6),
            "wood": M(_c((92, 66, 56), (146, 114, 88), (200, 168, 126), (234, 212, 168)), z=2),
        },
        "legend": {
            "L": ("leaf", 0), "v": ("leaf", -2), "S": ("wood", 0), "R": ("wood", 0),
            "k": ("field", (255, 198, 96, 255)), "K": ("field", (196, 102, 50, 255)),
        },
        "art": {
            32: [
                "................",
                "................",
                "................",
                "...............L",
                "..............LL",
                "..............LL",
                ".............LLL",
                "......L....L.LLL",
                "......LL...LLLLv",
                ".......LL..LLLLv",
                "...L...LLL.LLLLv",
                "...LLL.LLLLLLLLv",
                "....LLLLvLLLLLLv",
                ".LLLLLLLLvLLLLLv",
                "..LLLLLLLLvLLLLv",
                "...LLLLLLLLvLLLv",
                "....LLLLLLLLvLLv",
                "..LLLLLLvvvvvvvv",
                "...LLLLvLLLLLLLv",
                "....LLvLLLLLLLLv",
                ".....vLLLLL..LLv",
                "......LLLL.....S",
                "...............S",
                "..............SS",
                ".............R.S",
                "............R..R",
                "................",
                "................",
                "................",
                "................",
                "................",
                "................",
            ],
            16: [
                "........",
                "........",
                ".......L",
                "......LL",
                "...L..LL",
                "...LL.LL",
                ".L.LLLLL",
                ".LLLLLLL",
                "..LLLLLL",
                "...LLLLL",
                "..LLLL.L",
                "...LL..S",
                ".......S",
                "........",
                "........",
                "........",
            ],
            12: [
                "......",
                ".....L",
                ".....L",
                "..L.LL",
                "..LLLL",
                ".LLLLL",
                "..LLLL",
                "...LLL",
                "..LL.L",
                ".....S",
                ".....S",
                "......",
            ],
        },
        "shift": {32: (0, 1)},
        "rings": (12, 16, 32),
        "extra": {32: [(7, 24, "k"), (24, 22, "K"), (22, 7, "K")]},
    },
    # ------------------------------------------------------------------ Glass Caravans
    # a scarab rolling a glass sun over the Sunken Dunes
    "glass": {
        "mat": {
            "rim": M(_c((62, 26, 58), (106, 46, 98), (156, 82, 152), (198, 124, 200), (236, 184, 234)), z=1),
            "field": M(_c((30, 14, 40), (48, 22, 60), (72, 34, 80), (102, 50, 98), (138, 70, 112)), base=1, inset=True, grad=-1.8, dither=True, shadow=True),
            "sand": M(_c((112, 64, 66), (164, 100, 84), (208, 146, 104), (236, 194, 136)), base=1, z=1, clip=True),
            "shell": SHELL,
            "shell~": SHELL,
            "pron": M(_c((36, 20, 46), (70, 36, 84), (112, 60, 128), (162, 98, 176), (214, 156, 222)), z=3, outline=True),
            "head": M(_c((30, 18, 36), (56, 34, 62), (92, 60, 96), (136, 98, 136)), z=3, outline=True),
            "leg": M(_c((40, 24, 30), (96, 60, 52), (150, 102, 74), (200, 152, 100)), base=2, z=2, bevel=False, outline=True),
            "glass": M(_c((28, 96, 120), (60, 164, 184), (128, 226, 230), (208, 255, 252), (255, 255, 255)), z=4, outline=True, glow=2),
        },
        "legend": {
            "B": ("shell", 0), "c": ("shell", (170, 240, 236, 255)), "Q": ("pron", 0), "q": ("pron", (210, 250, 244, 255)),
            "H": ("head", 0), "D": ("leg", 0), "g": ("glass", 0), "h": ("glass", (255, 255, 255, 255)),
            "n": ("sand", 0), "N": ("sand", -1),
        },
        "art": {
            32: [
                "................",
                "................",
                "................",
                "..............gg",
                ".............hgg",
                "............hggg",
                "............gggg",
                "...........Dgggg",
                "..........D.gggg",
                ".........D...ggg",
                ".........D....gg",
                ".........D..H...",
                "..........D.HHHH",
                "...........D.HHH",
                "...........QQQQQ",
                "..........QqQQQQ",
                "..........QQQQQQ",
                ".......DDDQQQQQQ",
                "......D..BBBBBBB",
                "....nD..BBBBBBBB",
                "....nnn.BcBBBBBB",
                "....nnnnBcBBBBBB",
                "....nnnnBBBBBBBB",
                "nnnnnnDDBBBBBBBB",
                "nnnnnD.nnBBBBBBB",
                "nnnnnDnnnBBBBBBB",
                "nnNNnnnnnnBBBBBB",
                "nnnnnnnnnnnnBBBB",
                "nnnnnnnnnnnnnnnn",
                "nnnnnnnnnnnnnnnn",
                "nnnnnnnnnnnnnnnn",
                "nnnnnnnnnnnnnnnn",
            ],
            16: [
                "........",
                "........",
                "......gg",
                ".....hgg",
                ".....Dgg",
                ".....D.H",
                "......QQ",
                "....DBBB",
                ".....BcB",
                "....DBBB",
                "nnn..BBB",
                "nnnnnnnB",
                "nnnnnnnn",
                "nnnnnnnn",
                "nnnnnnnn",
                "nnnnnnnn",
            ],
            12: [
                "............",
                ".....##.....",
                "....#gg#....",
                "...#ghgg#...",
                "....#gg#....",
                "...D#HH#D...",
                "...#BBBB#...",
                "..D#BcBB#D..",
                "..nn#BB#nn..",
                "...nn##nn...",
                "............",
                "............",
            ],
        },
    },
}


def _grid(rows, w):
    """Rows of half width are mirrored around the centre; full rows are used as they are."""
    out = []
    for r in rows:
        out.append(r + r[::-1] if len(r) * 2 == w else r)
    return out


def draw(name, size):
    """One faction emblem at 12, 16 or 32 px (64 is the 32 doubled)."""
    if size == 64:
        return draw(name, 32).resize((64, 64), Image.NEAREST)
    spec = FACTIONS[name]
    mats, legend = dict(spec["mat"], ink=M([INK], base=0, z=9, bevel=False)), spec["legend"]
    W = H = size
    mat = [[None] * W for _ in range(H)]
    off = [[0] * W for _ in range(H)]
    fixed = {}
    # the seal
    r_out, r_in = SEAL[size]
    c = (size - 1) / 2
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - c, y - c)
            if d <= r_out:
                mat[y][x] = "rim" if d > r_in else "field"
    # the sign
    sx, sy = spec.get("shift", {}).get(size, (0, 0))
    rows = _grid(spec["art"][size], W)
    cells = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            cells.append((x, y, ch))
    # extras are lone asymmetric touches, placed in seal coordinates
    for (x, y, ch) in spec.get("extra", {}).get(size, []):
        cells.append((x - sx, y - sy, ch))
    for (x, y, ch) in cells:
        X, Y = x + sx, y + sy
        if ch == "." or not (0 <= X < W and 0 <= Y < H):
            continue
        m, o = ("ink", 0) if ch == "#" else legend[ch]
        if mats[m]["clip"] and mat[Y][X] != "field":
            continue
        # split materials take their right-hand twin, so the seam down the middle gets shaded
        if X >= W // 2 and m + "~" in mats:
            m = m + "~"
        mat[Y][X] = m
        if isinstance(o, tuple):
            fixed[(X, Y)] = o
            off[Y][X] = 0
        else:
            off[Y][X] = o

    def at(x, y):
        return mat[y][x] if 0 <= x < W and 0 <= y < H else None

    def z(m):
        return mats[m]["z"] if m else -1

    # vertical extent of each material, for gradients
    span = {}
    for y in range(H):
        for x in range(W):
            m = mat[y][x]
            if m:
                lo, hi = span.get(m, (y, y))
                span[m] = (min(lo, y), max(hi, y))
    # glow sources
    glows = [(x, y, mats[mat[y][x]]["glow"]) for y in range(H) for x in range(W) if mat[y][x] and mats[mat[y][x]]["glow"]]

    tone = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            m = mat[y][x]
            if not m:
                continue
            P = mats[m]
            t = P["base"] + off[y][x]
            if P["bevel"]:
                lit = at(x, y - 1) != m or at(x - 1, y) != m
                dark = at(x, y + 1) != m or at(x + 1, y) != m
                if P["inset"]:
                    lit, dark = dark, lit
                if lit and not dark:
                    t += 1
                elif dark and not lit:
                    t -= 1
            if P["grad"]:
                lo, hi = span[m]
                rel = (y - lo) / max(1, hi - lo)
                b = ((BAYER[y % 2][x % 2] + 0.5) / 4 - 0.5) * 0.5 if P["dither"] else 0
                t += math.floor(P["grad"] * (0.5 - rel) + 0.5 + b)
            if m == "field" and glows:
                best = min(math.hypot(x - gx, y - gy) / g for gx, gy, g in glows)
                if best <= 0.75:
                    t += 2
                elif best <= 1.0:
                    t += 1
            tone[y][x] = t

    # ink rings around raised materials, drawn on the lower neighbour
    ring = set()
    for y in range(H if size in spec.get("rings", RINGS) else 0):
        for x in range(W):
            m = mat[y][x]
            if not m:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = at(x + dx, y + dy)
                if n and mats[n]["outline"] and z(n) > z(m) and n.rstrip("~") != m.rstrip("~"):
                    ring.add((x, y))
                    break
    # drop shadow under-right of raised things
    for y in range(H):
        for x in range(W):
            m = mat[y][x]
            if not m or (x, y) in ring or not mats[m]["shadow"]:
                continue
            ul = at(x - 1, y - 1)
            if (x - 1, y - 1) in ring or (ul and z(ul) > z(m)):
                tone[y][x] -= 1

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            m = mat[y][x]
            if not m:
                continue
            if (x, y) in ring:
                px[x, y] = INK
            elif (x, y) in fixed:
                px[x, y] = fixed[(x, y)]
            else:
                ramp = mats[m]["ramp"]
                px[x, y] = ramp[max(0, min(len(ramp) - 1, tone[y][x]))]
    # outer ink line
    edge = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < W and 0 <= y + dy < H and px[x + dx, y + dy][3] and px[x + dx, y + dy] != INK:
                    edge.append((x, y))
                    break
    for (x, y) in edge:
        px[x, y] = INK
    return img
