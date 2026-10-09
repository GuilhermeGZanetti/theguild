"""The regions' apex creatures (the beasts of 6-7 skull quests).

Humanoid ones dress the shared humanoid rig of units.py (and use its poses);
the others build their own rigs for the floater, scorpion and quad posers.
Front is -Y, the creature's right is -X, Z is up; slots are palette names.
"""
import math
import bl_common as C


class Rig(dict):
    pass


def _ring(n, r, z=0.0, a0=0.0):
    return [(math.cos(a0 + 2 * math.pi * k / n) * r, math.sin(a0 + 2 * math.pi * k / n) * r, z) for k in range(n)]


def _legs(R, slot, foot, r=0.055, foot_scale=(0.07, 0.1, 0.05)):
    """Plain legs from the hips to the ground, whatever the rig's height."""
    L = 0.40 * R["tall"]
    for leg in (R["legR"], R["legL"]):
        C.cyl(slot, (0, 0, -L * 0.45), parent=leg, r=r, depth=L * 0.85)
        C.sphere(foot, (0, -0.03, -L + foot_scale[2]), foot_scale, parent=leg)


# ======================================================================
# Humanoid rig
# ======================================================================
def knell(R, spec):
    """Knell Dancer: a cultist of the cracked Bell. Ribbon skirt, sash of
    bells, a bell-mask with the crack painted red, twin crescent knives."""
    t = R["tall"]
    torso, head = R["torso"], R["head"]
    C.sphere("cloth1", (0, 0, 0.21 * t), (0.14, 0.11, 0.23 * t), parent=torso)
    C.lathe("cloth1", [(0.14, 0.05), (0.17, -0.04), (0.23, -0.14), (0.28, -0.24 * t)], parent=torso,
            folds=6, fold_amp=0.14, hem=0.06, hem_n=6, thick=0.012, name="skirt")
    C.torus("cloth2", (0, 0, 0.05), (1, 0.85, 0.7), parent=torso, R=0.15, r=0.035)
    for s in (-1, 1):   # sash tails flying behind
        C.sweep("cloth2", [(s * 0.04, 0.12, 0.05), (s * 0.08, 0.24, -0.02), (s * 0.12, 0.34, -0.14), (s * 0.1, 0.42, -0.26)],
                [(0.045, 0.01), (0.05, 0.01), (0.045, 0.01), (0.0, 0.0)], parent=torso, up=(0, 1, 0))
    for (x, y) in ((-0.1, -0.11), (0.0, -0.15), (0.1, -0.11)):   # little bells on the sash
        C.cone("metal", (x, y, -0.01), parent=torso, r1=0.03, r2=0.012, depth=0.05, verts=10)
        C.sphere("trim", (x, y, -0.04), (0.012, 0.012, 0.012), parent=torso)
    for side, arm, hand in ((-1, R["armR"], R["handR"]), (1, R["armL"], R["handL"])):
        C.cyl("cloth1", (0, 0, -0.12 * t), parent=arm, r=0.042, depth=0.22 * t)
        C.cone("cloth2", (0, 0, -0.23 * t), parent=arm, r1=0.07, r2=0.045, depth=0.06)
        C.sphere("skin", (0, 0, 0.02), (0.05, 0.05, 0.05), parent=hand)
        w = C.pivot("weapon", (0, -0.02, 0.0), hand)
        C.flat("metal", [(0.0, 0.03), (0.07, -0.08), (0.1, -0.24), (0.05, -0.4), (0.0, -0.43), (0.035, -0.24), (0.012, -0.08)],
               thick=0.016, parent=w, rot=(0, 0, side * 30))
        C.cyl("leather", (0, 0, 0.03), parent=w, r=0.018, depth=0.07)
    _legs(R, "cloth2", "leather", r=0.045, foot_scale=(0.05, 0.11, 0.04))
    # head: hood, bell-mask, ponytail
    C.sphere("skin", (0, 0, 0.27), (0.27, 0.26, 0.26), parent=head)
    C.sphere("cloth1", (0, 0.06, 0.32), (0.3, 0.27, 0.29), parent=head)
    C.lathe("metal", [(0.08, 0.5), (0.16, 0.46), (0.22, 0.34), (0.26, 0.16), (0.29, 0.06)], parent=head,
            loc=(0, -0.05, 0.0), arc=(-75, 75), thick=0.02, name="mask")
    for s in (-1, 1):
        C.box("eyes", (s * 0.09, -0.3, 0.3), (0.08, 0.02, 0.018), (0, 0, s * -12), parent=head)
    C.sweep("cloth2", [(0.06, -0.22, 0.46), (0.02, -0.255, 0.36), (0.05, -0.3, 0.24), (0.0, -0.325, 0.12)],
            [0.012, 0.012, 0.011, 0.006], parent=head, ring=6, name="crack")
    C.sweep("hair", [(0, 0.22, 0.46), (0, 0.36, 0.34), (0, 0.42, 0.12), (0.03, 0.4, -0.12)],
            [0.08, 0.07, 0.05, 0.0], parent=head)


def automaton(R, spec):
    """Bellguard Automaton: a bronze bell walking on stone-steady legs, with
    great fists and a visor slit glowing where a face should be."""
    t = R["tall"]
    torso, head = R["torso"], R["head"]
    C.lathe("cloth1", [(0.09, 0.5 * t), (0.15, 0.46 * t), (0.21, 0.33 * t), (0.26, 0.16 * t), (0.31, 0.0), (0.35, -0.1)],
            parent=torso, cap_top=True, name="bell")
    C.torus("metal", (0, 0, -0.1), (1, 1, 0.6), parent=torso, R=0.345, r=0.045)
    C.torus("trim", (0, 0, 0.22 * t), (1, 1, 0.45), parent=torso, R=0.245, r=0.022)
    C.torus("trim", (0, 0, 0.36 * t), (1, 1, 0.45), parent=torso, R=0.19, r=0.018)
    for (x, y, z) in ((-0.16, -0.18, 0.1), (0.2, -0.12, 0.25 * t), (0.05, -0.22, 0.02), (-0.2, 0.1, 0.3 * t), (0.22, 0.12, 0.05)):
        C.ico("cloth2", (x, y, z), (1, 1, 0.6), parent=torso, r=0.06, sub=1)   # verdigris
    C.sweep("feature", [(0.06, -0.21, 0.42 * t), (0.02, -0.25, 0.3 * t), (0.07, -0.29, 0.16 * t), (0.03, -0.33, 0.02)],
            [0.014, 0.016, 0.014, 0.008], parent=torso, ring=6, name="crack")
    C.sphere("trim", (0, 0.0, -0.12), (0.09, 0.09, 0.09), parent=torso)   # the clapper
    # arms outside the bell
    for side, key in ((-1, "R"), (1, "L")):
        arm, hand = R["arm" + key], R["hand" + key]
        arm.location = (side * 0.3, 0, 0.36 * t)
        C.sphere("metal", (0, 0, 0), (0.1, 0.1, 0.1), parent=arm)
        C.cyl("cloth1", (0, 0, -0.13 * t), parent=arm, r=0.08, depth=0.2 * t)
        C.sphere("metal", (0, 0, -0.26 * t), (0.085, 0.085, 0.085), parent=arm)
        C.sphere("cloth1", (0, -0.01, -0.03), (0.16, 0.16, 0.14), parent=hand)
        for k in range(3):
            C.sphere("metal", ((k - 1) * 0.07, -0.14, 0.0), (0.04, 0.04, 0.04), parent=hand)
    L = 0.40 * t
    for leg in (R["legR"], R["legL"]):
        leg.location = (leg.location.x * 1.4, 0, 0)
        C.cyl("metal", (0, 0, -L * 0.5), parent=leg, r=0.075, depth=L, bevel=0.01)
        C.box("leather", (0, -0.04, -L + 0.035), (0.17, 0.24, 0.07), parent=leg, bevel=0.015)
    # head: a domed cap with a burning visor slit and the bell's hanger
    C.sphere("metal", (0, 0, 0.1), (0.2, 0.2, 0.16), parent=head)
    C.box("feature", (0, -0.17, 0.11), (0.3, 0.08, 0.06), parent=head, bevel=0.01)
    for s in (-1, 1):
        C.sphere("glow", (s * 0.07, -0.21, 0.11), (0.035, 0.02, 0.025), parent=head)
    C.torus("trim", (0, 0, 0.3), (1, 1, 1), (0, 90, 0), parent=head, R=0.09, r=0.025)


def mantis(R, spec):
    """Reed Mantis: a stick-thin hunter with folded scythe arms, a long
    abdomen and leaf wings, waiting in the reeds."""
    t = R["tall"]
    torso, head, hips = R["torso"], R["head"], R["hips"]
    C.sphere("cloth1", (0, 0, 0.22 * t), (0.1, 0.09, 0.21 * t), parent=torso)
    abd = [(0, 0.04, 0.03), (0, 0.18, -0.03), (0, 0.34, 0.0), (0, 0.46, 0.06)]
    C.sweep("cloth1", abd, [0.09, 0.13, 0.1, 0.0], parent=hips)
    for k, y in enumerate((0.14, 0.24, 0.34)):
        C.torus("cloth2", (0, y, -0.01 + 0.02 * k), (1, 1, 1), (90, 0, 0), parent=hips, R=0.1 - 0.012 * k, r=0.016)
    for s in (-1, 1):   # leaf wings folded along the back
        C.flat("cloth2", [(0.0, 0.0), (0.05, -0.08), (0.06, -0.24), (0.03, -0.4), (0.0, -0.44), (-0.02, -0.24), (-0.02, -0.06)],
               thick=0.01, parent=torso, loc=(s * 0.04, 0.08, 0.38 * t), rot=(72, 0, s * 8), bend=0.4)
        C.sweep("cloth1", [(s * 0.08, 0.04, 0.12), (s * 0.24, 0.0, -0.02), (s * 0.3, 0.02, -0.4 * t + 0.03)],
                [0.022, 0.018, 0.012], parent=torso)   # middle legs
    for side, arm, hand in ((-1, R["armR"], R["handR"]), (1, R["armL"], R["handL"])):
        C.cyl("cloth1", (0, 0, -0.12 * t), parent=arm, r=0.035, depth=0.24 * t)
        C.sphere("cloth1", (0, 0, 0.0), (0.04, 0.04, 0.04), parent=hand)
        w = C.pivot("weapon", (0, -0.03, 0.0), hand)
        C.flat("white", [(0.0, 0.04), (0.05, -0.04), (0.06, -0.2), (0.02, -0.38), (0.0, -0.4), (-0.015, -0.3), (0.025, -0.24),
                         (-0.01, -0.18), (0.02, -0.1), (-0.01, -0.04)], thick=0.016, parent=w, rot=(-20, 0, side * -8))
    _legs(R, "cloth1", "cloth2", r=0.03, foot_scale=(0.04, 0.08, 0.03))
    # head: a triangle of eyes and jaws on a long neck
    C.cyl("cloth1", (0, 0, -0.04), parent=head, r=0.035, depth=0.14)
    C.cone("cloth1", (0, -0.02, 0.24), (1, 0.7, 1), (180, 0, 0), parent=head, r1=0.2, r2=0.03, depth=0.3, verts=3)
    for s in (-1, 1):
        C.sphere("eyes", (s * 0.15, -0.05, 0.34), (0.08, 0.07, 0.09), parent=head)
        C.cone("white", (s * 0.03, -0.1, 0.08), (1, 1, 1), (160, 0, s * 20), parent=head, r1=0.025, r2=0.0, depth=0.08, verts=6)
        C.sweep("cloth1", [(s * 0.05, -0.04, 0.38), (s * 0.12, 0.02, 0.62), (s * 0.26, 0.14, 0.72)], [0.014, 0.01, 0.0], parent=head, ring=6)


def ashen(R, spec):
    """Ashen Huntress: a barkborn whose grave-seed burned. Charred wood
    seamed with embers, a mane of smoke, a long bow."""
    t = R["tall"]
    torso, head = R["torso"], R["head"]
    C.sphere("wood", (0, 0, 0.22 * t), (0.15, 0.12, 0.23 * t), parent=torso)
    for pts in ([(-0.06, -0.12, 0.38 * t), (-0.02, -0.13, 0.26 * t), (-0.07, -0.12, 0.12 * t)],
                [(0.07, -0.12, 0.34 * t), (0.04, -0.13, 0.2 * t), (0.08, -0.11, 0.06)]):
        C.sweep("glow", pts, [0.012, 0.014, 0.008], parent=torso, ring=6)
    C.lathe("cape", [(0.15, 0.4 * t), (0.2, 0.2 * t), (0.25, 0.0), (0.28, -0.24 * t)], parent=torso,
            arc=(110, 250), thick=0.012, hem=0.08, hem_n=7, hem_pow=3.0, name="cloak")
    C.torus("leather", (0, 0, 0.07 * t), (1, 0.82, 1), parent=torso, R=0.155, r=0.025)
    for side, arm, hand in ((-1, R["armR"], R["handR"]), (1, R["armL"], R["handL"])):
        C.cyl("wood", (0, 0, -0.12 * t), parent=arm, r=0.045, depth=0.22 * t)
        C.sphere("feature", (0, 0, -0.22 * t), (0.05, 0.05, 0.03), parent=arm)
        C.sphere("wood", (0, 0, 0.02), (0.05, 0.05, 0.05), parent=hand)
    w = C.pivot("weapon", (0.0, -0.03, 0.0), R["handL"])
    C.tube("wood", [(0, -0.02, 0.42), (0, -0.15, 0.24), (0, -0.18, 0.0), (0, -0.15, -0.24), (0, -0.02, -0.42)], radius=0.022,
           parent=w, taper=[0.5, 1, 1.2, 1, 0.5])
    C.tube("white", [(0, -0.02, 0.41), (0, 0.02, 0.0), (0, -0.02, -0.41)], radius=0.006, parent=w)
    C.cyl("leather", (0.06, 0.15, 0.3 * t), (1, 1, 1), (-15, 20, 0), parent=torso, r=0.055, depth=0.3)
    for dx in (-0.02, 0.02):
        C.cone("glow", (0.09 + dx, 0.19, 0.47 * t), (1, 0.5, 1), (-15, 20, 0), parent=torso, r1=0.03, r2=0.0, depth=0.08, verts=4)
    L = 0.40 * t
    for s, leg in ((-1, R["legR"]), (1, R["legL"])):
        C.cyl("wood", (0, 0, -L * 0.45), parent=leg, r=0.05, depth=L * 0.85)
        for a in (-40, 0, 40):   # root toes
            x, y = math.sin(math.radians(a)) * 0.1, -math.cos(math.radians(a)) * 0.1
            C.sweep("wood", [(0, 0, -L + 0.05), (x * 0.6, y * 0.6, -L + 0.02), (x, y, -L + 0.01)], [0.035, 0.025, 0.0], parent=leg, ring=6)
    # head: charred skull, ember eyes, a mane of rising smoke
    C.sphere("wood", (0, 0, 0.27), (0.27, 0.26, 0.26), parent=head)
    for s in (-1, 1):
        C.sphere("glow", (s * 0.1, -0.24, 0.26), (0.045, 0.025, 0.05), parent=head)
        C.sweep("feature", [(s * 0.2, -0.16, 0.12), (s * 0.12, -0.22, 0.06), (s * 0.04, -0.25, 0.08)], [0.012, 0.012, 0.0],
                parent=head, ring=6)
    for k, (x, y, h) in enumerate(((-0.14, 0.08, 0.55), (0.0, 0.12, 0.7), (0.14, 0.08, 0.58), (-0.06, 0.2, 0.62), (0.08, 0.22, 0.6))):
        C.sweep("hair", [(x * 0.6, y * 0.5, 0.4), (x, y + 0.1, 0.5), (x * 1.3, y + 0.24, h), (x * 1.5, y + 0.4, h + 0.08)],
                [0.09, 0.08, 0.05, 0.0], parent=head)
        C.sphere("feature", (x * 1.3, y + 0.24, h - 0.02), (0.03, 0.03, 0.03), parent=head)


def oak(R, spec):
    """Mourning Oak: a grave tree that walked off its hill. A hollow, grieving
    face in the trunk, a crown of blood-red leaves hung with grave lanterns
    and black mourning ribbons, roots for feet."""
    t = R["tall"]
    torso, head, hips = R["torso"], R["head"], R["hips"]

    def gnarl(th, u):
        return 1.0 + 0.07 * math.sin(3 * th + 1.1) + 0.05 * math.sin(7 * th + u * 4.0)

    C.lathe("wood", [(0.2, 0.62 * t), (0.22, 0.45 * t), (0.25, 0.2 * t), (0.27, 0.0), (0.33, -0.18)], parent=torso,
            folds=9, fold_amp=0.06, shape=gnarl, cap_top=True, name="trunk")
    for s in (-1, 1):   # hollow eyes and their faint glow
        C.sphere("feature", (s * 0.09, -0.21, 0.42 * t), (0.06, 0.04, 0.075), parent=torso)
        C.sphere("glow", (s * 0.09, -0.235, 0.41 * t), (0.022, 0.012, 0.022), parent=torso)
    C.sphere("feature", (0, -0.22, 0.22 * t), (0.07, 0.04, 0.05), parent=torso)    # a mouth like a knot hole
    C.ico("cape", (0.18, -0.12, 0.08), (1, 0.6, 1.4), parent=torso, r=0.07, sub=1)  # moss
    C.ico("cape", (-0.2, 0.06, 0.3 * t), (1, 0.7, 1.2), parent=torso, r=0.06, sub=1)
    for side, key in ((-1, "R"), (1, "L")):
        arm, hand = R["arm" + key], R["hand" + key]
        arm.location = (side * 0.24, 0, 0.5 * t)
        hand.location = (side * 0.42, -0.04, -0.08 * t)
        C.sweep("wood", [(0, 0, 0.02), (side * 0.16, -0.02, 0.04), (side * 0.32, -0.03, -0.02), (side * 0.42, -0.04, -0.08 * t)],
                [0.085, 0.07, 0.055, 0.045], parent=arm)
        C.sweep("wood", [(side * 0.2, -0.02, 0.04), (side * 0.26, 0.0, 0.2), (side * 0.3, 0.04, 0.3)], [0.035, 0.025, 0.0],
                parent=arm, ring=6)   # a twig growing off the bough
        C.ico("hair", (side * 0.3, 0.04, 0.32), (1, 1, 0.8), parent=arm, r=0.09, sub=2)
        for a in (-35, 0, 35):   # twig fingers
            x = math.sin(math.radians(a)) * 0.12
            C.sweep("wood", [(0, 0, 0), (side * 0.06 + x * 0.6, -0.04, -0.08), (side * 0.1 + x, -0.06, -0.18)], [0.035, 0.024, 0.0],
                    parent=hand, ring=6)
        C.sweep("cloth2", [(side * 0.3, 0.0, -0.02), (side * 0.31, 0.02, -0.2 * t), (side * 0.3, 0.04, -0.42 * t)],
                [(0.05, 0.006), (0.05, 0.006), (0.0, 0.0)], parent=arm, up=(0, 1, 0))   # mourning ribbon
    L = 0.40 * t
    for s, leg in ((-1, R["legR"]), (1, R["legL"])):
        leg.location = (s * 0.13, 0, 0)
        C.cyl("wood", (0, 0, -L * 0.4), parent=leg, r=0.085, depth=L * 0.8)
        for a in (-60, -10, 40, 160):
            x, y = math.sin(math.radians(a)) * 0.2, -math.cos(math.radians(a)) * 0.2
            C.sweep("wood", [(0, 0, -L * 0.7), (x * 0.5, y * 0.5, -L + 0.06), (x, y, -L + 0.015)], [0.06, 0.04, 0.0],
                    parent=leg, ring=6)
    # the crown sits on the head pivot (it nods with the rig's head)
    for (x, y, z) in ((0, 0, 0.0), (-0.18, 0.05, 0.12), (0.2, 0.02, 0.14), (0.05, 0.15, 0.2)):
        C.sweep("wood", [(x * 0.3, y * 0.3, -0.1), (x * 0.7, y * 0.7, z * 0.6), (x * 1.2, y * 1.1, z + 0.12)],
                [0.05, 0.035, 0.0], parent=head, ring=6)
    for (x, y, z, r) in ((0, 0.0, 0.34, 0.28), (-0.3, 0.06, 0.24, 0.22), (0.31, 0.04, 0.26, 0.22), (0.06, 0.22, 0.38, 0.22),
                         (-0.14, -0.14, 0.42, 0.18), (0.16, -0.12, 0.44, 0.17), (-0.2, 0.2, 0.3, 0.18), (0.22, 0.2, 0.32, 0.17)):
        C.ico("hair", (x, y, z), (1, 1, 0.75), parent=head, r=r, sub=2)
    for (x, y, z) in ((-0.3, -0.05, 0.14), (0.32, 0.0, 0.16)):   # grave lanterns
        C.tube("leather", [(x, y, z + 0.02), (x, y, z - 0.16)], radius=0.008, parent=head)
        C.sphere("glow", (x, y, z - 0.21), (0.045, 0.045, 0.06), parent=head)
        C.cone("leather", (x, y, z - 0.15), parent=head, r1=0.04, r2=0.015, depth=0.03, verts=8)
    for x in (-0.2, 0.0, 0.18):
        C.sweep("cloth2", [(x, 0.08, 0.16), (x * 1.1, 0.12, -0.04), (x * 1.2, 0.16, -0.26)],
                [(0.03, 0.006), (0.035, 0.006), (0.0, 0.0)], parent=head, up=(0, 1, 0))


def monument(R, spec):
    """Nameless Monument: the statue of someone the Hush erased. A robed stone
    figure with a smoothed-away face, a blank plaque on its chest and a broken
    tablet in hand, pebbles drifting around its head."""
    t = R["tall"]
    torso, head, body = R["torso"], R["head"], R["body"]
    C.sphere("cloth1", (0, 0, 0.24 * t), (0.19, 0.15, 0.25 * t), parent=torso)
    C.lathe("cloth1", [(0.18, 0.12 * t), (0.22, -0.05), (0.27, -0.2 * t), (0.31, -0.37 * t)], parent=torso,
            folds=8, fold_amp=0.09, cap_bot=True, name="robe")
    C.box("cloth2", (0, 0, 0.05), (0.7, 0.6, 0.1), parent=body, bevel=0.02)   # plinth
    C.box("white", (0, -0.14, 0.27 * t), (0.17, 0.02, 0.12), parent=torso, bevel=0.005)   # the blank plaque
    for (x, z, a) in ((-0.03, 0.29, 30), (0.03, 0.26, -25), (0.0, 0.23, 70)):
        C.box("feature", (x, -0.155, z * t), (0.08, 0.008, 0.008), (0, a, 0), parent=torso)   # scratched-out letters
    C.sweep("feature", [(0.12, -0.15, 0.4 * t), (0.08, -0.2, 0.16 * t), (0.14, -0.24, -0.08), (0.1, -0.28, -0.3 * t)],
            [0.01, 0.012, 0.01, 0.006], parent=torso, ring=6, name="crack")
    for side, arm, hand in ((-1, R["armR"], R["handR"]), (1, R["armL"], R["handL"])):
        C.cyl("cloth1", (0, 0, -0.12 * t), parent=arm, r=0.06, depth=0.24 * t)
        C.cone("cloth1", (0, 0, -0.24 * t), parent=arm, r1=0.09, r2=0.06, depth=0.08)
        C.sphere("skin", (0, 0, 0.02), (0.065, 0.065, 0.065), parent=hand)
    w = C.pivot("weapon", (0, -0.04, 0.02), R["handR"])
    C.box("white", (0, -0.06, -0.12), (0.2, 0.05, 0.26), (0, 0, 8), parent=w, bevel=0.01)
    C.box("white", (0.03, -0.06, -0.31), (0.14, 0.05, 0.1), (0, 0, -18), parent=w, bevel=0.01)   # broken-off piece
    # head: smooth stone, the face worn blank
    C.sphere("skin", (0, 0, 0.27), (0.25, 0.24, 0.27), parent=head)
    C.sphere("white", (0, -0.16, 0.26), (0.17, 0.09, 0.2), parent=head)
    C.sphere("cloth2", (0, 0.07, 0.31), (0.29, 0.26, 0.3), parent=head)
    C.lathe("cloth2", [(0.24, 0.12), (0.28, 0.0), (0.3, -0.12)], parent=head, loc=(0, 0.05, 0.0), folds=6, fold_amp=0.1,
            name="mantle")
    for (x, y, z, r) in ((-0.36, -0.05, 0.42, 0.045), (0.34, 0.08, 0.5, 0.035), (0.2, -0.1, 0.66, 0.03), (-0.18, 0.12, 0.7, 0.04)):
        C.ico("skin2", (x, y, z), (1, 1, 1), parent=head, r=r, sub=1)


HUMANOIDS = {"knell": knell, "automaton": automaton, "mantis": mantis, "ashen": ashen, "oak": oak, "monument": monument}
TALL = {"knell": 1.0, "automaton": 1.1, "mantis": 1.1, "ashen": 1.0, "oak": 1.35, "monument": 1.3}
BIG = ("automaton", "oak", "monument")


# ======================================================================
# Floater rig (pose_floater): body pivot, hanging "tentacles", flapping "wings"
# ======================================================================
def manta(spec):
    """Gale Manta: a sky-ray of the coast cliffs. Wide wings, horned head,
    a whip tail ending in a barb."""
    R = Rig(kind="manta", base=0.62)
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.62), root)
    C.sphere("cloth1", (0, 0.02, 0.0), (0.24, 0.34, 0.1), parent=body)
    C.sphere("cloth2", (0, 0.0, -0.035), (0.2, 0.3, 0.06), parent=body)
    wings = []
    for s in (-1, 1):
        wp = C.pivot("wing", (s * 0.16, 0.02, 0.0), body)
        C.flat("cloth1", [(0.0, 0.2), (s * 0.22, 0.12), (s * 0.46, -0.02), (s * 0.5, -0.1), (s * 0.3, -0.16), (0.0, -0.2)],
               thick=0.03, parent=wp, rot=(90, 0, 0), bend=-0.3)
        C.flat("cloth2", [(0.0, 0.14), (s * 0.3, 0.04), (s * 0.4, -0.06), (0.0, -0.14)], thick=0.01, parent=wp,
               loc=(0, 0, -0.02), rot=(90, 0, 0), bend=-0.3)
        wings.append((wp, s))
        C.flat("feature", [(0.0, 0.0), (s * 0.04, 0.05), (s * 0.06, 0.14), (s * 0.02, 0.18), (s * -0.01, 0.06)],
               thick=0.02, parent=body, loc=(s * 0.1, -0.33, 0.0), rot=(0, 0, 0))   # cephalic horns
        C.sphere("eyes", (s * 0.16, -0.27, 0.03), (0.035, 0.03, 0.035), parent=body)
        C.sphere("glow", (s * 0.06, -0.12, 0.08), (0.03, 0.04, 0.012), parent=body)   # pale spots
    C.sweep("feature", [(0, 0.3, 0.0), (0, 0.5, 0.02), (0.04, 0.7, 0.06), (0.0, 0.88, 0.1)], [0.035, 0.025, 0.015, 0.006],
            parent=body, ring=6, name="tail")
    C.cone("glow", (0.0, 0.84, 0.09), (0.5, 1, 1), (-80, 0, 0), parent=body, r1=0.035, r2=0.0, depth=0.12, verts=6)
    R.update(root=root, body=body, tentacles=[], wings=wings)
    return R


def wasp(spec):
    """Sunflare Wasp: a dune hornet with wings of fused glass that flash in
    the sun, and a sting that pierces armour."""
    R = Rig(kind="wasp", base=0.62)
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.62), root)
    C.sphere("cloth2", (0, 0.0, 0.05), (0.13, 0.14, 0.12), parent=body)   # thorax
    C.sphere("cloth1", (0, -0.2, 0.1), (0.13, 0.12, 0.12), parent=body)   # head
    for s in (-1, 1):
        C.sphere("eyes", (s * 0.09, -0.26, 0.13), (0.055, 0.05, 0.075), parent=body)
        C.cone("white", (s * 0.04, -0.31, 0.03), (1, 1, 1), (150, 0, s * 25), parent=body, r1=0.025, r2=0.0, depth=0.08, verts=6)
        C.sweep("cloth2", [(s * 0.04, -0.27, 0.2), (s * 0.08, -0.36, 0.32), (s * 0.12, -0.44, 0.34)], [0.012, 0.01, 0.0],
                parent=body, ring=6)
    abd = C.pivot("abdomen", (0, 0.1, 0.0), body)
    C.sphere("cloth1", (0, 0.16, -0.06), (0.14, 0.23, 0.13), (-25, 0, 0), parent=abd)
    for k, (y, z) in enumerate(((0.08, -0.02), (0.18, -0.07), (0.27, -0.12))):
        C.torus("cloth2", (0, y, z), (1, 1, 1), (65, 0, 0), parent=abd, R=0.13 - 0.02 * k, r=0.025)
    C.cone("white", (0, 0.37, -0.2), (1, 1, 1), (-125, 0, 0), parent=abd, r1=0.03, r2=0.0, depth=0.14, verts=6)
    wings = []
    for s in (-1, 1):
        wp = C.pivot("wing", (s * 0.06, 0.02, 0.15), body)
        C.flat("glow", C.ellipse(10, 0.2, 0.07, s * 0.2, 0.06, 0.0), thick=0.01, parent=wp, rot=(90, 0, s * -20))
        C.flat("white", C.ellipse(10, 0.13, 0.05, s * 0.14, 0.12, 0.0), thick=0.01, parent=wp, loc=(0, 0, -0.01), rot=(90, 0, s * -35))
        wings.append((wp, s))
    tent = []
    for i, (x, y) in enumerate(((-0.08, -0.06), (0.08, -0.06), (-0.1, 0.03), (0.1, 0.03), (-0.08, 0.1), (0.08, 0.1))):
        t = C.tube("cloth2", [(x, y, -0.04), (x * 1.3, y, -0.14), (x * 1.4, y, -0.24), (x * 1.3, y, -0.32)], radius=0.012,
                   parent=body, taper=[1.0, 0.9, 0.7, 0.4])
        tent.append((t, x * 1.3, y, i))
    R.update(root=root, body=body, tentacles=tent, wings=wings)
    return R


def paper(spec):
    """Paper Wraith: the Hush's scribe, a whirl of blank pages around an
    inked face, trailing torn strips."""
    R = Rig(kind="paper", base=0.5)
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.5), root)
    C.lathe("cloth1", [(0.12, 0.36), (0.18, 0.2), (0.24, 0.0), (0.3, -0.22)], parent=body, hem=0.1, hem_n=9, hem_pow=4.0,
            folds=9, fold_amp=0.1, thick=0.012, name="pages")
    C.sphere("cloth1", (0, 0.0, 0.48), (0.2, 0.18, 0.22), parent=body)
    C.flat("white", [(-0.13, 0.12), (0.13, 0.12), (0.14, -0.14), (-0.12, -0.15)], thick=0.01, parent=body, loc=(0, -0.19, 0.48),
           rot=(0, 0, 0), bend=0.4)
    for s in (-1, 1):
        C.sphere("feature", (s * 0.06, -0.205, 0.52), (0.03, 0.01, 0.045), parent=body)
        C.sweep("feature", [(s * 0.06, -0.205, 0.48), (s * 0.065, -0.205, 0.42), (s * 0.06, -0.205, 0.37)], [0.012, 0.009, 0.0],
                parent=body, ring=6)
    C.box("feature", (0, -0.205, 0.41), (0.08, 0.008, 0.012), parent=body)
    for (x, y, z, a, b) in ((-0.36, 0.05, 0.34, 20, 30), (0.38, -0.02, 0.2, -15, -40), (0.12, 0.32, 0.56, 60, 10),
                            (-0.26, -0.26, 0.04, -30, 60), (0.28, 0.22, -0.04, 40, -20), (-0.08, -0.34, 0.66, 15, -15),
                            (0.0, 0.36, 0.1, -50, 80)):
        pg = C.pivot("page", (x, y, z), body)
        C.set_rot(pg, a, 0, b)
        pg["static"] = True
        C.box("white", (0, 0, 0), (0.18, 0.012, 0.24), parent=pg)
        for k in range(3):
            for side in (-1, 1):
                C.box("feature", (0, side * 0.008, 0.06 - 0.05 * k), (0.12, 0.006, 0.008), parent=pg)
    for s, key in ((-1, "handR"), (1, "handL")):
        h = C.pivot("hand", (s * 0.28, -0.05, 0.1), body)
        for k in range(3):
            C.sweep("cloth1", [(0, 0, 0), (s * 0.03, -0.04, -0.06 - 0.02 * k), (s * (0.04 + 0.02 * k), -0.06, -0.14)],
                    [(0.03, 0.006), (0.025, 0.006), (0.0, 0.0)], parent=h, up=(0, 1, 0))
        R[key] = h
    tent = []
    for i in range(5):
        a = math.radians(i * 72 + 20)
        x, y = math.cos(a) * 0.18, math.sin(a) * 0.18
        t = C.tube("cloth1", [(x, y, -0.25), (x, y, -0.35), (x, y, -0.45)], radius=0.03, parent=body, taper=[1, 0.7, 0.2])
        tent.append((t, x, y, i))
    R.update(root=root, body=body, tentacles=tent)
    return R


FLOATERS = {"manta": manta, "wasp": wasp, "paper": paper}


# ======================================================================
# Scorpion rig (pose_scorpion): body, legs, claws, tail segments (none here)
# ======================================================================
def crab(spec):
    """Bellshell Hermit: a giant hermit crab living in a drowned church bell,
    one crushing claw, eyes on stalks, weed trailing off the bronze."""
    R = Rig(kind="crab")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.26), root)
    C.sphere("cloth2", (0, -0.12, 0.02), (0.22, 0.2, 0.13), parent=body)
    shell = C.pivot("shell", (0, 0.08, 0.04), body)
    C.set_rot(shell, -62, 0, 0)
    shell["static"] = True
    C.lathe("cloth1", [(0.1, 0.66), (0.2, 0.63), (0.25, 0.54), (0.26, 0.4), (0.28, 0.26), (0.33, 0.12), (0.42, 0.02), (0.44, 0.0)],
            parent=shell, cap_top=True, thick=0.03, name="bell")
    C.torus("metal", (0, 0, 0.0), (1, 1, 0.6), parent=shell, R=0.44, r=0.045)
    C.torus("trim", (0, 0, 0.3), (1, 1, 0.5), parent=shell, R=0.285, r=0.018)
    C.torus("trim", (0, 0, 0.7), (1, 1, 1), (90, 0, 0), parent=shell, R=0.07, r=0.022)
    for (x, y, z) in ((0.2, -0.1, 0.2), (-0.18, -0.15, 0.38), (0.1, 0.2, 0.3), (-0.25, 0.12, 0.12), (0.05, -0.2, 0.5)):
        C.ico("feature", (x, y, z), (1, 1, 0.7), parent=shell, r=0.05, sub=1)   # barnacles
    for x in (-0.22, 0.05, 0.25):
        C.sweep("cape", [(x, -0.3, 0.12), (x * 1.1, -0.36, -0.04), (x * 1.2, -0.34, -0.2)], [0.03, 0.025, 0.0], parent=shell, ring=6)
    for s in (-1, 1):
        C.sweep("cloth2", [(s * 0.07, -0.24, 0.06), (s * 0.09, -0.28, 0.18), (s * 0.1, -0.3, 0.3)], [0.02, 0.018, 0.016],
                parent=body, ring=6)
        C.sphere("eyes", (s * 0.1, -0.3, 0.33), (0.04, 0.04, 0.045), parent=body)
    legs = []
    for i, y in enumerate((-0.1, 0.02, 0.14)):
        for s in (-1, 1):
            lp = C.pivot("leg", (s * 0.2, y, 0.0), body)
            C.tube("cloth2", [(0, 0, 0), (s * 0.18, 0, 0.12), (s * 0.34, 0, -0.26)], radius=0.026, parent=lp)
            legs.append((lp, s, i))
    claws = []
    for s, k in ((-1, 1.35), (1, 0.8)):
        cp = C.pivot("claw", (s * 0.18, -0.26, 0.0), body)
        C.tube("cloth2", [(0, 0, 0), (s * 0.1 * k, -0.12 * k, 0.04), (s * 0.08 * k, -0.24 * k, 0.06)], radius=0.035 * k, parent=cp)
        C.sphere("cloth2", (s * 0.08 * k, -0.33 * k, 0.07), (0.1 * k, 0.12 * k, 0.08 * k), parent=cp)
        C.cone("white", (s * 0.04 * k, -0.45 * k, 0.07), (0.6, 1, 0.5), (90, 0, 0), parent=cp, r1=0.045 * k, r2=0.0, depth=0.12 * k, verts=6)
        C.cone("white", (s * 0.12 * k, -0.44 * k, 0.07), (0.6, 1, 0.5), (90, 0, 0), parent=cp, r1=0.035 * k, r2=0.0, depth=0.1 * k, verts=6)
        claws.append((cp, s))
    tail = C.pivot("tail", (0, 0.3, 0.0), body)
    R.update(root=root, body=body, legs=legs, claws=claws, tail=tail, segs=[])
    return R


def beetle(spec):
    """Scarab Juggernaut: a caravan war-beetle gone wild, obsidian shell with
    gold seams, a horn like a battering ram, its old saddle cloth in tatters."""
    R = Rig(kind="beetle")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.26), root)
    for s in (-1, 1):
        C.sphere("cloth1", (s * 0.11, 0.1, 0.1), (0.17, 0.36, 0.2), parent=body)   # elytra
        C.sweep("cloth2", [(s * 0.26, -0.15, 0.08), (s * 0.28, 0.1, 0.1), (s * 0.2, 0.38, 0.06)], [0.018, 0.02, 0.012],
                parent=body, ring=6)
    C.box("cloth2", (0, 0.1, 0.29), (0.025, 0.62, 0.02), parent=body)   # the seam
    C.sphere("cloth1", (0, -0.24, 0.09), (0.25, 0.17, 0.16), parent=body)   # pronotum
    C.torus("cloth2", (0, -0.25, 0.09), (1, 0.7, 0.8), parent=body, R=0.23, r=0.018)
    C.sphere("leather", (0, -0.4, 0.02), (0.13, 0.1, 0.09), parent=body)   # head
    for s in (-1, 1):
        C.sphere("glow", (s * 0.08, -0.46, 0.05), (0.03, 0.025, 0.03), parent=body)
    C.flat("cape", [(-0.24, 0.0), (0.24, 0.0), (0.26, -0.3), (0.12, -0.24), (0.0, -0.34), (-0.14, -0.24), (-0.26, -0.3)],
           thick=0.012, parent=body, loc=(0, 0.12, 0.32), rot=(90, 0, 0), bend=-1.2)   # saddle cloth draped over
    horn = C.pivot("claw", (0, -0.42, 0.06), body)
    C.sweep("cloth2", [(0, 0, 0), (0, -0.16, 0.06), (0, -0.28, 0.24), (0, -0.26, 0.44)], [0.075, 0.06, 0.04, 0.0], parent=horn)
    C.sweep("cloth2", [(0, -0.2, 0.12), (0.0, -0.3, 0.12), (0, -0.36, 0.08)], [0.03, 0.02, 0.0], parent=horn, ring=6)
    legs = []
    for i, y in enumerate((-0.18, 0.02, 0.22)):
        for s in (-1, 1):
            lp = C.pivot("leg", (s * 0.24, y, 0.0), body)
            C.tube("leather", [(0, 0, 0), (s * 0.14, 0, 0.06), (s * 0.24, 0, -0.24)], radius=0.048, parent=lp)
            C.sphere("cloth2", (s * 0.14, 0, 0.06), (0.05, 0.05, 0.05), parent=lp)
            legs.append((lp, s, i))
    tail = C.pivot("tail", (0, 0.4, 0.0), body)
    R.update(root=root, body=body, legs=legs, claws=[(horn, 0)], tail=tail, segs=[])
    return R


CRAWLERS = {"crab": crab, "beetle": beetle}


# ======================================================================
# Quad rig (pose_quad): body pivot at 0.58, four legs, neck, head
# ======================================================================
def toad(spec):
    """Mudback Toad: a bog toad the size of a cart, a garden of cattails
    growing on its back, a tongue that drags prey in."""
    R = Rig(kind="toad")
    root = C.pivot("root")
    body = C.pivot("body", (0, 0, 0.58), root)
    C.sphere("skin", (0, 0.06, -0.26), (0.4, 0.44, 0.27), parent=body)
    C.sphere("skin2", (0, -0.1, -0.34), (0.32, 0.32, 0.18), parent=body)
    for (x, y, z) in ((-0.2, 0.0, -0.06), (0.24, 0.14, -0.08), (0.0, 0.26, -0.06), (-0.12, 0.3, -0.14), (0.3, -0.06, -0.16)):
        C.ico("skin2", (x, y, z), (1, 1, 0.7), parent=body, r=0.04, sub=1)
    C.ico("cloth1", (0.05, 0.12, -0.02), (2.2, 2.4, 0.5), parent=body, r=0.1, sub=2)   # mud and moss
    for (x, y, h) in ((-0.08, 0.1, 0.42), (0.06, 0.16, 0.5), (0.16, 0.04, 0.36), (-0.02, 0.24, 0.3)):
        C.tube("cloth1", [(x, y, -0.04), (x * 1.1, y, h * 0.5), (x * 1.2, y + 0.03, h)], radius=0.012, parent=body)
        C.cyl("leather", (x * 1.2, y + 0.03, h - 0.04), parent=body, r=0.026, depth=0.11)   # cattails
    legs = []
    for (x, y, big) in ((-0.3, -0.24, False), (0.3, -0.24, False), (-0.34, 0.3, True), (0.34, 0.3, True)):
        lp = C.pivot("leg", (x, y, -0.3), body)
        if big:
            C.sphere("skin", (0, 0, 0.02), (0.13, 0.2, 0.13), parent=lp)
        C.cyl("skin", (0, -0.02, -0.12), parent=lp, r=0.06, depth=0.22)
        C.sphere("skin2", (0, -0.06, -0.26), (0.1, 0.13, 0.03), parent=lp)
        legs.append(lp)
    neck = C.pivot("neck", (0, -0.3, -0.18), body)
    head = C.pivot("head", (0, -0.1, 0.0), neck)
    C.sphere("skin", (0, -0.08, 0.0), (0.36, 0.28, 0.17), parent=head)
    C.sphere("skin2", (0, -0.12, -0.08), (0.3, 0.22, 0.08), parent=head)
    C.sweep("leather", [(-0.3, -0.18, -0.03), (-0.15, -0.31, -0.04), (0.0, -0.34, -0.04), (0.15, -0.31, -0.04), (0.3, -0.18, -0.03)],
            [0.012, 0.014, 0.014, 0.014, 0.012], parent=head, ring=6, name="mouth")
    C.sphere("cloth2", (0, -0.33, -0.06), (0.06, 0.04, 0.025), parent=head)   # tongue tip
    for s in (-1, 1):
        C.sphere("white", (s * 0.19, -0.1, 0.14), (0.09, 0.09, 0.09), parent=head)
        C.sphere("eyes", (s * 0.2, -0.18, 0.16), (0.045, 0.03, 0.05), parent=head)
    R.update(root=root, body=body, legs=legs, neck=neck, head=head)
    return R


QUADS = {"toad": toad}

# portrait framing for the non-humanoid rigs: (height of the focus, view size)
PORTRAIT = {"manta": (0.62, 1.2), "wasp": (0.72, 0.95), "paper": (0.95, 1.0), "crab": (0.42, 1.45),
            "beetle": (0.38, 1.5), "toad": (0.5, 1.55)}
