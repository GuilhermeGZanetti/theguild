"""Race models for Tidefolk, Mothkin, Barkborn and Khepri, following the
concept sheets in concept_art/.

Each race has a body kit (skin, ears, feet, hair and its signature feature)
and one outfit per look:

  tidefolk  teal skin, navy hair, golden fin ears, webbed feet and a glowing
            jellyfish companion floating beside the head
  mothkin   pale skin, fluffy hair, feathery golden antennae, big moth wings
            with eye spots, lanterns
  barkborn  bark skin, pointed ears, autumn-leaf hair, twig antlers, root feet,
            leaf ponchos and cloaks
  khepri    dark shell face with big orange eyes, long orange-tipped antennae,
            hoods and scarves, a travel pack with a bedroll

Characters face -Y; their right hand is at -X.
"""
import math
import random
from mathutils import Vector
import bl_common as C

RACES = ("tidefolk", "mothkin", "barkborn", "khepri")
TALL = {("barkborn", "graftwarden"): 1.08}


# ======================================================================
# helpers
# ======================================================================
def _dir_rot(d):
    """Euler angles (degrees) that turn local +Z toward direction d."""
    e = Vector(d).normalized().to_track_quat("Z", "Y").to_euler()
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def frame(name, loc, rot, parent):
    """A pivot with a fixed rotation (reset_pose leaves it alone)."""
    p = C.pivot(name, loc, parent)
    C.set_rot(p, *rot)
    p["static"] = True
    return p


def leaf(slot, base, d, parent, size=0.1, flat=0.34):
    """A leaf blade growing from base toward d (a faceted flattened ellipsoid)."""
    dv = Vector(d).normalized()
    c = Vector(base) + dv * size * 0.62
    return C.ico(slot, tuple(c), (size * 0.42, size * flat * 0.4, size * 0.78), _dir_rot(dv), parent=parent, r=1.0, sub=1)


def ellipsoid_along(slot, center, d, radii, parent):
    """Ellipsoid elongated along d (radii = across, thin, along)."""
    return C.sphere(slot, center, radii, _dir_rot(d), parent=parent, seg=12, rings=8)


def fib_dirs(n):
    """n roughly even directions on a sphere."""
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        r = math.sqrt(max(0.0, 1 - z * z))
        a = ga * i
        out.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
    return out


def leaf_mass(parent, center, radii, n, slots, rng, size=0.12, keep=None, flat=0.34, droop=0.0):
    """A clump of leaves growing outward from an ellipsoid surface; droop bends
    the side leaves downward like a mop of hair."""
    for d in fib_dirs(n):
        if keep is not None and not keep(d):
            continue
        base = Vector((center[0] + d.x * radii[0], center[1] + d.y * radii[1], center[2] + d.z * radii[2]))
        jitter = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.3)))
        down = Vector((0, 0, -droop * (1.0 - max(0.0, d.z))))
        leaf(rng.choice(slots), base - d * size * 0.35, d + jitter + down, parent, size * rng.uniform(0.8, 1.2), flat)


def hood(slot, head, rim=True, tip=False):
    """A hood around the head, open at the face, with a soft peak (or a long tip)."""
    C.sphere(slot, (0, 0.09, 0.32), (0.345, 0.325, 0.33), parent=head)
    if rim:
        C.torus(slot, (0, -0.232, 0.27), (1.0, 1.0, 1.12), (90, 0, 0), parent=head, R=0.215, r=0.042)
    if tip:
        C.cone(slot, (0, 0.3, 0.54), (1, 1, 1), (-58, 0, 0), parent=head, r1=0.13, r2=0.0, depth=0.34, verts=10)
    else:
        C.cone(slot, (0, 0.14, 0.62), (1, 1, 1), (-32, 0, 0), parent=head, r1=0.15, r2=0.02, depth=0.2, verts=10)
    # drapes over the shoulders
    C.cone(slot, (0, 0.05, 0.02), (1, 0.9, 1), parent=head, r1=0.25, r2=0.19, depth=0.16, verts=16)


def scarf(slot, R, tail=1, up=0.0, bulk=1.0):
    """A thick scarf around the neck with a hanging tail (tail: +1 left, -1 right, 0 none)."""
    t = R["tall"]
    torso = R["torso"]
    C.torus(slot, (0, 0, 0.44 * t + up), (bulk, bulk * 0.95, 1.2), parent=torso, R=0.135, r=0.06)
    if tail:
        s = tail
        C.tube(slot, [(s * 0.06, -0.12, 0.43 * t), (s * 0.1, -0.16, 0.32 * t), (s * 0.13, -0.15, 0.18 * t)],
               radius=0.042, parent=torso, taper=[1, 0.9, 0.7])


def belt_pouch(R, x=0.14, slot="leather"):
    C.box(slot, (x, -0.1, 0.02), (0.09, 0.06, 0.09), parent=R["torso"], bevel=0.015)
    C.sphere("trim", (x, -0.135, 0.04), (0.018, 0.01, 0.018), parent=R["torso"])


def small_lantern(parent, loc, scale=1.0):
    x, y, z = loc
    k = scale
    C.cyl("metal", (x, y, z + 0.07 * k), parent=parent, r=0.045 * k, depth=0.025 * k, verts=8)
    C.sphere("glow", (x, y, z), (0.04 * k, 0.04 * k, 0.055 * k), parent=parent)
    C.cyl("metal", (x, y, z - 0.065 * k), parent=parent, r=0.045 * k, depth=0.025 * k, verts=8)
    C.torus("metal", (x, y, z + 0.1 * k), (1, 1, 1), (90, 0, 0), parent=parent, R=0.025 * k, r=0.008)


# ======================================================================
# body kit
# ======================================================================
def body(R, top="cloth1", pants="cloth2", sleeves=None, cuffs=None, feet="boots", legs="pants",
         robe=False, skirt=True, bulk=1.0, belt=True):
    t = R["tall"]
    torso, head = R["torso"], R["head"]
    R["armR"].location.x = -0.19 * bulk
    R["armL"].location.x = 0.19 * bulk
    C.sphere(top, (0, 0, 0.22 * t), (0.165 * bulk, 0.13 * bulk, 0.25 * t), parent=torso)
    if belt:
        C.torus("leather", (0, 0, 0.07 * t), (bulk, 0.82 * bulk, 1), parent=torso, R=0.16, r=0.028)
        C.sphere("trim", (0, -0.132 * bulk, 0.07 * t), (0.034, 0.016, 0.03), parent=torso)
    for leg in (R["legR"], R["legL"]):
        if not robe:
            if legs == "pants":
                C.cyl(pants, (0, 0, -0.16), parent=leg, r=0.064, depth=0.26)
            elif legs == "breeches":   # knee breeches over bare shins
                C.cyl(pants, (0, 0, -0.1), parent=leg, r=0.066, depth=0.17)
                C.cyl("skin", (0, 0, -0.245), parent=leg, r=0.05, depth=0.14)
                C.torus("trim", (0, 0, -0.295), parent=leg, R=0.05, r=0.014)
            elif legs == "bare":
                C.cyl("skin", (0, 0, -0.17), parent=leg, r=0.055, depth=0.26)
        foot(leg, feet)
    if robe:
        C.cone(top, (0, 0, -0.17 * t), parent=torso, r1=0.25 * bulk, r2=0.155 * bulk, depth=0.46 * t)
    elif skirt:
        C.cone(top, (0, 0, -0.02), parent=torso, r1=0.2 * bulk, r2=0.155 * bulk, depth=0.16)
    sl = sleeves or top
    for arm, hand in ((R["armR"], R["handR"]), (R["armL"], R["handL"])):
        C.cyl(sl, (0, 0, -0.12 * t), parent=arm, r=0.054 * bulk, depth=0.22 * t)
        C.sphere(cuffs or pants, (0, 0, -0.215 * t), (0.062, 0.062, 0.036), parent=arm)
        C.sphere("skin", (0, 0, 0.03), (0.058, 0.058, 0.058), parent=hand)
    C.sphere("skin", (0, 0, 0.28), (0.31, 0.30, 0.29), parent=head)


def foot(leg, kind):
    if kind == "boots":
        C.sphere("leather", (0, -0.03, -0.335), (0.07, 0.1, 0.06), parent=leg)
    elif kind == "webbed":
        C.sphere("skin", (0, -0.06, -0.352), (0.088, 0.13, 0.05), parent=leg)
        for x in (-0.055, 0.0, 0.055):
            C.sphere("skin", (x, -0.18, -0.362), (0.032, 0.042, 0.03), parent=leg)
    elif kind == "root":
        C.sphere("skin", (0, -0.03, -0.34), (0.074, 0.1, 0.056), parent=leg)
        for x, a in ((-0.05, -22), (0.0, 0), (0.05, 22)):
            C.cone("skin", (x, -0.13, -0.365), (1, 1, 0.6), (98, 0, a), parent=leg, r1=0.028, r2=0.0, depth=0.11, verts=6)


def build(R, spec, W, bandage=False):
    race, look = spec["race"], spec["look"]
    rng = random.Random(sum(map(ord, race + look)))
    {"tidefolk": tidefolk, "mothkin": mothkin, "barkborn": barkborn, "khepri": khepri}[race](R, look, W, rng)


# ======================================================================
# Tidefolk
# ======================================================================
def tidefolk(R, look, W, rng):
    t = R["tall"]
    torso, head, handR, handL = R["torso"], R["head"], R["handR"], R["handL"]
    if look == "warrior":          # the old captain
        body(R, top="cloth1", pants="cloth1", cuffs="cloth2", feet="webbed", legs="breeches", bulk=1.12)
        # long coat with cream lapels
        C.cone("cloth1", (0, 0.01, -0.1), parent=torso, r1=0.25, r2=0.18, depth=0.3)
        for s in (-1, 1):
            C.box("cloth2", (s * 0.06, -0.14, 0.26), (0.05, 0.03, 0.3), (0, s * -18, 0), parent=torso)
        C.box("cloth2", (0, -0.2, -0.12), (0.05, 0.03, 0.26), (-8, 0, 0), parent=torso)
        for s in (-1, 1):
            C.sphere("cloth1", (s * 0.2, 0, 0.4), (0.1, 0.1, 0.07), parent=torso)
    elif look == "rogue":          # long-haired corsair
        body(R, top="cloth1", pants="cloth2", sleeves="skin", cuffs="trim", feet="webbed", legs="bare", skirt=False)
        C.torus("cloth2", (0, 0, 0.06), (1.05, 0.9, 1.4), parent=torso, R=0.16, r=0.04)   # red sash
        C.tube("cloth2", [(0.08, -0.13, 0.05), (0.13, -0.15, -0.1), (0.15, -0.14, -0.26)], radius=0.04, parent=torso, taper=[1, 0.9, 0.7])
        C.cone("cloth1", (0, 0, -0.08), parent=torso, r1=0.21, r2=0.15, depth=0.26)       # cream skirt
        C.box("cloth2", (-0.1, -0.16, -0.12), (0.07, 0.02, 0.2), (-10, 0, 8), parent=torso)
    elif look in ("ranger", "tidecaller"):   # spear fighter
        body(R, top="cloth1", pants="cloth2", cuffs="cloth2", feet="webbed", legs="breeches")
        belt_pouch(R, 0.15)
        C.tube("leather", [(-0.14, -0.12, 0.42), (0.0, -0.14, 0.25), (0.15, -0.12, 0.08)], radius=0.02, parent=torso)
    else:                          # mystic: hooded cloak
        body(R, top="cloth2", pants="cloth2", sleeves="cloth1", cuffs="cloth1", feet="webbed", robe=True)
        C.cone("cloth1", (0, 0.02, 0.02), parent=torso, r1=0.27, r2=0.17, depth=0.62)     # cloak
        for i, (x, z) in enumerate(((-0.2, 0.3), (-0.12, 0.18), (0.16, 0.26), (0.22, 0.1), (0.05, 0.22))):
            C.tube("cape", [(x, -0.14, z), (x * 1.1, -0.17, z - 0.14), (x * 1.05, -0.16, z - 0.3)], radius=0.022, parent=torso, taper=[1, 0.8, 0.4])
        C.ico("cloth2", (0, -0.15, 0.36), (1, 0.6, 1), parent=torso, r=0.04, sub=1)
        C.sphere("glow", (0.14, -0.14, 0.0), (0.045, 0.045, 0.055), parent=torso)          # potion
        C.cyl("leather", (0.14, -0.14, 0.07), parent=torso, r=0.018, depth=0.04, verts=6)
    W.eyes("tidefolk", head)
    # fin ears
    for s in (-1, 1):
        C.sphere("feature", (s * 0.3, 0.07, 0.3), (0.026, 0.12, 0.085), (18, 0, s * -28), parent=head)
        C.sphere("feature", (s * 0.33, 0.15, 0.36), (0.02, 0.07, 0.05), (38, 0, s * -28), parent=head)
    # hair
    if look == "warrior":
        C.sphere("hair", (0, 0.06, 0.34), (0.325, 0.31, 0.27), parent=head)
        cap = frame("cap", (0, 0.02, 0.5), (-8, 0, 0), head)
        C.cyl("cloth1", (0, 0, 0), parent=cap, r=0.31, depth=0.1, verts=20)
        C.sphere("cloth1", (0, 0.03, 0.06), (0.34, 0.33, 0.1), parent=cap)
        C.torus("trim", (0, 0, -0.02), (1, 1, 1), parent=cap, R=0.31, r=0.022)
        C.box("leather", (0, -0.27, -0.06), (0.36, 0.14, 0.03), (-15, 0, 0), parent=cap)
        C.ico("trim", (0, -0.31, 0.02), (1, 0.6, 1), parent=cap, r=0.04, sub=1)
        # white beard and moustache
        C.sphere("white", (0, -0.2, 0.1), (0.21, 0.12, 0.13), parent=head)
        C.sphere("white", (0, -0.23, 0.03), (0.14, 0.09, 0.1), parent=head)
        for s in (-1, 1):
            C.sphere("white", (s * 0.07, -0.285, 0.17), (0.07, 0.03, 0.03), (0, s * 12, 0), parent=head)
            C.sphere("white", (s * 0.23, -0.12, 0.2), (0.05, 0.08, 0.1), parent=head)
    elif look == "rogue":
        C.sphere("hair", (0, 0.05, 0.36), (0.33, 0.325, 0.29), parent=head)
        C.sphere("hair", (0, -0.2, 0.44), (0.25, 0.12, 0.12), parent=head)
        for s in (-1, 1):
            C.tube("hair", [(s * 0.24, -0.1, 0.36), (s * 0.3, -0.08, 0.14), (s * 0.28, -0.04, -0.06)], radius=0.075, parent=head, taper=[1, 0.9, 0.5])
        C.tube("hair", [(0, 0.2, 0.46), (0, 0.36, 0.28), (0, 0.38, 0.0), (0.02, 0.34, -0.3), (0.04, 0.3, -0.5)],
               radius=0.18, parent=head, taper=[1.0, 1.05, 0.95, 0.75, 0.35])
        C.torus("hair", (0, 0.08, 0.66), (1, 1, 1), (72, 0, 0), parent=head, R=0.08, r=0.03)     # top loop
        C.ico("trim", (0.3, -0.04, 0.16), (1, 1, 1), parent=head, r=0.022, sub=1)                  # earring
    elif look == "mystic":
        C.sphere("hair", (0, -0.19, 0.44), (0.25, 0.12, 0.12), parent=head)
        for s in (-1, 1):
            C.sphere("hair", (s * 0.22, -0.16, 0.24), (0.08, 0.08, 0.16), parent=head)
        hood("cloth1", head)
        C.ico("glow", (0.18, -0.22, 0.5), (1, 0.6, 1), parent=head, r=0.03, sub=1)
    else:   # messy spikes
        C.sphere("hair", (0, 0.05, 0.36), (0.33, 0.325, 0.29), parent=head)
        for (x, y, z, rx, ry) in [(0.02, -0.08, 0.62, -30, 5), (-0.16, 0.0, 0.58, -8, -38), (0.18, 0.02, 0.56, -5, 40),
                                  (-0.02, 0.2, 0.56, 38, 0), (-0.2, 0.2, 0.44, 55, -35), (0.2, 0.2, 0.42, 55, 38),
                                  (-0.28, -0.04, 0.36, -5, -72), (0.28, -0.04, 0.36, -5, 72), (0.0, 0.3, 0.3, 80, 0)]:
            C.cone("hair", (x, y, z), (1, 1, 1), (rx, ry, 0), parent=head, r1=0.1, r2=0.0, depth=0.22, verts=7)
        for x, a in ((-0.14, -12), (0.0, 0), (0.12, 14)):
            C.cone("hair", (x, -0.25, 0.42), (1, 0.6, 1), (160, a, 0), parent=head, r1=0.07, r2=0.0, depth=0.16, verts=6)
        # red scarf
        scarf("cape", R, tail=1)
    # jellyfish companion, floating by the head
    jellyfish(R, R["neck"], (0.47, 0.05, 0.47), 1.4)
    # weapons
    if look == "warrior":
        cutlass(handR)
        wheel_shield(handL)
    elif look == "rogue":
        cutlass(handR, 0.8)
        W.dagger(handL)
    elif look == "ranger":
        W.bow(handL)
        C.cyl("leather", (0.06, 0.16, 0.3), (1, 1, 1), (-15, 20, 0), parent=torso, r=0.06, depth=0.34)
        for dx in (-0.02, 0.02, 0.0):
            C.cone("white", (0.1 + dx, 0.2, 0.52), (1, 0.5, 1), (-15, 20, 0), parent=torso, r1=0.03, r2=0.0, depth=0.08, verts=4)
    elif look == "tidecaller":
        harpoon(handR)
    else:
        jelly_staff(handR)


def jellyfish(R, parent, loc, k=1.0):
    j = C.pivot("jelly", loc, parent)
    R["jelly"] = j
    R["jelly_base"] = loc
    C.sphere("glow", (0, 0, 0.02 * k), (0.12 * k, 0.12 * k, 0.09 * k), parent=j)
    C.torus("glow", (0, 0, -0.03 * k), (1, 1, 0.7), parent=j, R=0.105 * k, r=0.022 * k)
    C.sphere("white", (-0.035 * k, -0.07 * k, 0.05 * k), (0.035 * k, 0.03 * k, 0.03 * k), parent=j)
    for i in range(5):
        a = math.radians(i * 72 + 20)
        x, y = math.cos(a) * 0.06 * k, math.sin(a) * 0.06 * k
        C.tube("glow", [(x, y, -0.04 * k), (x * 1.3 + 0.02 * k, y * 1.3, -0.13 * k), (x * 0.9 - 0.02 * k, y * 0.9, -0.22 * k),
                        (x * 1.2, y * 1.2, -0.3 * k)], radius=0.016 * k, parent=j, taper=[1, 0.9, 0.8, 0.5])


def cutlass(hand, k=1.0):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.cyl("leather", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.022, depth=0.1)
    C.torus("trim", (0, -0.05, 0.02), (1, 1, 1), (0, 90, 0), parent=w, R=0.05, r=0.012)
    C.tube("metal", [(0, -0.06, 0), (0, -0.22 * k, 0.01), (0, -0.38 * k, 0.05), (0, -0.48 * k, 0.12)],
           radius=0.03, parent=w, taper=[1.0, 1.15, 1.0, 0.3])


def wheel_shield(hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.torus("wood", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, R=0.15, r=0.022)
    for i in range(8):
        a = i * 45
        C.cyl("wood", (0, 0, 0), (1, 1, 1), (0, a, 0), parent=w, r=0.012, depth=0.3, verts=6)
        x, z = math.sin(math.radians(a)) * 0.2, math.cos(math.radians(a)) * 0.2
        C.sphere("wood", (x, 0, z), (0.025, 0.025, 0.025), parent=w)
    C.cyl("trim", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.05, depth=0.05, verts=12)
    C.sphere("glow", (0, -0.03, 0), (0.025, 0.02, 0.025), parent=w)


def harpoon(hand):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.cyl("wood", (0, 0, 0.12), parent=w, r=0.022, depth=1.05)
    C.torus("trim", (0, 0, 0.5), parent=w, R=0.03, r=0.012)
    C.cone("metal", (0, 0, 0.74), (1, 0.4, 1), parent=w, r1=0.05, r2=0.0, depth=0.22, verts=4)
    for s in (-1, 1):
        C.cone("metal", (s * 0.05, 0, 0.64), (1, 0.5, 1), (0, s * -140, 0), parent=w, r1=0.02, r2=0.0, depth=0.1, verts=4)


def jelly_staff(hand):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.tube("wood", [(0, 0, -0.38), (0.02, 0, 0.0), (-0.01, 0, 0.3), (0.02, 0, 0.5)], radius=0.026, parent=w)
    C.torus("wood", (0.02, 0, 0.66), (1, 1, 1), (90, 0, 0), parent=w, R=0.13, r=0.022)
    C.sphere("glow", (0.02, 0, 0.7), (0.085, 0.085, 0.06), parent=w)
    for x in (-0.03, 0.02, 0.07):
        C.tube("glow", [(x, 0, 0.66), (x + 0.01, 0, 0.6), (x - 0.01, 0, 0.55)], radius=0.012, parent=w)
    for x, z in ((-0.11, 0.6), (0.14, 0.58)):
        C.tube("cape", [(x, 0, z), (x, -0.01, z - 0.1), (x + 0.01, 0, z - 0.2)], radius=0.014, parent=w)


# ======================================================================
# Mothkin
# ======================================================================
def mothkin(R, look, W, rng):
    t = R["tall"]
    torso, head, handR, handL = R["torso"], R["head"], R["handR"], R["handL"]
    if look == "warrior":
        body(R, top="cloth1", pants="cloth2", cuffs="cloth2")
        C.cone("cloth1", (0, 0.0, -0.08), parent=torso, r1=0.22, r2=0.16, depth=0.24)
        scarf("cape", R, tail=-1, bulk=1.1)
        small_lantern(torso, (0.17, -0.07, -0.02), 0.8)
    elif look == "rogue":
        body(R, top="cloth2", pants="leather", sleeves="cloth1", cuffs="cloth1")
        C.cone("cloth1", (0, 0.03, 0.06), parent=torso, r1=0.24, r2=0.16, depth=0.4)       # short cloak
        scarf("cloth2", R, tail=1)
        pack(R, roll="cloth1")
        small_lantern(torso, (0.18, -0.06, -0.02), 0.8)
    elif look == "ranger":
        body(R, top="cloth1", pants="cloth2", cuffs="cloth2")
        C.cone("cloth1", (0, 0.0, -0.08), parent=torso, r1=0.21, r2=0.16, depth=0.22)
        scarf("cape", R, tail=-1, bulk=1.15, up=0.01)
        C.box("leather", (0.17, -0.02, 0.0), (0.08, 0.16, 0.14), parent=torso, bevel=0.02)      # satchel
        C.tube("leather", [(-0.14, -0.12, 0.42), (0.0, -0.14, 0.25), (0.15, -0.1, 0.06)], radius=0.018, parent=torso)
        small_lantern(torso, (-0.17, -0.08, -0.02), 0.8)
    elif look == "mystic":         # the scholar
        body(R, top="cloth1", pants="cloth1", cuffs="cloth2", robe=True)
        C.box("cloth2", (0, -0.2, -0.17), (0.12, 0.02, 0.44), (-12, 0, 0), parent=torso)
        C.box("trim", (0, -0.21, -0.17), (0.02, 0.022, 0.44), (-12, 0, 0), parent=torso)
        C.torus("cloth2", (0, 0, 0.44 * t), (1.1, 1.05, 1.1), parent=torso, R=0.13, r=0.05)
        small_lantern(torso, (0.17, -0.1, 0.0), 0.8)
    else:                          # lanternbearer
        body(R, top="cloth2", pants="cloth2", sleeves="cloth1", cuffs="cloth2", robe=True)
        C.cone("cloth1", (0, 0.03, -0.06), parent=torso, r1=0.26, r2=0.17, depth=0.52)
        C.box("trim", (0, -0.21, -0.17), (0.03, 0.02, 0.44), (-12, 0, 0), parent=torso)
        scarf("cloth1", R, tail=0)
        for x in (-0.16, 0.16):
            small_lantern(torso, (x, -0.1, -0.04), 0.75)
    W.eyes("mothkin", head)
    # small pointed ears
    for s in (-1, 1):
        C.cone("skin", (s * 0.3, 0.02, 0.26), (0.5, 1, 1), (0, s * 72, 0), parent=head, r1=0.05, r2=0.0, depth=0.12, verts=6)
    # fluffy hair
    if look == "rogue":
        C.sphere("hair", (0, -0.2, 0.43), (0.25, 0.12, 0.12), parent=head)
        for s in (-1, 1):
            C.sphere("hair", (s * 0.2, -0.18, 0.28), (0.09, 0.08, 0.14), parent=head)
        hood("cloth1", head)
        for s in (-1, 1):   # little ears on the hood
            C.cone("cloth1", (s * 0.22, 0.08, 0.62), (1, 0.6, 1), (0, s * 25, 0), parent=head, r1=0.08, r2=0.0, depth=0.16, verts=8)
    else:
        fluffy_hair(head, rng)
        if look == "lanternbearer":
            C.tube("hair", [(0, 0.2, 0.4), (0, 0.34, 0.2), (0, 0.34, -0.1), (0, 0.3, -0.3)], radius=0.15, parent=head, taper=[1, 1, 0.8, 0.4])
    if look == "ranger":            # round glasses
        for s in (-1, 1):
            C.torus("metal", (s * 0.12, -0.3, 0.26), (1, 1, 1), (90, 0, 0), parent=head, R=0.07, r=0.012)
        C.cyl("metal", (0, -0.31, 0.27), (1, 1, 1), (0, 90, 0), parent=head, r=0.01, depth=0.08, verts=6)
    # feathery antennae
    for s in (-1, 1):
        pts = [(s * 0.07, -0.14, 0.52), (s * 0.1, -0.2, 0.72), (s * 0.18, -0.16, 0.88), (s * 0.3, -0.08, 0.94)]
        C.tube("feature", pts, radius=0.016, parent=head)
        ellipsoid_along("feature", (s * 0.25, -0.12, 0.9), (s * 0.14, 0.1, 0.07), (0.055, 0.018, 0.14), head)
    moth_wings(R, 1.12 if look == "lanternbearer" else 1.0)
    # weapons
    if look == "warrior":
        W.sword(handR)
        moth_shield(handL)
    elif look == "rogue":
        W.dagger(handR)
        W.dagger(handL)
    elif look == "ranger":
        W.bow(handL)
    elif look == "mystic":
        W.staff(handR, "glow")
        book(handL)
    else:
        W.lantern(handR)
        for s in (-1, 1):     # lanterns hanging from the wing tops
            small_lantern(R["wingR" if s < 0 else "wingL"], (s * 0.34, 0.06, 0.2), 0.7)


def fluffy_hair(head, rng):
    C.sphere("hair", (0, 0.07, 0.39), (0.32, 0.31, 0.26), parent=head)
    puffs = [(0, -0.02, 0.6, 0.12), (-0.16, 0.02, 0.55, 0.11), (0.16, 0.02, 0.55, 0.11), (0, 0.18, 0.52, 0.13),
             (-0.27, 0.1, 0.4, 0.1), (0.27, 0.1, 0.4, 0.1), (-0.28, 0.06, 0.26, 0.075), (0.28, 0.06, 0.26, 0.075),
             (0, 0.27, 0.3, 0.13), (-0.18, 0.21, 0.22, 0.09), (0.18, 0.21, 0.22, 0.09),
             (-0.12, -0.22, 0.49, 0.075), (0.1, -0.23, 0.5, 0.075), (0.0, -0.24, 0.52, 0.065)]
    for (x, y, z, r) in puffs:
        C.sphere("hair", (x, y, z), (r, r, r * 0.9), parent=head, seg=10, rings=6)


def moth_wings(R, k=1.0):
    t = R["tall"]
    for s, name in ((-1, "wingR"), (1, "wingL")):
        w = C.pivot(name, (s * 0.05, 0.12, 0.34 * t), R["torso"])
        R[name] = w
        f = frame(name + "_f", (0, 0, 0), (0, 0, s * 24), w)
        up_c = (s * 0.23 * k, 0.0, 0.17 * k)
        lo_c = (s * 0.15 * k, 0.0, -0.13 * k)
        # upper wing: cream, gold rim, purple eye spot
        C.sphere("white", up_c, (0.25 * k, 0.022, 0.19 * k), (0, s * -32, 0), parent=f, seg=16, rings=10)
        C.sphere("feature", up_c, (0.268 * k, 0.012, 0.207 * k), (0, s * -32, 0), parent=f, seg=16, rings=10)
        spot = (s * 0.3 * k, 0.0, 0.21 * k)
        C.sphere("skin2", spot, (0.085 * k, 0.034, 0.08 * k), parent=f, seg=12, rings=8)
        C.sphere("feature", spot, (0.05 * k, 0.04, 0.047 * k), parent=f, seg=10, rings=6)
        C.sphere("eyes", spot, (0.03 * k, 0.046, 0.028 * k), parent=f, seg=8, rings=6)
        C.sphere("skin2", (s * 0.16 * k, 0.0, 0.26 * k), (0.06 * k, 0.03, 0.035 * k), (0, s * -32, 0), parent=f, seg=10, rings=6)
        # lower wing
        C.sphere("skin2", lo_c, (0.15 * k, 0.022, 0.17 * k), (0, s * 28, 0), parent=f, seg=14, rings=8)
        C.sphere("white", lo_c, (0.12 * k, 0.03, 0.13 * k), (0, s * 28, 0), parent=f, seg=12, rings=8)
        C.sphere("feature", (s * 0.17 * k, 0.0, -0.16 * k), (0.045 * k, 0.036, 0.045 * k), parent=f, seg=10, rings=6)


def moth_shield(hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.cyl("white", (0, 0, 0), (1, 1, 1.15), (90, 0, 0), parent=w, r=0.16, depth=0.04, verts=20)
    C.torus("feature", (0, -0.005, 0), (1, 1, 1.15), (90, 0, 0), parent=w, R=0.16, r=0.02)
    C.cyl("skin2", (0, -0.02, 0.01), (1, 1, 1), (90, 0, 0), parent=w, r=0.075, depth=0.02, verts=16)
    C.cyl("eyes", (0, -0.03, 0.01), (1, 1, 1), (90, 0, 0), parent=w, r=0.03, depth=0.02, verts=12)


def book(hand):
    w = C.pivot("book", (0.02, -0.08, 0.02), hand)
    C.box("cloth2", (0, 0, 0), (0.05, 0.2, 0.24), (0, 0, 20), parent=w, bevel=0.01)
    C.box("white", (0.01, 0, 0), (0.05, 0.18, 0.22), (0, 0, 20), parent=w)
    C.ico("glow", (-0.035, -0.02, 0.0), (0.4, 1, 1), parent=w, r=0.04, sub=1)


# ======================================================================
# Barkborn
# ======================================================================
def barkborn(R, look, W, rng):
    t = R["tall"]
    torso, head, handR, handL = R["torso"], R["head"], R["handR"], R["handL"]
    if look == "warrior":          # masked leaf-mane warrior
        body(R, top="skin", pants="skin", sleeves="skin", cuffs="hair", feet="root", legs="bare", bulk=1.08)
        C.sphere("skin2", (0, -0.03, 0.25), (0.16, 0.12, 0.2), parent=torso)
        for s in (-1, 1):
            C.box("cloth2", (s * 0.05, -0.135, 0.28), (0.04, 0.02, 0.2), (0, s * 22, 0), parent=torso)
        leaf_skirt(torso, ["hair", "feature", "cloth1"], rng, 0.13)
        for s in (-1, 1):     # leaf pauldrons
            leaf_mass(torso, (s * 0.2, 0.0, 0.42), (0.07, 0.07, 0.05), 14, ["hair", "feature"], rng, 0.11,
                      keep=lambda d: d.z > -0.3)
    elif look == "rogue":          # flower-crowned forager
        body(R, top="cloth1", pants="skin", sleeves="skin", cuffs="feature", feet="root", legs="bare", skirt=False)
        C.cone("cloth1", (0, 0, -0.08), parent=torso, r1=0.21, r2=0.15, depth=0.26)
        leaf_skirt(torso, ["feature", "hair"], rng, 0.11, z=-0.12)
        scarf("cloth2", R, tail=1)
    elif look == "ranger":         # leaf-poncho archer
        body(R, top="skin", pants="skin", sleeves="skin", cuffs="cloth1", feet="root", legs="bare")
        poncho(torso, ["cloth1", "cloth1", "feature"], rng, 0.14)
        leaf_skirt(torso, ["cloth1", "feature", "hair"], rng, 0.12)
    else:                          # druid (mystic) and the big graftwarden
        big = look == "graftwarden"
        body(R, top="skin", pants="skin", sleeves="skin", cuffs="cloth1", feet="root", legs="bare", bulk=1.16 if big else 1.0,
             skirt=False)
        cloak(torso, ["cloth1", "cloth1", "feature"] if big else ["cloth1", "cloth1", "cloth1", "feature"], rng, 1.12 if big else 1.0)
        C.ico("glow", (0.0, -0.17, 0.2), (1, 0.6, 1.3), parent=torso, r=0.035, sub=1)   # amulet
        C.tube("leather", [(-0.06, -0.14, 0.4), (0.0, -0.17, 0.26), (0.06, -0.14, 0.4)], radius=0.01, parent=torso)
    # face
    if look == "warrior":
        C.sphere("wood", (0, -0.17, 0.25), (0.27, 0.16, 0.28), parent=head)                 # wooden mask
        C.box("wood", (0, -0.33, 0.2), (0.04, 0.03, 0.16), parent=head)
        for s in (-1, 1):
            C.box("cloth2", (s * 0.1, -0.325, 0.3), (0.08, 0.02, 0.028), (0, s * -12, 0), parent=head)
        C.box("skin2", (0, -0.32, 0.1), (0.1, 0.02, 0.015), parent=head)
    else:
        W.eyes("barkborn", head)
    for s in (-1, 1):   # pointed ears
        C.cone("skin", (s * 0.31, 0.02, 0.3), (0.45, 1, 1), (0, s * 70, s * 10), parent=head, r1=0.06, r2=0.0, depth=0.17, verts=6)
    # leaf hair over a dark bark crown, so single leaves stand out
    C.sphere("feature", (0, 0.05, 0.37), (0.31, 0.3, 0.27), parent=head)
    face_free = lambda d: not (d.y < -0.3 and d.z < 0.62)
    if look == "warrior":      # a big red mane
        leaf_mass(head, (0, 0.06, 0.34), (0.3, 0.3, 0.3), 44, ["hair", "hair", "hair", "feature"], rng, 0.18, keep=face_free, droop=0.7)
        leaf_mass(head, (0, 0.2, 0.05), (0.26, 0.14, 0.2), 14, ["hair", "feature"], rng, 0.2, keep=lambda d: d.y > -0.1)
    elif look == "rogue":      # long leafy hair with white flowers
        leaf_mass(head, (0, 0.05, 0.36), (0.3, 0.3, 0.26), 40, ["hair", "hair", "hair", "feature"], rng, 0.15, keep=face_free, droop=0.8)
        C.tube("hair", [(0, 0.22, 0.4), (0, 0.34, 0.2), (0, 0.34, -0.1), (0, 0.3, -0.34)], radius=0.16, parent=head, taper=[1, 1, 0.85, 0.45])
        for i in range(12):
            z = 0.3 - i * 0.055
            leaf(rng.choice(["hair", "feature"]), (rng.uniform(-0.12, 0.12), 0.4, z), (rng.uniform(-0.8, 0.8), 0.6, -0.6), head, 0.14)
        for (x, y, z) in ((-0.22, -0.14, 0.5), (0.24, -0.1, 0.46), (0.05, -0.2, 0.58), (-0.28, 0.08, 0.36)):
            flower(head, (x, y, z))
    elif look in ("mystic", "graftwarden"):
        leaf_mass(head, (0, 0.05, 0.37), (0.3, 0.3, 0.27), 42, ["hair", "hair", "hair", "feature"], rng, 0.16, keep=face_free, droop=0.6)
        if look == "graftwarden":      # mossy beard
            C.sphere("cape", (0, -0.2, 0.08), (0.2, 0.12, 0.14), parent=head)
            for x in (-0.1, 0.0, 0.1):
                leaf("cape", (x, -0.24, 0.02), (x, -0.3, -1), head, 0.1)
    else:
        leaf_mass(head, (0, 0.05, 0.37), (0.3, 0.3, 0.27), 44, ["hair", "hair", "hair", "feature"], rng, 0.17, keep=face_free, droop=0.6)
    antlers(head, 1.25 if look in ("mystic", "graftwarden") else 1.0, rng)
    # weapons
    if look == "warrior":
        axe(handR)
        leaf_shield(handL)
    elif look == "rogue":
        sickle(handR)
        basket(handL)
    elif look == "ranger":
        W.bow(handL)
        C.cyl("leather", (0.06, 0.16, 0.3), (1, 1, 1), (-15, 20, 0), parent=torso, r=0.06, depth=0.34)
        for dx in (-0.02, 0.02, 0.0):
            leaf("feature", (0.1 + dx, 0.2, 0.48), (0.2, 0.3, 1), torso, 0.06)
    else:
        gnarled_staff(handR, 1.12 if look == "graftwarden" else 1.0)


def leaf_skirt(torso, slots, rng, size, z=0.02):
    for i in range(18):
        a = math.radians(i * 20 + rng.uniform(-6, 6))
        base = (math.cos(a) * 0.16, math.sin(a) * 0.13, z)
        leaf(rng.choice(slots), base, (math.cos(a) * 0.35, math.sin(a) * 0.35, -1), torso, size * rng.uniform(0.85, 1.15))


def poncho(torso, slots, rng, size):
    for row, (z, r, n) in enumerate(((0.44, 0.13, 14), (0.3, 0.18, 16))):
        for i in range(n):
            a = math.radians(i * 360 / n + row * 11 + rng.uniform(-5, 5))
            base = (math.cos(a) * r, math.sin(a) * r * 0.85, z)
            leaf(rng.choice(slots), base, (math.cos(a) * 0.55, math.sin(a) * 0.5, -1), torso, size * rng.uniform(0.9, 1.15))


def cloak(torso, slots, rng, k=1.0):
    C.cone("cloth1", (0, 0.02, 0.0), parent=torso, r1=0.26 * k, r2=0.17 * k, depth=0.7)
    for row, (z, r, n, sz) in enumerate(((0.46, 0.15, 16, 0.14), (0.28, 0.2, 18, 0.15), (0.06, 0.23, 20, 0.15), (-0.16, 0.26, 20, 0.15))):
        for i in range(n):
            a = math.radians(i * 360 / n + row * 9 + rng.uniform(-5, 5))
            base = (math.cos(a) * r * k, math.sin(a) * r * k * 0.85, z)
            leaf(rng.choice(slots), base, (math.cos(a) * 0.4, math.sin(a) * 0.35, -1), torso, sz * k * rng.uniform(0.9, 1.15))


def flower(parent, loc):
    x, y, z = loc
    for i in range(5):
        a = math.radians(i * 72)
        C.sphere("white", (x + math.cos(a) * 0.035, y - 0.01, z + math.sin(a) * 0.035), (0.03, 0.02, 0.03), parent=parent, seg=8, rings=5)
    C.sphere("trim", (x, y - 0.025, z), (0.02, 0.015, 0.02), parent=parent, seg=8, rings=5)


def antlers(head, k, rng):
    for s in (-1, 1):
        C.tube("wood", [(s * 0.12, 0.0, 0.5), (s * 0.18, 0.02, 0.64 * k), (s * 0.22, 0.07, 0.78 * k)], radius=0.022,
               parent=head, taper=[1, 0.8, 0.5])
        C.tube("wood", [(s * 0.18, 0.02, 0.62 * k), (s * 0.28, 0.0, 0.68 * k), (s * 0.34, -0.03, 0.76 * k)], radius=0.017,
               parent=head, taper=[1, 0.7, 0.4])
        leaf("feature", (s * 0.34, -0.03, 0.76 * k), (s * 0.5, -0.2, 1), head, 0.08)


def axe(hand):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.cyl("wood", (0, -0.1, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.024, depth=0.46)
    C.box("metal", (0, -0.32, 0.08), (0.03, 0.12, 0.14), parent=w, bevel=0.01)
    C.cyl("metal", (0, -0.32, 0.15), (1, 1, 1), (0, 90, 0), parent=w, r=0.08, depth=0.03, verts=12)
    C.torus("leather", (0, -0.25, 0), (1, 1, 1), (90, 0, 0), parent=w, R=0.028, r=0.01)


def leaf_shield(hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.cyl("wood", (0, 0, 0), (0.85, 1, 1.15), (90, 0, 0), parent=w, r=0.17, depth=0.05, verts=16)
    C.torus("skin2", (0, -0.005, 0), (0.85, 1, 1.15), (90, 0, 0), parent=w, R=0.17, r=0.018)
    C.cone("feature", (0, -0.035, 0.0), (1, 0.25, 1), parent=w, r1=0.07, r2=0.0, depth=0.24, verts=6)


def sickle(hand):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.cyl("wood", (0, -0.05, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.022, depth=0.16)
    C.tube("metal", [(0, -0.12, 0), (0, -0.22, 0.1), (0, -0.2, 0.22), (0, -0.1, 0.26)], radius=0.022, parent=w,
           taper=[1.1, 1.0, 0.8, 0.3])


def basket(hand):
    w = C.pivot("basket", (0.03, -0.02, -0.08), hand)
    C.cyl("wood", (0, 0, 0), parent=w, r=0.1, depth=0.1, verts=12)
    C.torus("wood", (0, 0, 0.13), (1, 1, 1), (0, 90, 0), parent=w, R=0.1, r=0.012)
    for (x, y, c) in ((-0.04, 0.0, "cloth2"), (0.04, 0.02, "feature"), (0.0, -0.04, "white")):
        C.sphere(c, (x, y, 0.06), (0.04, 0.04, 0.035), parent=w, seg=8, rings=5)


def gnarled_staff(hand, k=1.0):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.tube("wood", [(0, 0, -0.4 * k), (0.03, -0.02, 0.0), (-0.02, 0.0, 0.3 * k), (0.05, 0.0, 0.56 * k), (0.12, 0.0, 0.66 * k)],
           radius=0.032, parent=w, taper=[0.8, 1, 1, 1.1, 0.9])
    C.tube("wood", [(0.04, 0.0, 0.52 * k), (-0.06, 0.0, 0.68 * k), (-0.02, 0.0, 0.8 * k)], radius=0.024, parent=w,
           taper=[1, 0.8, 0.5])
    C.ico("glow", (0.03, 0.0, 0.7 * k), (1, 1, 1.3), parent=w, r=0.065, sub=1)
    for x, z in ((0.12, 0.66 * k), (-0.02, 0.8 * k), (0.0, 0.3 * k)):
        leaf("feature" if z > 0.5 else "cloth1", (x, 0, z), (0.4, -0.3, 0.6), w, 0.08)


# ======================================================================
# Khepri
# ======================================================================
def khepri(R, look, W, rng):
    t = R["tall"]
    torso, head, handR, handL = R["torso"], R["head"], R["handR"], R["handL"]
    if look == "warrior":          # beetle-helmed bulwark
        body(R, top="cloth1", pants="cloth2", sleeves="cloth1", cuffs="trim", bulk=1.1)
        C.cone("cloth2", (0, 0.0, -0.1), parent=torso, r1=0.24, r2=0.17, depth=0.3)
        C.cone("cloth1", (0, 0.0, -0.12), (1, 1, 1), parent=torso, r1=0.25, r2=0.18, depth=0.14)
        C.box("trim", (0, -0.15, 0.24), (0.06, 0.02, 0.26), parent=torso)
        for s in (-1, 1):
            C.sphere("trim", (s * 0.21, 0, 0.41), (0.1, 0.1, 0.07), parent=torso)
        scarf("white", R, tail=0, bulk=1.1)
    elif look == "rogue":          # hooded scout
        body(R, top="cloth2", pants="cloth1", cuffs="leather")
        C.box("trim", (0, -0.14, 0.2), (0.12, 0.02, 0.03), (0, 0, 0), parent=torso)
        C.cone("cloth2", (0, 0.0, -0.08), parent=torso, r1=0.22, r2=0.16, depth=0.24)
    elif look == "ranger":
        body(R, top="cloth2", pants="leather", cuffs="leather")
        C.cone("cloth2", (0, 0.0, -0.08), parent=torso, r1=0.21, r2=0.16, depth=0.22)
        C.tube("leather", [(-0.14, -0.12, 0.42), (0.0, -0.14, 0.25), (0.15, -0.1, 0.06)], radius=0.018, parent=torso)
    elif look == "mystic":         # the elder
        body(R, top="cloth1", pants="cloth1", cuffs="cloth2", robe=True, bulk=1.06)
        C.box("cloth2", (0, -0.2, -0.17), (0.13, 0.02, 0.44), (-12, 0, 0), parent=torso)
        for s in (-1, 1):
            C.box("trim", (s * 0.075, -0.205, -0.17), (0.018, 0.02, 0.44), (-12, 0, 0), parent=torso)
        C.ico("glow", (0.0, -0.16, 0.34), (1, 0.6, 1.3), parent=torso, r=0.035, sub=1)
    else:                          # sandreaver: goggles and red scarf
        body(R, top="cloth1", pants="cape", cuffs="leather")
        C.cone("cloth1", (0, 0.0, -0.08), parent=torso, r1=0.21, r2=0.16, depth=0.22)
        belt_pouch(R, -0.15)
    pack(R, roll="cloth1" if look == "mystic" else "white")
    W.eyes("khepri", head)
    # shell: a darker carapace ridge over the head
    C.sphere("skin2", (0, 0.06, 0.36), (0.3, 0.3, 0.26), parent=head)
    if look == "warrior":          # bronze beetle helmet with a turquoise gem
        C.sphere("hair", (0, 0.03, 0.38), (0.345, 0.335, 0.27), parent=head)
        C.tube("trim", [(0, -0.3, 0.44), (0, -0.1, 0.66), (0, 0.2, 0.62), (0, 0.34, 0.4)], radius=0.03, parent=head)
        C.sphere("trim", (0, -0.29, 0.45), (0.1, 0.04, 0.09), parent=head)
        C.ico("glow", (0, -0.325, 0.45), (1, 0.6, 1.2), parent=head, r=0.045, sub=1)
        for s in (-1, 1):
            C.sphere("hair", (s * 0.27, -0.06, 0.2), (0.07, 0.14, 0.16), parent=head)
    elif look in ("rogue", "ranger"):
        hood("cloth2", head, tip=(look == "rogue"))
        # scarf over the lower face
        C.torus("cloth1", (0, -0.02, 0.06), (1, 1, 1.3), parent=head, R=0.2, r=0.07)
        C.sphere("cloth1", (0, -0.22, 0.12), (0.2, 0.1, 0.09), parent=head)
        if look == "rogue":
            C.tube("cloth1", [(0.12, 0.14, 0.08), (0.2, 0.3, -0.04), (0.24, 0.36, -0.2)], radius=0.045, parent=head, taper=[1, 0.9, 0.6])
    elif look == "mystic":         # cream headcloth and a long white beard
        C.sphere("white", (0, 0.08, 0.34), (0.345, 0.33, 0.3), parent=head)
        C.torus("trim", (0, 0.02, 0.44), (1, 1, 1), (-10, 0, 0), parent=head, R=0.32, r=0.022)
        C.ico("glow", (0, -0.3, 0.46), (1, 0.6, 1.2), parent=head, r=0.035, sub=1)
        for s in (-1, 1):
            C.tube("white", [(s * 0.26, 0.0, 0.3), (s * 0.3, 0.1, 0.0), (s * 0.28, 0.14, -0.16)], radius=0.09, parent=head, taper=[1, 0.9, 0.6])
        C.sphere("white", (0, -0.21, 0.07), (0.17, 0.1, 0.16), parent=head)
        C.cone("white", (0, -0.22, -0.1), (1, 0.7, 1), (180, 0, 0), parent=head, r1=0.12, r2=0.0, depth=0.22, verts=10)
    else:                          # leather cap with goggles
        C.sphere("leather", (0, 0.04, 0.4), (0.335, 0.325, 0.25), parent=head)
        C.torus("leather", (0, 0.0, 0.43), (1, 1, 1), (-12, 0, 0), parent=head, R=0.32, r=0.02)
        for s in (-1, 1):
            C.torus("metal", (s * 0.1, -0.27, 0.49), (1, 1, 1), (72, 0, 0), parent=head, R=0.06, r=0.022)
            C.sphere("white", (s * 0.1, -0.275, 0.49), (0.045, 0.02, 0.045), (-18, 0, 0), parent=head)
        C.tube("leather", [(0.28, 0.1, 0.44), (0.36, 0.16, 0.5), (0.38, 0.12, 0.62)], radius=0.035, parent=head, taper=[1, 0.9, 0.6])
        scarf("cloth2", R, tail=1, bulk=1.1)
    # long antennae with orange tips
    for s in (-1, 1):
        base_y = -0.14 if look not in ("rogue", "ranger", "mystic") else -0.1
        pts = [(s * 0.08, base_y, 0.52), (s * 0.1, base_y + 0.04, 0.74), (s * 0.16, base_y + 0.06, 0.9), (s * 0.24, base_y - 0.02, 0.96)]
        C.tube("skin", pts, radius=0.017, parent=head)
        ellipsoid_along("feature", (s * 0.25, base_y - 0.03, 0.965), (s * 0.5, -0.4, 0.2), (0.034, 0.034, 0.07), head)
    # weapons
    if look == "warrior":
        scimitar(handR)
        buckler(handL)
    elif look == "rogue":
        W.dagger(handR)
        scimitar(handL, 0.7)
    elif look == "ranger":
        W.bow(handL)
    elif look == "mystic":
        crook(handR)
    else:
        W.glass_blade(handR)
        W.glass_blade(handL)


def pack(R, roll="white"):
    """A travel pack with a bedroll, straps and dangling trinkets."""
    t = R["tall"]
    torso = R["torso"]
    C.box("leather", (0, 0.21, 0.26 * t), (0.3, 0.16, 0.34), parent=torso, bevel=0.035)
    C.box("leather", (0, 0.3, 0.2 * t), (0.18, 0.05, 0.13), parent=torso, bevel=0.015)
    C.sphere("trim", (0, 0.33, 0.24 * t), (0.025, 0.012, 0.02), parent=torso)
    C.cyl(roll, (0, 0.2, 0.47 * t), (1, 1, 1), (0, 90, 0), parent=torso, r=0.075, depth=0.36)
    C.torus("leather", (0, 0.2, 0.47 * t), (1, 1, 1), (0, 90, 0), parent=torso, R=0.078, r=0.012)
    for s in (-1, 1):
        C.tube("leather", [(s * 0.1, -0.1, 0.42 * t), (s * 0.12, 0.0, 0.47 * t), (s * 0.11, 0.14, 0.42 * t)], radius=0.02, parent=torso)
    C.ico("glow", (0.17, 0.24, 0.1 * t), (1, 1, 1.3), parent=torso, r=0.035, sub=1)
    C.sphere("trim", (-0.17, 0.24, 0.13 * t), (0.03, 0.03, 0.035), parent=torso)


def scimitar(hand, k=1.0):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.cyl("leather", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.022, depth=0.1)
    C.box("trim", (0, -0.06, 0), (0.12, 0.03, 0.03), parent=w)
    C.tube("metal", [(0, -0.07, 0), (0, -0.24 * k, 0.0), (0, -0.4 * k, 0.05), (0, -0.5 * k, 0.16)], radius=0.034, parent=w,
           taper=[0.9, 1.2, 1.1, 0.25])


def buckler(hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.cyl("trim", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.15, depth=0.04, verts=18)
    C.cyl("hair", (0, -0.015, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.12, depth=0.03, verts=18)
    C.ico("glow", (0, -0.04, 0), (1, 0.6, 1), parent=w, r=0.045, sub=1)


def crook(hand):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.cyl("wood", (0, 0, 0.1), parent=w, r=0.024, depth=1.0)
    C.tube("wood", [(0, 0, 0.58), (0.02, 0, 0.72), (0.12, 0, 0.78), (0.18, 0, 0.7), (0.14, 0, 0.62)], radius=0.026, parent=w)
    C.torus("trim", (0, 0, 0.55), parent=w, R=0.03, r=0.012)
    C.tube("trim", [(0.14, 0, 0.62), (0.14, 0, 0.54)], radius=0.006, parent=w)
    C.ico("glow", (0.14, 0, 0.5), (1, 1, 1.4), parent=w, r=0.04, sub=1)
