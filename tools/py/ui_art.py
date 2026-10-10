"""Pixel-art UI: panels, buttons, frames, skill/stat/status/resource icons,
faction emblems, the guild emblem, cursors and the map of Ambral.

Output: assets/sprites/ui/*.png (+ icons.json)
"""
import os
import json
import math
import colorsys
import numpy as np
from PIL import Image, ImageDraw

import emblems

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "ui")


def shade(rgb, k):
    r, g, b = [c / 255 for c in rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if k < 1:
        h = h + ((0.72 - h + 0.5) % 1 - 0.5) * (1 - k) * 0.4
    else:
        h = h + ((0.14 - h + 0.5) % 1 - 0.5) * (k - 1) * 0.4
    rr, gg, bb = colorsys.hsv_to_rgb(h % 1, min(1, s * (1.1 if k < 1 else 0.85)), min(1, v * k))
    return (int(rr * 255), int(gg * 255), int(bb * 255), 255)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


# ====================================================================== panels
def panel(fill, light, dark, edge, size=24, inner=True, name="panel"):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for y in range(size):
        for x in range(size):
            corner = (x in (0, size - 1)) and (y in (0, size - 1))
            if corner:
                continue
            if x == 0 or y == 0 or x == size - 1 or y == size - 1:
                px[x, y] = rgba(edge)
            elif inner and (x == 1 or y == 1):
                px[x, y] = rgba(light)
            elif inner and (x == size - 2 or y == size - 2):
                px[x, y] = rgba(dark)
            else:
                px[x, y] = rgba(fill)
    # subtle texture in the fill
    rng = np.random.default_rng(len(name))
    for _ in range(size):
        x, y = rng.integers(3, size - 3), rng.integers(3, size - 3)
        px[int(x), int(y)] = shade(fill, 0.93 if rng.random() < 0.5 else 1.05)
    img.save(os.path.join(OUT, name + ".png"))


def frame_gold(size=24, name="frame_gold"):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, size - 1], outline=(40, 26, 30, 255))
    d.rectangle([1, 1, size - 2, size - 2], outline=(216, 170, 84, 255))
    d.rectangle([2, 2, size - 3, size - 3], outline=(120, 84, 48, 255))
    d.rectangle([3, 3, size - 4, size - 4], fill=(44, 34, 42, 255))
    for (x, y) in ((1, 1), (size - 2, 1), (1, size - 2), (size - 2, size - 2)):
        img.putpixel((x, y), (250, 226, 150, 255))
    img.save(os.path.join(OUT, name + ".png"))


def button(base, name):
    for state, k, off in (("normal", 1.0, 0), ("hover", 1.15, 0), ("pressed", 0.85, 1), ("disabled", 0.7, 0)):
        size = 16
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = img.load()
        b = base if state != "disabled" else (int(sum(base) / 3),) * 3
        fill = shade(b, k)
        for y in range(size):
            for x in range(size):
                if (x in (0, size - 1)) and (y in (0, size - 1)):
                    continue
                if x == 0 or y == 0 or x == size - 1 or y == size - 1:
                    px[x, y] = (26, 18, 26, 255)
                elif y == 1 + off:
                    px[x, y] = shade(b, k * 1.3)
                elif y >= size - 3 + off:
                    px[x, y] = shade(b, k * 0.62)
                elif y == 1 and off:
                    px[x, y] = shade(b, k * 0.6)
                else:
                    px[x, y] = fill
        img.save(os.path.join(OUT, f"{name}_{state}.png"))


def bars():
    # hp bar frame 3px tall pieces: fill colours drawn in code; here a frame
    img = Image.new("RGBA", (8, 5), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 7, 4], fill=(22, 16, 24, 255))
    d.rectangle([1, 1, 6, 3], fill=(58, 44, 56, 255))
    img.save(os.path.join(OUT, "bar_bg.png"))


# ====================================================================== glyphs (12x12)
G = {
    "sword": ["..........##", ".........#+#", "........#+#.", ".......#+#..", "......#+#...", "..#..#+#....", "...##+#.....",
              "...##o......", "..#o##......", ".#o..#......", "#o..........", "o..........."],
    "dagger": ["............", "........##..", ".......#+#..", "......#+#...", ".....#+#....", "....#+#.....", "..#o+#......",
               "...##.......", "..#o#.......", ".#o.........", "............", "............"],
    "bow": ["......##....", ".....#..#...", "....#....#..", "...#.....#..", "...#....+##+", "..#.....#...", "..#....+....", "..#...+#....",
            "...#.+.#....", "...#+.#.....", "....##......", "...+........"],
    "orb": ["....####....", "...#++++#...", "..#+#+++##..", ".#+#++++++#.", ".#+++++++##.", ".#++++++###.", ".#+++++####.", ".##++#####..",
            "..######....", "...####.....", "....oo......", "..oooooo...."],
    "shield": ["..########..", ".#++++++++#.", ".#+######+#.", ".#+#++++#+#.", ".#+#++++#+#.", ".#+######+#.", ".#++++++++#.", "..#+++++++#.",
               "..#+++++#...", "...#+++#....", "....#+#.....", ".....#......"],
    "heart": ["............", "..###..###..", ".#+++##+++#.", "#++++++++++#", "#++++++++++#", "#++++++++++#", ".#++++++++#.", "..#++++++#..",
              "...#++++#...", "....#++#....", ".....##.....", "............"],
    "cross": ["....####....", "....#++#....", "....#++#....", "....#++#....", "####+++++###", "#++++++++++#", "#++++++++++#", "####++++####",
              "....#++#....", "....#++#....", "....#++#....", "....####...."],
    "skull": ["...######...", "..#++++++#..", ".#++++++++#.", ".#+oo++oo+#.", ".#+oo++oo+#.", ".#++++++++#.", "..#+++o++#..", "...#+++++#..",
              "...#+#+#+#..", "....#.#.#...", "............", "............"],
    "arrow": ["............", "........###.", ".........##.", "........#.#.", ".......#....", "......#.....", ".....#......", "....#.......",
              "...#........", ".+#.........", "++..........", "+..........."],
    "flame": [".....#......", ".....##.....", "....#+#.....", "...#++#..#..", "..#+++##.##.", "..#++++#+#..", ".#++oo++++#.", ".#+oooo+++#.",
              ".#+oooo+++#.", "..#+oo+++#..", "...#####....", "............"],
    "snow": [".....#......", "...#.#.#....", "....###.....", ".#..###..#..", "..#.###.#...", "#####+#####.", "..#.###.#...", ".#..###..#..",
             "....###.....", "...#.#.#....", ".....#......", "............"],
    "bolt": ["......###...", ".....###....", "....###.....", "...###......", "..#######...", ".....###....", "....###.....", "...###......",
             "..###.......", ".##.........", "#...........", "............"],
    "leaf": ["........####", "......##+++#", ".....#++++##", "....#+++#+#.", "...#+++#++#.", "..#+++#++#..", "..#++#++#...", "..#+#++#....",
             "...##+#.....", "..#.##......", ".#..........", "#..........."],
    "eye": ["............", "............", "...######...", "..#++++++#..", ".#++####++#.", "#++#oo+#++#.", "#++#oo##++#.", ".#++####++#.",
            "..#++++++#..", "...######...", "............", "............"],
    "star": [".....#......", ".....#......", "....#+#.....", "....#+#.....", "###+++++###.", ".#+++++++#..", "..#+++++#...", "..#++#++#...",
             ".#++#.#++#..", ".##.....##..", "............", "............"],
    "wave": ["............", "....###.....", "...#+++#....", "..#++##+#...", ".#+##..#+#..", "..#......#.#", "....###...#.", "...#+++#....",
             "..#++##+#...", ".#+##..#+#..", "#.......#+#.", "..........#."],
    "lantern": ["....####....", "....#..#....", "...######...", "...#++++#...", "..#+#++#+#..", "..#++++++#..", "..#+#++#+#..", "..#++++++#..",
                "...#++++#...", "...######...", "....####....", "............"],
    "moon": ["....####....", "..##++##....", ".#++##......", ".#+#........", "#++#........", "#++#........", "#++#........", ".#+#........",
             ".#++##.....#", "..##++####..", "....####....", "............"],
    "fist": ["............", "...##.##....", "..#++#++##..", "..#++#++#+#.", "..#++#++#+#.", "..#+++++#+#.", "..#++++++++#", "..#+++++++#.",
             "...#+++++#..", "...#+++++#..", "...######...", "............"],
    "boot": ["............", "...####.....", "...#++#.....", "...#++#.....", "...#++#.....", "...#++#.....", "...#++####..", "...#++++++#.",
             "...#+++++++#", "...#########", "............", "............"],
    "drop": [".....#......", ".....#......", "....#+#.....", "....#+#.....", "...#+++#....", "..#++++o#...", "..#+++++#...", ".#+++++o+#..",
             ".#++++oo+#..", "..#++oo+#...", "...#####....", "............"],
    "claw": ["#.....#.....", "#.....#...#.", "#.#...#...#.", "#.#...#..#..", ".##..#..#...", ".#.#.#.#....", "..#.#.#.....", "..#.#.#.....",
             "...#.#......", "...#.#......", "............", "............"],
    "cloud": ["............", "....###.....", "...#+++#....", "..#+++++###.", ".#+++++++++#", "#+++++++++++", "#++++++++++#", ".##########.",
              "..#.#.#.#...", "...#.#.#....", "............", "............"],
    "spiral": ["..######....", ".#++++++#...", "#+######+#..", "#+#++++#+#..", "#+#+##+#+#..", "#+#+#.#+#+#.", "#+#+###+#+#.", "#+#++++#+#..",
               "#+#####+#...", ".#+++++#....", "..#####.....", "............"],
    "target": ["...######...", "..#++++++#..", ".#+######+#.", "#+#++++++#+#", "#+#+####+#+#", "#+#+#oo#+#+#", "#+#+#oo#+#+#", "#+#+####+#+#",
               "#+#++++++#+#", ".#+######+#.", "..#++++++#..", "...######..."],
    "banner": ["#...........", "#########...", "#+++++++#...", "#++###++#...", "#++#++#+#...", "#++###++#...", "#+++++++#...", "#++++++#....",
               "#+++++#.....", "#++++#......", "#...........", "#..........."],
    "roots": ["....#.......", "....#.......", "...###......", "..#.#.#.....", ".#..#..#....", "#..#.#..#...", "..#..#...#..", ".#...#....#.",
              "#...#.#.....", "...#...#....", "..#.....#...", "............"],
    "horn": ["..........#.", ".........##.", "........#+#.", ".......#+#..", "......#+#...", "....##+#....", "..##+++#....", ".#+++++#....",
             ".#++++#.....", "..####......", "............", "............"],
    "quill": ["..........##", ".........#+#", "........#++#", ".......#++#.", "......#++#..", ".....#++#...", "....#++#....", "...#+#......",
              "..##........", ".#..........", "#...........", "............"],
    "page": ["..#######...", "..#+++++##..", "..#+ooo++#..", "..#++++++#..", "..#+oooo+#..", "..#++++++#..", "..#+ooo++#..", "..#++++++#..",
             "..#+oooo+#..", "..#++++++#..", "..########..", "............"],
    "hour": ["..########..", "..#++++++#..", "...#++++#...", "....#++#....", ".....##.....", ".....##.....", "....#oo#....", "...#oooo#...",
             "..#oooooo#..", "..########..", "............", "............"],
    "foot": ["............", "....##......", "...#++#.##..", "...#++##++#.", "...#+++#++#.", "....#+++##..", "....#+++#...", "....#++#....",
             "..###++#....", ".#++++#.....", "..####......", "............"],
    "hand": ["....#.#.#...", "...#+#+#+#..", "...#+#+#+#..", "...#+#+#+#..", ".#.#++++++#.", "#+##++++++#.", ".#++++++++#.", "..#+++++++#.",
             "...#+++++#..", "....#####...", "............", "............"],
    "exit": ["#######.....", "#+++++#.....", "#+++++#..#..", "#+++++#..##.", "#+++++#####.", "#+++++#+++##", "#+++++#####.", "#+++++#..##.",
             "#+++++#..#..", "#+++++#.....", "#######.....", "............"],
    "wait": ["..########..", ".#++++++++#.", "#++++#+++++#", "#++++#+++++#", "#++++#+++++#", "#++++####++#", "#++++++++++#", "#++++++++++#",
             ".#++++++++#.", "..########..", "............", "............"],
}

ICON_MAP = {
    # name: (glyph, background colour)
    "sword": ("sword", "red"), "dagger": ("dagger", "red"), "bow": ("bow", "red"), "orb": ("orb", "violet"), "trident": ("wave", "teal"),
    "lantern": ("lantern", "gold"), "staff": ("fist", "red"), "glass": ("dagger", "teal"), "shield": ("shield", "blue"), "brace": ("shield", "blue"),
    "taunt": ("banner", "orange"), "bulwark": ("shield", "steel"), "last_stand": ("heart", "orange"), "cleave": ("sword", "orange"),
    "sunder": ("fist", "orange"), "rally": ("banner", "gold"), "execute": ("skull", "red"), "backstab": ("dagger", "violet"),
    "shadowstep": ("spiral", "violet"), "evasion": ("boot", "steel"), "smoke": ("cloud", "steel"), "assassinate": ("skull", "violet"),
    "poison": ("drop", "green"), "knives": ("dagger", "green"), "cripple": ("foot", "green"), "venom": ("cloud", "green"),
    "aimed": ("target", "red"), "steady": ("eye", "steel"), "pierce": ("arrow", "red"), "suppress": ("arrow", "orange"),
    "headshot": ("target", "violet"), "pin": ("arrow", "green"), "mark": ("target", "orange"), "volley": ("arrow", "orange"),
    "trap": ("claw", "green"), "mend": ("cross", "green"), "fire": ("flame", "orange"), "frost": ("snow", "teal"),
    "flame_wave": ("flame", "red"), "lightning": ("bolt", "gold"), "purify": ("star", "teal"), "ward": ("shield", "teal"),
    "sanctuary": ("cross", "gold"), "resurgence": ("heart", "green"), "knight": ("shield", "gold"), "shield_wall": ("shield", "gold"),
    "berserk": ("fist", "red"), "whirlwind": ("spiral", "red"), "assassin": ("skull", "violet"), "vanish": ("moon", "violet"),
    "riposte": ("sword", "steel"), "flurry": ("dagger", "orange"), "sharpshooter": ("eye", "gold"), "deadeye": ("target", "red"),
    "warden": ("eye", "blue"), "rain": ("arrow", "blue"), "pyro": ("flame", "gold"), "inferno": ("flame", "red"), "oracle": ("eye", "violet"),
    "foresight": ("hour", "violet"), "undertow": ("wave", "blue"), "riptide": ("wave", "teal"), "drown": ("drop", "blue"),
    "tidal": ("wave", "green"), "maelstrom": ("spiral", "blue"), "flare": ("star", "gold"), "reveal": ("eye", "gold"),
    "cleansing": ("lantern", "teal"), "memory": ("page", "gold"), "beacon": ("lantern", "orange"), "entangle": ("roots", "green"),
    "roots": ("roots", "steel"), "thorns": ("roots", "red"), "sap": ("leaf", "green"), "barkskin": ("shield", "green"), "grove": ("leaf", "orange"),
    "glass_edge": ("dagger", "teal"), "burrow": ("spiral", "gold"), "sandblast": ("cloud", "gold"), "dune": ("boot", "gold"),
    "shatter": ("star", "teal"), "claw": ("claw", "red"), "sting": ("drop", "violet"), "sling": ("orb", "orange"), "bite": ("claw", "orange"),
    "coil": ("spiral", "green"), "fear": ("skull", "violet"), "gore": ("horn", "red"), "charge": ("horn", "orange"), "cleaver": ("sword", "red"),
    "hush": ("moon", "steel"), "quill": ("quill", "steel"), "erase": ("page", "steel"),
    "iron_hide": ("shield", "steel"), "sentinel": ("eye", "steel"), "bastion": ("shield", "violet"), "battle_hunger": ("heart", "red"), "headlong": ("horn", "red"),
    "rampage": ("skull", "orange"), "unseen": ("moon", "steel"), "death_blossom": ("star", "violet"), "venom_mastery": ("drop", "teal"), "envenom": ("dagger", "teal"),
    "paralytic": ("bolt", "green"), "plague": ("skull", "green"), "keen_sight": ("eye", "green"), "ricochet": ("arrow", "teal"), "deaths_eye": ("eye", "red"),
    "covering_fire": ("arrow", "steel"), "predator": ("claw", "gold"), "kill_zone": ("target", "gold"), "arcane_focus": ("orb", "gold"), "frost_nova": ("snow", "blue"),
    "meteor": ("flame", "violet"), "serenity": ("moon", "teal"), "guardian_spirit": ("shield", "violet"), "rebirth": ("heart", "gold"), "tidal_wave": ("wave", "blue"),
    "flowing_tides": ("wave", "steel"), "drowning_depths": ("drop", "violet"), "surge": ("bolt", "teal"), "tsunami": ("wave", "violet"), "saltblood": ("drop", "red"),
    "barbed_harpoon": ("horn", "teal"), "anchor": ("hand", "blue"), "second_wind": ("heart", "teal"), "kraken": ("spiral", "violet"), "salt_scar": ("shield", "teal"),
    "tidal_surge": ("wave", "orange"), "leviathan": ("claw", "blue"), "call_deep": ("spiral", "teal"), "far_light": ("lantern", "blue"), "searing": ("star", "orange"),
    "sunburst": ("star", "red"), "wicklight": ("flame", "teal"), "judgement": ("sword", "gold"), "dawn": ("star", "violet"), "kindle": ("flame", "gold"),
    "lantern_ward": ("lantern", "steel"), "remembrance": ("page", "violet"), "lamplighter": ("lantern", "green"), "mass_recall": ("page", "blue"), "shepherd": ("hand", "gold"),
    "keeper": ("quill", "gold"), "unforgetting": ("page", "red"), "bark_hide": ("shield", "orange"), "ancient_bark": ("leaf", "steel"), "verdant": ("leaf", "teal"),
    "heartwood": ("heart", "orange"), "sacred_grove": ("leaf", "gold"), "evergreen": ("leaf", "blue"), "world_tree": ("roots", "gold"), "thorn_lash": ("roots", "orange"),
    "thornmail": ("shield", "red"), "vine_snare": ("roots", "teal"), "bramble": ("roots", "violet"), "rootquake": ("fist", "green"), "impale": ("horn", "green"),
    "thornstorm": ("spiral", "orange"), "sandstep": ("foot", "gold"), "mirage": ("moon", "gold"), "sand_tomb": ("hour", "gold"), "dust_devil": ("spiral", "steel"),
    "dune_ambush": ("claw", "violet"), "sunken_strike": ("sword", "violet"), "shard_toss": ("dagger", "blue"), "razor": ("sword", "teal"), "glass_flurry": ("star", "blue"),
    "fracture": ("fist", "teal"), "glass_heart": ("heart", "violet"), "bleeding_edge": ("drop", "orange"), "kiln": ("flame", "steel"), "thousand_shards": ("star", "green"),
    "defend": ("shield", "blue"), "overwatch": ("eye", "orange"), "wait": ("wait", "steel"), "end_turn": ("hour", "steel"),
    "stabilize": ("cross", "red"), "carry": ("hand", "steel"), "extract": ("exit", "green"), "interact": ("hand", "gold"), "move": ("foot", "blue"),
}
BG = {"red": (150, 58, 52), "orange": (176, 102, 44), "gold": (170, 136, 52), "green": (70, 128, 66), "teal": (48, 120, 128),
      "blue": (58, 86, 150), "violet": (104, 66, 140), "steel": (96, 100, 116)}


def draw_icon(glyph, bg, size=16):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    base = BG[bg]
    for y in range(size):
        for x in range(size):
            if (x in (0, size - 1)) and (y in (0, size - 1)):
                continue
            if x == 0 or y == 0 or x == size - 1 or y == size - 1:
                px[x, y] = (24, 16, 24, 255)
            elif y <= 2:
                px[x, y] = shade(base, 1.15)
            elif y >= size - 3:
                px[x, y] = shade(base, 0.7)
            else:
                px[x, y] = shade(base, 0.9)
    rows = G[glyph]
    ox, oy = (size - 12) // 2, (size - 12) // 2
    light = (250, 244, 226, 255)
    mid = shade(base, 1.7)
    dark = shade(base, 0.45)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            X, Y = ox + x, oy + y
            if ch == "#":
                # drop shadow
                if 0 < X + 1 < size - 1 and 0 < Y + 1 < size - 1 and px[X + 1, Y + 1][3] and rows[min(11, y + 1)][min(11, x + 1)] == ".":
                    px[X + 1, Y + 1] = dark
                px[X, Y] = light
            elif ch == "+":
                px[X, Y] = mid
            elif ch == "o":
                px[X, Y] = dark
    return img


def build_icons():
    names = list(ICON_MAP.keys())
    sheet = Image.new("RGBA", (16 * len(names), 16), (0, 0, 0, 0))
    for i, n in enumerate(names):
        g, bg = ICON_MAP[n]
        sheet.paste(draw_icon(g, bg), (i * 16, 0))
    sheet.save(os.path.join(OUT, "icons.png"))
    return names


# ====================================================================== small icons (10x10)
SMALL = {
    "hp": ["..........", ".##..##...", "#++##++#..", "#++++++#..", "#++++++#..", ".#++++#...", "..#++#....", "...##.....", "..........", ".........."],
    "defense": [".######...", "#++++++#..", "#++++++#..", "#++++++#..", ".#++++#...", ".#++++#...", "..#++#....", "...##.....", "..........", ".........."],
    "dodge": ["......##..", ".....#+#..", "....#++#..", "...#++#...", "..#++#....", ".#++#.....", "#+##......", "##........", "..........", ".........."],
    "speed": ["...#......", "..#+#.....", ".#+++#....", "#+++++#...", "..#+#.....", "..#+#.....", "..#+#.....", "..###.....", "..........", ".........."],
    "move": ["..##......", ".#++#.##..", ".#++##++#.", "..#+#+++#.", "..#++++#..", "...#++#...", ".###++#...", "#++++#....", ".####.....", ".........."],
    "crit": ["....#.....", "...#+#....", "#######...", ".#+++#....", "..#+#.....", ".#+#+#....", "#.....#...", "..........", "..........", ".........."],
    "attack": [".......##.", "......#+#.", ".....#+#..", "....#+#...", ".#.#+#....", "..#+#.....", "..##......", ".#..#.....", "#.........", ".........."],
    "accuracy": ["..####....", ".#++++#...", "#+#++#+#..", "#++##++#..", "#++##++#..", "#+#++#+#..", ".#++++#...", "..####....", "..........", ".........."],
    "range": [".......#..", "......##..", ".....#.#..", "....#.....", "...#......", "..#.......", ".#........", "#.........", "..........", ".........."],
    "resolve": ["...#......", "...##.....", "..#+#.....", "..#++#....", ".#+++#....", ".#++++#...", ".#++++#...", "..####....", "..........", ".........."],
    "gold": ["..####....", ".#++++#...", "#++##++#..", "#+#++++#..", "#++##++#..", "#++++#+#..", ".#++++#...", "..####....", "..........", ".........."],
    "renown": ["....#.....", "...#+#....", "#######...", ".#+++#....", "..#+#.....", ".#+#+#....", "#.....#...", "..........", "..........", ".........."],
    "materials": ["..........", "..#####...", ".#+++++#..", "#+++++#+#.", "#######+#.", "#+++++#+#.", "#+++++##..", "#######...", "..........", ".........."],
    "hush": ["..####....", ".#++++#...", "#+#####+#.", "#+#+++#+#.", "#+#+#.#+#.", "#+##..#+#.", ".#+###+#..", "..#+++#...", "...###....", ".........."],
    "days": ["....#.....", ".#..#..#..", "..#####...", ".##+++##..", "##+++++##.", ".##+++##..", "..#####...", ".#..#..#..", "....#.....", ".........."],
    "skull": ["..####....", ".#++++#...", "#+#++#+#..", "#+#++#+#..", "#++++++#..", ".#+##+#...", ".#####....", "..........", "..........", ".........."],
    "week": ["#######...", "#+#+#+#...", "#######...", "#+++++#...", "#+#+#+#...", "#+++++#...", "#######...", "..........", "..........", ".........."],
    "roster": ["..##......", ".#++#.##..", ".#++##++#.", "..##.#++#.", ".####.##..", "#++++####.", "#+++##+++#", "#####.####", "..........", ".........."],
    "wage": ["..####....", ".#++++#...", "#++##++#..", "#+#++++#..", "#++##++#..", "#++++#+#..", ".#++++#...", "..####....", "..........", ".........."],
    "xp": ["....#.....", "...#+#....", "..#+++#...", ".#+++++#..", "...#+#....", "...#+#....", "...###....", "..........", "..........", ".........."],
    "cover_half": ["..........", "..........", "..........", "..######..", ".#++++++#.", ".#++++++#.", ".#++++++#.", "..######..", "..........", ".........."],
    "cover_full": ["..######..", ".#++++++#.", ".#++++++#.", ".#++++++#.", ".#++++++#.", ".#++++++#.", ".#++++++#.", "..######..", "..........", ".........."],
    "flank": ["....#.....", "...#+#....", "..#+++#...", ".#+++++#..", "#+++++++#.", "...#+#....", "...#+#....", "...###....", "..........", ".........."],
    "high": ["....#.....", "...#+#....", "..#+++#...", ".#######..", "..#+++#...", ".#+++++#..", "#########.", "..........", "..........", ".........."],
    "aoo": ["#.......#.", ".#.....#..", "..#...#...", "...#.#....", "....#.....", "...#.#....", "..#...#...", ".#.....#..", "#.......#.", ".........."],
}
SMALL_COL = {"hp": (220, 70, 70), "defense": (120, 160, 220), "dodge": (130, 220, 210), "speed": (240, 210, 110), "move": (160, 200, 120),
             "crit": (250, 190, 80), "attack": (230, 110, 80), "accuracy": (230, 230, 220), "range": (200, 170, 130), "resolve": (190, 140, 230),
             "gold": (246, 202, 80), "renown": (240, 220, 140), "materials": (170, 170, 186), "hush": (170, 170, 180), "days": (250, 210, 110),
             "skull": (236, 226, 206), "week": (210, 196, 170), "roster": (200, 180, 150), "wage": (246, 202, 80), "xp": (140, 220, 140),
             "cover_half": (120, 170, 240), "cover_full": (120, 170, 240), "flank": (250, 200, 80), "high": (160, 220, 140), "aoo": (240, 90, 70)}


def build_small():
    names = list(SMALL.keys())
    sheet = Image.new("RGBA", (10 * len(names), 10), (0, 0, 0, 0))
    for i, n in enumerate(names):
        c = SMALL_COL[n]
        for y, row in enumerate(SMALL[n]):
            for x, ch in enumerate(row):
                if ch == "#":
                    sheet.putpixel((i * 10 + x, y), (28, 20, 30, 255))
                elif ch == "+":
                    sheet.putpixel((i * 10 + x, y), (*c, 255))
        # fill interiors of outline-only glyphs with colour where "#" outlines enclose nothing
    # recolour: make '#' the dark outline, '+' the fill; glyphs drawn only with '#' get the colour instead
    for i, n in enumerate(names):
        rows = SMALL[n]
        if not any("+" in r for r in rows):
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch == "#":
                        sheet.putpixel((i * 10 + x, y), (*SMALL_COL[n], 255))
    sheet.save(os.path.join(OUT, "small_icons.png"))
    return names


def build_status_icons(statuses):
    names = list(statuses.keys())
    sheet = Image.new("RGBA", (8 * len(names), 8), (0, 0, 0, 0))
    for i, n in enumerate(names):
        c = tuple(statuses[n]["color"])
        bad = statuses[n].get("bad", True)
        for y in range(8):
            for x in range(8):
                inside = (x - 3.5) ** 2 + (y - 3.5) ** 2 <= 12.5 if bad else (1 <= x <= 6 and 1 <= y <= 6) or (x in (0, 7) and 2 <= y <= 5) or (y in (0, 7) and 2 <= x <= 5)
                edge = (x - 3.5) ** 2 + (y - 3.5) ** 2 > 7.5 if bad else (x in (0, 7) or y in (0, 7) or (x in (1, 6) and y in (1, 6)))
                if inside:
                    sheet.putpixel((i * 8 + x, y), (28, 20, 30, 255) if edge else (*shade(c, 1.0)[:3], 255))
        # letter-ish mark
        sheet.putpixel((i * 8 + 3, 3), (255, 255, 255, 255))
        sheet.putpixel((i * 8 + 4, 3), (255, 255, 255, 200))
        sheet.putpixel((i * 8 + 3, 4), (255, 255, 255, 200))
    sheet.save(os.path.join(OUT, "status_icons.png"))
    return names


# ====================================================================== emblems
def emblem(size, colors, kind):
    """The guild's own emblem (faction emblems live in emblems.py)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c1, c2, c3 = colors
    s = size
    if kind == "guild":
        # the old guild emblem: a cracked bell over a quill, on a shield
        d.polygon([(s * .15, s * .1), (s * .85, s * .1), (s * .85, s * .55), (s * .5, s * .92), (s * .15, s * .55)], fill=c1, outline=(24, 16, 24))
        d.polygon([(s * .2, s * .15), (s * .8, s * .15), (s * .8, s * .53), (s * .5, s * .85), (s * .2, s * .53)], outline=c3)
        d.ellipse([s * .36, s * .2, s * .64, s * .42], fill=c2, outline=(24, 16, 24))
        d.polygon([(s * .3, s * .58), (s * .7, s * .58), (s * .62, s * .32), (s * .38, s * .32)], fill=c2, outline=(24, 16, 24))
        d.rectangle([s * .27, s * .56, s * .73, s * .62], fill=c2, outline=(24, 16, 24))
        d.line([(s * .5, s * .22), (s * .44, s * .4), (s * .53, s * .5)], fill=(24, 16, 24), width=max(1, s // 32))
        d.ellipse([s * .46, s * .62, s * .54, s * .7], fill=c2, outline=(24, 16, 24))
    return img


def build_emblems():
    specs = {"guild": ((146, 54, 50), (216, 176, 86), (240, 214, 150))}
    for k, cols in specs.items():
        for s in (16, 32, 64):
            emblem(s, cols, k).save(os.path.join(OUT, f"emblem_{k}_{s}.png"))
    # the factions are hand-placed pixel art (tools/py/emblems.py)
    for k in emblems.FACTIONS:
        for s in (12, 16, 32, 64):
            emblems.draw(k, s).save(os.path.join(OUT, f"emblem_{k}_{s}.png"))
    icon = emblem(64, specs["guild"], "guild").resize((256, 256), Image.NEAREST)
    bg = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    bg.alpha_composite(icon)
    bg.save(os.path.join(OUT, "icon.png"))


# ====================================================================== cursor & misc
def cursors():
    arrow = ["#.........", "##........", "#+#.......", "#++#......", "#+++#.....", "#++++#....", "#+++++#...", "#++++++#..",
             "#+++++###.", "#++#++#...", "#+#.#++#..", "##..#++#..", "#....##..."]
    img = Image.new("RGBA", (10, 13), (0, 0, 0, 0))
    for y, row in enumerate(arrow):
        for x, ch in enumerate(row):
            if ch == "#":
                img.putpixel((x, y), (30, 20, 30, 255))
            elif ch == "+":
                img.putpixel((x, y), (246, 232, 196, 255))
    img.resize((20, 26), Image.NEAREST).save(os.path.join(OUT, "cursor.png"))


def skull_icon():
    # difficulty skulls 8x8
    rows = ["..####..", ".#++++#.", "#+#++#+#", "#++++++#", ".#+##+#.", ".######.", "........", "........"]
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                img.putpixel((x, y), (30, 20, 30, 255))
            elif ch == "+":
                img.putpixel((x, y), (236, 226, 206, 255))
    img.save(os.path.join(OUT, "skull.png"))


# ====================================================================== map of Ambral
def world_map():
    W, H = 320, 190
    rng = np.random.default_rng(12)
    img = np.zeros((H, W, 3), dtype=np.uint8)
    # parchment sea
    yy, xx = np.mgrid[0:H, 0:W]

    def noise2(scale, seed):
        r = np.random.default_rng(seed)
        g = r.random((H // scale + 2, W // scale + 2))
        big = np.kron(g, np.ones((scale, scale)))[:H, :W]
        return big

    n = (noise2(16, 1) * 0.5 + noise2(8, 2) * 0.3 + noise2(4, 3) * 0.2)
    cx, cy = W * 0.5, H * 0.55
    d = np.sqrt(((xx - cx) / (W * 0.46)) ** 2 + ((yy - cy) / (H * 0.44)) ** 2)
    land = (d + (n - 0.5) * 0.35) < 0.95
    sea = np.array([196, 178, 142])
    img[:] = sea
    img[(xx + yy) % 7 == 0] = sea * 0.94
    regions = {
        "coast": ((0.18, 0.72), (224, 206, 150)), "stilts": ((0.78, 0.66), (150, 196, 90)), "ember": ((0.3, 0.26), (206, 130, 60)),
        "dunes": ((0.72, 0.24), (220, 162, 128)), "carrow": ((0.5, 0.52), (150, 170, 100)),
    }
    best = np.full((H, W), 9.0)
    lab = np.zeros((H, W), dtype=int)
    keys = list(regions.keys())
    for i, k in enumerate(keys):
        (px, py), _ = regions[k]
        dd = np.sqrt((xx - px * W) ** 2 + ((yy - py * H) * 1.2) ** 2) / W + (n - 0.5) * 0.06
        if k == "carrow":
            dd = dd * 1.6
        m = dd < best
        best[m] = dd[m]
        lab[m] = i
    for i, k in enumerate(keys):
        col = np.array(regions[k][1])
        mask = land & (lab == i)
        img[mask] = col
        img[mask & (n > 0.62)] = (col * 0.88).astype(np.uint8)
    # borders between regions
    edge = (np.roll(lab, 1, 0) != lab) | (np.roll(lab, 1, 1) != lab)
    img[land & edge] = (120, 96, 72)
    # coastline
    coast = land & ~(np.roll(land, 1, 0) & np.roll(land, -1, 0) & np.roll(land, 1, 1) & np.roll(land, -1, 1))
    img[coast] = (92, 70, 56)
    # the Hush creeping from the north edge
    hush = (yy < 26 + (n * 22).astype(int))
    img[hush] = (img[hush] * 0.35 + np.array([150, 150, 156]) * 0.65).astype(np.uint8)
    im = Image.fromarray(img, "RGB")
    dr = ImageDraw.Draw(im)
    # Carrow: the cracked bell
    bx, by = int(0.5 * W), int(0.52 * H)
    dr.polygon([(bx - 5, by + 4), (bx + 5, by + 4), (bx + 3, by - 4), (bx - 3, by - 4)], fill=(170, 130, 70), outline=(50, 34, 30))
    dr.line([(bx, by - 3), (bx - 1, by + 2)], fill=(50, 34, 30))
    # trees in the ember wood / jungle, dunes marks
    for _ in range(40):
        k = rng.integers(0, 2)
        (px, py), _c = regions[["ember", "stilts"][k]]
        x, y = int(px * W + rng.normal(0, 16)), int(py * H + rng.normal(0, 10))
        if 0 <= x < W and 0 <= y < H and land[y, x]:
            col = (170, 80, 40) if k == 0 else (60, 120, 50)
            dr.polygon([(x, y - 3), (x - 2, y + 1), (x + 2, y + 1)], fill=col, outline=(50, 34, 30))
    for _ in range(14):
        (px, py), _c = regions["dunes"]
        x, y = int(px * W + rng.normal(0, 18)), int(py * H + rng.normal(0, 10))
        if 0 <= x < W and 0 <= y < H and land[y, x]:
            dr.arc([x - 4, y - 2, x + 4, y + 3], 180, 360, fill=(160, 100, 80))
    for _ in range(10):
        x, y = rng.integers(10, W - 10), rng.integers(40, H - 10)
        if not land[y, x]:
            dr.arc([x - 3, y - 1, x + 3, y + 2], 200, 340, fill=(150, 130, 100))
    im.save(os.path.join(OUT, "world_map.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    panel((44, 34, 46), (86, 70, 82), (28, 20, 30), (16, 10, 18), name="panel")
    panel((58, 44, 54), (104, 84, 92), (34, 24, 34), (16, 10, 18), name="panel_light")
    panel((226, 208, 166), (244, 232, 200), (190, 164, 120), (70, 48, 36), name="parchment")
    panel((30, 24, 34), (60, 48, 62), (20, 14, 22), (12, 8, 14), size=16, name="panel_inset")
    panel((64, 40, 40), (120, 76, 64), (40, 24, 28), (16, 10, 18), size=16, name="tooltip")
    frame_gold()
    button((134, 90, 58), "btn")
    button((88, 118, 72), "btn_green")
    button((150, 60, 52), "btn_red")
    button((70, 80, 120), "btn_blue")
    bars()
    icon_names = build_icons()
    small_names = build_small()
    statuses = json.load(open(os.path.join(ROOT, "data", "statuses.json")))
    status_names = build_status_icons(statuses)
    build_emblems()
    cursors()
    skull_icon()
    world_map()
    json.dump({"icons": icon_names, "small": small_names, "status": status_names}, open(os.path.join(OUT, "icons.json"), "w"), indent=1)
    print("[ui] done")


if __name__ == "__main__":
    main()
