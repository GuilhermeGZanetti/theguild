"""Model every environment prop of A Guilda and export them as .glb.

Run: blender -b --factory-startup --python tools/blender/props.py -- --out assets/models/props [--only a,b]

Vertex colours encode data, not colour (FLOAT_COLOR, linear):
  R = (palette slot + 0.5) / 16   -> recoloured per region in the game shader
  G = per-face jitter 0..1        -> subtle faceted variation
  B = ground contact 0..1         -> darker near the ground
"""
import sys
import os
import math
import random
import zlib
import bpy
import bmesh
from mathutils import Vector, Matrix, noise

S = {"stone": 0, "stone_dark": 1, "wood": 2, "wood_dark": 3, "leaf": 4, "leaf2": 5, "leaf3": 6, "metal": 7,
     "cloth": 8, "cloth2": 9, "thatch": 10, "glow": 11, "bone": 12, "earth": 13, "moss": 14, "accent": 15}

rnd = random.Random(1)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _paint(obj, slot, jitter=0.25, height_ref=1.0):
    me = obj.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr = me.color_attributes["Col"]
    me.color_attributes.active_color = attr
    sv = (S[slot] + 0.5) / 16.0
    mw = obj.matrix_world
    for poly in me.polygons:
        j = 0.5 + (rnd.random() - 0.5) * 2 * jitter
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            z = (mw @ v).z
            b = max(0.0, min(1.0, 0.45 + z / max(0.05, height_ref) * 0.8))
            attr.data[li].color = (sv, j, b, 1.0)


def _new(obj, slot, smooth=False, jitter=0.25, height_ref=1.0):
    for p in obj.data.polygons:
        p.use_smooth = smooth
    obj["slot"] = slot
    obj["jit"] = jitter
    obj["href"] = height_ref
    return obj


def cube(slot, loc, size, rot=(0, 0, 0), bevel=0.0, smooth=False, jitter=0.25):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        m = o.modifiers.new("b", "BEVEL")
        m.width = bevel
        m.segments = 1
        bpy.ops.object.modifier_apply(modifier=m.name)
    return _new(o, slot, smooth, jitter)


def cyl(slot, loc, r, depth, verts=8, rot=(0, 0, 0), r2=None, smooth=False, jitter=0.25):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=[math.radians(a) for a in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, vertices=verts, location=loc, rotation=[math.radians(a) for a in rot])
    return _new(bpy.context.active_object, slot, smooth, jitter)


def ico(slot, loc, r, scale=(1, 1, 1), sub=1, rough=0.0, smooth=False, jitter=0.25, seed=0):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=(0, 0, 0))
    o = bpy.context.active_object
    if rough > 0:
        for v in o.data.vertices:
            n = noise.noise(v.co * 3.1 + Vector((seed, seed * 0.7, seed * 1.3)))
            v.co *= 1.0 + n * rough + (rnd.random() - 0.5) * rough * 0.6
    o.scale = scale
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _new(o, slot, smooth, jitter)


def sphere(slot, loc, r, scale=(1, 1, 1), seg=10, rings=6, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=rings, location=(0, 0, 0))
    o = bpy.context.active_object
    o.scale = scale
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _new(o, slot, smooth)


def torus(slot, loc, R, r, rot=(0, 0, 0), seg=12):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=5, location=loc,
                                     rotation=[math.radians(a) for a in rot])
    return _new(bpy.context.active_object, slot, True)


def plane(slot, loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.scale = (size[0], size[1], 1)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _new(o, slot)


def tube(slot, pts, radius, taper=None, res=3):
    cu = bpy.data.curves.new("t", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS" if len(pts) > 2 else "POLY")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p[0], p[1], p[2], 1)
        if taper:
            sp.points[i].radius = taper[i]
    if len(pts) > 2:
        sp.use_endpoint_u = True
        sp.order_u = min(4, len(pts))
    o = bpy.data.objects.new("t", cu)
    bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.active_object
    return _new(o, slot, True)


def finish(objs, name, out):
    """Paint, join and export."""
    for o in objs:
        _paint(o, o["slot"], o["jit"], o["href"])
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    path = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_vertex_color="ACTIVE",
                              export_all_vertex_colors=False, export_materials="NONE", export_yup=True, export_apply=True,
                              export_normals=True, export_texcoords=False)
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        if block.users == 0:
            bpy.data.meshes.remove(block)
    print("[props]", name, flush=True)


# ====================================================================== props
def rock(k, big):
    objs = []
    n = 1 if not big else 2
    for i in range(n + (1 if k == 2 else 0)):
        r = (0.32 if not big else 0.42) * (1 - i * 0.3)
        o = ico("stone" if i == 0 else "stone_dark", (i * 0.28 - 0.12 * n, (i % 2) * 0.18 - 0.08, r * 0.55 * (0.8 if big else 0.7)),
                r, scale=(1.1, 0.95, 0.75 if big else 0.62), sub=2, rough=0.45, seed=k * 3 + i)
        objs.append(o)
    if k == 1:
        objs.append(ico("moss", (0.0, 0.0, 0.38 if big else 0.26), 0.2, scale=(1.2, 1.1, 0.35), sub=1, rough=0.3, seed=k))
    return objs


def boulder(k):
    objs = [ico("stone", (0, 0, 0.5), 0.52, scale=(1.0, 0.95, 1.0), sub=2, rough=0.35, seed=k + 11)]
    objs.append(ico("stone_dark", (0.3, 0.25, 0.22), 0.28, sub=1, rough=0.4, seed=k + 12))
    objs.append(ico("moss", (-0.05, -0.05, 0.9), 0.25, scale=(1.3, 1.2, 0.35), sub=1, rough=0.3, seed=k))
    return objs


def log():
    objs = [cyl("wood", (0, 0, 0.2), 0.2, 0.9, verts=8, rot=(0, 90, 20))]
    objs.append(cyl("wood_dark", (0.45 * math.cos(math.radians(20)), 0.45 * math.sin(math.radians(20)), 0.2), 0.16, 0.02, verts=8, rot=(0, 90, 20)))
    objs.append(cyl("wood_dark", (-0.45 * math.cos(math.radians(20)), -0.45 * math.sin(math.radians(20)), 0.2), 0.16, 0.02, verts=8, rot=(0, 90, 20)))
    objs.append(ico("moss", (0.1, 0.0, 0.36), 0.14, scale=(1.5, 1, 0.4), sub=1, rough=0.3))
    return objs


def stump():
    objs = [cyl("wood", (0, 0, 0.2), 0.26, 0.4, verts=9, r2=0.22)]
    objs.append(cyl("wood_dark", (0, 0, 0.41), 0.22, 0.02, verts=9))
    for a in (0, 120, 240):
        objs.append(cyl("wood", (math.cos(math.radians(a)) * 0.26, math.sin(math.radians(a)) * 0.26, 0.06), 0.08, 0.3, verts=5,
                        rot=(0, 70, a)))
    objs.append(ico("leaf3", (0.12, -0.18, 0.44), 0.06, sub=1))
    return objs


def crate(stack=False):
    objs = [cube("wood", (0, 0, 0.21), (0.46, 0.46, 0.42), bevel=0.02)]
    for dz in (0.03, 0.39):
        objs.append(cube("wood_dark", (0, 0, dz), (0.5, 0.5, 0.05)))
    objs.append(cube("wood_dark", (0, -0.235, 0.21), (0.06, 0.02, 0.42)))
    if stack:
        objs.append(cube("wood", (0.06, 0.03, 0.62), (0.4, 0.4, 0.38), rot=(0, 0, 15), bevel=0.02))
        objs.append(cube("wood_dark", (0.06, 0.03, 0.8), (0.44, 0.44, 0.04), rot=(0, 0, 15)))
        objs.append(cube("wood", (0.3, 0.3, 0.16), (0.3, 0.3, 0.3), rot=(0, 0, 30), bevel=0.02))
    return objs


def barrel():
    objs = [cyl("wood", (0, 0, 0.26), 0.22, 0.52, verts=10, smooth=True)]
    objs.append(cyl("wood", (0, 0, 0.26), 0.25, 0.3, verts=10, smooth=True))
    for z in (0.1, 0.42):
        objs.append(cyl("metal", (0, 0, z), 0.235, 0.04, verts=10))
    objs.append(cyl("wood_dark", (0, 0, 0.525), 0.2, 0.01, verts=10))
    return objs


def fence():
    objs = []
    for x in (-0.4, 0.0, 0.4):
        objs.append(cube("wood", (x, 0, 0.3), (0.08, 0.08, 0.6)))
    for z in (0.22, 0.46):
        objs.append(cube("wood_dark", (0, 0, z), (0.95, 0.05, 0.07), rot=(0, rnd.uniform(-4, 4), 0)))
    return objs


def canopy(slot_a, slot_b, center, size, blobs=5, seed=0, flat=0.8):
    objs = []
    for i in range(blobs):
        a = i / blobs * math.tau + seed
        rr = size * (0.45 if i else 0.0)
        c = (center[0] + math.cos(a) * rr, center[1] + math.sin(a) * rr, center[2] + (rnd.random() - 0.3) * size * 0.4 + (0.2 * size if i == 0 else 0))
        r = size * (0.72 if i == 0 else rnd.uniform(0.45, 0.6))
        objs.append(ico(slot_a if (i % 2 == 0) else slot_b, c, r, scale=(1, 1, flat), sub=2, rough=0.25, smooth=True, seed=seed + i, jitter=0.15))
    return objs


def tree(kind, k):
    objs = []
    if kind == "palm":
        pts = [(0, 0, 0), (0.1, 0.05, 0.7), (0.3, 0.1, 1.4), (0.45, 0.1, 1.9)]
        objs.append(tube("wood", pts, 0.1, taper=[1.4, 1.0, 0.9, 0.8]))
        top = Vector((0.45, 0.1, 1.95))
        for i in range(7):
            a = i / 7 * math.tau
            d = Vector((math.cos(a), math.sin(a), 0))
            objs.append(tube("leaf" if i % 2 else "leaf2", [top, top + d * 0.45 + Vector((0, 0, 0.15)), top + d * 0.9 - Vector((0, 0, 0.25))], 0.07,
                             taper=[0.6, 1.2, 0.3]))
        objs.append(ico("wood_dark", tuple(top), 0.12, sub=1))
        return objs
    if kind == "dead":
        objs.append(cyl("wood", (0, 0, 0.6), 0.14, 1.2, verts=7, r2=0.07))
        for i, (a, z, L) in enumerate([(30, 0.8, 0.5), (160, 1.0, 0.45), (260, 0.65, 0.4), (90, 1.15, 0.35)]):
            d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0.7))
            objs.append(tube("wood", [(0, 0, z), tuple(Vector((0, 0, z)) + d * L * 0.5), tuple(Vector((0, 0, z)) + d * L + Vector((0, 0, 0.12)))], 0.035,
                             taper=[1.0, 0.8, 0.4]))
        for a in (0, 130, 250):
            objs.append(cyl("wood_dark", (math.cos(math.radians(a)) * 0.14, math.sin(math.radians(a)) * 0.14, 0.05), 0.06, 0.28, verts=5, rot=(0, 70, a)))
        return objs
    h = {"oak": 1.1, "jungle": 1.35, "autumn": 1.2}[kind]
    bend = (rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12))
    objs.append(tube("wood", [(0, 0, 0), (bend[0] * 0.5, bend[1] * 0.5, h * 0.5), (bend[0], bend[1], h)], 0.13, taper=[1.4, 1.0, 0.8]))
    for a in (20, 140, 260):
        objs.append(cyl("wood_dark", (math.cos(math.radians(a)) * 0.15, math.sin(math.radians(a)) * 0.15, 0.06), 0.07, 0.3, verts=5, rot=(0, 72, a)))
    size = {"oak": 0.62, "jungle": 0.7, "autumn": 0.66}[kind]
    objs += canopy("leaf", "leaf2", (bend[0], bend[1], h + size * 0.55), size, blobs=5 if kind != "jungle" else 6, seed=k * 1.7)
    if kind == "jungle":
        for i in range(3):
            a = i * 2.1
            objs.append(tube("leaf2", [(math.cos(a) * 0.4, math.sin(a) * 0.4, h + 0.3), (math.cos(a) * 0.5, math.sin(a) * 0.5, h - 0.2),
                                       (math.cos(a) * 0.48, math.sin(a) * 0.52, h - 0.7)], 0.02))
    if kind == "oak" and k == 1:
        for i in range(4):
            a = i * 1.7
            objs.append(ico("leaf3", (math.cos(a) * 0.45, math.sin(a) * 0.45, h + 0.5 + (i % 2) * 0.2), 0.06, sub=1))
    return objs


def bush(k):
    objs = canopy("leaf", "leaf2", (0, 0, 0.22), 0.3, blobs=3, seed=k * 2.3, flat=0.7)
    if k == 1:
        for i in range(3):
            objs.append(ico("leaf3", (math.cos(i * 2.1) * 0.22, math.sin(i * 2.1) * 0.22, 0.34), 0.05, sub=1))
    return objs


def wall(broken):
    objs = []
    h = 1.1 if not broken else 0.55
    for row in range(int(h / 0.22) + 1):
        z = row * 0.22 + 0.11
        if z > h + 0.05:
            break
        off = 0.12 if row % 2 else 0.0
        x = -0.5 + off
        while x < 0.5:
            w = rnd.uniform(0.22, 0.34)
            if broken and row >= 1 and rnd.random() < 0.3 + 0.2 * row:
                x += w
                continue
            cx = min(x + w / 2, 0.5 - 0.06)
            objs.append(cube("stone" if rnd.random() < 0.7 else "stone_dark", (cx, rnd.uniform(-0.02, 0.02), z), (w - 0.02, 0.36, 0.2), bevel=0.015))
            x += w
    objs.append(ico("moss", (rnd.uniform(-0.3, 0.3), 0.0, h * 0.8), 0.14, scale=(1.4, 1.3, 0.5), sub=1, rough=0.3))
    if broken:
        for i in range(3):
            objs.append(ico("stone", (rnd.uniform(-0.4, 0.4), rnd.uniform(0.25, 0.4), 0.06), 0.08, sub=1, rough=0.3, seed=i))
    return objs


def pillar(broken):
    objs = [cube("stone", (0, 0, 0.06), (0.5, 0.5, 0.12), bevel=0.02)]
    h = 1.4 if not broken else rnd.uniform(0.45, 0.7)
    objs.append(cyl("stone", (0, 0, 0.12 + h / 2), 0.17, h, verts=10, smooth=False))
    if not broken:
        objs.append(cube("stone", (0, 0, 0.12 + h + 0.05), (0.46, 0.46, 0.1), bevel=0.02))
    else:
        objs.append(cyl("stone_dark", (0.35, 0.1, 0.12), 0.16, 0.5, verts=10, rot=(90, 0, 40)))
    objs.append(ico("moss", (0.05, 0, 0.12 + h * 0.7), 0.1, scale=(1.8, 1.5, 0.4), sub=1, rough=0.3))
    return objs


def statue():
    objs = [cube("stone_dark", (0, 0, 0.12), (0.6, 0.6, 0.24), bevel=0.03)]
    objs.append(cyl("stone", (0, 0, 0.62), 0.2, 0.75, verts=8, r2=0.14))
    objs.append(ico("stone", (0, 0, 1.12), 0.2, sub=2, smooth=True))
    objs.append(tube("stone", [(-0.18, 0, 0.9), (-0.3, -0.1, 0.7), (-0.25, -0.2, 0.55)], 0.06))
    objs.append(tube("stone", [(0.18, 0, 0.9), (0.28, -0.12, 1.1), (0.2, -0.18, 1.35)], 0.06))
    objs.append(ico("moss", (0.0, 0.1, 1.25), 0.14, scale=(1.4, 1.2, 0.5), sub=1, rough=0.3))
    return objs


def shrine():
    objs = [cube("stone", (0, 0, 0.1), (0.55, 0.55, 0.2), bevel=0.02)]
    objs.append(cube("stone", (0, 0, 0.35), (0.22, 0.22, 0.3)))
    objs.append(cube("stone_dark", (0, 0, 0.56), (0.4, 0.4, 0.12)))
    objs.append(cube("glow", (0, 0, 0.7), (0.2, 0.2, 0.16)))
    objs.append(cyl("stone", (0, 0, 0.88), 0.34, 0.2, verts=4, r2=0.04, rot=(0, 0, 45)))
    objs.append(ico("stone", (0, 0, 1.0), 0.06, sub=1))
    objs.append(ico("moss", (0.1, 0.1, 0.9), 0.1, scale=(1.4, 1.4, 0.4), sub=1, rough=0.3))
    return objs


def lantern_post():
    objs = [cyl("wood_dark", (0, 0, 0.7), 0.05, 1.4, verts=6)]
    objs.append(tube("wood_dark", [(0, 0, 1.35), (0.18, 0, 1.42), (0.3, 0, 1.36)], 0.025))
    objs.append(cube("metal", (0.3, 0, 1.24), (0.16, 0.16, 0.03)))
    objs.append(cube("glow", (0.3, 0, 1.13), (0.11, 0.11, 0.16)))
    objs.append(cube("metal", (0.3, 0, 1.02), (0.16, 0.16, 0.03)))
    objs.append(cube("stone", (0, 0, 0.05), (0.2, 0.2, 0.1)))
    return objs


def post():
    objs = [cyl("wood", (0, 0, 0.4), 0.09, 0.8, verts=7)]
    objs.append(torus("cloth2", (0, 0, 0.55), 0.1, 0.025))
    objs.append(tube("cloth2", [(0.09, 0, 0.55), (0.3, 0.05, 0.35), (0.5, 0.0, 0.5)], 0.02))
    return objs


def boat():
    objs = []
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=12, ring_count=6)
    o = bpy.context.active_object
    o.scale = (0.45, 1.1, 0.35)
    bpy.ops.object.transform_apply(scale=True)
    for v in o.data.vertices:
        if v.co.z > 0.05:
            v.co.z = 0.05 + (v.co.z - 0.05) * 0.1
    o.location = (0, 0, 0.3)
    bpy.ops.object.transform_apply(location=True)
    o.rotation_euler = (0, math.radians(18), math.radians(10))
    bpy.ops.object.transform_apply(rotation=True)
    objs.append(_new(o, "wood"))
    objs.append(cube("wood_dark", (0, 0, 0.36), (0.6, 0.08, 0.04), rot=(0, 18, 10)))
    objs.append(cube("wood_dark", (0, 0.5, 0.4), (0.5, 0.08, 0.04), rot=(0, 18, 10)))
    objs.append(tube("wood", [(0.1, -0.2, 0.3), (0.2, -0.3, 1.0)], 0.04))
    return objs


def hut():
    objs = []
    for (x, y) in ((-0.8, -0.8), (0.8, -0.8), (-0.8, 0.8), (0.8, 0.8)):
        objs.append(cyl("wood_dark", (x, y, 0.3), 0.07, 0.6, verts=6))
    objs.append(cube("wood", (0, 0, 0.62), (2.0, 2.0, 0.08)))
    objs.append(cyl("cloth2", (0, 0, 1.05), 0.8, 0.8, verts=10))
    objs.append(cube("wood_dark", (0, -0.8, 0.95), (0.34, 0.06, 0.55)))
    objs.append(cyl("thatch", (0, 0, 1.75), 1.2, 0.8, verts=10, r2=0.05))
    objs.append(torus("thatch", (0, 0, 1.4), 1.12, 0.08, seg=14))
    for a in range(0, 360, 60):
        objs.append(cube("accent", (math.cos(math.radians(a)) * 1.02, math.sin(math.radians(a)) * 1.02, 1.5), (0.16, 0.03, 0.14),
                         rot=(0, 0, a + 90)))
    objs.append(cube("glow", (0.55, -0.62, 1.05), (0.18, 0.04, 0.16)))
    return [o for o in objs]


def house():
    objs = []
    W, D = 2.9, 1.9
    objs.append(cube("stone", (0, 0, 0.12), (W + 0.1, D + 0.1, 0.24), bevel=0.02))
    objs.append(cube("cloth2", (0, 0, 0.8), (W, D, 1.2)))
    for x in (-W / 2, 0, W / 2):
        objs.append(cube("wood_dark", (x, -D / 2, 0.8), (0.12, 0.08, 1.2)))
        objs.append(cube("wood_dark", (x, D / 2, 0.8), (0.12, 0.08, 1.2)))
    objs.append(cube("wood_dark", (0, -D / 2, 1.38), (W, 0.1, 0.1)))
    objs.append(cube("wood_dark", (-0.7, -D / 2 - 0.02, 0.55), (0.42, 0.06, 0.7)))
    objs.append(cube("glow", (0.7, -D / 2 - 0.02, 0.9), (0.32, 0.04, 0.28)))
    objs.append(cube("wood_dark", (0.7, -D / 2 - 0.04, 0.9), (0.36, 0.03, 0.04)))
    bpy.ops.mesh.primitive_cube_add(size=1)
    roof = bpy.context.active_object
    roof.scale = (W + 0.4, D + 0.5, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    for v in roof.data.vertices:
        if v.co.z > 0:
            v.co.y = 0.0
            v.co.z = 0.7
        else:
            v.co.z = 0.0
    roof.location = (0, 0, 1.4)
    bpy.ops.object.transform_apply(location=True)
    objs.append(_new(roof, "accent"))
    objs.append(cube("stone_dark", (W / 2 - 0.4, 0.3, 2.1), (0.25, 0.25, 0.6)))
    return objs


def stall():
    objs = []
    for (x, y) in ((-0.42, -0.35), (0.42, -0.35), (-0.42, 0.35), (0.42, 0.35)):
        objs.append(cyl("wood_dark", (x, y, 0.5), 0.035, 1.0, verts=5))
    objs.append(cube("wood", (0, 0, 0.42), (0.9, 0.7, 0.08)))
    objs.append(cube("cloth", (0, 0.05, 1.02), (1.0, 0.85, 0.05), rot=(10, 0, 0)))
    for i in range(4):
        objs.append(ico(["leaf3", "accent", "leaf", "earth"][i], (-0.3 + i * 0.2, -0.15, 0.52), 0.07, sub=1))
    objs.append(barrel_small((0.3, 0.2, 0.46)))
    return objs


def barrel_small(loc):
    return cyl("wood", loc, 0.1, 0.12, verts=8)


def cart():
    objs = [cube("wood", (0, 0, 0.45), (0.6, 0.9, 0.08))]
    for s in (-1, 1):
        objs.append(cube("wood", (s * 0.3, 0, 0.58), (0.04, 0.9, 0.2)))
        objs.append(cyl("wood_dark", (s * 0.36, 0.1, 0.28), 0.26, 0.06, verts=10, rot=(0, 90, 0)))
    objs.append(cube("wood", (0, -0.4, 0.58), (0.6, 0.04, 0.2)))
    objs.append(tube("wood", [(0, 0.45, 0.45), (0, 0.9, 0.3)], 0.03))
    for i in range(3):
        objs.append(ico("earth", (rnd.uniform(-0.15, 0.15), rnd.uniform(-0.25, 0.25), 0.62), 0.15, sub=1, rough=0.2))
    return objs


def well():
    objs = [cyl("stone", (0, 0, 0.25), 0.4, 0.5, verts=10)]
    objs.append(cyl("stone_dark", (0, 0, 0.51), 0.3, 0.02, verts=10))
    for s in (-1, 1):
        objs.append(cube("wood_dark", (s * 0.36, 0, 0.8), (0.07, 0.07, 0.6)))
    objs.append(cyl("wood", (0, 0, 1.08), 0.05, 0.8, verts=6, rot=(0, 90, 0)))
    objs.append(cyl("thatch", (0, 0, 1.25), 0.55, 0.3, verts=4, r2=0.05, rot=(0, 0, 45)))
    objs.append(cube("wood", (0.05, 0, 0.8), (0.12, 0.12, 0.14)))
    return objs


def coral():
    objs = []
    for i in range(5):
        a = i * 1.3
        pts = [(math.cos(a) * 0.1, math.sin(a) * 0.1, 0), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.2 + i * 0.03),
               (math.cos(a) * 0.25, math.sin(a) * 0.3, 0.35 + i * 0.05)]
        objs.append(tube("leaf3" if i % 2 else "accent", pts, 0.05, taper=[1.2, 1.0, 0.7]))
    objs.append(ico("stone", (0, 0, 0.05), 0.22, scale=(1.2, 1, 0.4), sub=1, rough=0.3))
    return objs


def tent():
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.7, radius2=0.0, depth=0.9, location=(0, 0, 0.45), rotation=(0, 0, math.radians(45)))
    o = bpy.context.active_object
    o.scale = (1.0, 1.35, 1.0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    objs = [_new(o, "cloth2")]
    objs.append(cube("wood_dark", (0, -0.46, 0.25), (0.25, 0.04, 0.45)))
    objs.append(cyl("wood_dark", (0, 0, 0.5), 0.02, 1.1, verts=4))
    objs.append(ico("accent", (0.2, -0.5, 0.45), 0.06, sub=1))
    return objs


def campfire():
    objs = []
    for a in range(0, 360, 45):
        objs.append(ico("stone", (math.cos(math.radians(a)) * 0.28, math.sin(math.radians(a)) * 0.28, 0.05), 0.08, sub=1, rough=0.3))
    for a in (0, 60, 120):
        objs.append(cyl("wood", (0, 0, 0.1), 0.04, 0.5, verts=5, rot=(0, 75, a)))
    objs.append(ico("glow", (0, 0, 0.18), 0.12, scale=(1, 1, 1.6), sub=1, rough=0.3))
    return objs


def signpost():
    objs = [cyl("wood", (0, 0, 0.55), 0.05, 1.1, verts=6)]
    objs.append(cube("wood_dark", (0.18, 0, 0.9), (0.45, 0.04, 0.14), rot=(0, 0, 10)))
    objs.append(cube("wood_dark", (-0.12, 0, 0.7), (0.4, 0.04, 0.12), rot=(0, 0, -25)))
    return objs


def doorframe():
    objs = [cube("stone", (0, 0, 0.05), (0.9, 0.3, 0.1))]
    for s in (-1, 1):
        objs.append(cube("wood_dark", (s * 0.34, 0, 0.7), (0.12, 0.14, 1.3)))
    objs.append(cube("wood_dark", (0, 0, 1.36), (0.9, 0.16, 0.12)))
    objs.append(cube("wood", (0.1, -0.1, 0.62), (0.52, 0.06, 1.1), rot=(0, 0, 35)))
    objs.append(cube("metal", (0.25, -0.18, 0.62), (0.06, 0.03, 0.06), rot=(0, 0, 35)))
    return objs


def bell():
    objs = []
    bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.5, radius2=0.28, depth=0.8, location=(0, 0, 0.5))
    o = bpy.context.active_object
    objs.append(_new(o, "metal", smooth=True))
    objs.append(torus("metal", (0, 0, 0.12), 0.5, 0.06, seg=16))
    objs.append(sphere("metal", (0, 0, 0.92), 0.28, scale=(1, 1, 0.5)))
    objs.append(cube("stone_dark", (0.15, -0.3, 0.5), (0.05, 0.3, 0.6), rot=(0, 20, 0)))
    objs.append(tube("metal", [(0, 0, 1.05), (0, 0, 1.2)], 0.05))
    objs.append(cube("wood_dark", (0.5, 0.3, 0.06), (0.8, 0.12, 0.12), rot=(0, 0, 30)))
    o = bpy.context.active_object
    return objs


def mushrooms():
    objs = []
    for i in range(4):
        x, y = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(0.1, 0.28)
        objs.append(cyl("bone", (x, y, h / 2), 0.03, h, verts=5))
        objs.append(sphere("accent" if i % 2 else "leaf3", (x, y, h), 0.09, scale=(1, 1, 0.5), seg=8, rings=4))
    return objs


def reeds():
    objs = []
    for i in range(7):
        x, y = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(0.4, 0.8)
        objs.append(tube("leaf2", [(x, y, 0), (x + rnd.uniform(-0.1, 0.1), y, h)], 0.018))
        if i % 3 == 0:
            objs.append(cyl("wood_dark", (x + 0.02, y, h - 0.05), 0.03, 0.14, verts=5))
    return objs


def cactus():
    objs = [cyl("leaf2", (0, 0, 0.45), 0.13, 0.9, verts=8, smooth=True)]
    objs.append(tube("leaf2", [(0.1, 0, 0.4), (0.3, 0, 0.45), (0.3, 0, 0.7)], 0.07))
    objs.append(tube("leaf2", [(-0.1, 0, 0.55), (-0.26, 0, 0.6), (-0.26, 0, 0.8)], 0.06))
    objs.append(ico("leaf3", (0, 0, 0.92), 0.05, sub=1))
    return objs


def pots():
    objs = []
    for i, (x, y, s) in enumerate([(-0.15, 0.05, 1.0), (0.18, -0.1, 0.8), (0.05, 0.25, 0.65)]):
        objs.append(sphere("earth", (x, y, 0.18 * s), 0.18 * s, scale=(1, 1, 1.1), seg=10, rings=6))
        objs.append(cyl("earth", (x, y, 0.38 * s), 0.07 * s, 0.1 * s, verts=8))
        objs.append(torus("accent", (x, y, 0.2 * s), 0.17 * s, 0.015))
    return objs


def arch():
    objs = []
    for x in (-1.0, 1.0):
        for z in range(6):
            objs.append(cube("stone" if z % 2 else "stone_dark", (x + rnd.uniform(-0.02, 0.02), 0, 0.15 + z * 0.28), (0.5, 0.5, 0.26), bevel=0.02))
    for i in range(9):
        a = math.radians(180 - i * 22.5)
        objs.append(cube("stone", (math.cos(a) * 1.0, 0, 1.75 + math.sin(a) * 0.7), (0.34, 0.5, 0.26), rot=(0, -(90 - i * 22.5) + 90, 0), bevel=0.02))
    objs.append(ico("moss", (-0.9, 0, 1.9), 0.16, scale=(1.5, 1.2, 0.5), sub=1, rough=0.3))
    return objs


def lectern():
    objs = [cyl("wood_dark", (0, 0, 0.4), 0.06, 0.8, verts=6)]
    objs.append(cube("wood", (0, 0, 0.82), (0.45, 0.35, 0.06), rot=(-20, 0, 0)))
    objs.append(cube("bone", (0, -0.02, 0.87), (0.38, 0.28, 0.04), rot=(-20, 0, 0)))
    objs.append(cube("wood_dark", (0, 0, 0.04), (0.35, 0.35, 0.08)))
    return objs


def chest():
    objs = [cube("wood", (0, 0, 0.17), (0.55, 0.36, 0.34), bevel=0.02)]
    objs.append(cyl("wood", (0, 0, 0.34), 0.18, 0.55, verts=8, rot=(0, 90, 0)))
    for x in (-0.2, 0.2):
        objs.append(cube("metal", (x, 0, 0.26), (0.05, 0.38, 0.44)))
    objs.append(cube("glow", (0, -0.19, 0.3), (0.08, 0.03, 0.08)))
    return objs


def cache():
    objs = [ico("cloth2", (0, 0, 0.22), 0.25, scale=(1, 1, 0.9), sub=2, rough=0.15, smooth=True)]
    objs.append(tube("cloth2", [(0, 0, 0.42), (0, 0, 0.52), (0.05, 0, 0.58)], 0.06))
    objs.append(torus("accent", (0, 0, 0.44), 0.07, 0.02))
    objs.append(crate()[0])
    objs[-1].location = (0.3, 0.2, 0)
    return objs


def page():
    objs = [cube("bone", (0, 0, 0.6), (0.3, 0.02, 0.4), rot=(10, 0, 15))]
    objs.append(cube("glow", (0, 0, 0.6), (0.12, 0.03, 0.18), rot=(10, 0, 15)))
    objs.append(ico("stone", (0, 0, 0.06), 0.2, scale=(1, 1, 0.3), sub=1, rough=0.3))
    return objs


def stake():
    objs = [cyl("wood", (0, 0.2, 0.55), 0.06, 1.1, verts=6)]
    objs.append(torus("cloth2", (0, 0.2, 0.6), 0.09, 0.025))
    objs.append(torus("cloth2", (0, 0.2, 0.4), 0.09, 0.025))
    return objs


# ---------------- hub (tavern interior)
def bar_counter():
    objs = [cube("wood", (0, 0, 0.45), (3.0, 0.6, 0.9), bevel=0.02)]
    objs.append(cube("wood_dark", (0, 0, 0.93), (3.1, 0.72, 0.08)))
    for x in (-1.2, -0.4, 0.4, 1.2):
        objs.append(cube("wood_dark", (x, -0.31, 0.45), (0.06, 0.02, 0.8)))
    for i in range(6):
        objs.append(cyl(["leaf", "accent", "glow", "leaf3", "metal", "earth"][i], (-1.2 + i * 0.45, 0.1, 1.07), 0.05, 0.2, verts=6))
    return objs


def table():
    objs = [cyl("wood", (0, 0, 0.62), 0.5, 0.07, verts=10)]
    objs.append(cyl("wood_dark", (0, 0, 0.3), 0.07, 0.6, verts=6))
    objs.append(cyl("wood_dark", (0, 0, 0.03), 0.28, 0.06, verts=8))
    objs.append(cyl("metal", (0.15, 0.1, 0.72), 0.06, 0.14, verts=6))
    objs.append(cyl("glow", (-0.15, -0.05, 0.72), 0.04, 0.12, verts=6))
    return objs


def stool():
    objs = [cyl("wood", (0, 0, 0.4), 0.18, 0.06, verts=8)]
    for a in (0, 120, 240):
        objs.append(cyl("wood_dark", (math.cos(math.radians(a)) * 0.11, math.sin(math.radians(a)) * 0.11, 0.19), 0.025, 0.4, verts=4, rot=(8, 0, a)))
    return objs


def bench():
    objs = [cube("wood", (0, 0, 0.4), (1.4, 0.35, 0.07))]
    for x in (-0.55, 0.55):
        objs.append(cube("wood_dark", (x, 0, 0.19), (0.08, 0.3, 0.38)))
    return objs


def fireplace():
    objs = [cube("stone", (0, 0, 0.8), (1.8, 0.6, 1.6), bevel=0.03)]
    objs.append(cube("stone_dark", (0, -0.2, 0.45), (1.0, 0.4, 0.8)))
    objs.append(cube("glow", (0, -0.25, 0.25), (0.7, 0.3, 0.35)))
    objs.append(cube("wood_dark", (0, -0.35, 1.0), (2.0, 0.3, 0.12)))
    objs.append(cube("stone", (0, 0.05, 2.1), (1.2, 0.5, 1.0)))
    for x in (-0.6, 0.6):
        objs.append(cyl("metal", (x, -0.4, 1.15), 0.05, 0.14, verts=6))
    return objs


def shelf():
    objs = [cube("wood_dark", (0, 0, 0.9), (1.4, 0.35, 1.8))]
    for z in (0.4, 0.9, 1.4):
        objs.append(cube("wood", (0, -0.05, z), (1.35, 0.35, 0.05)))
        for i in range(5):
            objs.append(cyl(["leaf", "accent", "leaf3", "metal", "earth", "glow"][(i + int(z * 3)) % 6], (-0.5 + i * 0.25, -0.08, z + 0.12), 0.05,
                            0.2, verts=6))
    return objs


def bookshelf():
    objs = [cube("wood_dark", (0, 0, 1.0), (1.4, 0.35, 2.0))]
    for z in (0.35, 0.85, 1.35, 1.8):
        objs.append(cube("wood", (0, -0.05, z - 0.14), (1.35, 0.35, 0.04)))
        x = -0.6
        while x < 0.6:
            w = rnd.uniform(0.05, 0.1)
            h = rnd.uniform(0.2, 0.3)
            objs.append(cube(["accent", "cloth", "leaf2", "cloth2", "earth"][rnd.randrange(5)], (x, -0.08, z - 0.12 + h / 2), (w, 0.26, h)))
            x += w + 0.01
    return objs


def quest_board():
    objs = [cube("wood", (0, 0, 1.2), (1.6, 0.08, 1.1))]
    objs.append(cube("wood_dark", (0, 0, 1.2), (1.7, 0.06, 1.2)))
    for i in range(7):
        objs.append(cube("bone", (rnd.uniform(-0.6, 0.6), -0.06, rnd.uniform(0.85, 1.55)), (0.26, 0.02, 0.3), rot=(0, rnd.uniform(-10, 10), 0)))
    for x in (-0.8, 0.8):
        objs.append(cube("wood_dark", (x, 0, 0.6), (0.1, 0.1, 1.2)))
    objs.append(cube("accent", (0, -0.07, 1.72), (0.6, 0.02, 0.16)))
    return objs


def memorial_wall():
    objs = [cube("stone", (0, 0, 0.9), (2.2, 0.35, 1.8), bevel=0.04)]
    objs.append(cube("stone_dark", (0, 0, 1.85), (2.4, 0.45, 0.16)))
    for r in range(4):
        for c in range(5):
            objs.append(cube("metal", (-0.8 + c * 0.4, -0.19, 0.4 + r * 0.35), (0.3, 0.02, 0.18)))
    for x in (-0.9, 0.9):
        objs.append(cyl("glow", (x, -0.3, 0.12), 0.05, 0.16, verts=6))
    return objs


def dummy():
    objs = [cyl("wood_dark", (0, 0, 0.6), 0.04, 1.2, verts=5)]
    objs.append(cyl("thatch", (0, 0, 0.8), 0.18, 0.5, verts=8, smooth=True))
    objs.append(sphere("thatch", (0, 0, 1.15), 0.15))
    objs.append(cyl("wood_dark", (0, 0, 0.9), 0.03, 0.8, verts=4, rot=(0, 90, 0)))
    objs.append(cube("stone", (0, 0, 0.05), (0.4, 0.4, 0.1)))
    return objs


def anvil():
    objs = [cube("wood_dark", (0, 0, 0.2), (0.4, 0.4, 0.4))]
    objs.append(cube("metal", (0, 0, 0.5), (0.25, 0.5, 0.2)))
    objs.append(cube("metal", (0, 0, 0.64), (0.3, 0.7, 0.1)))
    objs.append(cyl("metal", (0, 0.4, 0.64), 0.08, 0.2, verts=6, r2=0.0, rot=(-90, 0, 0)))
    objs.append(cube("glow", (0.5, 0.0, 0.35), (0.35, 0.35, 0.25)))
    objs.append(cube("stone", (0.5, 0.0, 0.15), (0.5, 0.5, 0.3)))
    return objs


def bed():
    objs = [cube("wood_dark", (0, 0, 0.2), (0.8, 1.6, 0.3))]
    objs.append(cube("cloth2", (0, 0.1, 0.4), (0.72, 1.3, 0.14), bevel=0.03))
    objs.append(cube("bone", (0, -0.6, 0.45), (0.5, 0.25, 0.12), bevel=0.03))
    objs.append(cube("wood_dark", (0, 0.8, 0.45), (0.8, 0.08, 0.6)))
    return objs


def weapon_rack():
    objs = [cube("wood_dark", (0, 0, 0.1), (1.2, 0.3, 0.08))]
    objs.append(cube("wood_dark", (0, 0, 0.9), (1.2, 0.08, 0.08)))
    for x in (-0.55, 0.55):
        objs.append(cube("wood_dark", (x, 0, 0.5), (0.08, 0.08, 1.0)))
    for i in range(4):
        objs.append(cube("metal", (-0.4 + i * 0.27, -0.04, 0.55), (0.05, 0.02, 0.8), rot=(0, 8, 0)))
    return objs


def chandelier():
    objs = [torus("metal", (0, 0, 0), 0.5, 0.04, seg=16)]
    for a in range(0, 360, 60):
        objs.append(cyl("bone", (math.cos(math.radians(a)) * 0.5, math.sin(math.radians(a)) * 0.5, 0.08), 0.03, 0.12, verts=5))
        objs.append(ico("glow", (math.cos(math.radians(a)) * 0.5, math.sin(math.radians(a)) * 0.5, 0.2), 0.04, sub=1))
    objs.append(cyl("metal", (0, 0, 0.6), 0.015, 1.2, verts=4))
    return objs


def banner():
    objs = [cyl("wood_dark", (0, 0, 2.1), 0.03, 1.2, verts=5, rot=(0, 90, 0))]
    objs.append(cube("accent", (0, 0.02, 1.55), (0.9, 0.03, 1.05)))
    objs.append(cube("glow", (0, -0.0, 1.62), (0.32, 0.04, 0.32), rot=(0, 45, 0)))
    objs.append(cube("trim" if False else "bone", (0, 0.0, 1.62), (0.18, 0.05, 0.18), rot=(0, 45, 0)))
    return objs


def rug():
    return [cube("accent", (0, 0, 0.01), (2.2, 1.4, 0.02)), cube("cloth2", (0, 0, 0.02), (1.8, 1.0, 0.02))]


def door():
    objs = [cube("wood_dark", (0, 0, 1.0), (1.2, 0.2, 2.0))]
    objs.append(cube("wood", (0, -0.05, 0.95), (0.95, 0.12, 1.8)))
    objs.append(cube("metal", (0.3, -0.12, 0.95), (0.08, 0.04, 0.08)))
    return objs


def boarded():
    objs = [cube("wood_dark", (0, 0, 1.0), (1.3, 0.1, 2.0))]
    for z in (0.5, 1.0, 1.5):
        objs.append(cube("wood", (0, -0.08, z), (1.4, 0.06, 0.16), rot=(0, rnd.uniform(-12, 12), 0)))
    return objs


def window():
    objs = [cube("wood_dark", (0, 0, 1.4), (1.0, 0.14, 1.0))]
    objs.append(cube("glow", (0, -0.03, 1.4), (0.8, 0.1, 0.8)))
    objs.append(cube("wood_dark", (0, -0.08, 1.4), (0.06, 0.06, 0.85)))
    objs.append(cube("wood_dark", (0, -0.08, 1.4), (0.85, 0.06, 0.06)))
    return objs


def emblem():
    objs = [cyl("wood_dark", (0, 0, 0), 0.5, 0.08, verts=16, rot=(90, 0, 0))]
    objs.append(cyl("metal", (0, -0.05, 0), 0.4, 0.04, verts=16, rot=(90, 0, 0)))
    objs.append(cube("accent", (0, -0.08, 0.0), (0.3, 0.03, 0.3), rot=(0, 45, 0)))
    objs.append(cyl("glow", (0, -0.1, 0), 0.08, 0.03, verts=8, rot=(90, 0, 0)))
    return objs


BUILD = {
    "rock_s": lambda: rock(0, False), "rock_s_1": lambda: rock(1, False), "rock_l": lambda: rock(0, True), "rock_l_1": lambda: rock(2, True),
    "boulder": lambda: boulder(0), "boulder_1": lambda: boulder(1), "log": log, "stump": stump, "crate": lambda: crate(False),
    "crates": lambda: crate(True), "barrel": barrel, "fence": fence,
    "tree_oak": lambda: tree("oak", 0), "tree_oak_1": lambda: tree("oak", 1), "tree_jungle": lambda: tree("jungle", 0),
    "tree_jungle_1": lambda: tree("jungle", 1), "tree_autumn": lambda: tree("autumn", 0), "tree_autumn_1": lambda: tree("autumn", 1),
    "tree_autumn_2": lambda: tree("autumn", 2), "palm": lambda: tree("palm", 0), "tree_dead": lambda: tree("dead", 0),
    "tree_dead_1": lambda: tree("dead", 1), "bush": lambda: bush(0), "bush_1": lambda: bush(1),
    "wall": lambda: wall(False), "wall_1": lambda: wall(False), "wall_broken": lambda: wall(True), "wall_broken_1": lambda: wall(True),
    "pillar": lambda: pillar(False), "column_broken": lambda: pillar(True), "column_broken_1": lambda: pillar(True),
    "statue": statue, "shrine": shrine, "lantern_post": lantern_post, "post": post, "boat": boat, "hut": hut, "house": house,
    "stall": stall, "cart": cart, "well": well, "coral": coral, "tent": tent, "campfire": campfire, "signpost": signpost,
    "doorframe": doorframe, "bell": bell, "mushrooms": mushrooms, "reeds": reeds, "cactus": cactus, "pots": pots, "arch": arch,
    "lectern": lectern, "chest": chest, "cache": cache, "page": page, "stake": stake,
    "bar_counter": bar_counter, "table": table, "stool": stool, "bench": bench, "fireplace": fireplace, "shelf": shelf,
    "bookshelf": bookshelf, "quest_board": quest_board, "memorial_wall": memorial_wall, "dummy": dummy, "anvil": anvil,
    "bed": bed, "weapon_rack": weapon_rack, "chandelier": chandelier, "banner": banner, "rug": rug, "door": door,
    "boarded": boarded, "window": window, "emblem": emblem,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = "assets/models/props"
    only = None
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        else:
            i += 1
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    for name, fn in BUILD.items():
        if only and name not in only:
            continue
        reset()
        rnd.seed(zlib.crc32(name.encode()))
        objs = fn()
        finish(objs, name, out)


if __name__ == "__main__":
    main()
