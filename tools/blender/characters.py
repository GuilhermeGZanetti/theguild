"""Anime character models for the playable races of A Guilda, in a masculine
and a feminine build for every class, following the concept sheets in
concept_art/.

The kit (class Kit) builds chibi bodies from sweeps and lathes: a gendered
torso, limbs, hands and feet; an anime head with big projected eyes (dark
lash line, lit lower iris, highlight), brows and a mouth; hair from tapered
flat locks that fall around the skull; cloth with folds and ragged hems.
The designs (one function per race) dress it:

  human     anime adventurers, two hairstyles per build
  tidefolk  teal skin, navy hair, golden fin ears, webbed feet and a glowing
            jellyfish companion; the old captain, the corsair, the spear
            fighter and the hooded tide mystic
  mothkin   pale skin, fluffy hair, feathered antennae, big eye-spotted moth
            wings and lanterns; the scout with round glasses, the scholar
            with a book, the hooded wanderer and the lantern priestess
  barkborn  bark skin, long ears, maple-leaf hair, twig antlers and root
            feet; the leaf-poncho archer, the treant druid, the flower
            forager and the masked leaf warrior
  khepri    beetle folk with big orange eyes and long antennae under hoods,
            helmets and headcloths, carrying travel packs

Characters face -Y; their right hand is at -X. One unit is one tile.
"""
import math
import random
from mathutils import Vector, Matrix
import bl_common as C

RACES = ("human", "tidefolk", "mothkin", "barkborn", "khepri")
HEAD_C = Vector((0.0, 0.0, 0.28))      # skull centre in head-pivot space
UP = Vector((0.0, 0.0, 1.0))


def tall_of(spec):
    """Height factor of a variant (the rig scales hips, torso and arms by it)."""
    t = 0.975 if spec.get("gender") == "f" else 1.035
    return t * {("barkborn", "graftwarden"): 1.1, ("khepri", "warrior"): 1.02}.get((spec["race"], spec["look"]), 1.0)


# ======================================================================
# small helpers
# ======================================================================
def dirv(az, el):
    """Unit vector: azimuth in degrees (0 = front -Y, +90 = the character's
    left +X, 180 = back) and elevation in degrees."""
    a, e = math.radians(az), math.radians(el)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def frame(name, loc, rot, parent):
    """A pivot with a fixed rotation (reset_pose leaves it alone)."""
    p = C.pivot(name, loc, parent)
    C.set_rot(p, *rot)
    p["static"] = True
    return p


def basis_rot(z, y_hint):
    """Euler degrees turning local Z toward z and local Y toward y_hint."""
    z = Vector(z).normalized()
    y = Vector(y_hint) - z * Vector(y_hint).dot(z)
    if y.length < 1e-6:
        y = z.orthogonal()
    y.normalize()
    x = y.cross(z)
    e = Matrix((x, y, z)).transposed().to_euler()
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def eye_outline(w, h, outer, flick=False, n=22):
    """Anime eye: a squarer, wider upper lid and a round lower edge; `flick`
    adds a lash at the outer top corner (outer = +1 toward +u)."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        x = math.cos(a) * w * 0.5
        s = math.sin(a)
        if s > 0:
            y = h * 0.5 * s ** 0.62
            x *= 1.1
        else:
            y = h * 0.5 * s
        pts.append((x, y))
    if flick:
        ang = 0.42 if outer > 0 else math.pi - 0.42
        i = int(ang / (2 * math.pi) * n) + (1 if outer > 0 else 0)
        pts.insert(i, (outer * w * 0.74, h * 0.43))
    return pts


def maple_outline(lobes=5, N=34):
    """A lobed leaf with its base at v=0 and tip at v=1."""
    pts = []
    for k in range(N):
        a = 2 * math.pi * k / N
        r = 0.46 + 0.54 * abs(math.cos(lobes * a / 2)) ** 2.2
        r *= 1.0 - 0.55 * max(0.0, math.cos(a - math.pi)) ** 8
        pts.append((math.sin(a) * r * 0.5, 0.5 + math.cos(a) * r * 0.5))
    return pts


def oval_outline(w=0.36, N=16):
    """A pointed almond leaf, base v=0, tip v=1."""
    pts = []
    for k in range(N):
        s = k / (N // 2) if k <= N // 2 else 2 - k / (N // 2)
        side = 1 if k <= N // 2 else -1
        pts.append((side * w * math.sin(math.pi * s) ** 0.85, s))
    return pts


MAPLE = maple_outline()
OVAL = oval_outline()


# ======================================================================
# the kit
# ======================================================================
class Kit:
    def __init__(self, R, spec):
        self.R = R
        self.race, self.look = spec["race"], spec["look"]
        self.g = spec.get("gender", "m")
        self.f = self.g == "f"
        self.style = spec.get("hair", "a")
        self.rng = random.Random(sum(ord(ch) * (i + 1) for i, ch in enumerate(self.race + self.look + self.g + self.style)))
        self.t = R["tall"]
        self.head, self.neck, self.torso = R["head"], R["neck"], R["torso"]
        self.band = (0.36, 0.42, -16)      # head bandage: radius, height, tilt
        self.bvh = None
        self.scalp = 0.305
        self.setup_body(1.0)

    # ------------------------------------------------------------ metrics
    def setup_body(self, bulk=1.0):
        f, t = self.f, self.t
        self.bulk = bulk
        self.sh = (0.168 if f else 0.19) * bulk
        self.arm_r = (0.039 if f else 0.047) * bulk
        self.leg_x = (0.072 if f else 0.08) * bulk
        self.leg_r = (0.056 if f else 0.062) * bulk
        if f:
            keys = [(-0.1, .150, .116), (0.0, .150, .116), (.12, .140, .108), (.34, .112, .090), (.60, .130, .104),
                    (.78, .134, .100), (.91, .104, .082), (1.0, .050, .045)]
        else:
            keys = [(-0.1, .146, .113), (0.0, .146, .113), (.12, .144, .110), (.34, .140, .106), (.60, .160, .120),
                    (.78, .166, .120), (.91, .128, .097), (1.0, .058, .052)]
        self.tkeys = [(z * 0.44 * t, rx * bulk, ry * bulk) for z, rx, ry in keys]
        self.R["armR"].location = (-self.sh, 0.0, 0.38 * t)
        self.R["armL"].location = (self.sh, 0.0, 0.38 * t)
        self.R["legR"].location = (-self.leg_x, 0.0, 0.0)
        self.R["legL"].location = (self.leg_x, 0.0, 0.0)
        self.R["handR"].location = (0.0, 0.0, -0.30 * t)
        self.R["handL"].location = (0.0, 0.0, -0.30 * t)

    def trad(self, z, infl=0.0):
        k = self.tkeys
        if z <= k[0][0]:
            return k[0][1] + infl, k[0][2] + infl
        for i in range(len(k) - 1):
            if z <= k[i + 1][0]:
                u = (z - k[i][0]) / (k[i + 1][0] - k[i][0])
                return (k[i][1] + (k[i + 1][1] - k[i][1]) * u + infl, k[i][2] + (k[i + 1][2] - k[i][2]) * u + infl)
        return k[-1][1] + infl, k[-1][2] + infl

    def on_torso(self, az, z, infl=0.0):
        """A point on the torso surface (az as in dirv)."""
        rx, ry = self.trad(z, infl)
        a = math.radians(az)
        return Vector((math.sin(a) * rx, -math.cos(a) * ry, z))

    # ------------------------------------------------------------ body
    def neck_part(self, slot="skin"):
        r = 0.045 if self.f else 0.054
        C.sweep(slot, [(0, 0.004, -0.04), (0, 0.0, 0.1)], [r, r * 0.9], self.neck, res=1, ring=12, up=(0, -1, 0))

    def torso_piece(self, slot, z0, z1, infl=0.0, n=8, seg=28, folds=0, fold_amp=0.0, cap_top=False,
                    cap_bot=False, shape=None, flare=0.0, parent=None, arc=None, thick=0.012):
        """A band of the torso between heights z0 (bottom) and z1 (top); flare
        widens it below the hips (tunics, jerkins)."""
        prof = []
        for i in range(n + 1):
            z = z1 + (z0 - z1) * i / n
            rx, ry = self.trad(z, infl)
            if z < 0 and flare:
                e = flare * min(1.0, -z / 0.12)
                rx, ry = rx + e, ry + e * 0.8
            prof.append((rx, ry, z))
        return C.lathe(slot, prof, parent or self.torso, seg=seg if arc is None else seg + 8, res=1, folds=folds, fold_amp=fold_amp,
                       fold_from=0.5 if folds else 0.0, cap_top=cap_top, cap_bot=cap_bot, shape=shape, arc=arc,
                       thick=thick if arc else 0.0)

    def chest(self, slot, infl=0.0):
        if not self.f:
            return
        t = self.t
        for s in (-1, 1):
            C.sphere(slot, (s * 0.05, -0.068 - infl, 0.262 * t), (0.052 + infl, 0.046 + infl, 0.047 + infl * 0.5),
                     parent=self.torso, seg=14, rings=8)

    def pelvis(self, slot, infl=0.004):
        t = self.t
        rx, ry = self.trad(0.02, infl)
        prof = [(rx, ry, 0.07 * t), (rx, ry, 0.0), (rx * 0.94, ry * 0.93, -0.045 * t), (rx * 0.62, ry * 0.7, -0.085 * t)]
        C.lathe(slot, prof, self.torso, seg=24, res=2, cap_bot=True)

    def legs(self, style="pants", slot="cloth2", feet="boots", foot_slot="leather", wrap=None, knee=None, cuff=None):
        t = self.t
        for leg in (self.R["legR"], self.R["legL"]):
            r = self.leg_r
            thigh, kn, ank = (0, 0, 0.02), (0, -0.012, -0.175 * t), (0, 0.0, -0.33 * t)
            if style in ("bare", "shorts", "tights", "breeches", "short_shorts"):
                C.sweep("skin" if style != "tights" else slot, [thigh, kn, ank], [r, r * 0.74, r * 0.6], leg, ring=12, up=(0, -1, 0))
            if style == "pants":
                C.sweep(slot, [thigh, kn, ank], [r + 0.012, r * 0.82 + 0.012, r * 0.72 + 0.012], leg, ring=12, up=(0, -1, 0))
            elif style == "baggy":
                C.sweep(slot, [thigh, kn, (0, -0.005, -0.28 * t), ank], [r + 0.014, r * 0.9 + 0.024, r * 0.9 + 0.022, r * 0.66 + 0.01],
                        leg, ring=12, up=(0, -1, 0))
            elif style == "shorts":
                C.sweep(slot, [thigh, (0, -0.008, -0.1 * t), (0, -0.012, -0.15 * t)], [r + 0.014, r * 0.92 + 0.016, r * 0.86 + 0.018],
                        leg, ring=12, up=(0, -1, 0))
            elif style == "short_shorts":
                C.sweep(slot, [thigh, (0, -0.006, -0.07 * t)], [r + 0.012, r * 0.95 + 0.014], leg, ring=12, up=(0, -1, 0), res=1)
            elif style == "breeches":
                C.sweep(slot, [thigh, (0, -0.01, -0.12 * t), (0, -0.012, -0.2 * t)], [r + 0.014, r * 0.92 + 0.02, r * 0.78 + 0.02],
                        leg, ring=12, up=(0, -1, 0))
                C.lathe(cuff or "trim", [(r * 0.78 + 0.024, -0.19 * t), (r * 0.78 + 0.026, -0.215 * t)], leg, seg=16, res=1)
            if wrap:
                for i in range(3):
                    z = -0.225 * t - i * 0.035 * t
                    rr = r * (0.7 - i * 0.03) + 0.008
                    C.lathe(wrap, [(rr, z + 0.012), (rr + 0.006, z), (rr, z - 0.012)], leg, seg=14, res=1, rot=(8 * (-1) ** i, 0, 0))
            if knee:
                C.sphere(knee, (0, -0.045, -0.185 * t), (0.05, 0.03, 0.055), parent=leg, seg=12, rings=8)
            self.foot(leg, feet, foot_slot)

    def foot(self, leg, kind, slot="leather"):
        t = self.t
        zb = -0.40 * t
        r = self.leg_r
        if kind in ("boots", "tall_boots"):
            top = -0.23 * t if kind == "boots" else -0.13 * t
            C.sweep(slot, [(0, 0, top), (0, 0.0, -0.36 * t)], [r * 0.7 + 0.018, r * 0.62 + 0.016], leg, res=1, ring=12, up=(0, -1, 0))
            C.lathe(slot, [(r * 0.7 + 0.03, top + 0.012), (r * 0.7 + 0.03, top - 0.012)], leg, seg=16, res=1)
            C.sweep(slot, [(0, 0.03, zb + 0.045), (0, -0.02, zb + 0.04), (0, -0.075, zb + 0.032), (0, -0.1, zb + 0.026)],
                    [(0.046, 0.045), (0.05, 0.042), (0.044, 0.032), (0.03, 0.02)], leg, up=(0, 0, 1), ring=10)
        elif kind == "shoes":
            C.sweep(slot, [(0, 0.028, zb + 0.04), (0, -0.02, zb + 0.036), (0, -0.07, zb + 0.028), (0, -0.09, zb + 0.022)],
                    [(0.042, 0.04), (0.045, 0.036), (0.04, 0.028), (0.026, 0.018)], leg, up=(0, 0, 1), ring=10)
        elif kind == "webbed":
            C.sweep("skin", [(0, 0.03, zb + 0.05), (0, -0.03, zb + 0.035)], [(0.05, 0.045), (0.062, 0.03)], leg, up=(0, 0, 1), ring=10, res=2)
            for a in (-30, 0, 30):
                d = Vector((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
                b = Vector((0, -0.035, zb + 0.028))
                C.sweep("skin", [b, b + d * 0.06, b + d * 0.1 + Vector((0, 0, -0.008))], [(0.024, 0.02), (0.021, 0.016), (0.01, 0.008)],
                        leg, up=(0, 0, 1), ring=8, res=2)
            web = [(0, 0)] + [(math.sin(math.radians(a)) * 0.095, -math.cos(math.radians(a)) * 0.095) for a in range(-32, 33, 8)]
            C.flat("skin", [(u, -v) for (u, v) in web], 0.008, leg, loc=(0, -0.035, zb + 0.02), rot=(90, 0, 0), rings=1)
        elif kind == "root":
            C.sweep("skin", [(0, 0.035, zb + 0.06), (0, -0.02, zb + 0.045)], [(0.05, 0.048), (0.058, 0.035)], leg, up=(0, 0, 1), ring=10, res=2)
            for a in (-28, 0, 28):
                d = Vector((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
                b = Vector((0, -0.03, zb + 0.035))
                C.sweep("skin2", [b, b + d * 0.06 + Vector((0, 0, 0.004)), b + d * 0.1 + Vector((0, 0, -0.03))],
                        [(0.02, 0.018), (0.016, 0.014), (0.0, 0.0)], leg, up=(0, 0, 1), ring=8, res=2)
            C.sweep("skin2", [(0, 0.04, zb + 0.04), (0, 0.09, zb + 0.005)], [(0.018, 0.016), (0.0, 0.0)], leg, up=(0, 0, 1), ring=8, res=1)
        elif kind == "hoof":      # khepri: rounded chitin boots with two claws
            C.sweep(slot, [(0, 0, -0.26 * t), (0, 0.0, -0.36 * t)], [r * 0.7 + 0.02, r * 0.7 + 0.024], leg, res=1, ring=12, up=(0, -1, 0))
            C.sweep(slot, [(0, 0.03, zb + 0.05), (0, -0.02, zb + 0.045), (0, -0.07, zb + 0.035)], [(0.05, 0.05), (0.055, 0.045), (0.042, 0.03)],
                    leg, up=(0, 0, 1), ring=10)
            for s in (-1, 1):
                C.sweep("feature", [(s * 0.022, -0.075, zb + 0.03), (s * 0.026, -0.105, zb + 0.012)], [(0.014, 0.012), (0.0, 0.0)], leg,
                        up=(0, 0, 1), ring=6, res=1)

    def arms(self, style="long", slot="cloth1", cuff=None, bracer=None, shoulder=None, wide=0.06, skin="skin"):
        """style: bare, long, short, puffy, wide (bell sleeves), cap."""
        t = self.t
        for side, arm in ((-1, self.R["armR"]), (1, self.R["armL"])):
            r = self.arm_r
            sh_pt, el_pt, wr_pt = (0, 0, 0.02), (0, 0.01, -0.135 * t), (0, 0.0, -0.255 * t)
            C.sphere(shoulder or (slot if style != "bare" else skin), (0, 0, -0.01), (r * 1.3, r * 1.25, r * 1.25), parent=arm, seg=14, rings=10)
            if style in ("bare", "short", "puffy", "cap"):
                C.sweep(skin, [sh_pt, el_pt, wr_pt], [r, r * 0.86, r * 0.72], arm, ring=10, up=(0, -1, 0))
            if style == "long":
                C.sweep(slot, [sh_pt, el_pt, wr_pt], [r + 0.012, r * 0.9 + 0.013, r * 0.8 + 0.014], arm, ring=10, up=(0, -1, 0))
                C.lathe(cuff or slot, [(r * 0.8 + 0.024, -0.225 * t), (r * 0.8 + 0.027, -0.25 * t), (r * 0.8 + 0.022, -0.262 * t)],
                        arm, seg=14, res=1)
            elif style == "short":
                C.sweep(slot, [sh_pt, (0, 0.006, -0.1 * t)], [r + 0.014, r * 0.95 + 0.017], arm, ring=10, res=2, up=(0, -1, 0))
            elif style == "cap":
                C.sweep(slot, [sh_pt, (0, 0.004, -0.05 * t)], [r + 0.016, r + 0.018], arm, ring=10, res=1, up=(0, -1, 0))
            elif style == "puffy":
                C.lathe(slot, [(r * 0.6, 0.04), (r + 0.03, 0.0), (r + 0.034, -0.06 * t), (r + 0.02, -0.11 * t), (r * 0.9, -0.125 * t)],
                        arm, seg=16, res=2, folds=6, fold_amp=0.08)
                if cuff:
                    C.lathe(cuff, [(r * 0.95 + 0.004, -0.115 * t), (r * 0.95 + 0.008, -0.13 * t)], arm, seg=14, res=1)
            elif style == "wide":
                C.sweep(slot, [sh_pt, el_pt, (0, 0, -0.2 * t)], [r + 0.012, r * 0.9 + 0.016, r * 0.9 + 0.02], arm, ring=10, up=(0, -1, 0))
                C.lathe(slot, [(r * 0.9 + 0.02, -0.15 * t), (r + 0.02 + wide * 0.6, -0.22 * t), (r + 0.02 + wide, -0.29 * t)],
                        arm, seg=18, res=2, folds=5, fold_amp=0.12, thick=0.012)
                C.sweep(skin, [(0, 0, -0.18 * t), wr_pt], [r * 0.78, r * 0.72], arm, ring=8, res=1, up=(0, -1, 0))
                if cuff:
                    C.lathe(cuff, [(r + 0.022 + wide, -0.28 * t), (r + 0.024 + wide, -0.3 * t)], arm, seg=18, res=1)
            if bracer:
                C.sweep(bracer, [(0, 0.006, -0.16 * t), (0, 0.0, -0.245 * t)], [r * 0.86 + 0.016, r * 0.78 + 0.018], arm, res=1, ring=10,
                        up=(0, -1, 0))
                C.lathe(bracer, [(r * 0.86 + 0.022, -0.155 * t), (r * 0.86 + 0.024, -0.17 * t)], arm, seg=14, res=1)

    def hands(self, slot="skin", claws=None):
        for side, hand in ((-1, self.R["handR"]), (1, self.R["handL"])):
            r = self.arm_r
            C.sweep(slot, [(0, 0, 0.055), (0, -0.004, 0.02), (0, -0.01, -0.02), (0, -0.012, -0.036)],
                    [(r * 0.78, r * 0.72), (r * 1.08, r * 0.82), (r * 0.95, r * 0.66), (r * 0.55, r * 0.45)], hand, up=(1, 0, 0), ring=10, res=2)
            C.sweep(slot, [(-side * r * 0.4, -0.026, 0.03), (-side * r * 0.55, -0.045, 0.005)], [r * 0.36, r * 0.28], hand, res=2, ring=8,
                    up=(1, 0, 0))
            if claws:
                for dz in (-0.012, 0.012):
                    C.sweep(claws, [(side * 0.0, -0.02 + dz * 0.5, -0.03), (0, -0.03, -0.06)], [(0.012, 0.01), (0.0, 0.0)], hand, res=1, ring=6)

    # ------------------------------------------------------------ head
    def head_base(self, slot="skin", hx=0.292, hy=0.282, hz=0.278, chin=1.0, jaw=0.3, snout=0.0):
        segs, rings = 30, 20
        verts, faces = [], []

        def pt(d):
            x, y, z = d.x * hx, d.y * hy, d.z * hz
            low = max(0.0, -d.z)
            front = max(0.0, -d.y)
            k = 1.0 - jaw * (low ** 1.4) * (0.35 + 0.65 * front)
            x *= k
            z -= 0.034 * low * low * front * chin
            y -= 0.016 * low * front * chin
            if d.y < 0:
                y *= 1.0 - 0.07 * front * (1.0 - low)
            if snout:
                y -= snout * max(0.0, front - 0.6) * max(0.0, 1 - abs(d.z + 0.25) * 2.5)
            return Vector((x, y, z)) + HEAD_C

        for i in range(1, rings):
            phi = math.pi * i / rings
            for j in range(segs):
                th = 2 * math.pi * j / segs
                verts.append(pt(Vector((math.sin(phi) * math.sin(th), -math.sin(phi) * math.cos(th), math.cos(phi)))))
        top = len(verts)
        verts.append(pt(Vector((0, 0, 1))))
        bot = len(verts)
        verts.append(pt(Vector((0, 0, -1))))
        for i in range(rings - 2):
            for j in range(segs):
                a, b = i * segs + j, i * segs + (j + 1) % segs
                faces.append((a, b, b + segs, a + segs))
        for j in range(segs):
            faces.append((top, (j + 1) % segs, j))
            base = (rings - 2) * segs
            faces.append((bot, base + j, base + (j + 1) % segs))
        self.head_mesh = C.mesh_obj(slot, verts, faces, self.head, True, name="head")
        self.bvh = C.surface_bvh(self.head_mesh)
        return self.head_mesh

    def on_head(self, az, el, lift=0.0):
        d = dirv(az, el)
        hit = self.bvh.ray_cast(HEAD_C + d * 2.0, -d)
        p = hit[0] if hit[0] is not None else HEAD_C + d * 0.29
        return p + d * lift

    def eyes(self, size=1.0, gap=22.0, el=-9.0, iris=("eyes", 0.03), lit=("eyes", 0.64), pupil=None, lashes=None, hl=True,
             wide=1.0, tall=1.0, lids=None):
        """Big anime eyes projected on the face: a dark lash line and iris, a
        lighter lower iris, an optional pupil and highlights."""
        f = self.f
        w = (0.108 if f else 0.098) * size * wide
        h = (0.142 if f else 0.122) * size * tall
        for s in (-1, 1):
            d = dirv(s * gap, el)
            C.decal(iris, self.bvh, eye_outline(w, h, s, flick=f if lashes is None else lashes), HEAD_C, d, lift=0.004, parent=self.head)
            if lit:
                lo = [(x * 0.74, y * 0.5 - h * 0.17) for (x, y) in C.ellipse(14, w * 0.5, h * 0.5)]
                C.decal(lit, self.bvh, lo, HEAD_C, d, lift=0.0055, parent=self.head)
            if pupil:
                C.decal(pupil, self.bvh, C.ellipse(10, w * 0.2, h * 0.22, 0, -h * 0.05), HEAD_C, d, lift=0.0065, parent=self.head)
            if lids:
                top = [(x, y) for (x, y) in eye_outline(w * 1.08, h * 1.02, s, flick=f) if y > h * 0.18]
                top = top + [(x * 0.9, h * 0.2) for (x, y) in reversed(top)]
                C.decal(lids, self.bvh, top, HEAD_C, d, lift=0.0068, parent=self.head)
            if hl:
                C.only_in(C.decal(("white", 1.0, "prio"), self.bvh, C.ellipse(10, w * 0.2, h * 0.16, -w * 0.16, h * 0.17), HEAD_C, d,
                                  lift=0.008, parent=self.head), "portrait")
                C.only_in(C.decal(("white", 0.9, "prio"), self.bvh, C.ellipse(8, w * 0.1, h * 0.07, w * 0.16, -h * 0.26), HEAD_C, d,
                                  lift=0.008, parent=self.head), "portrait")
        self.eye_w, self.eye_h = w, h

    def brows(self, slot="hair", el=13.0, gap=22.0, thick=None, arch=None):
        f = self.f
        th = thick or (0.013 if f else 0.02)
        arch = (0.012 if f else 0.004) if arch is None else arch
        for s in (-1, 1):
            pts_top, pts_bot = [], []
            for i in range(7):
                u = i / 6
                x = (-0.5 + u) * 0.105 * s
                y = arch * math.sin(math.pi * u) + (0.0 if f else 0.012 * (u - 0.5))
                tk = th * (1.0 - 0.45 * u) if not f else th * (0.6 + 0.4 * math.sin(math.pi * u))
                pts_top.append((x, y + tk * 0.5))
                pts_bot.append((x, y - tk * 0.5))
            ol = pts_top + list(reversed(pts_bot))
            if s < 0:
                ol = list(reversed(ol))
            C.decal(slot, self.bvh, ol, HEAD_C, dirv(s * gap, el), lift=0.005, parent=self.head)

    def head_band(self, slot, el_front=30.0, el_back=42.0, lift=0.045, r=(0.02, 0.009)):
        """A band hugging the head (or whatever sits `lift` above it): circlets, straps."""
        pts = []
        for i in range(25):
            az = 360.0 * i / 24
            el = el_front + (el_back - el_front) * (1 - math.cos(math.radians(az))) / 2
            pts.append(self.on_head(az, el, lift))
        C.sweep(slot, pts, [r] * len(pts), self.head, up=(0, 0, 1), ring=6, res=2)

    def mouth(self, slot="skin2", smile=True, el=-36.0):
        ol = [(x, y - (0.006 * (1 - (x / 0.024) ** 2) if smile else 0.0)) for (x, y) in C.ellipse(10, 0.024, 0.0075)]
        C.only_in(C.decal(slot, self.bvh, ol, HEAD_C, dirv(0, el), lift=0.004, parent=self.head), "portrait")

    def blush(self, slot="skin2"):
        for s in (-1, 1):
            C.only_in(C.decal(slot, self.bvh, C.ellipse(10, 0.034, 0.013), HEAD_C, dirv(s * 30, -24), lift=0.003, parent=self.head), "portrait")

    def ears(self, kind="human", slot="skin", k=1.0):
        head = self.head
        for s in (-1, 1):
            if kind == "human":
                C.sphere(slot, (s * 0.285, 0.03, 0.25), (0.03, 0.05, 0.065), parent=head, seg=10, rings=8)
            elif kind == "pointed":      # mothkin: small elf ears
                C.sweep(slot, [(s * 0.26, 0.03, 0.26), (s * 0.34, 0.05, 0.3), (s * 0.4 * k, 0.07, 0.35 * k)],
                        [(0.04, 0.014), (0.03, 0.012), (0.0, 0.0)], head, up=(0, 1, 0), ring=8, res=2)
            elif kind == "long":         # barkborn: long leaf-shaped ears
                C.sweep(slot, [(s * 0.25, 0.03, 0.26), (s * 0.36, 0.06, 0.31), (s * 0.47 * k, 0.1, 0.37 * k)],
                        [(0.05, 0.016), (0.034, 0.013), (0.0, 0.0)], head, up=(0, 1, 0), ring=8, res=3)
            elif kind == "fin":          # tidefolk: golden fins with three spines
                fr = frame("fin", (s * 0.27, 0.05, 0.27), (s * 22, -22, 90 - s * 38), head)
                ol = [(0.0, 0.05), (0.06, 0.1), (0.13, 0.14), (0.12, 0.08), (0.2, 0.085), (0.15, 0.03), (0.21, 0.0), (0.14, -0.035),
                      (0.06, -0.05), (0.0, -0.035)]
                k = k * 1.25
                ol = [(u * k, v * k) for (u, v) in ol]
                # thin translucent-looking membrane: flat, evenly lit gold with darker spines
                C.flat((slot, 0.74), ol, 0.012, fr, bend=0.8, rot=(0, 0, 0))
                for (u1, v1) in ((0.13, 0.14), (0.2, 0.085), (0.21, 0.0)):
                    C.sweep((slot, 0.42), [(0.01, 0, 0.0), (u1 * k * 0.92, 0, v1 * k * 0.92)], [0.008, 0.0], fr, ring=5, res=1)

    # ------------------------------------------------------------ hair
    def hair_cap(self, slot="hair", back=0.03, up=0.022, r=(0.303, 0.298, 0.288), parent=None):
        return C.sphere(slot, (0, back, 0.28 + up), r, parent=parent or self.head, seg=28, rings=16)

    def lock_path(self, az, el, zmin=-9.0, length=0.4, droop=1.0, out=0.25, side=0.0, curl=0.0, step=0.03, rs=None, lift=0.012,
                  wave=0.0):
        c = HEAD_C
        d = dirv(az, el)
        rs = rs or self.scalp
        p = c + d * (rs - 0.03)
        down = Vector((0, 0, -1))
        tan = down - d * down.dot(d)
        if tan.length < 1e-3:
            tan = Vector((0, 1, 0))
        tan.normalize()
        sidev = UP.cross(d)
        if sidev.length < 1e-3:
            sidev = Vector((1, 0, 0))
        sidev.normalize()
        v = (d * out + tan + sidev * side).normalized()
        pts = [p.copy()]
        dist = 0.0
        body_c, body_r = Vector((0, 0.01, -0.2)), Vector((0.235, 0.17, 0.2))
        while dist < length:
            p = p + v * step
            dist += step
            rel = p - c
            lim = rs + lift
            if rel.length < lim:
                p = c + rel.normalized() * lim
            q = p - body_c
            e = Vector((q.x / body_r.x, q.y / body_r.y, q.z / body_r.z))
            if e.length < 1.0 and e.length > 1e-6:
                e = e.normalized()
                p = body_c + Vector((e.x * body_r.x, e.y * body_r.y, e.z * body_r.z))
            pts.append(p.copy())
            if p.z < zmin:
                break
            nd = (p - c).normalized()
            v = (v + down * droop * 0.33 + nd * curl * 0.35 + sidev * (side * 0.08 + wave * math.cos(dist * 15.0))).normalized()
        return pts, d

    def lock(self, slot, az, el, w=0.07, th=0.026, zmin=-9.0, length=0.4, droop=1.0, out=0.25, side=0.0, curl=0.0,
             parent=None, ring=6, tip=0.0, root=0.7, rs=None, lift=0.012, wave=0.0):
        """A flat tapered lock of hair growing from the scalp at (az, el)."""
        pts, d = self.lock_path(az, el, zmin, length, droop, out, side, curl, rs=rs, lift=lift, wave=wave)
        n = len(pts)
        if n < 2:
            return None
        radii = []
        for i in range(n):
            u = i / (n - 1)
            prof = root + (1 - root) * (u / 0.28) if u < 0.28 else (1.0 - (u - 0.28) / 0.72) ** 0.85
            if i == n - 1:
                radii.append((tip, tip * 0.4))
            else:
                radii.append((max(tip, w * prof), max(0.004, th * prof)))
        return C.sweep(slot, pts, radii, parent or self.head, up=tuple(d), ring=ring, res=2)

    def bangs(self, slot="hair", n=5, spread=110.0, el=62.0, zmin=0.36, w=0.075, th=0.026, droop=1.4, out=0.2,
              longer_sides=0.06, side_sweep=0.0, jitter=5.0):
        """A fringe of pointed locks over the forehead; tips stop above the
        eyes (zmin is raised a little: the sprite camera looks down 30 degrees)."""
        for i in range(n):
            u = (i / (n - 1)) * 2 - 1 if n > 1 else 0.0
            az = u * spread / 2 + self.rng.uniform(-jitter, jitter)
            zz = zmin + 0.055 - longer_sides * abs(u) ** 1.5 + self.rng.uniform(-0.012, 0.012)
            self.lock(slot, az, el - 8 * abs(u), w * (1.0 - 0.15 * abs(u)), th, zmin=zz, length=0.5, droop=droop, out=out,
                      side=side_sweep, lift=0.004)

    def side_locks(self, slot="hair", zmin=0.08, w=0.07, th=0.026, az=74.0, el=30.0, n=1, droop=1.2, out=0.3, wave=0.0, curl=0.0):
        for s in (-1, 1):
            for i in range(n):
                self.lock(slot, s * (az + i * 14), el - i * 6, w, th, zmin=zmin - i * 0.03, length=1.2, droop=droop, out=out,
                          wave=wave * s, curl=curl)

    def back_hair(self, slot="hair", zmin=0.05, n=7, w=0.085, th=0.03, el=(25, 55), spread=150.0, droop=1.3, out=0.3, curl=0.0,
                  wave=0.0):
        for i in range(n):
            u = (i / (n - 1)) * 2 - 1
            az = 180 + u * spread / 2 + self.rng.uniform(-6, 6)
            e = el[0] + (el[1] - el[0]) * self.rng.random()
            self.lock(slot, az, e, w, th, zmin=zmin + self.rng.uniform(-0.04, 0.04) + 0.03 * abs(u), length=2.0, droop=droop,
                      out=out, curl=curl, wave=wave * self.rng.choice((-1, 1)))

    def spikes(self, slot="hair", n=9, length=0.17, w=0.075, th=0.045, out=1.4, droop=0.35, el=(20, 75), az=(-140, 140), curl=0.0):
        for i in range(n):
            a = az[0] + (az[1] - az[0]) * (i + 0.5) / n + self.rng.uniform(-8, 8)
            e = el[0] + (el[1] - el[0]) * self.rng.random()
            if abs(a) < 40 and e < 45:
                e = 50
            self.lock(slot, 180 + a, e, w, th, length=length * self.rng.uniform(0.85, 1.15), droop=droop, out=out, curl=curl, ring=6)

    def ahoge(self, slot="hair", az=10.0, el=80.0, k=1.0):
        base = HEAD_C + dirv(az, el) * (self.scalp - 0.02)
        pts = [base, base + Vector((0.01, -0.03, 0.09)) * k, base + Vector((0.05, -0.08, 0.13)) * k, base + Vector((0.1, -0.07, 0.1)) * k]
        C.sweep(slot, pts, [(0.03, 0.012), (0.026, 0.011), (0.016, 0.008), (0.0, 0.0)], self.head, up=(0, -1, 0), ring=6, res=3)

    def ponytail(self, slot="hair", tie=None, az=180.0, el=38.0, length=0.55, w=0.1, n=5, droop=1.0, out=0.9, tie_slot="cloth2"):
        d = dirv(az, el)
        base = HEAD_C + d * (self.scalp + 0.01)
        C.lathe(tie_slot, [(0.055, 0.02), (0.06, 0.0), (0.055, -0.02)], self.head, loc=tuple(base), rot=basis_rot(d, UP), seg=12, res=1)
        C.sphere(slot, tuple(base + d * 0.03), (0.07, 0.07, 0.07), parent=self.head, seg=12, rings=8)
        for i in range(n):
            a = 2 * math.pi * i / n
            off = Vector((math.cos(a) * 0.03, 0, math.sin(a) * 0.03))
            p = base + d * 0.04 + off
            v = (d * out + Vector((0, 0, -0.2))).normalized()
            pts = [p.copy()]
            for j in range(int(length / 0.035)):
                p = p + v * 0.035
                pts.append(p.copy())
                v = (v + Vector((0, 0, -1)) * droop * 0.22 + off * 0.8).normalized()
            m = len(pts)
            radii = [((w * (0.8 + 0.4 * math.sin(math.pi * min(1, j / (m * 0.45))))) * (1 - j / m) ** 0.7 if j < m - 1 else 0.0,
                      (w * 0.5 * (1 - j / m) ** 0.7) if j < m - 1 else 0.0) for j in range(m)]
            C.sweep(slot, pts, radii, self.head, up=(0, 1, 0), ring=6, res=2)

    def braid(self, slot, start, end, r=0.045, n=7, tie="cloth2"):
        a, b = Vector(start), Vector(end)
        for i in range(n):
            u = i / (n - 1)
            p = a.lerp(b, u) + Vector((0.012 * (-1) ** i, 0, 0))
            rr = r * (1.0 - 0.35 * u)
            C.sphere(slot, tuple(p), (rr, rr * 0.85, rr * 1.2), parent=self.head, seg=10, rings=6)
        C.lathe(tie, [(r * 0.7, 0.012), (r * 0.72, -0.012)], self.head, loc=tuple(b + Vector((0, 0, 0.02))), seg=10, res=1)
        C.sweep(slot, [tuple(b), tuple(b + Vector((0, 0.02, -0.08)))], [(r * 0.7, r * 0.6), (0.0, 0.0)], self.head, res=2, ring=6)

    def bun(self, slot, az, el, r=0.08):
        p = HEAD_C + dirv(az, el) * (self.scalp + r * 0.4)
        C.sphere(slot, tuple(p), (r, r, r * 0.9), parent=self.head, seg=14, rings=10)
        return p

    # ------------------------------------------------------------ leaves & flowers
    def leaf(self, slot, base, d, size, parent, normal=None, roll=0.0, shape=None, bend=-0.45):
        d = Vector(d).normalized()
        nrm = Vector(normal) if normal is not None else d.orthogonal()
        rot = basis_rot(d, nrm)
        ol = [(u * size, v * size) for (u, v) in (shape or MAPLE)]
        return C.flat(slot, ol, max(0.006, size * 0.07), parent, loc=tuple(Vector(base)), rot=rot, bend=bend / max(size, 0.05), rings=2,
                      center=(0.0, 0.45 * size))

    def leaf_lock(self, slots, az, el, size=0.13, zmin=-9.0, length=0.4, droop=1.0, out=0.4, side=0.0, gap=0.5, grow=0.25,
                  shape=None, parent=None):
        pts, d = self.lock_path(az, el, zmin, length, droop, out, side, lift=0.02)
        acc, last = 0.0, pts[0]
        n = 0
        for i in range(1, len(pts)):
            seg = (pts[i] - pts[i - 1]).length
            acc += seg
            if acc >= size * gap or i == len(pts) - 1:
                acc = 0.0
                t = (pts[i] - pts[i - 1]).normalized()
                nrm = (pts[i] - HEAD_C).normalized()
                u = i / (len(pts) - 1)
                self.leaf(self.rng.choice(slots), pts[i - 1], (t + nrm * 0.3).normalized(), size * (1 - grow + grow * u) * self.rng.uniform(0.9, 1.1),
                          parent or self.head, normal=nrm, shape=shape)
                n += 1
        return n

    def flower(self, parent, loc, d, r=0.03, petal="white", heart="trim"):
        d = Vector(d).normalized()
        rot = basis_rot(d, UP)
        fr = frame("flower", tuple(Vector(loc)), rot, parent)
        for i in range(5):
            a = 2 * math.pi * i / 5
            C.sphere(petal, (math.cos(a) * r, math.sin(a) * r, 0.0), (r * 0.75, r * 0.75, r * 0.3), parent=fr, seg=8, rings=5)
        C.sphere(heart, (0, 0, 0.006), (r * 0.5, r * 0.5, r * 0.35), parent=fr, seg=8, rings=5)

    # ------------------------------------------------------------ clothing
    def belt(self, z, slot="leather", buckle="trim", infl=0.012, h=0.03, round_buckle=False, parent=None):
        rx, ry = self.trad(z, infl)
        C.lathe(slot, [(rx, ry, z + h / 2), (rx + 0.004, ry + 0.004, z), (rx, ry, z - h / 2)], parent or self.torso, seg=28, res=1)
        if buckle:
            if round_buckle:
                C.lathe(buckle, [(0.012, 0.012), (0.034, 0.006), (0.036, -0.006), (0.012, -0.012)], parent or self.torso,
                        loc=(0, -ry - 0.008, z), rot=(90, 0, 0), seg=16, res=1, cap_top=True, cap_bot=True)
                C.sphere("leather" if slot != "leather" else "cloth2", (0, -ry - 0.018, z), (0.014, 0.008, 0.014), parent=parent or self.torso,
                         seg=8, rings=5)
            else:
                C.box(buckle, (0, -ry - 0.006, z), (0.05, 0.014, 0.044), parent=parent or self.torso, bevel=0.004)
                C.box(slot, (0, -ry - 0.012, z), (0.026, 0.01, 0.024), parent=parent or self.torso)

    def strap(self, slot, az0, z0, az1, z1, infl=0.014, r=0.013, back=True):
        """A strap across the chest from (az0, z0) to (az1, z1), over the shoulder and down the back."""
        pts = []
        for i in range(9):
            u = i / 8
            pts.append(self.on_torso(az0 + (az1 - az0) * u, z0 + (z1 - z0) * u, infl))
        if back:
            t = self.t
            top = self.on_torso(az0 + (-1 if az0 < 0 else 1) * 25, 0.44 * t, infl + 0.005)
            pts = [self.on_torso(180 - az0 * 0.3, z0 - 0.02, infl), top] + pts
        C.sweep(slot, pts, [(r, r * 0.45)] * len(pts), self.torso, up=(0, -1, 0), ring=6, res=2)

    def scarf(self, slot, z=None, bulk=1.0, tail=1, tail_len=0.18, mask=False, up=0.0, tails=1):
        t = self.t
        z = (0.44 * t if z is None else z) + up
        rx, ry = 0.13 * bulk, 0.118 * bulk
        C.lathe(slot, [(rx * 0.55, ry * 0.55, z + 0.05), (rx * 0.95, ry * 0.95, z + 0.04), (rx * 1.05, ry * 1.05, z),
                       (rx * 1.02, ry * 1.02, z - 0.035), (rx * 0.8, ry * 0.8, z - 0.05)], self.torso, seg=24, res=2, folds=7, fold_amp=0.06)
        if mask:
            # pulled up over the chin (head space)
            C.lathe(slot, [(0.2, 0.19, 0.17), (0.235, 0.225, 0.1), (0.24, 0.23, 0.04), (0.17, 0.16, -0.03)], self.head, seg=24, res=2,
                    folds=6, fold_amp=0.05, shape=lambda th, u: 1.0 + 0.12 * max(0.0, math.cos(th)) ** 2)
        for i in range(tails if tail else 0):
            s = tail if i == 0 else -tail
            L = tail_len * (1.0 if i == 0 else 0.75)
            p0 = Vector((s * 0.06, -ry * 0.95, z - 0.02))
            pts = [p0, p0 + Vector((s * 0.03, -0.035, -L * 0.35)), p0 + Vector((s * 0.05, -0.04, -L * 0.7)), p0 + Vector((s * 0.055, -0.03, -L))]
            C.sweep(slot, pts, [(0.04, 0.014), (0.04, 0.013), (0.038, 0.012), (0.036, 0.01)], self.torso, up=(0, -1, 0), ring=6, res=2)
            C.sweep(slot, [pts[-1], pts[-1] + Vector((0, 0.0, -0.03))], [(0.036, 0.01), (0.0, 0.0)], self.torso, up=(0, -1, 0), ring=6, res=1)

    def skirt(self, slot, z, length, flare=0.06, infl=0.012, folds=9, fold_amp=0.1, arc=None, hem=0.0, hem_n=0, thick=0.012,
              phase=0.0, rows=5, parent=None, shape=None, hem_pow=2.0):
        rx, ry = self.trad(z, infl)
        prof = []
        for i in range(rows + 1):
            u = i / rows
            e = flare * u ** 1.2
            prof.append((rx + e, ry + e * 0.85, z - length * u))
        return C.lathe(slot, prof, parent or self.torso, seg=36, res=2, folds=folds, fold_amp=fold_amp, fold_from=0.15, arc=arc,
                       hem=hem, hem_n=hem_n, thick=thick if arc else 0.0, phase=phase, shape=shape, hem_pow=hem_pow)

    def cape(self, slot, length=0.55, z=None, width=150.0, flare=0.12, folds=7, fold_amp=0.12, hem=0.0, hem_n=0, collar=None,
             infl=0.03, thick=0.014):
        t = self.t
        z = 0.42 * t if z is None else z
        rx, ry = self.trad(z, infl)
        prof = []
        for i in range(7):
            u = i / 6
            e = flare * u ** 1.1
            sw = min(1.0, u * 5)
            prof.append((rx * (0.75 + 0.25 * sw) + e, ry * (0.75 + 0.25 * sw) + e * 0.9 + 0.035 * sw, z - length * u))
        C.lathe(slot, prof, self.torso, seg=40, res=2, arc=(180 - width / 2, 180 + width / 2), folds=folds, fold_amp=fold_amp,
                fold_from=0.1, hem=hem, hem_n=hem_n, thick=thick)
        if collar:
            C.lathe(collar, [(rx * 0.75, ry * 0.75, z + 0.05), (rx + 0.03, ry + 0.03, z), (rx + 0.04, ry + 0.035, z - 0.035)], self.torso,
                    seg=28, res=2, thick=0.01)

    def mantle(self, slot, z=None, length=0.14, infl=0.02, flare=0.07, hem=0.03, hem_n=9, folds=0, thick=0.012, arc=None):
        """A short shoulder cape / poncho that hangs from the neck."""
        t = self.t
        z = 0.455 * t if z is None else z
        prof = [(0.07, 0.065, z + 0.01), (self.sh * 0.8, self.trad(z - 0.03, infl)[1] + 0.01, z - 0.02)]
        rx, ry = self.trad(z - length, infl)
        prof += [(self.sh + self.arm_r + flare * 0.6, ry + flare * 0.5, z - length * 0.55),
                 (self.sh + self.arm_r + flare, ry + flare * 0.8, z - length)]
        return C.lathe(slot, prof, self.torso, seg=40, res=2, hem=hem, hem_n=hem_n, folds=folds, fold_amp=0.08, fold_from=0.3,
                       arc=arc, thick=thick if arc else 0.0)

    def hood(self, slot, up=True, tip=0.0, rim=None, drape=True, ears=False, lining=None, brow=34.0, side=64.0, jaw=-38.0,
             back=-60.0, gap=0.032, peak=0.05, lip=0.014, tip_dir=(0, 1.0, -0.5), tip_slot=None):
        """A soft cloth hood fitted over the head (and its hair): it covers the
        crown down to `brow` over the forehead, frames the face down to `jaw`
        at the sides and falls to the nape (`back`) behind, with a slight peak
        at the back of the crown and a turned-out lip. Lining shows inside."""
        head = self.head
        if up:
            def edge(a):
                a = abs(a)
                s0 = side - 24.0
                if a <= s0:
                    return brow - 8.0 * (a / s0) ** 2
                if a <= side:
                    u = (a - s0) / 24.0
                    return (brow - 8.0) + (jaw - brow + 8.0) * (u * u * (3 - 2 * u))
                u = (a - side) / (180.0 - side)
                return jaw + (back - jaw) * (u * u * (3 - 2 * u))

            pk = dirv(180, 58)

            def rad(d, v):
                hit = self.bvh.ray_cast(HEAD_C + d * 2.0, -d)
                base = (hit[0] - HEAD_C).length if hit[0] is not None else 0.29
                bump = peak * max(0.0, d.dot(pk)) ** 3
                return base + gap + bump + lip * max(0.0, v - 0.8) / 0.2

            B, A = 40, 9
            verts, faces = [], []
            pole = len(verts)
            verts.append(HEAD_C + Vector((0, 0, 1)) * rad(Vector((0, 0, 1)), 0.0))
            for i in range(1, A + 1):
                v = i / A
                for j in range(B):
                    az = -180 + 360 * j / B
                    el = 90 - (90 - edge(az)) * v
                    d = dirv(az, el)
                    verts.append(HEAD_C + d * rad(d, v))
            for j in range(B):
                faces.append((pole, 1 + j, 1 + (j + 1) % B))
            for i in range(A - 1):
                for j in range(B):
                    a, b = 1 + i * B + j, 1 + i * B + (j + 1) % B
                    faces.append((a, b, b + B, a + B))
            h = C.mesh_obj(slot, verts, faces, head, True, name="hood")
            m = h.modifiers.new("solid", "SOLIDIFY")
            m.thickness = 0.016
            if lining:
                h.data.materials.append(C.mat(lining))
                m.material_offset = 1
            loop = [verts[1 + (A - 1) * B + j] for j in range(B)]
            if rim:
                nrm = [(p - HEAD_C).normalized() for p in loop]
                pts = [p + n * 0.006 for p, n in zip(loop, nrm)]
                C.sweep(rim, pts + [pts[0]], [(0.02, 0.009)] * (B + 1), head, up=(0, -1, 0), ring=6, res=1)
            if tip:
                top = HEAD_C + pk * (self.scalp + gap + peak - 0.02)
                td = Vector(tip_dir).normalized()
                pts = [top - td * 0.08, top + td * tip * 0.45 + Vector((0, 0, 0.015)), top + td * tip]
                C.sweep(tip_slot or slot, pts, [(0.075, 0.05), (0.04, 0.028), (0.0, 0.0)], head, up=(0, 0, 1), ring=10, res=3)
            if ears:
                for s in (-1, 1):
                    C.sweep(slot, [(s * 0.19, 0.04, 0.58), (s * 0.24, 0.06, 0.7)], [(0.07, 0.03), (0.0, 0.0)], head, up=(0, -1, 0),
                            ring=8, res=2)
        else:
            t = self.t
            C.lathe(slot, [(0.1, 0.095, 0.47 * t), (0.17, 0.155, 0.45 * t), (0.2, 0.18, 0.42 * t), (0.19, 0.17, 0.39 * t)], self.torso,
                    seg=28, res=2, folds=6, fold_amp=0.08, shape=lambda th, u: 1.0 + 0.25 * max(0.0, math.cos(th)) ** 2)
        if drape:
            self.mantle(slot, length=0.1, flare=0.03, hem=0.0, hem_n=0)

    def lapels(self, slot, z0=None, z1=None, w=0.05, infl=0.016, open_=0.035):
        t = self.t
        z0 = 0.16 * t if z0 is None else z0
        z1 = 0.43 * t if z1 is None else z1
        for s in (-1, 1):
            pts = []
            for i in range(6):
                u = i / 5
                z = z1 + (z0 - z1) * u
                rx, ry = self.trad(z, infl)
                x = s * (open_ + (0.1 - open_) * (1 - u) ** 1.5)
                pts.append(Vector((x, -ry * math.sqrt(max(0.0, 1 - (x / rx) ** 2)) - 0.004, z)))
            C.sweep(slot, pts, [(w * (0.6 + 0.4 * (1 - i / 5)), 0.008) for i in range(6)], self.torso, up=(0, -1, 0), ring=6, res=2)

    def front_panel(self, slot, z0, z1, w=0.07, infl=0.014, taper=1.0, drop=0.0, tip=False):
        """A hanging cloth panel down the front (tabards, sashes, apron)."""
        pts = []
        n = 6
        for i in range(n):
            u = i / (n - 1)
            z = z1 + (z0 - z1) * u
            rx, ry = self.trad(max(z, -0.05), infl)
            y = -ry - 0.004 - (drop * u * u)
            pts.append((0, y, z))
        radii = [(w * (1 - (1 - taper) * i / (n - 1)), 0.007) for i in range(n)]
        if tip:
            radii[-1] = (0.0, 0.0)
        C.sweep(slot, pts, radii, self.torso, up=(0, -1, 0), ring=6, res=2)

    def pauldron(self, slot, trim=None, k=1.0, layers=2):
        for arm in (self.R["armR"], self.R["armL"]):
            r = self.arm_r
            for i in range(layers):
                z = 0.03 - i * 0.045 * k
                rr = (r + 0.05 - i * 0.008) * k
                C.lathe(slot, [(0.01, z + 0.05 * k), (rr * 0.8, z + 0.035 * k), (rr, z), (rr * 1.02, z - 0.03 * k)], arm, seg=18, res=2,
                        thick=0.012)
            if trim:
                C.lathe(trim, [(r * 1.0 + 0.05 * k, -0.02 * k), (r * 1.02 + 0.052 * k, -0.035 * k)], arm, seg=18, res=1)

    # ------------------------------------------------------------ accessories
    def pack(self, body="leather", roll="white", flap="leather", trinkets=("glow", "trim", "feature"), k=1.0, roll_side=False):
        t, torso = self.t, self.torso
        z = 0.26 * t
        yb = self.trad(z)[1] + 0.02
        C.box(body, (0, yb + 0.1 * k, z), (0.3 * k, 0.17 * k, 0.32 * k), parent=torso, bevel=0.04 * k)
        C.box(flap, (0, yb + 0.16 * k, z + 0.1 * k), (0.28 * k, 0.07 * k, 0.12 * k), parent=torso, bevel=0.025 * k)
        C.box(body, (0, yb + 0.19 * k, z - 0.05 * k), (0.2 * k, 0.05 * k, 0.12 * k), parent=torso, bevel=0.02 * k)
        C.sphere("trim", (0, yb + 0.22 * k, z - 0.04 * k), (0.02, 0.01, 0.018), parent=torso, seg=8, rings=5)
        C.cyl(roll, (0, yb + 0.09 * k, z + 0.2 * k), (1, 1, 1), (0, 90, 0), parent=torso, r=0.075 * k, depth=0.38 * k, verts=14)
        for x in (-0.12, 0.12):
            C.lathe("leather", [(0.079 * k, 0.012), (0.082 * k, 0.0), (0.079 * k, -0.012)], torso, loc=(x * k, yb + 0.09 * k, z + 0.2 * k),
                    rot=(0, 90, 0), seg=14, res=1)
        for s in (-1, 1):
            self_pts = [self.on_torso(s * 150, 0.4 * t, 0.012), self.on_torso(s * 60, 0.44 * t, 0.014), self.on_torso(s * 25, 0.36 * t, 0.014),
                        self.on_torso(s * 30, 0.2 * t, 0.014)]
            C.sweep("leather", self_pts, [(0.016, 0.006)] * 4, torso, up=(0, -1, 0), ring=6, res=2)
        for i, sl in enumerate(trinkets):
            x = (-0.12 + 0.12 * i) * k
            C.sweep("leather", [(x, yb + 0.19 * k, z - 0.12 * k), (x, yb + 0.2 * k, z - 0.18 * k)], [0.004, 0.004], torso, res=1, ring=4)
            C.ico(sl, (x, yb + 0.2 * k, z - 0.21 * k), (1, 1, 1.4), parent=torso, r=0.026, sub=1)
        if roll_side:
            C.cyl(roll, (0.2 * k, yb + 0.06 * k, z - 0.02 * k), (1, 1, 1), (0, 0, 0), parent=torso, r=0.06 * k, depth=0.2 * k, verts=12)

    def pouch(self, az, z, slot="leather", k=1.0):
        p = self.on_torso(az, z, 0.03)
        C.box(slot, tuple(p), (0.07 * k, 0.05 * k, 0.07 * k), rot=(0, 0, az), parent=self.torso, bevel=0.012 * k)
        C.box(slot, tuple(p + Vector((0, 0, 0.03 * k))), (0.074 * k, 0.056 * k, 0.025 * k), rot=(0, 0, az), parent=self.torso, bevel=0.008)
        C.sphere("trim", tuple(self.on_torso(az, z + 0.02, 0.058)), (0.01, 0.006, 0.01), parent=self.torso, seg=6, rings=4)

    def potion(self, az, z, liquid="glow"):
        p = self.on_torso(az, z, 0.04)
        C.sphere(liquid, tuple(p), (0.035, 0.035, 0.035), parent=self.torso, seg=10, rings=8)
        C.cyl("white", tuple(p + Vector((0, 0, 0.042))), parent=self.torso, r=0.012, depth=0.03, verts=6)
        C.cyl("leather", tuple(p + Vector((0, 0, 0.062))), parent=self.torso, r=0.014, depth=0.014, verts=6)

    def small_lantern(self, parent, loc, k=1.0, glow="glow", metal="trim"):
        x, y, z = loc
        C.lathe(metal, [(0.01 * k, 0.1 * k), (0.03 * k, 0.085 * k), (0.045 * k, 0.065 * k), (0.047 * k, 0.055 * k)], parent,
                loc=(x, y, z), seg=10, res=1, cap_top=True)
        C.sphere(glow, (x, y, z), (0.037 * k, 0.037 * k, 0.05 * k), parent=parent, seg=10, rings=8)
        for a in (45, 135, 225, 315):
            C.cyl(metal, (x + math.cos(math.radians(a)) * 0.037 * k, y + math.sin(math.radians(a)) * 0.037 * k, z), parent=parent,
                  r=0.006 * k, depth=0.1 * k, verts=4)
        C.lathe(metal, [(0.047 * k, -0.052 * k), (0.04 * k, -0.07 * k), (0.012 * k, -0.08 * k)], parent, loc=(x, y, z), seg=10, res=1,
                cap_bot=True)
        C.torus(metal, (x, y, z + 0.12 * k), (1, 1, 1), (90, 0, 0), parent=parent, R=0.018 * k, r=0.005)

    def glasses(self, slot="metal", el=-6.0, gap=21.0):
        for s in (-1, 1):
            p = self.on_head(s * gap, el, 0.03)
            C.torus(slot, tuple(p), (1, 1, 1), basis_rot(dirv(s * gap * 0.7, el), UP), parent=self.head, R=0.06, r=0.009, seg=16, mseg=5)
        a, b = self.on_head(-7, el + 2, 0.028), self.on_head(7, el + 2, 0.028)
        C.sweep(slot, [a, b], [0.008, 0.008], self.head, res=1, ring=5)

    def earrings(self, slot="trim", drop=True):
        for s in (-1, 1):
            p = Vector((s * 0.29, 0.01, 0.16))
            C.torus(slot, tuple(p), (1, 1, 1), (0, 90, 0), parent=self.head, R=0.024, r=0.007, seg=10, mseg=4)
            if drop:
                C.ico(slot, tuple(p + Vector((0, 0, -0.035))), (1, 1, 1.4), parent=self.head, r=0.014, sub=1)

    def amulet(self, gem="glow", cord="leather", z=None):
        t = self.t
        z = 0.28 * t if z is None else z
        a, b = self.on_torso(-40, 0.43 * t, 0.012), self.on_torso(40, 0.43 * t, 0.012)
        c = self.on_torso(0, z + 0.03, 0.02)
        C.sweep(cord, [a, c + Vector((-0.02, 0, 0.02)), c, c + Vector((0.02, 0, 0.02)), b], [0.006] * 5, self.torso, res=2, ring=4)
        C.ico(gem, tuple(self.on_torso(0, z, 0.03)), (1, 0.6, 1.4), parent=self.torso, r=0.028, sub=1)

    def bandage(self):
        """Injured look: a head wrap with trailing ends, a cheek plaster and an arm wrap."""
        r, z, tilt = self.band
        C.lathe("bandage", [(r, 0.028), (r + 0.012, 0.0), (r, -0.028)], self.head, loc=(0, 0.02, z), rot=(tilt, 0, 0), seg=30, res=1)
        back = Vector((0.06, 0.02 + r * math.cos(math.radians(tilt)), z + r * math.sin(math.radians(-tilt))))
        for sd in (-1, 1):
            C.sweep("bandage", [back, back + Vector((sd * 0.05, 0.06, -0.05)), back + Vector((sd * 0.06, 0.08, -0.12))],
                    [(0.024, 0.008), (0.022, 0.008), (0.0, 0.0)], self.head, up=(0, 1, 0), ring=5, res=2)
        if self.bvh is not None:
            C.decal("bandage", self.bvh, [(-0.04, -0.02), (0.04, -0.02), (0.04, 0.02), (-0.04, 0.02)], HEAD_C, dirv(-33, -20), lift=0.007,
                    parent=self.head)
        arm, t = self.R["armL"], self.t
        for i in range(2):
            z0 = -0.07 * t - i * 0.032
            rr = self.arm_r + 0.026
            C.lathe("bandage", [(rr, z0 + 0.014), (rr + 0.006, z0), (rr, z0 - 0.014)], arm, seg=14, res=1, rot=(0, 10 * (-1) ** i, 0))

    # ------------------------------------------------------------ weapons
    def sword(self, hand, k=1.0, blade="metal", guard="trim", grip="leather"):
        w = C.pivot("weapon", (0, -0.02, 0.02), hand)
        C.cyl(grip, (0, 0.0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.02, depth=0.1, verts=8)
        C.sphere(guard, (0, 0.06, 0), (0.026, 0.026, 0.026), parent=w, seg=8, rings=6)
        C.sweep(guard, [(-0.08, -0.06, 0.012), (0, -0.055, 0), (0.08, -0.06, 0.012)], [(0.018, 0.014), (0.022, 0.016), (0.018, 0.014)], w,
                up=(0, -1, 0), ring=6, res=2)
        L = 0.46 * k
        ol = [(-0.028, 0.0), (0.028, 0.0), (0.026, L * 0.8), (0.0, L), (-0.026, L * 0.8)]
        C.flat(blade, ol, 0.014, w, loc=(0, -0.065, 0), rot=(90, -90, 0), rings=2)
        C.flat("white", [(-0.006, 0.0), (0.006, 0.0), (0.005, L * 0.78), (0.0, L * 0.9), (-0.005, L * 0.78)], 0.016, w, loc=(0, -0.066, 0),
               rot=(90, -90, 0), rings=1)

    def dagger(self, hand, k=1.0, blade="metal"):
        w = C.pivot("weapon", (0, -0.02, 0.0), hand)
        C.cyl("leather", (0, 0.0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.017, depth=0.07, verts=8)
        C.sweep("trim", [(-0.045, -0.04, 0.0), (0.045, -0.04, 0.0)], [(0.014, 0.01), (0.014, 0.01)], w, res=1, ring=6)
        L = 0.2 * k
        C.flat(blade, [(-0.02, 0.0), (0.022, 0.0), (0.018, L * 0.7), (0.0, L), (-0.016, L * 0.8)], 0.01, w, loc=(0, -0.045, 0),
               rot=(90, -90, 0), rings=2)

    def curved_blade(self, hand, k=1.0, blade="metal", guard="trim", back=0.1):
        """Cutlass / scimitar: a broadening curved flat blade."""
        w = C.pivot("weapon", (0, -0.02, 0.02), hand)
        C.cyl("leather", (0, 0.0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.02, depth=0.1, verts=8)
        C.torus(guard, (0, -0.04, 0.02), (1, 1, 1), (0, 90, 0), parent=w, R=0.045, r=0.01, seg=12, mseg=4)
        L = 0.46 * k
        ol = []
        for i in range(8):
            u = i / 7
            ol.append((0.02 + 0.018 * math.sin(u * math.pi * 0.8) + back * u * u, L * u))
        for i in range(7, -1, -1):
            u = i / 7
            if u > 0.9:
                continue
            ol.append((-0.022 + back * u * u * 1.15, L * u))
        C.flat(blade, ol, 0.012, w, loc=(0, -0.06, 0), rot=(90, -90, 0), rings=2)

    def round_shield(self, hand, face="wood", rim="metal", boss="trim", r=0.17, emblem=None):
        w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
        C.lathe(face, [(0.001, 0.03), (r * 0.5, 0.022), (r, 0.0), (r, -0.02), (0.001, -0.02)], w, rot=(90, 0, 0), seg=24, res=1)
        C.torus(rim, (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, R=r, r=0.02, seg=24, mseg=6)
        C.sphere(boss, (0, -0.035, 0), (0.05, 0.028, 0.05), parent=w, seg=12, rings=8)
        if emblem:
            C.flat(emblem, [(u * 0.2, v * 0.2 - 0.1) for (u, v) in MAPLE], 0.01, w, loc=(0, -0.03, -0.0), rot=(0, 0, 0), rings=2)

    def bow(self, hand, wood="wood", k=1.0, string="white", grip="leather"):
        w = C.pivot("weapon", (0.0, -0.03, 0.0), hand)
        pts = [(0, 0.02, 0.4 * k), (0, -0.06, 0.3 * k), (0, -0.13, 0.13 * k), (0, -0.14, 0.0), (0, -0.13, -0.13 * k), (0, -0.06, -0.3 * k),
               (0, 0.02, -0.4 * k)]
        C.sweep(wood, pts, [0.01, 0.017, 0.022, 0.026, 0.022, 0.017, 0.01], w, ring=8, res=3)
        C.sweep(grip, [(0, -0.14, 0.05), (0, -0.14, -0.05)], [0.03, 0.03], w, ring=8, res=1)
        C.sweep(string, [(0, 0.02, 0.39 * k), (0, 0.04, 0.0), (0, 0.02, -0.39 * k)], [0.005, 0.005, 0.005], w, ring=4, res=1)
        for z in (0.4, -0.4):
            C.sphere("trim", (0, 0.02, z * k), (0.018, 0.018, 0.018), parent=w, seg=8, rings=5)

    def quiver(self, slot="leather", fletch="white", tip=None):
        t = self.t
        yb = self.trad(0.3 * t)[1]
        fr = frame("quiver", (0.07, yb + 0.05, 0.3 * t), (-16, 22, 0), self.torso)
        C.lathe(slot, [(0.05, 0.2), (0.055, 0.1), (0.05, -0.16), (0.03, -0.18)], fr, seg=12, res=1, cap_bot=True)
        C.lathe(tip or "trim", [(0.056, 0.2), (0.058, 0.18)], fr, seg=12, res=1)
        for i, (dx, dy) in enumerate(((-0.02, 0.0), (0.02, 0.01), (0.0, -0.02))):
            C.cyl("wood", (dx, dy, 0.24), parent=fr, r=0.006, depth=0.1, verts=5)
            C.flat(fletch, [(-0.02, 0.0), (0.02, 0.0), (0.012, 0.06), (0.0, 0.07), (-0.012, 0.06)], 0.006, fr, loc=(dx, dy, 0.25),
                   rot=(0, 0, 30 * i), rings=1)

    def staff(self, hand, head="orb", wood="wood", gem="glow", k=1.0, trim="trim"):
        w = C.pivot("weapon", (0, 0, 0), hand)
        C.sweep(wood, [(0, 0, -0.42 * k), (0.005, 0, 0.1), (0, 0, 0.55 * k)], [0.02, 0.023, 0.022], w, ring=8, res=2)
        C.lathe(trim, [(0.028, 0.53 * k), (0.03, 0.51 * k), (0.028, 0.49 * k)], w, seg=10, res=1)
        if head == "orb":
            C.sweep(trim, [(0, 0, 0.54 * k), (-0.06, 0, 0.62 * k), (-0.05, 0, 0.72 * k), (0.0, 0, 0.77 * k), (0.05, 0, 0.72 * k),
                           (0.07, 0, 0.64 * k)], [0.014, 0.014, 0.013, 0.012, 0.01, 0.0], w, ring=6, res=3)
            C.ico(gem, (0, 0, 0.66 * k), (1, 1, 1.15), parent=w, r=0.052, sub=2)
        elif head == "crescent":
            C.sweep(trim, [(0, 0, 0.54 * k), (-0.07, 0, 0.6 * k), (-0.08, 0, 0.7 * k), (-0.03, 0, 0.78 * k)], [0.016, 0.02, 0.016, 0.0], w,
                    ring=6, res=3)
            C.ico(gem, (0.0, 0, 0.66 * k), (1, 1, 1.2), parent=w, r=0.045, sub=2)
        return w

    def lantern_staff(self, hand, k=1.0, wood="wood", metal="trim"):
        w = C.pivot("weapon", (0, 0, 0), hand)
        C.sweep(wood, [(0, 0, -0.42 * k), (0, 0, 0.6 * k), (0, -0.08, 0.72 * k), (0, -0.19, 0.7 * k)], [0.02, 0.022, 0.02, 0.016], w,
                ring=8, res=3)
        C.sweep(metal, [(0, -0.19, 0.7 * k), (0, -0.2, 0.64 * k)], [0.006, 0.006], w, ring=4, res=1)
        self.small_lantern(w, (0, -0.2, 0.54 * k), 1.35, metal=metal)
        return w

    def book(self, hand, cover="cloth2", pages="white", sigil="glow"):
        w = frame("book", (0.02, -0.07, 0.03), (0, 0, 22), hand)
        C.box(cover, (0, 0, 0), (0.06, 0.2, 0.25), parent=w, bevel=0.012)
        C.box(pages, (0.004, 0.006, 0), (0.05, 0.19, 0.23), parent=w)
        C.lathe(sigil, [(0.04, 0.004), (0.05, 0.0), (0.04, -0.004)], w, loc=(-0.032, -0.0, 0.0), rot=(0, 90, 0), seg=12, res=1)
        C.box("trim", (-0.032, 0, 0.1), (0.008, 0.2, 0.02), parent=w)
        C.box("trim", (-0.032, 0, -0.1), (0.008, 0.2, 0.02), parent=w)


# ======================================================================
# jellyfish, wings and other race features
# ======================================================================
def jellyfish(k, loc=(0.5, 0.1, 0.42), s=1.22):
    j = C.pivot("jelly", loc, k.neck)
    k.R["jelly"] = j
    k.R["jelly_base"] = loc
    C.lathe("glow", [(0.001, 0.13 * s), (0.06 * s, 0.125 * s), (0.105 * s, 0.095 * s), (0.13 * s, 0.045 * s), (0.138 * s, 0.0),
                     (0.128 * s, -0.018 * s)], j, seg=26, res=2, hem=0.022 * s, hem_n=9, thick=0.012, cap_top=False, arc=(0, 359.9))
    C.sphere("white", (0, 0, 0.055 * s), (0.065 * s, 0.065 * s, 0.045 * s), parent=j, seg=12, rings=8)
    C.sphere("glow", (-0.045 * s, -0.06 * s, 0.095 * s), (0.028 * s, 0.02 * s, 0.022 * s), parent=j, seg=8, rings=5)
    for i in range(8):
        a = math.radians(i * 45 + 10)
        x, y = math.cos(a) * 0.1 * s, math.sin(a) * 0.1 * s
        L = (0.32 + 0.1 * ((i * 37) % 3) / 2) * s
        pts = [(x, y, -0.01 * s)]
        for q in range(1, 6):
            u = q / 5
            pts.append((x * (1 - 0.3 * u) + 0.025 * s * math.sin(u * 7 + i), y * (1 - 0.3 * u) + 0.02 * s * math.cos(u * 6 + i), -L * u))
        C.sweep("glow", pts, [0.011 * s, 0.01 * s, 0.009 * s, 0.008 * s, 0.006 * s, 0.0], j, ring=5, res=2)
    for i in range(3):
        a = math.radians(i * 120 + 40)
        x, y = math.cos(a) * 0.03 * s, math.sin(a) * 0.03 * s
        pts = [(x, y, 0.0), (x * 1.5 + 0.02 * s, y * 1.5, -0.08 * s), (x * 1.2 - 0.02 * s, y * 1.2, -0.17 * s), (x * 1.4, y * 1.4, -0.24 * s)]
        C.sweep("white", pts, [(0.03 * s, 0.012 * s), (0.034 * s, 0.012 * s), (0.026 * s, 0.01 * s), (0.0, 0.0)], j, up=(0, -1, 0), ring=6,
                res=3)


def moth_wings(k, base="white", rim="feature", ring_slot="skin2", core="eyes", accent="feature", s=1.34, lanterns=False,
               spot_mid="feature"):
    t = k.t
    fore = [(0.0, 0.02), (0.05, 0.12), (0.13, 0.23), (0.24, 0.31), (0.34, 0.345), (0.41, 0.31), (0.43, 0.22), (0.39, 0.12), (0.31, 0.04),
            (0.19, -0.01), (0.07, -0.03)]
    hind = [(0.0, -0.01), (0.08, -0.03), (0.19, -0.08), (0.27, -0.17), (0.28, -0.28), (0.22, -0.37), (0.13, -0.39), (0.06, -0.3),
            (0.02, -0.16)]
    for sd, name in ((-1, "wingR"), (1, "wingL")):
        w = C.pivot(name, (sd * 0.035, k.trad(0.33 * t)[1] - 0.01, 0.34 * t), k.torso)
        k.R[name] = w
        fr = frame(name + "_f", (0, 0, 0), (-10, 0, sd * 30), w)
        for ol, spot, sr, cen in ((fore, (0.27, 0.2), 0.085, (0.1, 0.1)), (hind, (0.17, -0.22), 0.06, (0.08, -0.12))):
            pts = [(sd * u * s, v * s) for (u, v) in ol]
            cx, cy = sd * cen[0] * s, cen[1] * s
            big = [(cx + (u - cx) * 1.06, cy + (v - cy) * 1.06) for (u, v) in pts]
            C.flat(rim, big, 0.007, fr, bend=0.35, rings=3, center=(cx, cy))
            C.flat(base, pts, 0.013, fr, bend=0.35, rings=3, center=(cx, cy))
            sx, sy = sd * spot[0] * s, spot[1] * s
            yb = 0.35 * sx * sx
            for face in (-1, 1):
                y = yb + face * 0.0085
                C.flat(ring_slot, C.ellipse(16, sr * s, sr * 0.92 * s, sx, sy), 0.002, fr, loc=(0, y, 0), rings=1)
                C.flat(spot_mid, C.ellipse(14, sr * 0.62 * s, sr * 0.58 * s, sx, sy), 0.002, fr, loc=(0, y + face * 0.001, 0), rings=1)
                C.flat(core, C.ellipse(10, sr * 0.3 * s, sr * 0.3 * s, sx, sy), 0.002, fr, loc=(0, y + face * 0.002, 0), rings=1)
            # vein accents near the root
            for face in (-1, 1):
                C.flat(accent, C.ellipse(10, 0.05 * s, 0.022 * s, sd * 0.11 * s, (0.2 if spot[1] > 0 else -0.14) * s), 0.002, fr,
                       loc=(0, face * 0.0085, 0), rings=1)
        if lanterns:
            k.small_lantern(fr, (sd * 0.4 * s, 0.0, 0.2 * s), 0.85)
            C.sweep("trim", [(sd * 0.41 * s, 0, 0.31 * s), (sd * 0.4 * s, 0, 0.33 * s)], [0.005, 0.005], fr, res=1, ring=4)
            k.small_lantern(fr, (sd * 0.27 * s, 0.0, -0.44 * s), 0.8)
            C.sweep("trim", [(sd * 0.25 * s, 0, -0.36 * s), (sd * 0.27 * s, 0, -0.38 * s)], [0.005, 0.005], fr, res=1, ring=4)


def moth_antennae(k, stalk="leather", plume="feature", s=1.0, base_y=-0.06):
    for sd in (-1, 1):
        pts = [Vector((sd * 0.07, base_y, 0.54)), Vector((sd * 0.09, base_y - 0.05, 0.76 * s)), Vector((sd * 0.14, base_y - 0.06, 0.94 * s)),
               Vector((sd * 0.24, base_y - 0.03, 1.06 * s)), Vector((sd * 0.34, base_y + 0.01, 1.07 * s))]
        C.sweep(stalk, pts, [0.012, 0.011, 0.01, 0.008, 0.005], k.head, ring=6, res=3)
        # plume: a feathered comb hanging off the outer side of the upper stalk
        path = C.catmull([tuple(p) for p in pts[2:]], 5)
        n = len(path)
        for i in range(1, n):
            u = i / (n - 1)
            p = Vector(path[i])
            t = (Vector(path[i]) - Vector(path[i - 1])).normalized()
            out = Vector((sd, 0, 0))
            out = (out - t * out.dot(t)).normalized()
            ln = 0.11 * s * math.sin(math.pi * (0.15 + 0.8 * u)) ** 0.7
            tip = p + out * ln - t * ln * 0.35 + Vector((0, 0, -0.01))
            C.sweep(plume, [p, tip], [(0.028 * s, 0.008), (0.006, 0.004)], k.head, up=(0, -1, 0), ring=4, res=1)
        C.sphere(plume, tuple(pts[-1]), (0.018, 0.016, 0.018), parent=k.head, seg=8, rings=6)


def khepri_antennae(k, stalk="skin2", tip="feature", base=None, s=1.0):
    base = base or (0.08, -0.12, 0.5)
    bx, by, bz = base
    for sd in (-1, 1):
        pts = [(sd * bx, by, bz), (sd * (bx + 0.06), by + 0.02, bz + 0.18 * s), (sd * (bx + 0.15), by + 0.04, bz + 0.34 * s),
               (sd * (bx + 0.27), by + 0.0, bz + 0.43 * s), (sd * (bx + 0.35), by - 0.06, bz + 0.41 * s)]
        C.sweep(stalk, pts[:4], [0.015, 0.014, 0.013, 0.012], k.head, ring=6, res=3)
        C.sweep(tip, pts[2:], [0.016, 0.026, 0.0], k.head, ring=8, res=3)


def antlers(k, s=1.0, slot="wood", leaf_slot="feature"):
    head = k.head
    for sd in (-1, 1):
        a = Vector((sd * 0.12, 0.02, 0.5))
        main = [a, a + Vector((sd * 0.05, 0.02, 0.14 * s)), a + Vector((sd * 0.1, 0.06, 0.28 * s)), a + Vector((sd * 0.12, 0.12, 0.38 * s))]
        C.sweep(slot, main, [0.026, 0.022, 0.016, 0.0], head, ring=6, res=3)
        br = main[1] + Vector((sd * 0.01, 0.0, 0.03 * s))
        C.sweep(slot, [br, br + Vector((sd * 0.12, -0.04, 0.08 * s)), br + Vector((sd * 0.2, -0.04, 0.16 * s))], [0.016, 0.012, 0.0], head,
                ring=6, res=3)
        br2 = main[2]
        C.sweep(slot, [br2, br2 + Vector((-sd * 0.02, -0.07, 0.06 * s)), br2 + Vector((-sd * 0.01, -0.1, 0.12 * s))], [0.013, 0.01, 0.0],
                head, ring=6, res=2)
        k.leaf(leaf_slot, main[2] + Vector((sd * 0.01, 0, 0)), (sd * 0.6, -0.3, 0.7), 0.085, head, normal=(0, -1, 0), shape=OVAL)


def bark_lines(k, limbs=True):
    """Dark bark grooves down bare wooden limbs."""
    t = k.t
    if limbs:
        for leg in (k.R["legR"], k.R["legL"]):
            for a in (-40, 30, 170):
                d = Vector((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
                r = k.leg_r
                pts = [d * (r * 0.98) + Vector((0, -0.006, -0.02)), d * (r * 0.8) + Vector((0, -0.012, -0.17 * t)), d * (r * 0.63) + Vector((0, 0, -0.3 * t))]
                C.sweep("skin2", pts, [(0.008, 0.004)] * 3, leg, up=tuple(d), ring=4, res=2)
        for arm in (k.R["armR"], k.R["armL"]):
            for a in (-30, 150):
                d = Vector((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
                r = k.arm_r
                pts = [d * (r * 1.0) + Vector((0, 0, -0.01)), d * (r * 0.88) + Vector((0, 0.008, -0.13 * t)), d * (r * 0.74) + Vector((0, 0, -0.24 * t))]
                C.sweep("skin2", pts, [(0.007, 0.004)] * 3, arm, up=tuple(d), ring=4, res=2)


# ======================================================================
# race weapons and gear
# ======================================================================
def wheel_shield(k, hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.torus("trim", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, R=0.15, r=0.02, seg=28, mseg=6)
    C.torus("trim", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, R=0.075, r=0.014, seg=20, mseg=5)
    for i in range(8):
        a = i * 45
        C.cyl("wood", (0, 0, 0), (1, 1, 1), (0, a, 0), parent=w, r=0.011, depth=0.3, verts=6)
        x, z = math.sin(math.radians(a)) * 0.2, math.cos(math.radians(a)) * 0.2
        C.sphere("trim", (x, 0, z), (0.024, 0.024, 0.024), parent=w, seg=8, rings=6)
    C.cyl("trim", (0, 0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.04, depth=0.05, verts=12)
    C.sphere("glow", (0, -0.03, 0), (0.024, 0.018, 0.024), parent=w, seg=8, rings=6)
    C.sweep("trim", [(0, -0.02, -0.04), (0, -0.03, -0.1)], [0.004, 0.004], w, res=1, ring=4)
    C.ico("glow", (0, -0.03, -0.12), (1, 1, 1.4), parent=w, r=0.02, sub=1)


def harpoon(k, hand, tip="metal"):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.sweep("wood", [(0, 0, -0.46), (0, 0, 0.66)], [0.019, 0.019], w, res=1, ring=8)
    for z in (0.22, 0.6):
        C.lathe("trim", [(0.025, z + 0.02), (0.028, z), (0.025, z - 0.02)], w, seg=10, res=1)
    C.flat(tip, [(-0.045, 0.0), (0.0, -0.02), (0.045, 0.0), (0.035, 0.09), (0.0, 0.2), (-0.035, 0.09)], 0.014, w, loc=(0, 0, 0.66),
           rot=(0, 0, 90), rings=2, center=(0, 0.06))
    for sd in (-1, 1):
        C.sweep(tip, [(0, sd * 0.03, 0.7), (0, sd * 0.065, 0.66), (0, sd * 0.07, 0.62)], [0.01, 0.008, 0.0], w, res=2, ring=5)
    C.sweep("cape", [(0, 0.02, 0.6), (0.02, 0.05, 0.52), (0.0, 0.05, 0.44)], [(0.02, 0.006)] * 3, w, up=(1, 0, 0), res=2, ring=5)


def jelly_staff(k, hand):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.sweep("wood", [(0, 0, -0.42), (0.02, 0, -0.1), (-0.01, 0, 0.25), (0.015, 0, 0.5)], [0.022, 0.024, 0.022, 0.02], w, ring=8, res=3)
    C.torus("wood", (0.015, 0, 0.66), (1, 1, 1), (90, 0, 0), parent=w, R=0.14, r=0.02, seg=24, mseg=6)
    C.lathe("glow", [(0.001, 0.07), (0.05, 0.065), (0.08, 0.03), (0.085, 0.0)], w, loc=(0.015, 0, 0.66), seg=18, res=2, cap_top=True,
            hem=0.012, hem_n=7)
    for x in (-0.04, 0.0, 0.04):
        C.sweep("glow", [(0.015 + x, 0, 0.66), (0.015 + x * 1.2 + 0.01, 0, 0.6), (0.015 + x, 0, 0.55)], [0.009, 0.007, 0.0], w, ring=5, res=2)
    for x, L in ((-0.12, 0.2), (0.14, 0.24), (0.0, 0.12)):
        z0 = 0.66 - math.sqrt(max(0.0, 0.14 ** 2 - x * x))
        C.sweep("cape", [(0.015 + x, 0, z0), (0.015 + x + 0.015, -0.01, z0 - L * 0.5), (0.015 + x, 0, z0 - L)],
                [(0.018, 0.006), (0.016, 0.005), (0.0, 0.0)], w, up=(0, -1, 0), ring=5, res=2)
    for x in (-0.09, 0.11):
        C.sweep("trim", [(0.015 + x, 0, 0.56), (0.015 + x, 0, 0.47)], [0.004, 0.004], w, res=1, ring=4)
        C.ico("trim", (0.015 + x, 0, 0.45), (1, 1, 1.3), parent=w, r=0.016, sub=1)


def moth_shield(k, hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.lathe("white", [(0.001, 0.025), (0.1, 0.018), (0.16, 0.0), (0.16, -0.02), (0.001, -0.02)], w, rot=(90, 0, 0), seg=24, res=1,
            shape=lambda th, u: 1.0 + 0.18 * math.cos(th) ** 2)
    C.torus("feature", (0, 0, 0), (1, 1, 1.18), (90, 0, 0), parent=w, R=0.16, r=0.018, seg=24, mseg=6)
    C.lathe("skin2", [(0.001, 0.004), (0.08, 0.0), (0.08, -0.004)], w, loc=(0, -0.03, 0.01), rot=(90, 0, 0), seg=18, res=1, cap_bot=True)
    C.lathe("feature", [(0.001, 0.004), (0.05, 0.0), (0.05, -0.004)], w, loc=(0, -0.035, 0.01), rot=(90, 0, 0), seg=16, res=1)
    C.lathe("eyes", [(0.001, 0.004), (0.024, 0.0), (0.024, -0.004)], w, loc=(0, -0.04, 0.01), rot=(90, 0, 0), seg=12, res=1)


def axe(k, hand):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.sweep("wood", [(0, 0.08, 0.0), (0, -0.2, 0.01), (0, -0.44, 0.0)], [0.022, 0.024, 0.02], w, ring=8, res=2)
    C.lathe("leather", [(0.028, 0.03), (0.03, -0.03)], w, loc=(0, 0.02, 0), rot=(90, 0, 0), seg=10, res=1)
    ol = [(-0.02, -0.03), (0.06, -0.03), (0.1, -0.1), (0.14, -0.06), (0.15, 0.04), (0.13, 0.13), (0.09, 0.17), (0.06, 0.07), (-0.02, 0.05)]
    C.flat("metal", ol, 0.014, w, loc=(0, -0.38, 0.0), rot=(0, 0, -90), rings=2, center=(0.07, 0.03))
    C.flat("white", [(0.13, -0.05), (0.145, 0.04), (0.125, 0.12), (0.115, 0.1), (0.125, 0.03), (0.115, -0.03)], 0.016, w,
           loc=(0, -0.38, 0.0), rot=(0, 0, -90), rings=1)


def leaf_shield(k, hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.lathe("wood", [(0.001, 0.03), (0.1, 0.022), (0.17, 0.0), (0.17, -0.02), (0.001, -0.02)], w, rot=(90, 0, 0), seg=22, res=1,
            shape=lambda th, u: 1.0 + 0.12 * math.cos(th) ** 2)
    C.torus("skin2", (0, 0, 0), (1, 1, 1.12), (90, 0, 0), parent=w, R=0.17, r=0.018, seg=22, mseg=5)
    k.leaf("feature", (0, -0.035, -0.12), (0, 0, 1), 0.24, w, normal=(0, -1, 0), bend=-0.1)
    C.sweep("skin2", [(0, -0.045, -0.1), (0, -0.045, 0.08)], [0.007, 0.004], w, res=1, ring=4)


def sickle(k, hand):
    w = C.pivot("weapon", (0, -0.02, 0.02), hand)
    C.sweep("wood", [(0, 0.05, 0), (0, -0.12, 0.0)], [0.02, 0.022], w, res=1, ring=8)
    C.lathe("leather", [(0.026, 0.02), (0.026, -0.02)], w, loc=(0, 0.0, 0), rot=(90, 0, 0), seg=8, res=1)
    C.sweep("metal", [(0, -0.12, 0), (0, -0.22, 0.06), (0, -0.25, 0.16), (0, -0.2, 0.26), (0, -0.1, 0.3)],
            [(0.012, 0.03), (0.012, 0.036), (0.011, 0.03), (0.009, 0.02), (0.0, 0.0)], w, up=(-1, 0, 0), ring=6, res=3)


def basket(k, hand):
    w = C.pivot("basket", (0.03, -0.02, -0.1), hand)
    C.lathe("wood", [(0.1, 0.05), (0.105, 0.02), (0.09, -0.04), (0.06, -0.06)], w, seg=16, res=2, cap_bot=True, folds=16, fold_amp=0.05)
    C.torus("wood", (0, 0, 0.05), (1, 1, 1), (0, 0, 0), parent=w, R=0.1, r=0.012, seg=16, mseg=4)
    C.torus("wood", (0, 0, 0.06), (1, 1, 1), (0, 90, 0), parent=w, R=0.1, r=0.01, seg=16, mseg=4)
    for (x, y, c) in ((-0.04, 0.0, "cloth2"), (0.04, 0.02, "feature"), (0.0, -0.04, "white"), (0.02, 0.05, "glow")):
        C.sphere(c, (x, y, 0.06), (0.036, 0.036, 0.032), parent=w, seg=8, rings=6)


def gnarled_staff(k, hand, s=1.0):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.sweep("wood", [(0, 0, -0.42 * s), (0.03, -0.02, 0.0), (-0.02, 0.0, 0.3 * s), (0.05, 0.0, 0.56 * s), (0.13, 0.0, 0.7 * s)],
            [0.026, 0.03, 0.03, 0.028, 0.012], w, ring=8, res=3)
    C.sweep("wood", [(0.04, 0.0, 0.52 * s), (-0.07, 0.0, 0.66 * s), (-0.05, 0.0, 0.8 * s), (0.0, 0, 0.84 * s)], [0.022, 0.018, 0.012, 0.0],
            w, ring=8, res=3)
    C.sweep("wood", [(0.1, 0.0, 0.66 * s), (0.08, 0.0, 0.8 * s), (0.02, 0, 0.84 * s)], [0.014, 0.01, 0.0], w, ring=6, res=2)
    C.ico("glow", (0.02, 0.0, 0.7 * s), (0.9, 0.9, 1.4), parent=w, r=0.06, sub=1)
    for x, z, d in ((0.13, 0.7, (1, -0.2, 0.3)), (-0.07, 0.72, (-1, -0.3, 0.6)), (0.03, 0.36, (1, -0.3, -0.2)), (-0.02, 0.2, (-1, -0.2, -0.3))):
        k.leaf("feature" if z > 0.5 else "cloth1", (x, 0, z * s), d, 0.09, w, normal=(0, -1, 0), shape=OVAL)


def crook(k, hand):
    w = C.pivot("weapon", (0, 0, 0), hand)
    C.sweep("wood", [(0, 0, -0.42), (0.004, 0, 0.1), (0, 0, 0.6)], [0.022, 0.024, 0.022], w, ring=8, res=2)
    C.sweep("wood", [(0, 0, 0.6), (0.01, 0, 0.72), (0.08, 0, 0.8), (0.17, 0, 0.76), (0.18, 0, 0.66), (0.12, 0, 0.62)],
            [0.022, 0.022, 0.022, 0.02, 0.018, 0.014], w, ring=8, res=3)
    for z in (0.56, 0.5):
        C.lathe("trim", [(0.027, z + 0.012), (0.03, z), (0.027, z - 0.012)], w, seg=10, res=1)
    C.sweep("trim", [(0.12, 0, 0.61), (0.12, 0, 0.5)], [0.004, 0.004], w, res=1, ring=4)
    C.ico("glow", (0.12, 0, 0.47), (1, 1, 1.5), parent=w, r=0.026, sub=1)
    C.sweep("trim", [(0.12, 0, 0.44), (0.12, 0, 0.4)], [0.004, 0.004], w, res=1, ring=4)
    C.ico("feature", (0.12, 0, 0.385), (1, 1, 1.2), parent=w, r=0.014, sub=1)


def glass_blade(k, hand, k2=1.0):
    w = C.pivot("weapon", (0, -0.02, 0.0), hand)
    C.cyl("leather", (0, 0.0, 0), (1, 1, 1), (90, 0, 0), parent=w, r=0.018, depth=0.08, verts=8)
    C.sweep("trim", [(0, -0.04, -0.03), (0, -0.045, 0.0), (0, -0.04, 0.03)], [0.012, 0.014, 0.012], w, res=2, ring=6)
    L = 0.36 * k2
    ol = []
    for i in range(8):
        u = i / 7
        ol.append((0.022 + 0.012 * math.sin(u * math.pi) + 0.1 * u * u, L * u))
    for i in range(6, -1, -1):
        u = i / 7
        ol.append((-0.02 + 0.12 * u * u, L * u))
    C.flat("glow", ol, 0.012, w, loc=(0, -0.05, 0), rot=(90, -90, 0), rings=2)


def buckler(k, hand):
    w = C.pivot("shield", (0.05, -0.1, 0.1), hand)
    C.lathe("trim", [(0.001, 0.03), (0.1, 0.02), (0.15, 0.0), (0.15, -0.02), (0.001, -0.02)], w, rot=(90, 0, 0), seg=22, res=1)
    C.lathe("hair", [(0.001, 0.036), (0.08, 0.026), (0.115, 0.012), (0.12, 0.0)], w, rot=(90, 0, 0), seg=20, res=1)
    for i in range(6):
        a = math.radians(i * 60)
        C.sphere("trim", (math.cos(a) * 0.132, -0.02, math.sin(a) * 0.132), (0.014, 0.01, 0.014), parent=w, seg=6, rings=4)
    C.ico("glow", (0, -0.045, 0), (1, 0.6, 1), parent=w, r=0.04, sub=2)


# ======================================================================
# faces and hair
# ======================================================================
def anime_face(k, skin="skin", brow="hair", blush=True, mouth=True, **eye):
    k.head_base(skin)
    k.eyes(**eye)
    k.brows(brow)
    if mouth:
        k.mouth()
    if blush:
        k.blush()


def human_hair(k, hat=False):
    st = k.g + k.style
    k.hair_cap("hair")
    if st == "ma":          # spiky
        k.bangs(n=5, spread=120, zmin=0.37, w=0.085, th=0.034, droop=0.9, out=0.45, longer_sides=0.05)
        k.side_locks(zmin=0.2, w=0.065, az=80, el=28)
        if hat:
            k.back_hair(zmin=0.14, n=6, w=0.08, el=(10, 30))
        else:
            k.spikes(n=11, length=0.19, w=0.09, th=0.05, out=1.3, droop=0.3)
            k.ahoge()
    elif st == "mb":        # swept fringe and a short nape tail
        k.bangs(n=4, spread=100, zmin=0.33, w=0.09, droop=1.3, longer_sides=0.08, side_sweep=0.4)
        k.side_locks(zmin=0.15, w=0.07, az=78, el=26)
        k.back_hair(zmin=0.12, n=7, w=0.09, el=(15, 50))
        if not hat:
            k.lock("hair", 180, 12, w=0.06, th=0.03, zmin=-0.14, length=0.4, droop=1.6, out=0.6)
            C.lathe("cloth2", [(0.035, 0.015), (0.038, 0.0), (0.035, -0.015)], k.head, loc=(0, 0.3, 0.2), rot=(-60, 0, 0), seg=10, res=1)
    elif st == "fa":        # high ponytail
        k.bangs(n=5, spread=115, zmin=0.36, w=0.078, droop=1.4, longer_sides=0.07)
        k.side_locks(zmin=0.06, w=0.06, az=78, el=24)
        k.back_hair(zmin=0.22, n=6, w=0.085, el=(20, 45), spread=130)
        if not hat:
            k.ponytail(az=180, el=50, length=0.5)
    else:                   # long straight hair
        k.bangs(n=6, spread=120, zmin=0.35, w=0.072, droop=1.5, longer_sides=0.08)
        k.side_locks(zmin=-0.14, w=0.07, az=76, el=24, n=2)
        k.back_hair(zmin=-0.34, n=9, w=0.095, el=(15, 55), spread=160)


def witch_hat(k, slot="cloth2", band="trim", gem="glow", tilt=-8):
    hat = frame("hat", (0, 0.02, 0.5), (tilt, 0, 6), k.head)
    C.lathe(slot, [(0.2, 0.02), (0.33, 0.006), (0.44, -0.02), (0.47, -0.05)], hat, seg=34, res=2, thick=0.014, hem=0.012, hem_n=6)
    C.sweep(slot, [(0, 0, 0.0), (0, 0.01, 0.18), (0, 0.06, 0.33), (0, 0.15, 0.43), (0, 0.24, 0.42)], [0.235, 0.17, 0.1, 0.045, 0.0], hat,
            ring=18, res=3, up=(0, -1, 0))
    C.lathe(band, [(0.232, 0.08), (0.24, 0.05), (0.232, 0.02)], hat, seg=24, res=1)
    C.ico(gem, (0, -0.24, 0.05), (1, 0.6, 1), parent=hat, r=0.03, sub=1)


def captain_cap(k):
    cap = frame("cap", (0, 0.03, 0.5), (-10, 0, 0), k.head)
    C.lathe("cloth1", [(0.001, 0.13), (0.2, 0.125), (0.31, 0.09), (0.335, 0.045), (0.31, 0.0), (0.275, -0.02)], cap, seg=28, res=2,
            cap_top=True)
    C.lathe("trim", [(0.28, 0.005), (0.285, -0.015), (0.28, -0.035)], cap, seg=28, res=1)
    C.flat("leather", [(-0.2, 0.0), (0.2, 0.0), (0.16, 0.08), (0.0, 0.11), (-0.16, 0.08)], 0.016, cap, loc=(0, -0.22, -0.03),
           rot=(78, 0, 0), rings=2)
    C.ico("trim", (0, -0.29, 0.03), (1, 0.6, 1), parent=cap, r=0.03, sub=1)


def bicorne(k):
    hat = frame("hat", (0, 0.03, 0.47), (-12, 0, 0), k.head)
    hat.scale = (0.82, 0.82, 0.82)
    C.lathe("cloth1", [(0.001, 0.1), (0.2, 0.09), (0.28, 0.04), (0.28, -0.02)], hat, seg=24, res=2, cap_top=True)
    for sd in (-1, 1):
        ol = [(-0.44, 0.0), (0.44, 0.0), (0.36, 0.1), (0.2, 0.2), (0.0, 0.25), (-0.2, 0.2), (-0.36, 0.1)]
        C.flat("cloth1", ol, 0.016, hat, loc=(0, sd * 0.2, -0.02), rot=(sd * 18, 0, 0), rings=2, bend=0.25, center=(0, 0.1))
        C.sweep("trim", [(-0.44, sd * 0.2, -0.02), (-0.2, sd * 0.2 + sd * 0.06, 0.17), (0.0, sd * 0.2 + sd * 0.08, 0.22),
                         (0.2, sd * 0.2 + sd * 0.06, 0.17), (0.44, sd * 0.2, -0.02)], [0.012] * 5, hat, ring=5, res=3)
    C.ico("trim", (0.0, -0.3, 0.12), (1, 0.5, 1), parent=hat, r=0.034, sub=1)
    k.leaf("white", (0.12, 0.1, 0.1), (0.4, 0.5, 1), 0.2, hat, normal=(1, 0, 0), shape=oval_outline(0.22), bend=0.2)


# ======================================================================
# humans
# ======================================================================
def human(k):
    f, look, t, R = k.f, k.look, k.t, k.R
    if look == "warrior":
        k.setup_body(1.0 if f else 1.06)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.pelvis("cloth2")
        k.legs("pants", "cloth2", feet="tall_boots" if f else "boots")
        k.torso_piece("metal", 0.13 * t, 0.42 * t, infl=0.018)
        k.chest("metal", 0.018)
        k.torso_piece("trim", 0.32 * t, 0.34 * t, infl=0.023)
        k.belt(0.12 * t, "leather", "trim", infl=0.024)
        k.skirt("cloth1", 0.1 * t, 0.22 if f else 0.15, flare=0.09 if f else 0.04, folds=10, fold_amp=0.08)
        for a in (((-32, 32), (148, 212)) if not f else ((-55, -8), (8, 55), (140, 220))):
            k.skirt("metal", 0.11 * t, 0.13, flare=0.04, folds=0, arc=a, thick=0.012, infl=0.028)
        k.arms("long", "cloth1", cuff="leather", bracer="metal")
        k.pauldron("metal", trim="trim")
        k.hands("leather")
        k.cape("cape", length=0.5 if not f else 0.44, width=140 if not f else 120, collar="cape")
        anime_face(k)
        k.ears()
        human_hair(k)
        k.sword(R["handR"])
        k.round_shield(R["handL"], face="cloth2", rim="metal", boss="trim")
    elif look == "rogue":
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.torso_piece("leather", 0.03 * t, 0.34 * t, infl=0.013)
        k.chest("leather", 0.013)
        k.pelvis("cloth2")
        if f:
            k.legs("tights", "cloth2", feet="tall_boots")
            k.skirt("leather", 0.08 * t, 0.12, flare=0.05, folds=0, arc=(30, 330), thick=0.012, hem=0.03, hem_n=5)
        else:
            k.legs("pants", "cloth2", feet="boots", wrap="leather")
            k.skirt("leather", 0.08 * t, 0.16, flare=0.05, folds=0, arc=(35, 325), thick=0.012, hem=0.035, hem_n=5)
        k.belt(0.08 * t, "leather", "trim", infl=0.02)
        k.strap("leather", -30, 0.42 * t, 45, 0.04 * t)
        k.hood("cape", up=False, drape=False)
        k.arms("long", "cloth1", cuff="leather", bracer="leather")
        k.hands("leather")
        k.pouch(60, 0.07 * t)
        anime_face(k)
        k.ears()
        human_hair(k)
        k.dagger(R["handR"])
        k.dagger(R["handL"])
    elif look == "ranger":
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.pelvis("cloth2")
        k.legs("tights" if f else "pants", "cloth2", feet="tall_boots")
        k.skirt("cloth1", 0.1 * t, 0.2 if f else 0.16, flare=0.07, folds=8, fold_amp=0.07, hem=0.02, hem_n=4)
        k.belt(0.1 * t, "leather", "trim", infl=0.016)
        k.torso_piece("leather", 0.2 * t, 0.36 * t, infl=0.012)
        k.strap("leather", -38, 0.43 * t, 40, 0.1 * t)
        k.arms("long", "cloth1", cuff="leather", bracer="leather")
        k.hands("leather")
        k.cape("cape", length=0.46, width=150, flare=0.1, hem=0.03, hem_n=5)
        k.hood("cape", up=False, drape=False)
        k.quiver()
        anime_face(k)
        k.ears()
        human_hair(k)
        k.bow(R["handL"])
    elif look == "mystic":
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.legs("bare", "cloth1", feet="shoes")
        k.skirt("cloth1", 0.1 * t, 0.39 * t + 0.06, flare=0.1, folds=11, fold_amp=0.08, infl=0.006)
        k.front_panel("cloth2", -0.3 * t, 0.36 * t, w=0.05, drop=0.08)
        k.front_panel("trim", -0.3 * t, 0.36 * t, w=0.012, drop=0.085)
        k.belt(0.1 * t, "cloth2", "trim", infl=0.012, h=0.04)
        k.mantle("cloth2", length=0.13, flare=0.05, hem=0.035, hem_n=8)
        k.arms("wide", "cloth1", cuff="trim")
        k.hands("skin")
        k.amulet("glow", "trim")
        anime_face(k)
        k.ears()
        human_hair(k, hat=True)
        witch_hat(k)
        k.staff(R["handR"], head="crescent")
    else:   # villager
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.legs("bare", feet="shoes")
        k.skirt("cloth2", 0.1 * t, 0.3, flare=0.08, folds=9, fold_amp=0.08)
        k.front_panel("white", -0.2, 0.3 * t, w=0.1, drop=0.05)
        k.belt(0.1 * t, "white", None, infl=0.012, h=0.03)
        k.arms("puffy", "cloth1", cuff="white")
        k.hands()
        anime_face(k)
        k.ears()
        human_hair(k)
        C.lathe("cloth2", [(0.2, 0.3, 0.6), (0.3, 0.3, 0.48), (0.325, 0.33, 0.36), (0.31, 0.33, 0.28)], k.head, loc=(0, 0.05, 0), seg=24,
                res=2, arc=(60, 300), thick=0.012)


# ======================================================================
# Tidefolk
# ======================================================================
def tidefolk(k):
    f, look, t, R = k.f, k.look, k.t, k.R
    eye = dict(iris=("eyes", 0.03), lit=("eyes", 0.7))
    if look == "warrior" and not f:          # the old captain (concept)
        k.setup_body(1.16)
        k.neck_part()
        k.torso_piece("cloth2", 0.1 * t, 0.44 * t)
        k.torso_piece("cloth1", -0.04, 0.43 * t, infl=0.012, arc=(22, 338), thick=0.014)
        k.pelvis("cloth1")
        k.legs("breeches", "cloth1", feet="webbed", cuff="leather")
        k.skirt("cloth1", 0.07 * t, 0.3, flare=0.1, folds=7, fold_amp=0.09, arc=(24, 336), infl=0.02)
        rx, ry = k.trad(0.07 * t, 0.02)
        zh = 0.07 * t - 0.3
        C.lathe("cloth2", [(rx + 0.085, ry + 0.075, zh + 0.05), (rx + 0.1, ry + 0.088, zh + 0.01), (rx + 0.1, ry + 0.088, zh - 0.005)],
                k.torso, seg=40, res=1, arc=(24, 336), thick=0.03)
        for sd in (-1, 1):
            pts = [k.on_torso(sd * 22, 0.3 * t, 0.03)] + [
                Vector((math.sin(math.radians(sd * 24)) * (rx + 0.1 * u), -math.cos(math.radians(sd * 24)) * (ry + 0.088 * u) - 0.01,
                        0.07 * t - 0.3 * u)) for u in (0.05, 0.4, 0.75, 1.0)]
            C.sweep("cloth2", pts, [(0.03, 0.02)] * len(pts), k.torso, up=(0, -1, 0), ring=6, res=2)
        k.lapels("cloth2", w=0.06, open_=0.05)
        C.lathe("cloth2", [(0.1, 0.09, 0.48 * t), (0.19, 0.16, 0.45 * t), (0.23, 0.19, 0.41 * t), (0.2, 0.17, 0.37 * t)], k.torso, seg=28,
                res=2, folds=9, fold_amp=0.07)
        k.belt(0.1 * t, "leather", "trim", infl=0.03, h=0.048, round_buckle=True)
        k.strap("leather", 35, 0.42 * t, -45, 0.03 * t)
        C.box("leather", tuple(k.on_torso(-70, 0.02 * t, 0.07)), (0.08, 0.14, 0.13), rot=(0, 0, -20), parent=k.torso, bevel=0.025)
        k.arms("long", "cloth1", cuff="cloth2")
        k.hands("skin")
        k.head_base("skin")
        k.eyes(size=0.9, tall=0.82, **eye)
        k.brows("white", thick=0.03, el=13)
        k.hair_cap("hair", r=(0.3, 0.296, 0.28))
        k.side_locks("hair", zmin=0.2, w=0.06, az=80, el=20)
        for az in (-70, -52, -34, -16, 0, 16, 34, 52, 70):
            k.lock("white", az, -30 + abs(az) * 0.25, w=0.07, th=0.045, zmin=-0.06 + abs(az) * 0.0012, length=0.4, droop=1.8, out=0.8,
                   rs=0.25, lift=0.035, ring=6)
        for sd in (-1, 1):
            C.sweep("white", [k.on_head(sd * 4, -26, 0.02), k.on_head(sd * 22, -30, 0.035), k.on_head(sd * 34, -40, 0.03)],
                    [(0.035, 0.022), (0.03, 0.02), (0.0, 0.0)], k.head, up=(0, -1, 0), ring=6, res=2)
        captain_cap(k)
        k.ears("fin", "feature", k=1.1)
        k.curved_blade(R["handR"], back=0.08)
        wheel_shield(k, R["handL"])
    elif look == "warrior":                   # the captain's daughter
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.torso_piece("cloth1", 0.0, 0.43 * t, infl=0.012, arc=(26, 334), thick=0.012)
        k.pelvis("cloth1")
        k.legs("breeches", "cloth1", feet="webbed", cuff="trim")
        k.skirt("cloth1", 0.06 * t, 0.3, flare=0.12, folds=8, fold_amp=0.1, arc=(70, 290), infl=0.02)
        k.lapels("cloth2", w=0.045, open_=0.03)
        for z in (0.3, 0.22, 0.14):
            for sd in (-1, 1):
                C.sphere("trim", tuple(k.on_torso(sd * 30, z * t, 0.02)), (0.014, 0.01, 0.014), parent=k.torso, seg=6, rings=4)
        k.belt(0.08 * t, "leather", "trim", infl=0.025, h=0.04)
        C.lathe("cloth2", [(0.09, 0.085, 0.475 * t), (0.15, 0.13, 0.44 * t), (0.17, 0.145, 0.41 * t)], k.torso, seg=24, res=2, folds=8,
                fold_amp=0.12)
        k.arms("long", "cloth1", cuff="cloth2")
        k.pauldron("trim", layers=1, k=0.9)
        k.hands("skin")
        for leg in (R["legR"], R["legL"]):
            C.lathe("trim", [(k.leg_r * 0.62, -0.33 * t), (k.leg_r * 0.66, -0.345 * t)], leg, seg=12, res=1)
        anime_face(k, blush=False, **eye)
        k.hair_cap("hair")
        k.bangs("hair", n=5, spread=110, zmin=0.35, w=0.08, droop=1.3, longer_sides=0.08, side_sweep=0.25)
        k.side_locks("hair", zmin=0.04, w=0.065, az=76, el=24, wave=0.1)
        k.back_hair("hair", zmin=0.12, n=6, w=0.09, el=(15, 45), spread=120)
        k.braid("hair", (0.2, 0.2, 0.06), (0.24, 0.0, -0.3), r=0.05, n=8, tie="trim")
        bicorne(k)
        k.ears("fin", "feature")
        k.earrings()
        k.curved_blade(R["handR"], back=0.08)
        wheel_shield(k, R["handL"])
    elif look == "rogue":                     # corsair (concept: feminine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("skin", -0.03, 0.44 * t)
        if f:
            k.torso_piece("cloth1", 0.22 * t, 0.36 * t, infl=0.008)
            k.chest("cloth1", 0.008)
            k.strap("leather", -40, 0.42 * t, 40, 0.18 * t, r=0.011)
            k.strap("leather", 40, 0.42 * t, -40, 0.18 * t, r=0.011)
        else:
            k.torso_piece("cloth1", 0.02 * t, 0.43 * t, infl=0.012, arc=(28, 332), thick=0.012)
            k.strap("leather", 40, 0.42 * t, -40, 0.06 * t, r=0.013)
        k.pelvis("cloth1")
        rx, ry = k.trad(0.05 * t, 0.016)
        C.lathe("cloth2", [(rx, ry, 0.1 * t), (rx + 0.008, ry + 0.008, 0.05 * t), (rx, ry, 0.0)], k.torso, seg=28, res=1, folds=6,
                fold_amp=0.06)
        k.front_panel("cloth2", -0.3 if f else -0.2, 0.04 * t, w=0.05, drop=0.05, taper=0.8)
        C.sweep("cloth2", [k.on_torso(-60, 0.05 * t, 0.03), k.on_torso(-75, -0.06, 0.05), k.on_torso(-70, -0.16, 0.06)],
                [(0.03, 0.008), (0.028, 0.008), (0.0, 0.0)], k.torso, up=(-1, 0, 0), ring=5, res=2)
        if f:
            k.legs("bare", feet="webbed")
            k.skirt("cloth1", 0.02 * t, 0.2, flare=0.08, folds=6, fold_amp=0.1, hem=0.08, hem_n=5, arc=(10, 350), thick=0.01)
        else:
            k.legs("baggy", "cloth1", feet="webbed")
        for leg in (R["legR"], R["legL"]):
            C.lathe("trim", [(k.leg_r * 0.62, -0.33 * t), (k.leg_r * 0.66, -0.345 * t)], leg, seg=12, res=1)
        k.arms("bare")
        for arm in (R["armR"], R["armL"]):
            C.lathe("trim", [(k.arm_r * 0.76, -0.22 * t), (k.arm_r * 0.8, -0.235 * t)], arm, seg=12, res=1)
        k.hands("skin")
        anime_face(k, blush=False, **eye)
        k.hair_cap("hair")
        if f:
            k.bangs("hair", n=5, spread=110, zmin=0.35, w=0.08, droop=1.4, longer_sides=0.09)
            k.side_locks("hair", zmin=-0.2, w=0.075, az=76, el=24, n=2, wave=0.12)
            k.back_hair("hair", zmin=-0.42, n=10, w=0.1, el=(15, 60), spread=170, wave=0.12)
            C.torus("hair", (0, 0.04, 0.64), (1, 1, 1), (90, 0, 0), parent=k.head, R=0.07, r=0.022, seg=16, mseg=6)
        else:
            k.bangs("hair", n=5, spread=115, zmin=0.36, w=0.085, droop=1.1, out=0.35, longer_sides=0.06)
            k.side_locks("hair", zmin=0.1, w=0.07, az=78, el=24, wave=0.1)
            k.back_hair("hair", zmin=0.02, n=7, w=0.09, el=(15, 50), wave=0.1)
            C.lathe("cloth2", [(0.3, 0.3, 0.46), (0.315, 0.315, 0.42), (0.31, 0.31, 0.38)], k.head, loc=(0, 0.03, 0.0), rot=(-14, 0, 0), seg=28,
                    res=1)
            for sd in (-1, 1):
                C.sweep("cloth2", [(sd * 0.03, 0.33, 0.46), (sd * 0.07, 0.4, 0.36), (sd * 0.1, 0.42, 0.26)],
                        [(0.035, 0.01), (0.03, 0.01), (0.0, 0.0)], k.head, up=(0, 1, 0), ring=5, res=2)
        k.ears("fin", "feature")
        k.earrings()
        k.curved_blade(R["handR"], back=0.1, k=0.95)
        k.dagger(R["handL"])
    elif look in ("ranger", "tidecaller"):    # spear fighter (concept: masculine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.torso_piece("cloth2", 0.06 * t, 0.4 * t, infl=0.012, arc=(24, 336), thick=0.012)
        k.pelvis("cloth2")
        if f:
            k.legs("bare", feet="webbed", wrap="leather")
            k.skirt("cloth2", 0.06 * t, 0.15, flare=0.06, folds=8, fold_amp=0.08)
        else:
            k.legs("shorts", "cloth2", feet="webbed", wrap="leather")
        k.belt(0.08 * t, "leather", "trim", infl=0.02, round_buckle=True)
        k.pouch(55, 0.06 * t)
        k.strap("leather", -40, 0.42 * t, 45, 0.05 * t)
        k.arms("puffy", "cloth1", cuff="cloth2")
        k.hands("skin")
        k.scarf("cape", bulk=1.1, tail=1, tail_len=0.2)
        anime_face(k, blush=False, **eye)
        k.hair_cap("hair")
        if f:
            k.bangs("hair", n=5, spread=115, zmin=0.36, w=0.08, droop=1.2, out=0.3, longer_sides=0.07)
            k.side_locks("hair", zmin=0.1, w=0.065, az=78, el=24)
            k.back_hair("hair", zmin=0.14, n=6, w=0.085, el=(15, 45), spread=120)
            if look == "tidecaller":
                k.ponytail(az=180, el=52, length=0.55, tie_slot="trim")
            else:
                for sd in (-1, 1):
                    k.ponytail(az=sd * 118, el=20, length=0.26, w=0.08, n=4, out=0.7, droop=1.4)
        else:
            k.bangs("hair", n=5, spread=120, zmin=0.37, w=0.09, th=0.035, droop=0.8, out=0.5, longer_sides=0.05)
            k.side_locks("hair", zmin=0.18, w=0.07, az=80, el=26)
            k.spikes("hair", n=11, length=0.19, w=0.09, th=0.05, out=1.2, droop=0.45)
        k.ears("fin", "feature")
        if look == "tidecaller":
            C.lathe("white", [(0.001, 0.07), (0.06, 0.055), (0.085, 0.02), (0.09, -0.01)], R["armL"], seg=14, res=2, cap_top=True,
                    folds=5, fold_amp=0.15, hem=0.02, hem_n=5)
            harpoon(k, R["handR"])
        else:
            k.quiver()
            k.bow(R["handL"])
    else:                                     # mystic: hooded tide-reader (concept: feminine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.legs("bare", feet="webbed")
        k.skirt("cloth2", 0.08 * t, 0.34, flare=0.1, folds=10, fold_amp=0.08, infl=0.006)
        k.mantle("cloth1", length=0.3, flare=0.1, hem=0.06, hem_n=7)
        rx = k.sh + k.arm_r + 0.1
        ry = k.trad(0.455 * t - 0.3, 0.02)[1] + 0.08
        for a in (-150, -120, -80, -45, 45, 80, 120, 150):
            x, y = math.sin(math.radians(a)) * rx, -math.cos(math.radians(a)) * ry
            z0 = 0.455 * t - 0.3 - 0.02
            C.sweep("cape", [(x, y, z0 + 0.04), (x * 1.04 + 0.01, y * 1.04, z0 - 0.06), (x * 1.02, y * 1.03, z0 - 0.13)],
                    [(0.022, 0.006), (0.02, 0.006), (0.0, 0.0)], k.torso, up=(0, -1, 0), ring=5, res=2)
        k.belt(0.08 * t, "leather", "trim", infl=0.03)
        k.potion(40, 0.06 * t)
        k.pouch(-50, 0.06 * t)
        k.amulet("cloth2", "trim", z=0.36 * t)
        k.arms("wide", "cloth1", cuff="cloth2", wide=0.05)
        k.hands("skin")
        anime_face(k, blush=False, **eye)
        k.hair_cap("hair")
        k.bangs("hair", n=5, spread=100, zmin=0.34, w=0.075, droop=1.5, longer_sides=0.08)
        k.side_locks("hair", zmin=-0.12 if f else 0.08, w=0.07, az=64, el=22, n=2 if f else 1)
        k.hood("cloth1", lining="cloth2", drape=False, tip=0.2, tip_dir=(0, 1.0, -0.4))
        C.ico("feature", (0, -0.33, 0.52), (1, 0.5, 1.3), parent=k.head, r=0.035, sub=1)
        k.ears("fin", "feature", k=0.85)
        jelly_staff(k, R["handR"])
    jellyfish(k)


# ======================================================================
# Mothkin
# ======================================================================
def fluffy_hair(k, long=0.0, top=True):
    """Soft, messy moth fluff: a layered shag whose ends flick outward, a few
    tufts on the crown; `long` lets the back fall past the shoulders."""
    k.hair_cap("hair", r=(0.31, 0.305, 0.295))
    k.bangs("hair", n=5, spread=118, zmin=0.37, w=0.092, th=0.04, droop=1.1, out=0.3, longer_sides=0.05)
    k.side_locks("hair", zmin=0.17 - long * 0.6, w=0.085, th=0.04, az=78, el=24, droop=1.0, out=0.3, curl=0.3)
    if long:
        k.back_hair("hair", zmin=0.1 - long, n=9, w=0.1, th=0.042, el=(18, 55), spread=170, droop=1.4, out=0.25, curl=0.05)
    k.back_hair("hair", zmin=0.13, n=8, w=0.1, th=0.045, el=(30, 62), spread=200, droop=1.0, out=0.3, curl=0.4)
    if top:
        for (az, el) in ((-30, 72), (35, 70), (160, 74), (-120, 62), (100, 60)):
            k.lock("hair", az, el, w=0.09, th=0.05, length=0.1, droop=0.4, out=1.0, curl=0.3, tip=0.02)


def moth_ruff(k, slot="white"):
    t = k.t
    C.lathe(slot, [(0.08, 0.075, 0.49 * t), (0.16, 0.14, 0.46 * t), (0.2, 0.17, 0.42 * t), (0.19, 0.16, 0.39 * t)], k.torso, seg=30, res=2,
            folds=12, fold_amp=0.16, hem=0.02, hem_n=12)


def mothkin(k):
    f, look, t, R = k.f, k.look, k.t, k.R
    eye = dict(iris=("eyes", 0.03), lit=("eyes", 0.72), size=1.06)
    wings = dict()
    if look == "warrior":
        k.setup_body(1.0 if f else 1.04)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.pelvis("cloth2")
        k.legs("pants", "cloth2", feet="tall_boots")
        k.torso_piece("cloth1", -0.04, 0.4 * t, infl=0.012)
        k.chest("cloth1", 0.012)
        k.front_panel("cloth1", -0.2, 0.1 * t, w=0.08, drop=0.03)
        k.front_panel("trim", -0.2, 0.34 * t, w=0.012, drop=0.035)
        k.skirt("cloth1", 0.08 * t, 0.2 if f else 0.14, flare=0.07, folds=8, fold_amp=0.08, arc=(40, 320) if not f else None)
        k.belt(0.1 * t, "leather", "trim", infl=0.02)
        k.arms("long", "cloth2", cuff="cloth1", bracer="metal")
        k.pauldron("metal", trim="trim")
        k.hands("leather")
        moth_ruff(k, "white")
        anime_face(k, **eye)
        fluffy_hair(k, long=0.25 if f else 0.0)
        if f:
            k.braid("hair", (-0.22, 0.12, 0.12), (-0.26, 0.05, -0.2), r=0.045, n=7, tie="trim")
        k.ears("pointed", "skin")
        k.sword(R["handR"])
        moth_shield(k, R["handL"])
        wings = dict(base="white", ring_slot="skin2", core="eyes")
    elif look == "rogue":                   # hooded wanderer (concept: feminine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("white", -0.03, 0.44 * t)
        k.chest("white")
        k.torso_piece("cloth1", -0.04, 0.42 * t, infl=0.014, arc=(24, 336), thick=0.012)
        k.pelvis("cape")
        k.legs("tights" if f else "pants", "cape", feet="tall_boots")
        k.skirt("cloth1", 0.06 * t, 0.2, flare=0.08, folds=7, fold_amp=0.08, arc=(26, 334), hem=0.03, hem_n=6)
        k.belt(0.08 * t, "leather", "trim", infl=0.02)
        k.small_lantern(k.torso, tuple(k.on_torso(-62, 0.0, 0.07)), 0.9)
        k.arms("long", "cloth1", cuff="cloth2")
        k.hands("leather")
        k.scarf("cloth2", bulk=1.08, tail=-1, tail_len=0.16)
        k.amulet("trim", "trim", z=0.3 * t)
        k.pack(body="leather", roll="white", trinkets=("glow", "trim"), k=0.85)
        anime_face(k, **eye)
        k.hair_cap("hair", r=(0.31, 0.305, 0.295))
        k.bangs("hair", n=5, spread=100, zmin=0.35, w=0.09, th=0.04, droop=1.0, out=0.5, longer_sides=0.07)
        k.side_locks("hair", zmin=0.14 if f else 0.2, w=0.085, az=70, el=22, curl=0.4)
        k.hood("cloth1", drape=False, ears=False, tip=0.22, tip_dir=(0, 1.0, -0.35))
        k.ears("pointed", "skin", k=0.9)
        k.dagger(R["handR"])
        k.dagger(R["handL"])
        wings = dict(base="white", ring_slot="skin2", core="eyes", spot_mid="skin2")
    elif look == "ranger":                  # scout with round glasses (concept: masculine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.torso_piece("cloth1", -0.03, 0.42 * t, infl=0.014, arc=(26, 334), thick=0.012)
        k.pelvis("cloth1")
        if f:
            k.legs("tights", "cape", feet="tall_boots")
            k.skirt("cloth1", 0.06 * t, 0.2, flare=0.08, folds=8, fold_amp=0.08)
        else:
            k.legs("pants", "cloth1", feet="tall_boots")
            k.skirt("cloth1", 0.06 * t, 0.22, flare=0.08, folds=7, fold_amp=0.08, arc=(28, 332))
        k.belt(0.08 * t, "leather", "trim", infl=0.02)
        k.strap("leather", -40, 0.43 * t, 50, 0.06 * t)
        C.box("leather", tuple(k.on_torso(75, 0.0, 0.07)), (0.08, 0.15, 0.13), rot=(0, 0, 15), parent=k.torso, bevel=0.025)
        C.box("leather", tuple(k.on_torso(75, 0.04, 0.12)), (0.085, 0.155, 0.05), rot=(0, 0, 15), parent=k.torso, bevel=0.012)
        k.small_lantern(k.torso, tuple(k.on_torso(-65, -0.01, 0.07)), 0.95)
        k.arms("long", "cloth1", cuff="cloth2")
        k.hands("leather")
        k.mantle("cloth1", length=0.13, flare=0.05, hem=0.03, hem_n=7)
        k.scarf("cape", bulk=1.12, tail=1, tail_len=0.14, mask=True)
        k.quiver()
        anime_face(k, mouth=False, **eye)
        fluffy_hair(k, long=0.2 if f else 0.0)
        k.glasses()
        k.ears("pointed", "skin")
        k.bow(R["handL"])
        wings = dict(base="white", ring_slot="skin2", core="skin2", spot_mid="feature")
    elif look == "mystic":                  # scholar with a book (concept: masculine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.legs("bare", feet="shoes", foot_slot="cloth1")
        k.skirt("cloth2", 0.08 * t, 0.36, flare=0.08, folds=10, fold_amp=0.07, infl=0.006)
        k.torso_piece("cloth1", -0.03, 0.43 * t, infl=0.014, arc=(28, 332), thick=0.012)
        k.skirt("cloth1", 0.06 * t, 0.33, flare=0.13, folds=8, fold_amp=0.1, arc=(30, 330), infl=0.02)
        for sd in (-1, 1):
            rx, ry = k.trad(0.06 * t, 0.02)
            pts = [Vector((math.sin(math.radians(sd * 30)) * (rx + 0.13 * u), -math.cos(math.radians(sd * 30)) * (ry + 0.11 * u) - 0.012,
                           0.06 * t - 0.33 * u)) for u in (0.0, 0.33, 0.66, 1.0)]
            C.sweep("trim", pts, [(0.012, 0.008)] * 4, k.torso, up=(0, -1, 0), ring=5, res=2)
        k.belt(0.09 * t, "leather", "trim", infl=0.024)
        k.small_lantern(k.torso, tuple(k.on_torso(58, -0.04, 0.09)), 0.95)
        C.lathe("cloth1", [(0.08, 0.075, 0.53 * t), (0.13, 0.12, 0.49 * t), (0.16, 0.14, 0.44 * t), (0.17, 0.15, 0.41 * t)], k.torso, seg=26,
                res=2, arc=(30, 330), thick=0.014)
        k.arms("wide", "cloth1", cuff="trim", wide=0.05)
        k.hands("skin")
        anime_face(k, **eye)
        if f:
            fluffy_hair(k, long=0.45, top=False)
            k.side_locks("hair", zmin=-0.2, w=0.085, az=68, el=20, wave=0.1, curl=0.2)
            C.lathe("trim", [(0.3, 0.3, 0.42), (0.305, 0.305, 0.4)], k.head, loc=(0, 0.02, 0), rot=(-18, 0, 0), seg=28, res=1)
        else:
            fluffy_hair(k)
        k.ears("pointed", "skin", k=1.05)
        k.staff(R["handR"], head="orb")
        k.book(R["handL"], cover="cloth1", pages="white", sigil="glow")
        wings = dict(base="skin2", rim="cloth1", ring_slot="feature", core="eyes", spot_mid="cloth1", accent="white")
    else:                                   # lanternbearer (concept: feminine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.legs("bare", feet="shoes", foot_slot="trim")
        k.skirt("cloth2", 0.08 * t, 0.37, flare=0.1, folds=11, fold_amp=0.08, infl=0.006)
        k.torso_piece("cloth1", -0.03, 0.42 * t, infl=0.014, arc=(34, 326), thick=0.012)
        k.skirt("cloth1", 0.06 * t, 0.34, flare=0.14, folds=8, fold_amp=0.1, arc=(36, 324), infl=0.02, hem=0.04, hem_n=6)
        k.front_panel("cloth1", -0.28, 0.06 * t, w=0.045, drop=0.08, tip=True)
        k.front_panel("trim", -0.26, 0.06 * t, w=0.012, drop=0.085)
        k.belt(0.09 * t, "trim", None, infl=0.022, h=0.03)
        k.arms("wide", "cloth1", cuff="trim", wide=0.07)
        k.hands("skin")
        k.amulet("glow", "trim", z=0.32 * t)
        anime_face(k, **eye)
        k.hair_cap("hair", r=(0.31, 0.305, 0.295))
        k.bangs("hair", n=6, spread=120, zmin=0.34, w=0.075, droop=1.4, longer_sides=0.09)
        if f:
            k.side_locks("hair", zmin=-0.3, w=0.075, az=74, el=22, n=2)
            k.back_hair("hair", zmin=-0.48, n=10, w=0.1, el=(15, 60), spread=170)
        else:
            k.side_locks("hair", zmin=0.08, w=0.08, az=78, el=24)
            k.back_hair("hair", zmin=0.1, n=8, w=0.1, th=0.04, el=(15, 50), curl=0.4)
            k.lock("hair", 180, 20, w=0.08, th=0.035, zmin=-0.3, length=0.7, droop=1.6, out=0.5)
            k.spikes("hair", n=6, length=0.12, w=0.1, th=0.06, out=1.1, droop=0.55, el=(45, 75), curl=0.6)
        C.ico("glow", tuple(k.on_head(0, 23, 0.045)), (1, 0.5, 1.3), parent=k.head, r=0.03, sub=1)
        C.sweep("trim", [k.on_head(-12, 26, 0.04), k.on_head(0, 20, 0.05), k.on_head(12, 26, 0.04)], [0.008] * 3, k.head, res=2, ring=5)
        k.ears("pointed", "skin")
        k.lantern_staff(R["handR"])
        wings = dict(base="white", ring_slot="skin2", core="eyes", spot_mid="feature", lanterns=True, s=1.44)
    moth_antennae(k, s=1.0 if look != "lanternbearer" else 1.08, base_y=-0.02 if look == "rogue" else -0.06)
    moth_wings(k, **wings)


# ======================================================================
# Barkborn
# ======================================================================
def leaf_crown(k, slots, size, rings):
    """Big maple leaves standing out of the hair. rings = [(el, n, lean,
    size_k, clear_az)]: lean 1 points straight up, 0 out, -1 hanging; no
    leaf grows within clear_az of the front, so the face stays open."""
    rng = k.rng
    for ri, (el, n, lean, ks, clear) in enumerate(rings):
        for i in range(n):
            az = -180 + 360 * (i + 0.5 * (ri % 2)) / n + rng.uniform(-7, 7)
            if abs(az) < clear:
                continue
            r = dirv(az, el + rng.uniform(-5, 5))
            h = Vector((r.x, r.y, 0.0))
            h = h.normalized() if h.length > 1e-3 else Vector((0, 1, 0))
            ln = max(-1.0, min(1.0, lean + rng.uniform(-0.12, 0.12)))
            d = (h * (1 - abs(ln)) + UP * ln).normalized()
            nrm = h - d * h.dot(d)
            if nrm.length < 1e-3:
                nrm = r
            k.leaf(rng.choice(slots), HEAD_C + r * (k.scalp + 0.005), d, size * ks * rng.uniform(0.9, 1.1), k.head,
                   normal=nrm.normalized(), bend=-0.08)


def leaf_hair(k, slots, style="mane", size=0.14, long=0.0, bangs=True):
    """Anime hair in the leaf colour crowned with big maple leaves. The
    fringe stops above the eyes and nothing hangs in front of the face."""
    hair = slots[0]
    k.hair_cap(hair, r=(0.305, 0.3, 0.29))
    if bangs:
        k.bangs(hair, n=5, spread=116, zmin=0.37, w=0.09, th=0.036, droop=1.0, out=0.35, longer_sides=0.05)
    if style == "long":
        k.side_locks(hair, zmin=-0.06 - long, w=0.075, th=0.034, az=76, el=24, n=2, wave=0.08)
        k.back_hair(hair, zmin=-0.18 - long, n=9, w=0.1, th=0.04, el=(18, 55), spread=170, droop=1.4, out=0.3, wave=0.1)
        rings = [(80, 3, 0.85, 1.3, 0), (60, 8, 0.55, 1.45, 0), (38, 7, 0.15, 1.3, 80)]
    elif style == "spiky":
        k.side_locks(hair, zmin=0.18, w=0.075, th=0.034, az=84, el=26, droop=1.0, out=0.25)
        k.back_hair(hair, zmin=0.12, n=7, w=0.1, th=0.045, el=(25, 55), spread=190, droop=0.8, out=0.5, curl=0.5)
        rings = [(84, 3, 0.9, 1.4, 0), (64, 9, 0.7, 1.6, 0), (40, 8, 0.3, 1.45, 75)]
    else:   # mane
        k.side_locks(hair, zmin=0.1, w=0.08, th=0.036, az=84, el=26, droop=1.1, out=0.25)
        k.back_hair(hair, zmin=-long, n=9, w=0.11, th=0.045, el=(20, 55), spread=200, droop=1.1, out=0.45, curl=0.35)
        rings = [(82, 3, 0.9, 1.4, 0), (62, 10, 0.6, 1.6, 0), (34, 10, 0.1, 1.55, 78), (8, 9, -0.35, 1.45, 100)]
    leaf_crown(k, slots, size, rings)


def leaf_rows(k, slots, rows, parent=None, shape=None, out=0.55):
    """Rings of leaves around the torso: rows = [(z, r_extra, n, size)]."""
    rng = k.rng
    for ri, (z, rex, n, size) in enumerate(rows):
        for i in range(n):
            a = 360.0 * i / n + ri * 11 + rng.uniform(-5, 5)
            rx, ry = k.trad(z, rex)
            ar = math.radians(a)
            base = Vector((math.sin(ar) * rx, -math.cos(ar) * ry, z))
            out_d = Vector((math.sin(ar), -math.cos(ar), 0.0))
            k.leaf(rng.choice(slots), base, (out_d * out + Vector((0, 0, -1))).normalized(), size * rng.uniform(0.9, 1.12),
                   parent or k.torso, normal=out_d, shape=shape)


def wood_mask(k, parent, loc=(0, 0, 0), rot=(0, 0, 0), s=1.0, slot="wood"):
    m = frame("mask", loc, rot, parent)
    C.sphere(slot, (0, -0.2 * s, 0.24 * s), (0.24 * s, 0.13 * s, 0.3 * s), parent=m, seg=20, rings=14)
    C.sweep(slot, [(0, -0.32 * s, 0.42 * s), (0, -0.35 * s, 0.26 * s), (0, -0.36 * s, 0.14 * s)], [0.03 * s, 0.035 * s, 0.028 * s], m,
            ring=8, res=2)
    for sd in (-1, 1):
        # carved eye holes with a warm glow deep inside
        C.flat("skin2", [(-0.08 * s, -0.028 * s), (0.075 * s, 0.0), (0.07 * s, 0.045 * s), (-0.06 * s, 0.04 * s)], 0.01, m,
               loc=(sd * 0.09 * s, -0.318 * s, 0.3 * s), rot=(0, sd * 12, sd * -24), rings=1)
        C.flat(("eyes", 0.9, "prio"), C.ellipse(10, 0.022 * s, 0.017 * s, 0.0, 0.01 * s), 0.004, m,
               loc=(sd * 0.09 * s, -0.325 * s, 0.3 * s), rot=(0, sd * 12, sd * -24), rings=1)
        C.sweep("skin2", [(sd * 0.15 * s, -0.27 * s, 0.4 * s), (sd * 0.17 * s, -0.28 * s, 0.24 * s), (sd * 0.12 * s, -0.3 * s, 0.08 * s)],
                [0.008 * s, 0.009 * s, 0.006 * s], m, ring=4, res=2)
    C.sweep("skin2", [(-0.06 * s, -0.33 * s, 0.1 * s), (0.06 * s, -0.33 * s, 0.1 * s)], [0.007 * s, 0.007 * s], m, ring=4, res=1)
    return m


def barkborn(k):
    f, look, t, R = k.f, k.look, k.t, k.R
    eye = dict(iris=("eyes", 0.03), lit=("eyes", 0.74))
    ant = 1.0
    if look == "warrior":                   # masked leaf warrior (concept)
        k.setup_body(1.0 if f else 1.1)
        k.neck_part()
        k.torso_piece("skin", -0.03, 0.44 * t)
        k.chest("skin")
        k.pelvis("skin")
        k.legs("bare", feet="root")
        bark_lines(k)
        leaf_rows(k, ["cloth1", "feature", "hair"], [(0.3 * t, 0.012, 12, 0.11), (0.18 * t, 0.014, 13, 0.12)], out=0.3)
        k.belt(0.08 * t, "leather", "cloth2", infl=0.02, round_buckle=True)
        leaf_rows(k, ["hair", "feature", "cloth1", "hair"], [(0.05 * t, 0.03, 15, 0.15), (-0.04, 0.04, 16, 0.17)], out=0.35)
        leaf_rows(k, ["hair", "feature", "hair"], [(0.46 * t, 0.03, 12, 0.15), (0.4 * t, 0.06, 14, 0.16)], out=0.8)
        k.arms("bare")
        for arm in (R["armR"], R["armL"]):
            for i in range(4):
                a = math.radians(i * 90 + 20)
                k.leaf(k.rng.choice(["hair", "feature"]), (math.sin(a) * 0.05, -math.cos(a) * 0.05, -0.19 * t),
                       (math.sin(a) * 0.4, -math.cos(a) * 0.4, -1), 0.09, arm, normal=(math.sin(a), -math.cos(a), 0))
        k.hands("skin")
        k.head_base("skin")
        if f:
            k.eyes(**eye)
            k.brows("skin2")
            k.mouth("skin2")
            leaf_hair(k, ["hair", "hair", "feature"], style="long", size=0.15, long=0.15)
            wood_mask(k, k.head, (0.2, -0.02, 0.36), (0, -30, 62), s=0.62)
        else:
            wood_mask(k, k.head)
            leaf_hair(k, ["hair", "hair", "feature"], style="mane", size=0.17, bangs=False)
        k.ears("long", "skin")
        axe(k, R["handR"])
        leaf_shield(k, R["handL"])
    elif look == "rogue":                   # flower forager (concept: feminine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("skin", -0.03, 0.44 * t)
        k.torso_piece("cloth1", -0.03, 0.4 * t, infl=0.008)
        k.chest("cloth1", 0.008)
        k.pelvis("cloth1")
        k.legs("bare", feet="root", wrap="leather")
        bark_lines(k)
        k.skirt("cloth1", 0.06 * t, 0.24 if f else 0.16, flare=0.08, folds=8, fold_amp=0.1, hem=0.05, hem_n=6)
        leaf_rows(k, ["feature", "hair"], [(0.04 * t, 0.03, 13, 0.12)], shape=OVAL)
        k.belt(0.08 * t, "leather", "trim", infl=0.03, round_buckle=True)
        k.front_panel("leather", -0.1, 0.04 * t, w=0.04, drop=0.06, tip=True)
        k.arms("bare")
        k.hands("skin")
        k.scarf("cloth2", bulk=1.05, tail=1, tail_len=0.15)
        anime_face(k, brow="skin2", blush=False, **eye)
        if f:
            leaf_hair(k, ["hair", "hair", "feature"], style="long", size=0.13, long=0.12)
            for (az, el) in ((-40, 50), (35, 55), (70, 35), (-75, 30), (10, 72)):
                k.flower(k.head, k.on_head(az, el, 0.07), dirv(az, el), r=0.032)
        else:
            leaf_hair(k, ["hair", "hair", "feature"], style="mane", size=0.13)
            for (az, el) in ((-60, 45), (-30, 58), (0, 64), (30, 58), (60, 45)):
                k.flower(k.head, k.on_head(az, el, 0.08), dirv(az, el), r=0.028)
        k.ears("long", "skin")
        sickle(k, R["handR"])
        basket(k, R["handL"])
    elif look == "ranger":                  # leaf-poncho archer (concept: masculine)
        k.setup_body(1.0)
        k.neck_part()
        k.torso_piece("skin", -0.03, 0.44 * t)
        k.chest("skin")
        k.pelvis("skin2")
        k.legs("bare", feet="root")
        bark_lines(k)
        k.mantle("cloth1", length=0.2, flare=0.08, hem=0.05, hem_n=9)
        leaf_rows(k, ["cloth1", "cloth1", "feature"], [(0.44 * t, 0.06, 12, 0.11), (0.36 * t, 0.1, 14, 0.12)], shape=OVAL, out=0.7)
        k.belt(0.08 * t, "leather", "trim", infl=0.02, round_buckle=True)
        k.front_panel("white", -0.08, 0.06 * t, w=0.03, drop=0.03)
        leaf_rows(k, ["hair", "feature", "skin2", "hair"], [(0.05 * t, 0.03, 14, 0.13), (-0.03, 0.04, 15, 0.14 if f else 0.12)], out=0.3)
        k.arms("bare", bracer="cloth1")
        k.hands("skin")
        k.quiver(slot="leather", fletch="feature")
        anime_face(k, brow="skin2", blush=False, **eye)
        if f:
            leaf_hair(k, ["hair", "hair", "feature"], style="spiky", size=0.13)
            for sd in (-1, 1):
                k.leaf_lock(["hair", "feature"], sd * 110, 25, 0.13, zmin=-0.05, length=0.4, droop=1.3, out=0.8, gap=0.5, grow=0.2)
        else:
            leaf_hair(k, ["hair", "hair", "feature"], style="spiky", size=0.14)
        k.ears("long", "skin")
        k.bow(R["handL"])
    else:                                   # druid (mystic) and the big graftwarden (concept)
        big = look == "graftwarden"
        k.setup_body((1.24 if not f else 1.14) if big else (1.04 if not f else 1.0))
        k.neck_part()
        k.torso_piece("skin", -0.03, 0.44 * t)
        k.pelvis("skin")
        k.legs("bare", feet="root")
        bark_lines(k)
        k.skirt("cloth2", 0.08 * t, 0.3 if big else 0.34, flare=0.1, folds=9, fold_amp=0.1, infl=0.008, hem=0.05, hem_n=7)
        k.mantle("cloth1", length=0.32 if big else 0.26, flare=0.12, hem=0.07, hem_n=10)
        leaf_rows(k, ["cloth1", "cloth1", "feature", "cape"],
                  [(0.46 * t, 0.06, 14, 0.13), (0.36 * t, 0.12, 16, 0.14), (0.24 * t, 0.16, 18, 0.15)], shape=OVAL, out=0.8)
        k.belt(0.1 * t, "leather", "trim", infl=0.03, round_buckle=True)
        for x in (-0.06, 0.07):
            C.sweep("leather", [(x, -k.trad(0.1 * t)[1] - 0.035, 0.1 * t), (x, -k.trad(0.0)[1] - 0.05, 0.0)], [0.004, 0.004], k.torso,
                    res=1, ring=4)
            C.box("white", (x, -k.trad(0.0)[1] - 0.05, -0.025), (0.04, 0.012, 0.05), parent=k.torso)
        k.amulet("glow", "leather", z=0.3 * t)
        k.arms("bare", bracer="cloth1")
        k.hands("skin")
        k.head_base("skin", snout=0.07 if (big and not f) else 0.0)
        if big and not f:
            k.eyes(size=0.72, gap=23, el=-2, iris=("eyes", 0.3), lit=("eyes", 0.9), lashes=False)
            for sd in (-1, 1):
                C.sweep("skin2", [k.on_head(sd * 8, 12, 0.02), k.on_head(sd * 22, 14, 0.03), k.on_head(sd * 36, 8, 0.02)],
                        [0.02, 0.024, 0.0], k.head, ring=6, res=2)
            for az in (-40, -20, 0, 20, 40):
                k.leaf_lock(["cape", "cloth1"], az, -40 + abs(az) * 0.3, 0.1, zmin=-0.08, length=0.25, droop=1.8, out=0.9, gap=0.5,
                            shape=OVAL)
            leaf_hair(k, ["hair", "hair", "cloth1", "feature"], style="mane", size=0.16, bangs=False)
        else:
            k.eyes(**eye)
            k.brows("skin2")
            k.mouth("skin2")
            leaf_hair(k, ["hair", "hair", "feature"], style="long" if f else "mane", size=0.15, long=0.1 if f else 0.0)
            if f:
                for (az, el) in ((-45, 52), (50, 48), (-78, 30)):
                    k.flower(k.head, k.on_head(az, el, 0.08), dirv(az, el), r=0.032)
        ant = 1.35 if big else 1.2
        k.ears("long", "skin", k=1.05)
        gnarled_staff(k, R["handR"], s=1.12 if big else 1.0)
    antlers(k, s=ant)


# ======================================================================
# Khepri
# ======================================================================
def khepri_face(k):
    k.head_base("skin", hx=0.295, hy=0.29, hz=0.28, chin=0.5, jaw=0.18)
    C.sphere("skin2", (0, -0.2, 0.1), (0.15, 0.1, 0.085), parent=k.head, seg=16, rings=10)
    for sd in (-1, 1):
        C.sweep("skin2", [(sd * 0.1, -0.26, 0.09), (sd * 0.07, -0.3, 0.04), (sd * 0.03, -0.3, 0.01)], [0.018, 0.012, 0.0], k.head, ring=6,
                res=2)
    C.decal("hair", k.bvh, [(-0.04, 0.2), (0.04, 0.2), (0.07, -0.02), (0.0, -0.1), (-0.07, -0.02)], HEAD_C, dirv(0, 12), lift=0.004,
            parent=k.head)
    k.eyes(size=1.28, gap=25, el=-2, wide=1.05, iris=("eyes", 0.2), lit=("eyes", 0.9), pupil=("skin2", 0.0), lashes=k.f)


def khepri(k):
    f, look, t, R = k.f, k.look, k.t, k.R
    ant = dict()
    if look == "warrior":                   # beetle-helmed merchant guard (concept: masculine)
        k.setup_body(1.14 if not f else 1.02)
        k.neck_part("skin2")
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.pelvis("cloth1")
        k.legs("baggy", "cloth2", feet="hoof", foot_slot="leather")
        k.skirt("cloth1", 0.08 * t, 0.34 if not f else 0.3, flare=0.12, folds=9, fold_amp=0.09, hem=0.02, hem_n=9,
                arc=None if not f else (18, 342))
        k.front_panel("cloth2", -0.3, 0.3 * t, w=0.07, drop=0.1)
        for z in (-0.2, 0.2 * t):
            k.front_panel("trim", z - 0.02, z, w=0.07, drop=0.1 if z < 0 else 0.0)
        rx, ry = k.trad(0.08 * t, 0.012)
        C.lathe("trim", [(rx + 0.1, ry + 0.085, 0.08 * t - 0.3), (rx + 0.115, ry + 0.1, 0.08 * t - 0.33)], k.torso, seg=36, res=1,
                arc=None if not f else (18, 342), thick=0.012 if f else 0.0)
        k.belt(0.1 * t, "leather", "trim", infl=0.02, h=0.04)
        k.pouch(60, 0.04 * t)
        C.lathe("white", [(0.1, 0.095, 0.5 * t), (0.19, 0.17, 0.46 * t), (0.23, 0.2, 0.4 * t), (0.22, 0.19, 0.35 * t)], k.torso, seg=30,
                res=2, folds=8, fold_amp=0.1)
        k.arms("long", "cloth1", cuff="cloth2", bracer="leather")
        k.hands("skin2")
        k.pack(body="leather", roll="cape", k=1.1)
        khepri_face(k)
        k.hood("hair", drape=False, rim="trim", brow=40, side=70, jaw=-20, back=-40, gap=0.03, peak=0.0)
        C.sweep("trim", [(0, -0.29, 0.5), (0, -0.12, 0.66), (0, 0.15, 0.66), (0, 0.33, 0.44)], [0.022] * 4, k.head, ring=6, res=3)
        C.sphere("trim", (0, -0.31, 0.47), (0.07, 0.035, 0.06), parent=k.head, seg=12, rings=8)
        C.ico("glow", (0, -0.34, 0.47), (1, 0.6, 1.2), parent=k.head, r=0.04, sub=2)
        if not f:
            C.sweep("hair", [(0, -0.3, 0.52), (0, -0.36, 0.64), (0, -0.33, 0.78), (0, -0.25, 0.86)], [0.05, 0.04, 0.025, 0.0], k.head,
                    ring=8, res=3)
        else:
            for a in (-30, -10, 10, 30):
                d = Vector((math.sin(math.radians(a)) * 0.5, 0.6, 1.0))
                k.leaf("feature", (math.sin(math.radians(a)) * 0.06, 0.1, 0.6), d, 0.22, k.head, normal=(1, 0, 0), shape=oval_outline(0.2))
        ant = dict(base=(0.12, -0.08, 0.6))
        k.curved_blade(R["handR"], back=0.12)
        buckler(k, R["handL"])
    elif look == "rogue":                   # hooded scout (concept)
        k.setup_body(1.0)
        k.neck_part("skin2")
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.pelvis("cloth1")
        k.legs("shorts", "cloth1", feet="hoof", wrap="leather")
        k.skirt("cloth2", 0.06 * t, 0.17, flare=0.08, folds=0, hem=0.07, hem_n=6)
        rx, ry = k.trad(0.06 * t, 0.012)
        C.lathe("trim", [(rx + 0.06, ry + 0.05, 0.06 * t - 0.12), (rx + 0.074, ry + 0.064, 0.06 * t - 0.15)], k.torso, seg=36, res=1)
        k.belt(0.08 * t, "leather", "trim", infl=0.016)
        k.strap("leather", -35, 0.42 * t, 45, 0.04 * t)
        k.pouch(-55, 0.05 * t)
        k.arms("long", "cloth2", cuff="leather", bracer="leather")
        k.hands("skin2")
        k.pack(body="leather", roll="white", trinkets=("glow", "feature", "glow"), k=0.9)
        khepri_face(k)
        k.scarf("cloth1", bulk=1.05, tail=-1, tail_len=0.14, mask=True)
        k.hood("cloth2", lining="cloth1", tip=0.3 if not f else 0.0, tip_slot="cloth1", drape=True, tip_dir=(0.3, 1, -0.6))
        if f:
            C.sweep("cloth1", [(0.12, 0.2, 0.5), (0.2, 0.34, 0.32), (0.24, 0.36, 0.12)], [(0.05, 0.02), (0.045, 0.018), (0.0, 0.0)], k.head,
                    up=(1, 0, 0), ring=6, res=2)
        ant = dict(base=(0.09, -0.16, 0.56))
        k.dagger(R["handR"], k=1.1)
        k.curved_blade(R["handL"], k=0.62, back=0.1)
    elif look == "ranger":
        k.setup_body(1.0)
        k.neck_part("skin2")
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.torso_piece("leather", 0.06 * t, 0.4 * t, infl=0.012, arc=(26, 334), thick=0.012)
        k.pelvis("leather")
        k.legs("baggy", "leather", feet="hoof")
        k.skirt("cloth2", 0.06 * t, 0.18 if f else 0.14, flare=0.07, folds=8, fold_amp=0.08)
        k.belt(0.08 * t, "cloth1", "trim", infl=0.018, h=0.04)
        k.arms("long", "cloth2", cuff="cloth1", bracer="leather")
        k.hands("skin2")
        k.pack(body="leather", roll="cloth1", trinkets=("feature", "glow"), k=0.85)
        k.quiver(slot="leather", fletch="feature")
        khepri_face(k)
        if f:
            k.hood("cloth1", drape=True)
            for sd in (-1, 1):
                C.sweep("cloth1", [(sd * 0.1, 0.28, 0.3), (sd * 0.16, 0.36, 0.1), (sd * 0.17, 0.34, -0.12)],
                        [(0.06, 0.012), (0.055, 0.01), (0.03, 0.008)], k.head, up=(0, 1, 0), ring=6, res=2)
            k.earrings()
            k.scarf("cloth1", bulk=1.0, tail=0)
        else:
            k.hood("cloth2", drape=False, rim="cloth1")
            k.scarf("cloth1", bulk=1.08, tail=1, tail_len=0.16, mask=True)
        ant = dict(base=(0.09, -0.15, 0.56))
        k.bow(R["handL"])
    elif look == "mystic":                  # the elder (concept: masculine)
        k.setup_body(1.06 if not f else 1.0)
        k.neck_part("skin2")
        k.torso_piece("cloth2", -0.03, 0.44 * t)
        k.chest("cloth2")
        k.legs("bare", feet="hoof", foot_slot="leather")
        k.skirt("cloth2", 0.08 * t, 0.36, flare=0.08, folds=10, fold_amp=0.07, infl=0.006)
        k.torso_piece("cloth1", -0.03, 0.43 * t, infl=0.014, arc=(30, 330), thick=0.012)
        k.skirt("cloth1", 0.06 * t, 0.35, flare=0.14, folds=8, fold_amp=0.1, arc=(32, 328), infl=0.02)
        rx, ry = k.trad(0.06 * t, 0.02)
        for sd in (-1, 1):
            pts = [Vector((math.sin(math.radians(sd * 32)) * (rx + 0.14 * u), -math.cos(math.radians(sd * 32)) * (ry + 0.12 * u) - 0.012,
                           0.06 * t - 0.35 * u)) for u in (0.0, 0.33, 0.66, 1.0)]
            C.sweep("trim", pts, [(0.014, 0.008)] * 4, k.torso, up=(0, -1, 0), ring=5, res=2)
        C.lathe("trim", [(rx + 0.13, ry + 0.11, 0.06 * t - 0.31), (rx + 0.14, ry + 0.12, 0.06 * t - 0.345)], k.torso, seg=36, res=1,
                arc=(32, 328), thick=0.012)
        k.belt(0.09 * t, "trim", None, infl=0.024, h=0.035)
        k.front_panel("trim", -0.22, 0.09 * t, w=0.03, drop=0.08, tip=True)
        C.ico("glow", tuple(k.on_torso(0, -0.12, 0.1)), (1, 0.6, 1.3), parent=k.torso, r=0.026, sub=1)
        C.ico("glow", tuple(k.on_torso(0, 0.34 * t, 0.03)), (1, 0.6, 1.3), parent=k.torso, r=0.03, sub=1)
        k.arms("wide", "cloth1", cuff="trim", wide=0.06)
        k.hands("skin2")
        k.pack(body="leather", roll="white", trinkets=("glow",), k=0.9)
        khepri_face(k)
        k.hood("white", drape=True, brow=30, jaw=-46)
        k.head_band("trim", 32, 44, lift=0.05)
        C.ico("glow", (0, -0.33, 0.43), (1, 0.5, 1.2), parent=k.head, r=0.035, sub=2)
        if f:
            for sd in (-1, 1):
                C.sweep("white", [(sd * 0.14, 0.26, 0.32), (sd * 0.2, 0.36, 0.08), (sd * 0.2, 0.36, -0.22)],
                        [(0.08, 0.014), (0.075, 0.012), (0.06, 0.01)], k.head, up=(0, 1, 0), ring=6, res=2)
            k.earrings()
        else:
            for az in (-44, -26, -10, 10, 26, 44):
                k.lock("white", az, -35 + abs(az) * 0.2, w=0.06, th=0.04, zmin=-0.18 + abs(az) * 0.0025, length=0.5, droop=2.0, out=0.9,
                       rs=0.25, lift=0.04)
        ant = dict(base=(0.1, -0.1, 0.62))
        crook(k, R["handR"])
    else:                                   # sandreaver: goggles and red scarf (concept: masculine)
        k.setup_body(1.0)
        k.neck_part("skin2")
        k.torso_piece("cloth1", -0.03, 0.44 * t)
        k.chest("cloth1")
        k.torso_piece("leather", 0.1 * t, 0.36 * t, infl=0.012, arc=(28, 332), thick=0.012)
        k.pelvis("cape")
        if f:
            k.legs("shorts", "cape", feet="hoof", knee="leather", wrap="leather")
        else:
            k.legs("baggy", "cape", feet="hoof", knee="leather")
        k.skirt("cloth1", 0.06 * t, 0.12, flare=0.06, folds=0, hem=0.05, hem_n=5)
        k.belt(0.08 * t, "leather", "trim", infl=0.02)
        k.pouch(-55, 0.05 * t)
        k.pouch(55, 0.05 * t)
        k.arms("short" if f else "long", "cloth1", cuff="leather", bracer="leather")
        k.hands("skin2")
        k.pack(body="leather", roll="cloth2", trinkets=("glow", "trim"), k=0.85)
        k.scarf("cloth2", bulk=1.12, tail=1, tail_len=0.22 if f else 0.16, tails=2 if f else 1)
        khepri_face(k)
        k.hood("leather", drape=False, brow=42, side=74, jaw=-10, back=-35, gap=0.022, peak=0.0, lip=0.006)
        for sd in (-1, 1):
            C.sweep("leather", [(sd * 0.27, -0.05, 0.3), (sd * 0.3, -0.06, 0.16), (sd * 0.29, -0.08, 0.06)],
                    [(0.07, 0.016), (0.06, 0.014), (0.045, 0.012)], k.head, up=(1, 0, 0), ring=6, res=2)
            p = k.on_head(sd * 20, 26, 0.05)
            C.lathe("metal", [(0.045, 0.02), (0.07, 0.02), (0.07, -0.02), (0.045, -0.02)], k.head, loc=tuple(p),
                    rot=basis_rot(dirv(sd * 20, 32), UP), seg=16, res=1)
            C.lathe("white", [(0.001, 0.012), (0.05, 0.008), (0.05, -0.004)], k.head, loc=tuple(p), rot=basis_rot(dirv(sd * 20, 32), UP),
                    seg=14, res=1)
        k.head_band("leather", 32, 22, lift=0.036, r=(0.024, 0.008))
        ant = dict(base=(0.1, -0.08, 0.6))
        glass_blade(k, R["handR"])
        glass_blade(k, R["handL"], 0.85)
    khepri_antennae(k, **ant)


DESIGNS = {"human": human, "tidefolk": tidefolk, "mothkin": mothkin, "barkborn": barkborn, "khepri": khepri}


def build(R, spec, bandage=False):
    k = Kit(R, spec)
    DESIGNS[k.race](k)
    if bandage:
        k.bandage()
    return k
