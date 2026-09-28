"""Shared Blender helpers for the A Guilda art pipeline.

Characters are rendered as *index sprites*: every material encodes a palette
slot (R channel), a toon shade value (G channel) and view depth (B channel).
The post-process step (tools/py/sprites_post.py) turns that into clean pixel
art, and the game recolors each unit through a per-unit palette.
"""
import math
import os
import bpy
from mathutils import Vector, Matrix, Euler

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


def build_materials(light_vec, depth_range=3.0):
    """One emission material per palette slot, encoding slot/shade/depth."""
    _MATS.clear()
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
        ao_mix.inputs["To Min"].default_value = 0.55
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
        nt.links.new(mul.outputs["Value"], comb.inputs[1])
        nt.links.new(dmap.outputs["Result"], comb.inputs[2])
        nt.links.new(comb.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
        _MATS[name] = mat
    return _MATS


def mat(slot):
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


def render_to(path):
    scene = bpy.context.scene
    if not os.path.isabs(path):
        raise ValueError("render_to needs an absolute path: " + path)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
