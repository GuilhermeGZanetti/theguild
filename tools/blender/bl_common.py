"""Shared Blender helpers for the A Guilda art pipeline.

Characters are rendered as *index sprites*: every material encodes a palette
slot (R channel), a toon shade value (G channel) and view depth (B channel).
The post-process step (tools/py/sprites_post.py) turns that into clean pixel
art, and the game recolors each unit through a per-unit palette.
"""
import math
import os
import bpy
from mathutils import Vector, Matrix, Euler, Quaternion
from mathutils.bvhtree import BVHTree

PX_PER_UNIT = 24.0          # world units -> screen pixels (matches the game)
SPRITE_PITCH = 30.0         # degrees the sprite camera looks down
SUPERSAMPLE = 4             # render at 4x, downsample with majority vote

# Palette slots shared with the game shader (scripts/combat/unit_palette.gd)
SLOT = {
    "skin": 0, "skin2": 1, "hair": 2, "eyes": 3, "cloth1": 4, "cloth2": 5,
    "leather": 6, "metal": 7, "trim": 8, "wood": 9, "glow": 10,
    "feature": 11, "cape": 12, "white": 13, "bandage": 14,
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.diffuse_bounces = 0
    scene.cycles.glossy_bounces = 0
    scene.cycles.transmission_bounces = 0
    scene.cycles.transparent_max_bounces = 0
    scene.cycles.pixel_filter_type = "BOX"
    scene.cycles.filter_width = 0.01
    try:
        scene.cycles.use_adaptive_sampling = False
    except Exception:
        pass
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Raw"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.dither_intensity = 0.0
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    world = bpy.data.worlds.new("World")
    scene.world = world
    return scene


def setup_camera(scene, canvas_px, anchor_px, pitch_deg=SPRITE_PITCH, zoom=1.0):
    """Orthographic camera at the sprite angle.

    canvas_px: (w, h) of the final sprite; anchor_px: pixel of the world origin
    (feet) measured from the top-left of the final sprite.
    """
    w, h = canvas_px
    scene.render.resolution_x = w * SUPERSAMPLE
    scene.render.resolution_y = h * SUPERSAMPLE
    scene.render.resolution_percentage = 100
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(w, h) / PX_PER_UNIT / zoom
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("SpriteCam", cam_data)
    scene.collection.objects.link(cam)
    pitch = math.radians(pitch_deg)
    forward = Vector((0.0, math.cos(pitch), -math.sin(pitch)))
    up = Vector((0.0, math.sin(pitch), math.cos(pitch)))
    right = Vector((1.0, 0.0, 0.0))
    # shift so origin lands on anchor pixel
    ax, ay = anchor_px
    off_right = (ax - w / 2.0) / PX_PER_UNIT / zoom
    off_up = (ay - h / 2.0) / PX_PER_UNIT / zoom  # positive: origin below centre
    center = -right * off_right + up * off_up
    cam.location = center - forward * 20.0
    cam.rotation_euler = Euler((math.pi / 2 - pitch, 0.0, 0.0), "XYZ")
    scene.camera = cam
    return cam, forward, up, right


def light_vector(forward, up, right):
    """Light from the upper-left of the screen, slightly in front."""
    toward_viewer = -forward
    lv = right * -0.55 + up * 0.70 + toward_viewer * 0.55
    lv.normalize()
    return lv


_MATS = {}
_FLAT = {}
_DEPTH = [3.0]


def flat_mat(slot, shade, prio=False):
    """Unlit variant of a slot: constant shade (eye gradients, highlights).
    prio marks the pixels (depth channel 0) so they win the downsample vote."""
    key = (slot, round(shade, 3), prio)
    if key in _FLAT:
        return _FLAT[key]
    mat = bpy.data.materials.new("flat_%s_%d" % (slot, int(shade * 100)))
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    comb = nt.nodes.new("ShaderNodeCombineColor")
    camd = nt.nodes.new("ShaderNodeCameraData")
    dmap = nt.nodes.new("ShaderNodeMapRange")
    dmap.inputs["From Min"].default_value = 20.0 - _DEPTH[0]
    dmap.inputs["From Max"].default_value = 20.0 + _DEPTH[0]
    nt.links.new(camd.outputs["View Z Depth"], dmap.inputs["Value"])
    comb.inputs[0].default_value = (SLOT[slot] + 0.5) / 16.0
    comb.inputs[1].default_value = shade
    if prio:
        comb.inputs[2].default_value = 0.0
    else:
        nt.links.new(dmap.outputs["Result"], comb.inputs[2])
    nt.links.new(comb.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    _FLAT[key] = mat
    return mat


# Anime faces stay mostly lit: skin gets less occlusion under the hair and a
# lifted ramp (ao_min, lift).
SOFT = {"skin": (0.9, 0.36), "skin2": (0.8, 0.16)}


def build_materials(light_vec, depth_range=3.0):
    """One emission material per palette slot, encoding slot/shade/depth."""
    _MATS.clear()
    _FLAT.clear()
    _DEPTH[0] = depth_range
    for name, idx in SLOT.items():
        mat = bpy.data.materials.new("slot_" + name)
        try:
            mat.use_nodes = True
        except Exception:
            pass
        nt = mat.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        comb = nt.nodes.new("ShaderNodeCombineColor")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        dot.inputs[1].default_value = light_vec
        # half-lambert
        half = nt.nodes.new("ShaderNodeMath")
        half.operation = "MULTIPLY_ADD"
        half.inputs[1].default_value = 0.5
        half.inputs[2].default_value = 0.5
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 8
        ao.inputs["Distance"].default_value = 0.25
        ao_mix = nt.nodes.new("ShaderNodeMapRange")
        ao_mix.inputs["From Min"].default_value = 0.0
        ao_mix.inputs["From Max"].default_value = 1.0
        ao_min, lift = SOFT.get(name, (0.55, 0.0))
        ao_mix.inputs["To Min"].default_value = ao_min
        ao_mix.inputs["To Max"].default_value = 1.0
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.use_clamp = True
        camd = nt.nodes.new("ShaderNodeCameraData")
        dmap = nt.nodes.new("ShaderNodeMapRange")
        dmap.inputs["From Min"].default_value = 20.0 - depth_range
        dmap.inputs["From Max"].default_value = 20.0 + depth_range
        dmap.inputs["To Min"].default_value = 0.0
        dmap.inputs["To Max"].default_value = 1.0
        nt.links.new(geo.outputs["Normal"], dot.inputs[0])
        nt.links.new(dot.outputs["Value"], half.inputs[0])
        nt.links.new(ao.outputs["AO"], ao_mix.inputs["Value"])
        nt.links.new(half.outputs["Value"], mul.inputs[0])
        nt.links.new(ao_mix.outputs["Result"], mul.inputs[1])
        nt.links.new(camd.outputs["View Z Depth"], dmap.inputs["Value"])
        comb.inputs[0].default_value = (idx + 0.5) / 16.0
        lifted = nt.nodes.new("ShaderNodeMath")
        lifted.operation = "MULTIPLY_ADD"
        lifted.inputs[1].default_value = 1.0 - lift
        lifted.inputs[2].default_value = lift
        nt.links.new(mul.outputs["Value"], lifted.inputs[0])
        nt.links.new(lifted.outputs["Value"], comb.inputs[1])
        nt.links.new(dmap.outputs["Result"], comb.inputs[2])
        nt.links.new(comb.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
        _MATS[name] = mat
    return _MATS


def mat(slot):
    """A slot name, or (slot, shade) for an unlit constant-shade variant."""
    if isinstance(slot, tuple):
        return flat_mat(slot[0], slot[1], len(slot) > 2)
    return _MATS[slot]


# ---------------------------------------------------------------- primitives

def _finish(obj, slot, parent, smooth, bevel=0.0, subsurf=0):
    obj.data.materials.clear()
    obj.data.materials.append(mat(slot))
    if smooth and obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True
    if bevel > 0 and obj.type == "MESH":
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
    if subsurf > 0 and obj.type == "MESH":
        m = obj.modifiers.new("sub", "SUBSURF")
        m.levels = subsurf
        m.render_levels = subsurf
    if parent is not None:
        obj.parent = parent
    return obj


def _place(obj, loc, rot, scale):
    obj.location = Vector(loc)
    obj.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    obj.scale = Vector(scale)


def sphere(slot, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), parent=None, r=1.0, seg=20, rings=12, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=rings)
    obj = bpy.context.active_object
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, smooth)


def ico(slot, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), parent=None, r=1.0, sub=1, smooth=False):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub)
    obj = bpy.context.active_object
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, smooth)


def cyl(slot, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), parent=None, r=1.0, depth=1.0, verts=16, smooth=True, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts)
    obj = bpy.context.active_object
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, smooth, bevel)


def cone(slot, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), parent=None, r1=1.0, r2=0.0, depth=1.0, verts=16, smooth=True):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, vertices=verts)
    obj = bpy.context.active_object
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, smooth)


def box(slot, loc=(0, 0, 0), size=(1, 1, 1), rot=(0, 0, 0), parent=None, bevel=0.0, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    _place(obj, loc, rot, size)
    obj = _finish(obj, slot, parent, smooth, bevel)
    return obj


def torus(slot, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), parent=None, R=1.0, r=0.2, seg=24, mseg=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=mseg)
    obj = bpy.context.active_object
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, True)


def tube(slot, points, radius=0.03, parent=None, taper=None, res=4):
    """A curve with round bevel through points (local to parent)."""
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 2
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS" if len(points) > 2 else "POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        sp.points[i].co = (p[0], p[1], p[2], 1.0)
        if taper is not None:
            sp.points[i].radius = taper[i]
    if len(points) > 2:
        sp.use_endpoint_u = True
        sp.order_u = min(4, len(points))
    obj = bpy.data.objects.new("tube", cu)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat(slot))
    if parent is not None:
        obj.parent = parent
    return obj


def pivot(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = Vector(loc)
    e.rotation_mode = "XYZ"
    if parent is not None:
        e.parent = parent
    return e


def set_rot(obj, rx=0.0, ry=0.0, rz=0.0):
    obj.rotation_euler = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ")


# ---------------------------------------------------------------- mesh kit
# Built straight from vertex lists (much faster than bpy.ops and free of the
# primitive shapes): sweeps for limbs, hair locks and straps, lathes for
# bodies and cloth, flat plates for leaves, fins and wings, and decals
# projected onto a surface for faces.

def mesh_obj(slot, verts, faces, parent=None, smooth=True, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), name="mesh"):
    import bmesh
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    _place(obj, loc, rot, scale)
    return _finish(obj, slot, parent, smooth)


def catmull(pts, res=4):
    """Catmull-Rom points through pts, res samples per segment."""
    P = [Vector(p) for p in pts]
    n = len(P)
    if n < 2 or res <= 1:
        return [p.copy() for p in P]
    out = []
    for i in range(n - 1):
        p1, p2 = P[i], P[i + 1]
        p0 = P[i - 1] if i > 0 else p1 * 2 - p2
        p3 = P[i + 2] if i + 2 < n else p2 * 2 - p1
        for k in range(res):
            t = k / res
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1].copy())
    return out


def _pair(r):
    return (r[0], r[1]) if isinstance(r, (tuple, list)) else (r, r)


def sweep(slot, pts, radii, parent=None, up=(0, 0, 1), ring=8, res=4, cap=True, smooth=True,
          loc=(0, 0, 0), rot=(0, 0, 0), twist=0.0, name="sweep"):
    """A tube through pts with a per-point radius r or (width, thickness).
    The thickness axis follows `up` (parallel-transported), so flattened
    sweeps make ribbons: hair locks, straps, scarf tails. A zero radius
    collapses the ring into a point (tapered tips)."""
    Cs = catmull(pts, res if len(pts) > 2 else 1) if len(pts) > 2 else [Vector(p) for p in pts]
    if len(pts) == 2 and res > 1:
        a, b = Vector(pts[0]), Vector(pts[1])
        Cs = [a.lerp(b, k / res) for k in range(res + 1)]
    m = len(Cs)
    steps = (m - 1) / max(1, len(pts) - 1)
    Rr = []
    for j in range(m):
        u = j / steps
        i = min(int(u), len(pts) - 2)
        f = u - i
        a, b = _pair(radii[i]), _pair(radii[i + 1])
        Rr.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    T = []
    for j in range(m):
        d = Cs[min(j + 1, m - 1)] - Cs[max(j - 1, 0)]
        T.append(d.normalized() if d.length > 1e-9 else Vector((0, 0, 1)))
    upv = Vector(up)
    N = upv - T[0] * upv.dot(T[0])
    if N.length < 1e-6:
        N = T[0].orthogonal()
    N.normalize()
    Ns = [N]
    for j in range(1, m):
        n = T[j - 1].rotation_difference(T[j]) @ Ns[-1]
        n = n - T[j] * n.dot(T[j])
        if n.length < 1e-9:
            n = Ns[-1].copy()
        n.normalize()
        Ns.append(n)
    verts, faces, rings = [], [], []
    for j in range(m):
        rx, ry = Rr[j]
        if rx < 1e-5 and ry < 1e-5:
            rings.append([len(verts)])
            verts.append(Cs[j])
            continue
        Nj = Ns[j]
        Bj = T[j].cross(Nj)
        a0 = twist * j / max(1, m - 1)
        idx = []
        for k in range(ring):
            a = 2 * math.pi * k / ring + a0
            idx.append(len(verts))
            verts.append(Cs[j] + Bj * (rx * math.cos(a)) + Nj * (ry * math.sin(a)))
        rings.append(idx)
    for j in range(m - 1):
        A, B = rings[j], rings[j + 1]
        if len(A) == 1 and len(B) == 1:
            continue
        for k in range(ring):
            if len(A) == 1:
                faces.append((A[0], B[k], B[(k + 1) % ring]))
            elif len(B) == 1:
                faces.append((A[k], A[(k + 1) % ring], B[0]))
            else:
                faces.append((A[k], A[(k + 1) % ring], B[(k + 1) % ring], B[k]))
    if cap:
        if len(rings[0]) > 1:
            faces.append(tuple(reversed(rings[0])))
        if len(rings[-1]) > 1:
            faces.append(tuple(rings[-1]))
    return mesh_obj(slot, verts, faces, parent, smooth, loc, rot, name=name)


def lathe(slot, profile, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), seg=32, res=3,
          folds=0, fold_amp=0.0, fold_from=0.0, phase=0.0, arc=None, hem=0.0, hem_n=0, hem_pow=2.0,
          cap_top=False, cap_bot=False, thick=0.0, smooth=True, shape=None, name="lathe"):
    """Surface of revolution around local Z (0 degrees = front, -Y).

    profile: [(r, z)] or [(rx, ry, z)] from top to bottom. folds: vertical
    cloth folds that grow toward the hem; arc=(a0, a1) in degrees makes an
    open garment (capes, coat fronts) given `thick` by a solidify; hem drops
    hem_n points of the bottom edge (ragged or leafy hems); shape(theta, u)
    is an extra radial multiplier."""
    prof = [(p[0], p[0], p[1]) if len(p) == 2 else tuple(p) for p in profile]
    Pv = catmull(prof, res)
    rows = len(Pv)
    closed = arc is None
    if closed:
        angles = [2 * math.pi * k / seg for k in range(seg)]
    else:
        a0, a1 = math.radians(arc[0]), math.radians(arc[1])
        n = max(3, int(seg * (a1 - a0) / (2 * math.pi)) + 2)
        angles = [a0 + (a1 - a0) * k / (n - 1) for k in range(n)]
    na = len(angles)
    verts = []
    for j, pv in enumerate(Pv):
        u = j / (rows - 1)
        rx, ry, z = pv.x, pv.y, pv.z
        fu = max(0.0, (u - fold_from) / max(1e-6, 1.0 - fold_from))
        for th in angles:
            k = 1.0
            if folds:
                k += fold_amp * (fu ** 1.3) * math.sin(folds * th + phase)
            if shape is not None:
                k *= shape(th, u)
            zz = z
            if hem and hem_n:
                w = (0.5 + 0.5 * math.cos(hem_n * th + phase)) ** hem_pow
                zz -= hem * (u ** 5) * w
            verts.append((math.sin(th) * rx * k, -math.cos(th) * ry * k, zz))
    faces = []
    for j in range(rows - 1):
        for k in range(na if closed else na - 1):
            k2 = (k + 1) % na
            faces.append((j * na + k, j * na + k2, (j + 1) * na + k2, (j + 1) * na + k))
    if closed and cap_top:
        c = len(verts)
        verts.append((0, 0, Pv[0].z))
        for k in range(na):
            faces.append((c, (k + 1) % na, k))
    if closed and cap_bot:
        c = len(verts)
        verts.append((0, 0, Pv[-1].z))
        base = (rows - 1) * na
        for k in range(na):
            faces.append((c, base + k, base + (k + 1) % na))
    obj = mesh_obj(slot, verts, faces, parent, smooth, loc, rot, name=name)
    if thick > 0:
        m = obj.modifiers.new("solid", "SOLIDIFY")
        m.thickness = thick
        m.offset = 0.0
    return obj


def ellipse(n, rx, ry, cx=0.0, cy=0.0, a0=0.0):
    return [(cx + rx * math.cos(a0 + 2 * math.pi * k / n), cy + ry * math.sin(a0 + 2 * math.pi * k / n)) for k in range(n)]


def flat(slot, outline, thick=0.012, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
         bend=0.0, bend_v=0.0, center=None, rings=3, smooth=False, name="flat"):
    """A thin plate from a star-shaped 2D outline [(u, v)] in the local XZ
    plane (Y is the thickness). bend cups it along u (y += bend*u^2) and
    bend_v along v: leaves, fins, feathers, wings, blades."""
    n = len(outline)
    cx = center[0] if center else sum(p[0] for p in outline) / n
    cy = center[1] if center else sum(p[1] for p in outline) / n
    layers = []
    for r in range(rings, 0, -1):
        s = r / rings
        layers.append([(cx + (u - cx) * s, cy + (v - cy) * s) for (u, v) in outline])
    layers.append([(cx, cy)])

    def yb(u, v):
        return bend * u * u + bend_v * v * v

    verts, faces = [], []
    for side in (-1, 1):
        base = len(verts)
        idx = []
        for L in layers:
            row = []
            for (u, v) in L:
                row.append(len(verts))
                verts.append((u, yb(u, v) + side * thick * 0.5, v))
            idx.append(row)
        for li in range(len(idx) - 1):
            A, B = idx[li], idx[li + 1]
            for k in range(n):
                k2 = (k + 1) % n
                if len(B) == 1:
                    f = (A[k], A[k2], B[0])
                else:
                    f = (A[k], A[k2], B[k2], B[k])
                faces.append(f if side > 0 else tuple(reversed(f)))
        if side < 0:
            front_outer = idx[0]
        else:
            back_outer = idx[0]
    for k in range(n):
        k2 = (k + 1) % n
        faces.append((front_outer[k], front_outer[k2], back_outer[k2], back_outer[k]))
    return mesh_obj(slot, verts, faces, parent, smooth, loc, rot, scale, name=name)


def surface_bvh(obj):
    """BVH of a mesh in its parent's space (for decals on that surface)."""
    M = obj.matrix_basis
    verts = [M @ v.co for v in obj.data.vertices]
    return BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in obj.data.polygons])


def decal(slot, bvh, outline, center, direction, up=(0, 0, 1), lift=0.005, parent=None, rings=2, name="decal"):
    """Project a 2D outline (u = viewer's right, v = up, in units) onto the
    surface in `bvh`, seen from `direction` (outward, from `center`)."""
    d = Vector(direction).normalized()
    right = Vector(up).cross(d).normalized()
    upv = d.cross(right).normalized()
    c = Vector(center)
    hit = bvh.ray_cast(c + d * 3.0, -d)
    S = hit[0] if hit[0] is not None else c
    n = len(outline)
    cx = sum(p[0] for p in outline) / n
    cy = sum(p[1] for p in outline) / n
    layers = [[(cx + (u - cx) * r / rings, cy + (v - cy) * r / rings) for (u, v) in outline] for r in range(rings, 0, -1)]
    layers.append([(cx, cy)])
    verts, faces, idx = [], [], []
    for L in layers:
        row = []
        for (u, v) in L:
            o = S + right * u + upv * v + d * 1.0
            h = bvh.ray_cast(o, -d, 3.0)
            if h[0] is None:
                p = S + right * u + upv * v
                nrm = d
            else:
                p, nrm = h[0], h[1]
                if nrm.dot(d) < 0:
                    nrm = -nrm
            row.append(len(verts))
            verts.append(p + nrm * lift)
        idx.append(row)
    for li in range(len(idx) - 1):
        A, B = idx[li], idx[li + 1]
        for k in range(n):
            k2 = (k + 1) % n
            faces.append((A[k], A[k2], B[0]) if len(B) == 1 else (A[k], A[k2], B[k2], B[k]))
    return mesh_obj(slot, verts, faces, parent, True, name=name)


def only_in(obj, where):
    """Tag an object to render only in 'sprite' frames or only in the 'portrait'."""
    obj["only"] = where
    return obj


def render_to(path):
    scene = bpy.context.scene
    if not os.path.isabs(path):
        raise ValueError("render_to needs an absolute path: " + path)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
