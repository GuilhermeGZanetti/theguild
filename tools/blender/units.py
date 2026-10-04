"""Render every unit of A Guilda as index-encoded sprite frames.

Run:  blender -b --factory-startup --python tools/blender/units.py -- --out tools/_cache/units [--only id1,id2] [--quick]

Output per variant: <out>/<id>/<anim>_<dir>_<frame>.png at 4x resolution plus
<out>/<id>/portrait.png. tools/py/sprites_post.py builds the final sheets.
--quick renders only the idle pose in each direction, one attack frame and
the portrait (for tools/py/model_sheet.py).

Playable races are modelled in characters.py (a masculine and a feminine
variant of every class); the enemies are built here.
"""
import sys
import os
import math
import json
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import bl_common as C  # noqa: E402
import characters as CH  # noqa: E402

# (name, frames) — shared with sprites_post.py and the game (unit_sprite.gd)
ANIMS = [("idle", 4), ("walk", 4), ("attack", 4), ("cast", 4), ("hit", 2),
         ("dodge", 2), ("downed", 2), ("death", 4)]
DIRS = [45.0, -45.0, -135.0, 135.0]   # front-right, front-left, back-left, back-right


# ======================================================================
# Variant catalogue
# ======================================================================
FACTION_LOOK = {"tidefolk": "tidecaller", "mothkin": "lanternbearer", "barkborn": "graftwarden", "khepri": "sandreaver"}


def variants():
    """Playable variants: <race>_<look>_<m|f> (humans add a hairstyle: _a/_b)."""
    v = []
    for race in CH.RACES:
        looks = ["warrior", "rogue", "ranger", "mystic"] + ([FACTION_LOOK[race]] if race in FACTION_LOOK else [])
        for look in looks:
            for g in ("m", "f"):
                for h in (["a", "b"] if race == "human" else ["a"]):
                    vid = f"{race}_{look}_{g}" + (f"_{h}" if race == "human" else "")
                    v.append({"id": vid, "rig": "humanoid", "race": race, "look": look, "gender": g, "hair": h,
                              "canvas": 64, "bandage": True})
    # humanoid enemies
    v.append({"id": "toad_brute", "rig": "humanoid", "race": "toad", "look": "brute", "hair": "a", "canvas": 64})
    v.append({"id": "toad_slinger", "rig": "humanoid", "race": "toad", "look": "ranger", "hair": "a", "canvas": 64})
    v.append({"id": "hollow", "rig": "humanoid", "race": "hollow", "look": "hollow", "hair": "a", "canvas": 64})
    v.append({"id": "npc_villager", "rig": "humanoid", "race": "human", "look": "villager", "gender": "f", "hair": "b", "canvas": 64})
    # creatures
    v.append({"id": "stinger", "rig": "floater", "kind": "stinger", "canvas": 64})
    v.append({"id": "stinger_queen", "rig": "floater", "kind": "stinger", "canvas": 96, "scale": 1.55})
    v.append({"id": "serpent", "rig": "serpent", "kind": "serpent", "canvas": 64})
    v.append({"id": "serpent_elder", "rig": "serpent", "kind": "serpent", "canvas": 96, "scale": 1.45})
    v.append({"id": "spirit", "rig": "floater", "kind": "spirit", "canvas": 64})
    v.append({"id": "spirit_elder", "rig": "floater", "kind": "spirit", "canvas": 96, "scale": 1.4})
    v.append({"id": "deer", "rig": "quad", "kind": "deer", "canvas": 96})
    v.append({"id": "deer_elder", "rig": "quad", "kind": "deer", "canvas": 96, "scale": 1.3})
    v.append({"id": "scorpion", "rig": "scorpion", "kind": "scorpion", "canvas": 96})
    v.append({"id": "scorpion_matriarch", "rig": "scorpion", "kind": "scorpion", "canvas": 96, "scale": 1.3})
    v.append({"id": "quietling", "rig": "floater", "kind": "quietling", "canvas": 64})
    v.append({"id": "unwritten", "rig": "humanoid", "race": "unwritten", "look": "unwritten", "hair": "a", "canvas": 96})
    v.append({"id": "unnamed", "rig": "humanoid", "race": "unnamed", "look": "unnamed", "hair": "a", "canvas": 128})
    return v


# ======================================================================
# Humanoid builder
# ======================================================================
class Rig(dict):
    pass


def build_humanoid(spec, bandage=False):
    race, look = spec["race"], spec["look"]
    tall = CH.tall_of(spec) if race in CH.RACES else {"unwritten": 1.3, "unnamed": 1.55}.get(race, 1.0)
    R = Rig()
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0), root)
    hips = C.pivot("hips", (0, 0, 0.40 * tall), body)
    torso = C.pivot("torso", (0, 0, 0), hips)
    neck = C.pivot("neck", (0, 0, 0.44 * tall), torso)
    head = C.pivot("head", (0, 0, 0), neck)
    armR = C.pivot("armR", (-0.19, 0, 0.38 * tall), torso)
    armL = C.pivot("armL", (0.19, 0, 0.38 * tall), torso)
    handR = C.pivot("handR", (0, 0, -0.30 * tall), armR)
    handL = C.pivot("handL", (0, 0, -0.30 * tall), armL)
    legR = C.pivot("legR", (-0.085, 0, 0.0), hips)
    legL = C.pivot("legL", (0.085, 0, 0.0), hips)
    R.update(root=root, body=body, hips=hips, torso=torso, neck=neck, head=head,
             armR=armR, armL=armL, handR=handR, handL=handL, legR=legR, legL=legL,
             race=race, look=look, tall=tall)

    if race in CH.RACES:
        CH.build(R, spec, bandage)
        return R

    # ---- enemies: toads, the hollow and the two bosses
    robe = look in ("hollow", "unwritten", "unnamed")
    skin_arms = look == "brute"
    # ---- torso
    C.sphere("cloth1", (0, 0, 0.22 * tall), (0.165, 0.13, 0.25 * tall), parent=torso)
    C.torus("leather", (0, 0, 0.07 * tall), (1, 0.82, 1), parent=torso, R=0.16, r=0.028)
    C.sphere("trim", (0, -0.13, 0.07 * tall), (0.03, 0.015, 0.025), parent=torso)  # buckle
    # ---- legs
    for leg in (legR, legL):
        if not robe:
            C.cyl("cloth2", (0, 0, -0.16), (1, 1, 1), parent=leg, r=0.062, depth=0.26)
        C.sphere("leather", (0, -0.03, -0.335), (0.07, 0.1, 0.06), parent=leg)
    if not robe:
        C.cone("cloth1", (0, 0, -0.02), parent=torso, r1=0.2, r2=0.155, depth=0.16)
    else:
        C.cone("cloth1", (0, 0, -0.17 * tall), parent=torso, r1=0.25, r2=0.155, depth=0.46 * tall)
        C.torus("cloth2", (0, 0, -0.395 * tall), (1, 1, 0.6), parent=torso, R=0.235, r=0.03)
    # ---- arms
    for side, arm, hand in ((-1, armR, handR), (1, armL, handL)):
        sleeve = "skin" if skin_arms else "cloth1"
        C.cyl(sleeve, (0, 0, -0.12 * tall), parent=arm, r=0.052, depth=0.22 * tall)
        C.sphere("leather" if skin_arms else "cloth2", (0, 0, -0.215 * tall), (0.06, 0.06, 0.035), parent=arm)
        C.sphere("skin2" if race in ("hollow", "unnamed") else "skin", (0, 0, 0.03), (0.058, 0.058, 0.058), parent=hand)
    # ---- head
    hs = 1.0 if race != "unnamed" else 0.92
    head_mesh = C.sphere("skin", (0, 0, 0.28), (0.31 * hs, 0.30 * hs, 0.29 * hs), parent=head)
    if race == "toad":
        head_mesh.scale = (0.36, 0.3, 0.24)
        head_mesh.location = (0, -0.02, 0.22)
    eyes(race, head)
    hairdo(race, head)
    outfit(look, R)
    if bandage:
        C.torus("bandage", (0, -0.01, 0.36), (1.0, 1.0, 0.8), (-14, 0, 0), parent=head, R=0.305, r=0.034)
        C.box("bandage", (0.09, -0.06, -0.08), (0.06, 0.02, 0.1), parent=torso)
    return R


def eyes(race, head):
    if race in ("hollow", "unnamed"):
        return
    if race == "toad":
        for s in (-1, 1):
            C.sphere("white", (s * 0.15, -0.12, 0.38), (0.085, 0.085, 0.085), parent=head)
            C.sphere("eyes", (s * 0.155, -0.19, 0.39), (0.04, 0.03, 0.05), parent=head)
        C.tube("eyes", [(-0.18, -0.265, 0.17), (0, -0.30, 0.15), (0.18, -0.265, 0.17)], radius=0.012, parent=head)
        return
    for s in (-1, 1):
        C.sphere("eyes", (s * 0.11, -0.268, 0.25), (0.036, 0.03, 0.068), parent=head)


def hairdo(race, head):
    if race == "hollow":
        C.sphere("cloth2", (0, 0.04, 0.32), (0.34, 0.33, 0.33), parent=head)
        C.sphere("skin2", (0, -0.23, 0.25), (0.2, 0.08, 0.2), parent=head)
    elif race == "unwritten":
        # a blank page for a face
        C.box("white", (0, -0.1, 0.3), (0.42, 0.04, 0.52), (8, 0, 0), parent=head, bevel=0.01)
        C.sphere("cloth2", (0, 0.1, 0.34), (0.33, 0.25, 0.34), parent=head)
    elif race == "unnamed":
        C.sphere("hair", (0, 0.06, 0.36), (0.33, 0.32, 0.3), parent=head)
        C.tube("hair", [(0, 0.22, 0.4), (0, 0.46, 0.1), (0, 0.62, -0.3), (0, 0.7, -0.7)], radius=0.18, parent=head,
               taper=[1.0, 1.1, 0.9, 0.5])
        for s in (-1, 1):
            C.tube("hair", [(s * 0.25, 0.0, 0.3), (s * 0.34, 0.1, 0.0), (s * 0.3, 0.2, -0.35)], radius=0.08, parent=head,
                   taper=[1.0, 0.9, 0.4])


def outfit(look, R):
    torso, handR, armR, armL = R["torso"], R["handR"], R["armR"], R["armL"]
    t = R["tall"]
    if look == "ranger":            # toad slinger
        C.sphere("leather", (0, -0.01, 0.27), (0.17, 0.134, 0.17), parent=torso)
        C.sphere("cape", (0, 0.1, 0.2), (0.2, 0.08, 0.26), parent=torso)
        C.cyl("leather", (0.06, 0.16, 0.3), (1, 1, 1), (-15, 20, 0), parent=torso, r=0.06, depth=0.34)
        for dx in (-0.02, 0.02, 0.0):
            C.cone("white", (0.1 + dx, 0.2, 0.52), (1, 0.5, 1), (-15, 20, 0), parent=torso, r1=0.03, r2=0.0, depth=0.08, verts=4)
        bow(R["handL"])
    elif look == "brute":
        C.sphere("skin2", (0, -0.03, 0.2), (0.15, 0.12, 0.18), parent=torso)
        C.tube("leather", [(-0.16, -0.13, 0.42), (0.0, -0.15, 0.25), (0.16, -0.12, 0.06)], radius=0.025, parent=torso)
        cleaver(handR)
    elif look == "hollow":
        for s in (-1, 1):
            arm = armR if s < 0 else armL
            C.cone("skin2", (0, 0, -0.38), (1, 1, 1), (180, 0, 0), parent=arm, r1=0.03, r2=0.0, depth=0.12, verts=6)
    elif look == "unwritten":
        C.tube("feature", [(0, 0, -0.6), (0, 0, 0.9)], radius=0.035, parent=handR)
        C.cone("white", (0, 0, 1.05), (1, 0.35, 1), parent=handR, r1=0.1, r2=0.0, depth=0.42, verts=10)
        C.cone("metal", (0, 0, -0.68), (1, 1, 1), (180, 0, 0), parent=handR, r1=0.04, r2=0.0, depth=0.14, verts=6)
    elif look == "unnamed":
        C.torus("cloth2", (0, 0, 0.44 * t), (1, 1, 1), parent=torso, R=0.16, r=0.05)
        crown = C.pivot("crown", (0, 0, 0.75), R["head"])
        R["crown"] = crown
        for i in range(6):
            a = math.radians(i * 60)
            C.box("white", (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.0), (0.14, 0.02, 0.18), (0, 0, math.degrees(a) + 90), parent=crown)


def bow(hand):
    w = C.pivot("weapon", (0.0, -0.03, 0.0), hand)
    pts = [(0, -0.02, 0.36), (0, -0.13, 0.2), (0, -0.16, 0.0), (0, -0.13, -0.2), (0, -0.02, -0.36)]
    C.tube("wood", pts, radius=0.022, parent=w, taper=[0.6, 1, 1.2, 1, 0.6])
    C.tube("white", [(0, -0.02, 0.35), (0, 0.02, 0.0), (0, -0.02, -0.35)], radius=0.006, parent=w)


def cleaver(hand):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.cyl("wood", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.025, depth=0.14)
    C.box("metal", (0, -0.24, 0.05), (0.03, 0.3, 0.16), parent=w, bevel=0.005)


# ======================================================================
# Creatures
# ======================================================================
def build_floater(spec):
    kind = spec["kind"]
    R = Rig(kind=kind)
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.55), root)
    R.update(root=root, body=body, tentacles=[])
    if kind == "stinger":
        C.sphere("cloth1", (0, 0, 0.15), (0.42, 0.42, 0.32), parent=body)
        C.sphere("glow", (0, 0, 0.12), (0.2, 0.2, 0.16), parent=body)
        C.torus("cloth2", (0, 0, -0.04), (1, 1, 0.6), parent=body, R=0.36, r=0.07)
        for s in (-1, 1):
            C.sphere("eyes", (s * 0.12, -0.36, 0.14), (0.04, 0.03, 0.06), parent=body)
        for i in range(7):
            a = math.radians(i * 360 / 7 + 10)
            x, y = math.cos(a) * 0.24, math.sin(a) * 0.24
            t = C.tube("cloth2" if i % 2 else "feature", [(x, y, -0.05), (x, y, -0.2), (x, y, -0.35), (x, y, -0.5)],
                       radius=0.035, parent=body, taper=[1.0, 0.9, 0.7, 0.3])
            R["tentacles"].append((t, x, y, i))
    elif kind == "spirit":
        C.cone("cloth1", (0, 0, 0.05), (1, 0.9, 1), parent=body, r1=0.3, r2=0.12, depth=0.7)
        C.sphere("cloth1", (0, 0.02, 0.48), (0.26, 0.24, 0.28), parent=body)
        mask = C.pivot("mask", (0, -0.2, 0.47), body)
        C.sphere("white", (0, 0, 0), (0.22, 0.07, 0.27), parent=mask)
        for s in (-1, 1):
            C.sphere("eyes", (s * 0.08, -0.06, 0.05), (0.04, 0.02, 0.05), parent=mask)
            C.box("feature", (s * 0.08, -0.06, -0.08), (0.03, 0.02, 0.1), parent=mask)
        C.cone("wood", (0, 0.05, 0.25), (1, 1, 1), (-40, 0, 0), parent=mask, r1=0.05, r2=0.0, depth=0.22, verts=6)
        for s in (-1, 1):
            h = C.pivot("hand", (s * 0.3, -0.05, 0.1), body)
            C.sphere("skin2", (0, 0, 0), (0.06, 0.06, 0.06), parent=h)
            R["hand" + ("R" if s < 0 else "L")] = h
        for i in range(4):
            a = math.radians(i * 90 + 45)
            x, y = math.cos(a) * 0.18, math.sin(a) * 0.18
            t = C.tube("cloth1", [(x, y, -0.25), (x, y, -0.35), (x, y, -0.45)], radius=0.06, parent=body, taper=[1, 0.6, 0.1])
            R["tentacles"].append((t, x, y, i))
    elif kind == "quietling":
        body.location = (0, 0, 0.3)
        C.sphere("skin", (0, 0, 0.3), (0.26, 0.24, 0.24), parent=body)
        C.sphere("cloth1", (0, 0.02, 0.0), (0.13, 0.11, 0.16), parent=body)
        for s in (-1, 1):
            C.sphere("glow", (s * 0.1, -0.21, 0.3), (0.06, 0.03, 0.07), parent=body)
            C.cone("skin", (s * 0.22, 0.02, 0.5), (1, 1, 1), (0, s * 30, 0), parent=body, r1=0.06, r2=0.0, depth=0.18, verts=6)
            h = C.pivot("hand", (s * 0.16, -0.02, 0.0), body)
            C.tube("skin", [(0, 0, 0), (s * 0.06, -0.04, -0.12), (s * 0.05, -0.08, -0.2)], radius=0.022, parent=h)
            R["hand" + ("R" if s < 0 else "L")] = h
        for s in (-1, 1):
            C.tube("skin", [(s * 0.06, 0, -0.12), (s * 0.08, 0, -0.26)], radius=0.025, parent=body)
    return R


def build_serpent(spec):
    R = Rig(kind="serpent")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0), root)
    C.torus("skin", (0, 0.05, 0.08), (1, 1, 1.2), parent=body, R=0.3, r=0.1)
    C.torus("skin", (0.05, 0.08, 0.2), (0.8, 0.8, 1.1), parent=body, R=0.22, r=0.09)
    neck = C.tube("skin", [(0, -0.1, 0.2), (0, -0.05, 0.5), (0, -0.15, 0.8), (0, -0.25, 0.95)], radius=0.1, parent=body,
                  taper=[1.1, 1.0, 0.9, 0.85])
    head = C.pivot("head", (0, -0.28, 0.98), body)
    C.sphere("skin", (0, -0.08, 0), (0.15, 0.24, 0.12), parent=head)
    C.sphere("skin2", (0, -0.1, -0.06), (0.12, 0.2, 0.06), parent=head)
    for s in (-1, 1):
        C.sphere("eyes", (s * 0.11, -0.14, 0.06), (0.035, 0.04, 0.035), parent=head)
        C.cone("feature", (s * 0.14, 0.08, 0.06), (0.3, 1, 1), (60, 0, s * 25), parent=head, r1=0.1, r2=0.0, depth=0.22, verts=6)
    C.cone("feature", (0, 0.12, 0.14), (0.3, 1, 1), (70, 0, 0), parent=head, r1=0.1, r2=0.0, depth=0.26, verts=6)
    R.update(root=root, body=body, neck=neck, head=head)
    return R


def build_quad(spec):
    R = Rig(kind="deer")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.58), root)
    C.sphere("cloth1", (0, 0.05, 0), (0.22, 0.44, 0.22), parent=body)
    C.sphere("cloth2", (0, 0.0, -0.08), (0.18, 0.36, 0.14), parent=body)
    for (x, y, z) in ((0.14, 0.1, 0.1), (-0.12, 0.28, 0.12), (0.05, -0.2, 0.16)):
        C.ico("feature", (x, y, z), (1, 1, 0.7), parent=body, r=0.1, sub=1)
    for i in range(3):
        C.torus("white", (0.0, 0.0 + i * 0.1, -0.02), (1.05, 0.25, 1), (0, 0, 0), parent=body, R=0.2, r=0.015)
    legs = []
    for (x, y) in ((-0.13, -0.3), (0.13, -0.3), (-0.13, 0.36), (0.13, 0.36)):
        lp = C.pivot("leg", (x, y, -0.05), body)
        C.cyl("cloth1", (0, 0, -0.25), (1, 1, 1), parent=lp, r=0.045, depth=0.46)
        C.sphere("skin2", (0, 0, -0.5), (0.05, 0.06, 0.04), parent=lp)
        legs.append(lp)
    neckp = C.pivot("neck", (0, -0.38, 0.1), body)
    C.cyl("cloth1", (0, -0.05, 0.16), (1, 1, 1), (-30, 0, 0), parent=neckp, r=0.09, depth=0.36)
    head = C.pivot("head", (0, -0.14, 0.36), neckp)
    C.sphere("cloth1", (0, -0.06, 0), (0.13, 0.2, 0.12), parent=head)
    C.sphere("skin2", (0, -0.24, -0.03), (0.07, 0.07, 0.06), parent=head)
    for s in (-1, 1):
        C.sphere("glow", (s * 0.1, -0.1, 0.05), (0.03, 0.04, 0.035), parent=head)
        C.cone("cloth1", (s * 0.15, 0.06, 0.08), (0.4, 1, 1), (0, s * 70, 0), parent=head, r1=0.06, r2=0.0, depth=0.16, verts=6)
        C.tube("white", [(s * 0.06, 0.02, 0.1), (s * 0.18, 0.08, 0.36), (s * 0.3, 0.02, 0.54), (s * 0.34, -0.06, 0.66)],
               radius=0.025, parent=head, taper=[1, 0.9, 0.7, 0.4])
        C.tube("white", [(s * 0.18, 0.08, 0.36), (s * 0.12, -0.06, 0.5)], radius=0.018, parent=head)
        C.tube("white", [(s * 0.3, 0.02, 0.54), (s * 0.42, 0.12, 0.62)], radius=0.016, parent=head)
    C.cone("cloth2", (0, 0.5, 0.08), (1, 1, 1), (-60, 0, 0), parent=body, r1=0.06, r2=0.0, depth=0.14, verts=6)
    R.update(root=root, body=body, legs=legs, neck=neckp, head=head)
    return R


def build_scorpion(spec):
    R = Rig(kind="scorpion")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.26), root)
    C.sphere("cloth1", (0, 0, 0), (0.3, 0.4, 0.14), parent=body)
    C.sphere("cloth2", (0, -0.34, 0.02), (0.2, 0.16, 0.11), parent=body)
    for s in (-1, 1):
        C.sphere("glow", (s * 0.07, -0.46, 0.08), (0.03, 0.03, 0.03), parent=body)
    legs = []
    for i, y in enumerate((-0.15, 0.0, 0.14, 0.26)):
        for s in (-1, 1):
            lp = C.pivot("leg", (s * 0.26, y, 0.0), body)
            C.tube("cloth2", [(0, 0, 0), (s * 0.16, 0, 0.1), (s * 0.3, 0, -0.26)], radius=0.022, parent=lp)
            legs.append((lp, s, i))
    claws = []
    for s in (-1, 1):
        cp = C.pivot("claw", (s * 0.2, -0.42, 0.0), body)
        C.tube("cloth1", [(0, 0, 0), (s * 0.12, -0.14, 0.04), (s * 0.1, -0.3, 0.06)], radius=0.04, parent=cp)
        C.sphere("cloth1", (s * 0.1, -0.38, 0.06), (0.08, 0.1, 0.06), parent=cp)
        C.cone("cloth1", (s * 0.06, -0.5, 0.06), (0.6, 1, 0.5), (90, 0, 0), parent=cp, r1=0.05, r2=0.0, depth=0.14, verts=6)
        C.cone("cloth1", (s * 0.14, -0.49, 0.06), (0.6, 1, 0.5), (90, 0, 0), parent=cp, r1=0.04, r2=0.0, depth=0.12, verts=6)
        claws.append((cp, s))
    tail = C.pivot("tail", (0, 0.36, 0.04), body)
    segs = []
    parent = tail
    for i in range(5):
        sp = C.pivot("seg", (0, 0.12 if i else 0.0, 0.08 if i else 0.0), parent)
        C.sphere("cloth1" if i < 4 else "glow", (0, 0.04, 0.03), (0.09 - i * 0.008, 0.1, 0.08), parent=sp)
        segs.append(sp)
        parent = sp
    C.cone("glow", (0, -0.06, 0.1), (1, 1, 1), (-120, 0, 0), parent=segs[-1], r1=0.045, r2=0.0, depth=0.18, verts=6)
    R.update(root=root, body=body, legs=legs, claws=claws, tail=tail, segs=segs)
    return R


# ======================================================================
# Poses
# ======================================================================
def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def reset_pose(R):
    for obj in bpy.data.objects:
        if obj.type == "EMPTY" and obj.name != "yaw" and not obj.get("static"):
            C.set_rot(obj)
    R["root"].location = (0, 0, 0)
    if R.get("kind") in ("stinger", "spirit"):
        R["body"].location = (0, 0, 0.55)
    elif R.get("kind") == "quietling":
        R["body"].location = (0, 0, 0.3)
    elif R.get("kind") == "deer":
        R["body"].location = (0, 0, 0.58)
    elif R.get("kind") == "scorpion":
        R["body"].location = (0, 0, 0.26)
    elif "hips" in R:
        R["body"].location = (0, 0, 0)
    for k in ("body",):
        R[k].scale = (1, 1, 1)


def pose_humanoid(R, anim, f, n):
    ph = f / n
    look = R["look"]
    hips, torso, head, body = R["hips"], R["torso"], R["head"], R["body"]
    aR, aL, lR, lL = R["armR"], R["armL"], R["legR"], R["legL"]
    ranged = look in ("ranger",)
    caster = look in ("mystic", "lanternbearer", "graftwarden", "unnamed", "hollow")
    # neutral hold
    C.set_rot(aR, -25 if look != "ranger" else 8, 0, -8)
    C.set_rot(aL, 8 if look not in ("warrior", "ranger") else -30, 0, 8)
    if look == "ranger":
        C.set_rot(aL, -35, 0, 18)
    if look in ("mystic", "lanternbearer", "graftwarden", "tidecaller", "unwritten"):
        C.set_rot(aR, -12, 0, -10)
    if "crown" in R:
        C.set_rot(R["crown"], 0, 0, f * 15 + [a for a, _ in ANIMS].index(anim) * 7 if anim in dict(ANIMS) else 0)
    # the tidefolk jellyfish bobs; mothkin wings sway
    if "jelly" in R:
        bx, by, bz = R["jelly_base"]
        R["jelly"].location = (bx, by, bz + 0.035 * math.sin(ph * 2 * math.pi + 1.0))
    if "wingL" in R:
        a = 6 + 7 * math.sin(ph * 2 * math.pi)
        if anim in ("cast", "attack") and caster:
            a = -12 + 6 * f
        elif anim in ("hit", "dodge"):
            a = 18
        elif anim in ("downed", "death"):
            a = 22
        C.set_rot(R["wingL"], 0, 0, a)
        C.set_rot(R["wingR"], 0, 0, -a)
    if anim == "idle":
        b = math.sin(ph * 2 * math.pi)
        body.location = (0, 0, -0.012 * (1 - b) * 0.5)
        C.set_rot(torso, 2 * b, 0, 0)
        C.set_rot(head, -2 * b, 0, 0)
        C.set_rot(aR, aR.rotation_euler.x * 57.3 + 3 * b, 0, -8 - 2 * b)
        C.set_rot(aL, aL.rotation_euler.x * 57.3 - 3 * b, 0, 8 + 2 * b)
    elif anim == "walk":
        s = math.sin(ph * 2 * math.pi)
        c = abs(math.cos(ph * 2 * math.pi))
        body.location = (0, 0, 0.03 * c)
        C.set_rot(lR, 32 * s, 0, 0)
        C.set_rot(lL, -32 * s, 0, 0)
        if look not in ("ranger",):
            C.set_rot(aL, -25 * s + (-20 if look == "warrior" else 0), 0, 8)
        if look not in ("mystic", "lanternbearer", "graftwarden", "tidecaller", "unwritten"):
            C.set_rot(aR, 25 * s - 20, 0, -8)
        C.set_rot(torso, 6, 0, 5 * s)
    elif anim == "attack":
        if ranged:
            # draw, aim, release, recover
            draw = [0.4, 1.0, 1.0, 0.3][f]
            C.set_rot(aL, -90, 0, 10 - 10 * draw)
            C.set_rot(aR, -90 + 10 * draw, 0, -40 * draw)
            C.set_rot(torso, 0, 0, 25 * draw)
            if f == 2:
                C.set_rot(aR, -80, 0, -70)
            body.location = (0, 0.03 * draw, 0)
        elif caster:
            poses = [(-150, -150, 0.0), (-170, -165, -0.02), (-75, -80, -0.08), (-40, -30, -0.03)]
            r, l, dy = poses[f]
            C.set_rot(aR, r, 0, -12)
            C.set_rot(aL, l, 0, 12)
            body.location = (0, dy, 0)
            C.set_rot(torso, [-8, -12, 14, 5][f], 0, 0)
        elif look in ("rogue", "sandreaver", "tidecaller", "unwritten"):
            poses = [(20, 15, 0.03, 18), (-95, 10, -0.14, -20), (-85, -70, -0.16, 22), (-30, 0, -0.04, 0)]
            r, l, dy, tw = poses[f]
            C.set_rot(aR, r, 0, -10)
            if look != "tidecaller":
                C.set_rot(aL, l, 0, 10)
            body.location = (0, dy, 0)
            C.set_rot(torso, 10 if f in (1, 2) else 0, 0, tw)
            C.set_rot(lR, -20 if f in (1, 2) else 0, 0, 0)
            C.set_rot(lL, 25 if f in (1, 2) else 0, 0, 0)
        else:  # heavy swing
            poses = [(-165, 25, 0.02, 25), (-110, 10, -0.08, 5), (-25, -10, -0.14, -30), (-35, 0, -0.05, -10)]
            r, tilt, dy, tw = poses[f]
            C.set_rot(aR, r, 0, -15)
            C.set_rot(torso, 15 if f >= 1 else -8, 0, tw)
            body.location = (0, dy, 0)
            C.set_rot(lR, -20 if f >= 1 else 0, 0, 0)
            C.set_rot(lL, 25 if f >= 1 else 0, 0, 0)
    elif anim == "cast":
        poses = [(-100, -100, 0), (-160, -160, 0.02), (-165, -165, 0.03), (-70, -70, 0)]
        r, l, up = poses[f]
        C.set_rot(aR, r, 0, -20)
        C.set_rot(aL, l, 0, 20)
        body.location = (0, 0, up)
        C.set_rot(head, -10 if f in (1, 2) else 0, 0, 0)
    elif anim == "hit":
        k = [1.0, 0.5][f]
        body.location = (0, 0.07 * k, 0)
        C.set_rot(torso, -14 * k, 0, 0)
        C.set_rot(head, -16 * k, 0, 6 * k)
        C.set_rot(aR, -30 - 20 * k, 0, -30 * k)
        C.set_rot(aL, -20 - 20 * k, 0, 30 * k)
    elif anim == "dodge":
        k = [1.0, 0.5][f]
        body.location = (0.12 * k, 0.04 * k, -0.02 * k)
        C.set_rot(torso, -6 * k, -18 * k, 0)
        C.set_rot(lR, 15 * k, 0, -10 * k)
    elif anim in ("downed", "death"):
        if anim == "downed":
            fall, breathe = 1.0, (0.01 if f else 0.0)
        else:
            fall, breathe = [0.2, 0.55, 0.9, 1.0][f], 0.0
        kneel = min(1.0, fall * 1.6)
        lay = max(0.0, (fall - 0.35) / 0.65)
        C.set_rot(lR, -80 * kneel * (1 - lay), 0, 0)
        C.set_rot(lL, -60 * kneel * (1 - lay), 0, 0)
        body.location = (0, 0.0, -0.18 * kneel * (1 - lay))
        C.set_rot(R["root"], -84 * lay, 0, 0)
        R["root"].location = (0, -0.55 * lay, 0.1 * lay + breathe)
        C.set_rot(aR, -170 * lay, 0, -40 * lay)
        C.set_rot(aL, -150 * lay, 0, 50 * lay)
        C.set_rot(head, 10 * kneel - 10 * lay, 0, 20 * lay)


def pose_floater(R, anim, f, n):
    ph = f / n
    body = R["body"]
    base = {"stinger": 0.55, "spirit": 0.55, "quietling": 0.3}[R["kind"]]
    wob = 0.0
    lean = 0.0
    sx = sz = 1.0
    dy = 0.0
    if anim == "idle" or anim == "walk":
        wob = math.sin(ph * 2 * math.pi) * (0.04 if anim == "idle" else 0.06)
        lean = 8 if anim == "walk" else 0
        sz = 1.0 + 0.05 * math.sin(ph * 2 * math.pi)
        sx = 1.0 - 0.03 * math.sin(ph * 2 * math.pi)
    elif anim == "attack":
        dy, lean, sz = [(0.06, -10, 1.1), (-0.2, 25, 0.9), (-0.28, 30, 0.85), (-0.06, 5, 1.0)][f]
        sx = 2.0 - sz
    elif anim == "cast":
        wob, sz = [(0.05, 1.05), (0.12, 1.15), (0.14, 1.2), (0.03, 1.0)][f]
    elif anim == "hit":
        dy, lean, sz = [(0.08, -20, 0.8), (0.04, -8, 0.92)][f]
        sx = 2.0 - sz
    elif anim == "dodge":
        body.location = (0.14 * [1, 0.5][f], 0, base)
    elif anim in ("downed", "death"):
        k = 1.0 if anim == "downed" else [0.3, 0.6, 0.85, 1.0][f]
        wob = -base * 0.8 * k
        sz = 1.0 - 0.45 * k
        sx = 1.0 + 0.25 * k
        lean = 15 * k
    if anim != "dodge":
        body.location = (0, dy, base + wob)
    body.scale = (sx, sx, sz)
    C.set_rot(body, lean, 0, 0)
    for (t, x, y, i) in R.get("tentacles", []):
        sp = t.data.splines[0]
        for j, p in enumerate(sp.points):
            depth = p.co[2]
            sway = math.sin(ph * 2 * math.pi + i * 1.3 + j * 0.9) * 0.05 * j
            trail = 0.08 * j if anim in ("walk", "attack") else 0.0
            p.co = (x + sway, y + trail + (0.0 if j == 0 else sway * 0.5), depth, 1.0)
    for hk in ("handR", "handL"):
        if hk in R:
            s = -1 if hk == "handR" else 1
            reach = 0.0
            if anim == "attack":
                reach = [0.0, 0.2, 0.28, 0.08][f]
            if anim == "cast":
                reach = [0.05, 0.15, 0.18, 0.02][f]
            R[hk].location = (s * (0.3 if R["kind"] == "spirit" else 0.16), -0.05 - reach,
                              (0.1 if R["kind"] == "spirit" else 0.0) + reach * 0.8 + 0.02 * math.sin(ph * 6.28))


def pose_serpent(R, anim, f, n):
    ph = f / n
    head, neck, body = R["head"], R["neck"], R["body"]
    sw = math.sin(ph * 2 * math.pi)
    hy, hz, tilt = -0.28, 0.98, 0.0
    if anim in ("idle", "walk"):
        hy += 0.04 * sw
        hz += 0.03 * sw
        body.location = (0, 0.0, 0.0)
    elif anim == "attack":
        hy, hz, tilt = [(-0.1, 1.05, -20), (-0.6, 0.6, 40), (-0.7, 0.45, 50), (-0.35, 0.85, 10)][f]
    elif anim == "cast":
        hz, tilt = [(1.1, -25), (1.2, -35), (1.2, -35), (1.0, -5)][f]
    elif anim == "hit":
        hy, hz, tilt = [(-0.1, 0.9, -30), (-0.2, 0.95, -12)][f]
    elif anim == "dodge":
        body.location = (0.12 * [1, 0.5][f], 0, 0)
    elif anim in ("downed", "death"):
        k = 1.0 if anim == "downed" else [0.3, 0.6, 0.9, 1.0][f]
        hy, hz, tilt = -0.28 - 0.3 * k, 0.98 - 0.8 * k, 50 * k
    head.location = (0.02 * sw if anim == "idle" else 0, hy, hz)
    C.set_rot(head, tilt, 0, 0)
    sp = neck.data.splines[0]
    pts = [(0, -0.1, 0.2), (0.05 * sw, (hy - 0.1) * 0.3, 0.2 + (hz - 0.2) * 0.45),
           (-0.04 * sw, hy * 0.6, 0.2 + (hz - 0.2) * 0.85), (0, hy + 0.03, hz - 0.03)]
    for j, p in enumerate(sp.points):
        p.co = (pts[j][0], pts[j][1], pts[j][2], 1.0)


def pose_quad(R, anim, f, n):
    ph = f / n
    body, neck, head, legs = R["body"], R["neck"], R["head"], R["legs"]
    s = math.sin(ph * 2 * math.pi)
    C.set_rot(neck, 0, 0, 0)
    C.set_rot(head, 0, 0, 0)
    if anim == "idle":
        C.set_rot(neck, 4 * s, 0, 0)
        body.location = (0, 0, 0.58 + 0.008 * s)
    elif anim == "walk":
        for i, lp in enumerate(legs):
            C.set_rot(lp, 28 * s * (1 if i in (0, 3) else -1), 0, 0)
        body.location = (0, 0, 0.58 + 0.02 * abs(s))
    elif anim == "attack":
        lean, nk, dy = [(-8, -10, 0.06), (14, 40, -0.18), (18, 50, -0.3), (5, 10, -0.06)][f]
        C.set_rot(body, lean, 0, 0)
        C.set_rot(neck, nk, 0, 0)
        body.location = (0, dy, 0.58)
        C.set_rot(legs[0], -30 if f in (1, 2) else 0, 0, 0)
        C.set_rot(legs[1], -30 if f in (1, 2) else 0, 0, 0)
    elif anim == "cast":
        lean = [-10, -25, -28, -5][f]
        C.set_rot(body, lean, 0, 0)
        C.set_rot(neck, -20 if f in (1, 2) else 0, 0, 0)
        body.location = (0, 0.05, 0.58 + [0.02, 0.1, 0.12, 0.0][f])
        C.set_rot(legs[0], -50 if f in (1, 2) else 0, 0, 0)
        C.set_rot(legs[1], -60 if f in (1, 2) else 0, 0, 0)
    elif anim == "hit":
        k = [1.0, 0.5][f]
        C.set_rot(body, -8 * k, 0, 6 * k)
        C.set_rot(neck, -20 * k, 0, 0)
        body.location = (0, 0.08 * k, 0.58)
    elif anim == "dodge":
        body.location = (0.15 * [1, 0.5][f], 0, 0.58)
    elif anim in ("downed", "death"):
        k = 1.0 if anim == "downed" else [0.25, 0.6, 0.9, 1.0][f]
        C.set_rot(body, 0, 80 * k, 0)
        body.location = (0.25 * k, 0, 0.58 - 0.3 * k)
        C.set_rot(neck, 20 * k, 0, 0)
        for lp in legs:
            C.set_rot(lp, 0, 0, 10 * k)


def pose_scorpion(R, anim, f, n):
    ph = f / n
    body, segs, claws, legs = R["body"], R["segs"], R["claws"], R["legs"]
    s = math.sin(ph * 2 * math.pi)
    curl = [30, 45, 45, 45, 50]
    for i, sp in enumerate(segs):
        C.set_rot(sp, -curl[i] if i else -20, 0, 0)
    for cp, sd in claws:
        C.set_rot(cp, 0, 0, 0)
    body.location = (0, 0, 0.26)
    C.set_rot(body, 0, 0, 0)
    if anim == "idle":
        for i, sp in enumerate(segs):
            C.set_rot(sp, -(curl[i] if i else 20) - 4 * s, 0, 0)
        for cp, sd in claws:
            C.set_rot(cp, 0, 0, sd * 5 * s)
    elif anim == "walk":
        for lp, sd, i in legs:
            C.set_rot(lp, 25 * s * (1 if (i % 2) else -1) * sd, 0, 0)
        body.location = (0, 0, 0.26 + 0.015 * abs(s))
    elif anim == "attack":
        k = [0.3, 1.0, 1.0, 0.3][f]
        strike = [0, 1, 1.2, 0.3][f]
        for i, sp in enumerate(segs):
            base = (curl[i] if i else 20)
            C.set_rot(sp, -base - 18 * strike, 0, 0)
        C.set_rot(body, -8 * k, 0, 0)
        body.location = (0, -0.1 * strike, 0.26)
    elif anim == "cast":
        for cp, sd in claws:
            C.set_rot(cp, [-20, -45, -50, -10][f], 0, sd * 15)
        C.set_rot(body, [-5, -12, -12, 0][f], 0, 0)
    elif anim == "hit":
        k = [1.0, 0.5][f]
        C.set_rot(body, -10 * k, 0, 0)
        body.location = (0, 0.08 * k, 0.26)
    elif anim == "dodge":
        body.location = (0.14 * [1, 0.5][f], 0, 0.26)
    elif anim in ("downed", "death"):
        k = 1.0 if anim == "downed" else [0.3, 0.6, 0.9, 1.0][f]
        C.set_rot(body, 0, 150 * k, 0)
        body.location = (0.08 * k, 0, 0.26 + 0.05 * k)
        for lp, sd, i in legs:
            C.set_rot(lp, 0, 0, -sd * 40 * k)
        for i, sp in enumerate(segs):
            C.set_rot(sp, -(curl[i] if i else 20) - 25 * k, 0, 0)


POSERS = {"humanoid": pose_humanoid, "floater": pose_floater, "serpent": pose_serpent,
          "quad": pose_quad, "scorpion": pose_scorpion}
BUILDERS = {"floater": build_floater, "serpent": build_serpent, "quad": build_quad, "scorpion": build_scorpion}


# ======================================================================
# Main
# ======================================================================
CHAR_SCALE = 0.9


def portrait_camera(scene, center, ortho, pitch_deg):
    scene.render.resolution_x = 32 * C.SUPERSAMPLE
    scene.render.resolution_y = 32 * C.SUPERSAMPLE
    cd = bpy.data.cameras.new("PortraitCam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cam = bpy.data.objects.new("PortraitCam", cd)
    scene.collection.objects.link(cam)
    p = math.radians(pitch_deg)
    fwd = Vector((0.0, math.cos(p), -math.sin(p)))
    cam.location = center - fwd * 20.0
    cam.rotation_euler = (math.pi / 2 - p, 0.0, 0.0)
    scene.camera = cam
    return cam


def show_only(where):
    """Objects tagged by C.only_in render only in sprite frames or only in portraits."""
    for obj in bpy.data.objects:
        tag = obj.get("only")
        if tag:
            obj.hide_render = tag != where


QUICK = [("idle", 1), ("attack", 3)]


def render_variant(spec, out_root, quick=False):
    scale = spec.get("scale", 1.0) * CHAR_SCALE
    canvas = spec["canvas"]
    anchor = (canvas // 2, int(canvas * 0.78))
    todo = [(False, ANIMS if not quick else QUICK)]
    if spec.get("bandage") and not quick:
        todo.append((True, [("idle", 4)]))
    out_dir = os.path.join(out_root, spec["id"])
    os.makedirs(out_dir, exist_ok=True)
    meta = {"id": spec["id"], "canvas": canvas, "anchor": anchor, "anims": ANIMS, "bandage": bool(spec.get("bandage")), "quick": quick}
    for bandaged, anims in todo:
        scene = C.reset_scene()
        cam, fwd, up, right = C.setup_camera(scene, (canvas, canvas), anchor)
        C.build_materials(C.light_vector(fwd, up, right))
        if spec["rig"] == "humanoid":
            R = build_humanoid(spec, bandage=bandaged)
        else:
            R = BUILDERS[spec["rig"]](spec)
        R["root"].scale = (scale, scale, scale)
        poser = POSERS[spec["rig"]]
        yaw = C.pivot("yaw")
        R["root"].parent = yaw
        show_only("sprite")
        for di, deg in enumerate(DIRS):
            yaw.rotation_euler = (0, 0, math.radians(deg))
            for anim, n in anims:
                frames = range(n) if not quick else ([0] if anim == "idle" else [2])
                if quick and anim == "attack" and di != 0:
                    continue
                for f in frames:
                    reset_pose(R)
                    poser(R, anim, f, 4 if quick else n)
                    name = ("bandage_" if bandaged else "") + f"{anim}_{di}_{f}.png"
                    C.render_to(os.path.join(out_dir, name))
        show_only("portrait")
        # portrait: close-up of the head, front-right idle
        if spec["rig"] == "humanoid":
            yaw.rotation_euler = (0, 0, math.radians(28))
            reset_pose(R)
            pose_humanoid(R, "idle", 0, 4)
            big = R["race"] in ("unnamed", "unwritten")
            if R["race"] in CH.RACES:
                hz = (0.84 * R["tall"] + 0.265) * scale
                portrait_camera(scene, Vector((0, 0, hz)), 0.86 * scale, 12)
            else:
                hz = (0.84 * R["tall"] + 0.22) * scale
                portrait_camera(scene, Vector((0, 0, hz)), 0.8 * scale * (1.25 if big else 1.0), 12)
            C.render_to(os.path.join(out_dir, ("bandage_" if bandaged else "") + "portrait.png"))
        else:
            yaw.rotation_euler = (0, 0, math.radians(35))
            reset_pose(R)
            POSERS[spec["rig"]](R, "idle", 0, 4)
            kind = spec.get("kind")
            hz = {"deer": 0.75, "scorpion": 0.3, "serpent": 0.8, "quietling": 0.55, "stinger": 0.65, "spirit": 0.95}.get(kind, 0.6)
            size = {"deer": 1.5, "scorpion": 1.3, "serpent": 1.0, "quietling": 0.8, "stinger": 1.05, "spirit": 1.0}.get(kind, 1.2)
            base_scale = spec.get("scale", 1.0)
            portrait_camera(scene, Vector((0, 0, hz * scale)), size * CHAR_SCALE * (1 + (base_scale - 1) * 0.9), 22)
            C.render_to(os.path.join(out_dir, "portrait.png"))
    with open(os.path.join(out_dir, "meta.json"), "w") as fh:
        json.dump(meta, fh)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = "tools/_cache/units"
    only = None
    shard, nshards = 0, 1
    quick = False
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        elif argv[i] == "--shard":
            shard, nshards = [int(x) for x in argv[i + 1].split("/")]
            i += 2
        elif argv[i] == "--quick":
            quick = True
            i += 1
        else:
            i += 1
    out = os.path.abspath(out)
    specs = [s for s in variants() if only is None or s["id"] in only]
    specs = [s for k, s in enumerate(specs) if k % nshards == shard]
    for s in specs:
        t0 = time.time()
        render_variant(s, out, quick)
        print(f"[units] {s['id']} done in {time.time() - t0:.1f}s", flush=True)


if __name__ == "__main__":
    main()
