"""Hue-shifted toon ramps, shared by preview tools.

Mirrors scripts/combat/unit_palette.gd so previews match the game.
"""
import colorsys

SLOTS = ["skin", "skin2", "hair", "eyes", "cloth1", "cloth2", "leather", "metal",
         "trim", "wood", "glow", "feature", "cape", "white", "bandage", "outline"]


def _shift_hue(h, target, amount):
    d = ((target - h + 0.5) % 1.0) - 0.5
    return (h + d * amount) % 1.0


def ramp(rgb):
    """Return 4 shades (deep, shadow, base, light) for an (r,g,b) 0-255 colour."""
    r, g, b = [c / 255.0 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for level in range(4):
        if level == 2:
            hh, ss, vv = h, s, v
        elif level == 3:
            hh = _shift_hue(h, 1.0 / 6.0, 0.12)
            ss = s * 0.82
            vv = min(1.0, v * 1.16 + 0.05)
        elif level == 1:
            hh = _shift_hue(h, 0.70, 0.12)
            ss = min(1.0, s * 1.08 + 0.05)
            vv = v * 0.72
        else:
            hh = _shift_hue(h, 0.72, 0.22)
            ss = min(1.0, s * 1.12 + 0.08)
            vv = v * 0.48
        rr, gg, bb = colorsys.hsv_to_rgb(hh, ss, vv)
        out.append((int(rr * 255), int(gg * 255), int(bb * 255)))
    return out


def outline_of(rgb):
    deep = ramp(rgb)[0]
    r, g, b = [c / 255.0 for c in deep]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = _shift_hue(h, 0.75, 0.3)
    rr, gg, bb = colorsys.hsv_to_rgb(h, min(1.0, s * 1.1 + 0.1), v * 0.55 + 0.03)
    return (int(rr * 255), int(gg * 255), int(bb * 255))


TEST_PALETTE = {
    "skin": (238, 188, 150), "skin2": (196, 112, 104), "hair": (92, 58, 48), "eyes": (38, 28, 48),
    "cloth1": (64, 124, 170), "cloth2": (186, 70, 64), "leather": (126, 84, 54), "metal": (176, 184, 196),
    "trim": (226, 184, 74), "wood": (146, 98, 58), "glow": (130, 236, 255), "feature": (96, 176, 136),
    "cape": (84, 128, 72), "white": (236, 230, 218), "bandage": (242, 236, 224),
}
