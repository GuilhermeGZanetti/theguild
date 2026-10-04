class_name UnitView
extends Node3D
## A unit on the map: a pixel-perfect standee sprite (Y-billboard stretched
## by 1/cos(pitch) so it shows 1:1 on screen, lit by the scene), blob shadow
## and animations.

const PX := 24.0
const FRAME_TIME := {"idle": 0.2, "walk": 0.1, "attack": 0.085, "cast": 0.11, "hit": 0.12, "dodge": 0.1,
	"downed": 0.6, "death": 0.14, "idle_bandage": 0.2}
const LOOPING := ["idle", "walk", "downed", "idle_bandage"]
const SHADER := preload("res://shaders/unit_sprite.gdshader")
const OBJECT_PROPS := {"carrow": "cart", "coast": "bell", "stilts": "lantern_post", "ember": "bush_1", "dunes": "boat", "unremembered": "lectern"}

static var _sheets := {}

var uid := -1
var variant := ""
var meta := {}
var canvas := 64
var sprite: MeshInstance3D
var shadow: MeshInstance3D
var mat: ShaderMaterial
var anim := "idle"
var anim_frame := 0
var anim_time := 0.0
var anim_done := false
var facing := Vector2i(0, 1)
var cam_yaw := 0.0
var cam_fwd := Vector3.FORWARD
var cam_right := Vector3.RIGHT
var pitch := 30.0
var bandaged := false
var prop_node: Node3D = null
var base_pos := Vector3.ZERO
var bob_time := 0.0
var flash_t := 0.0
var is_ghost := false


func setup(p_variant: String, palette: Dictionary, p_pitch: float, region := "") -> void:
	variant = Member.fix_variant(p_variant)
	pitch = p_pitch
	if variant.begins_with("__object_"):
		_setup_object(region)
		return
	meta = DB.units.get(variant, {})
	if meta.is_empty():
		push_warning("Missing sprite " + variant)
		meta = DB.units.get("human_warrior_m_a", {})
		variant = "human_warrior_m_a"
	canvas = int(meta.get("canvas", 64))
	var tex := _sheet(variant)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("sheet", tex)
	mat.set_shader_parameter("palette", UnitPalette.build(palette))
	var cols := float(tex.get_width()) / canvas
	mat.set_shader_parameter("grid", Vector2(cols, 4.0))
	mat.render_priority = 1
	sprite = MeshInstance3D.new()
	var q := QuadMesh.new()
	var stretch := 1.0 / cos(deg_to_rad(pitch))
	q.size = Vector2(canvas / PX, canvas / PX * stretch)
	var anchor: Array = meta.get("anchor", [canvas / 2, int(canvas * 0.78)])
	q.center_offset = Vector3(0, (float(anchor[1]) - canvas / 2.0) / PX * stretch, 0)
	sprite.mesh = q
	sprite.material_override = mat
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	shadow = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var sw := 0.52 if canvas <= 64 else 0.82 * canvas / 96.0
	pm.size = Vector2(sw, sw * 0.62)
	shadow.mesh = pm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = load("res://assets/textures/shadow.png")
	smat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	smat.render_priority = 0
	shadow.material_override = smat
	shadow.position.y = 0.03
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	play("idle")


func _setup_object(region: String) -> void:
	var pid: String = OBJECT_PROPS.get(region, "cart")
	prop_node = PropLib.instance(pid, "town" if region == "carrow" else PropLib.biome_of_region(region))
	if prop_node:
		add_child(prop_node)


static func _sheet(v: String) -> Texture2D:
	if not _sheets.has(v):
		_sheets[v] = load("res://assets/sprites/units/%s.png" % v)
	return _sheets[v]


func set_palette(palette: Dictionary) -> void:
	if mat:
		mat.set_shader_parameter("palette", UnitPalette.build(palette))


func set_camera(yaw: float, fwd: Vector3, right: Vector3) -> void:
	cam_yaw = yaw
	cam_fwd = fwd
	cam_right = right


func play(a: String, restart := true) -> void:
	if meta.is_empty():
		return
	if bandaged and a == "idle" and meta["anims"].has("idle_bandage"):
		a = "idle_bandage"
	if not meta["anims"].has(a):
		a = "idle"
	if a == anim and not restart:
		return
	anim = a
	anim_frame = 0
	anim_time = 0.0
	anim_done = false


func anim_length(a: String) -> float:
	if meta.is_empty() or not meta["anims"].has(a):
		return 0.3
	return FRAME_TIME.get(a, 0.12) * int(meta["anims"][a][1]) / Settings.combat_speed


func _process(delta: float) -> void:
	if sprite == null:
		return
	# face the camera horizontally; nudge toward it so feet never clip
	sprite.global_rotation = Vector3(0, cam_yaw, 0)
	sprite.position = -cam_fwd * 0.4
	anim_time += delta * Settings.combat_speed
	var ft: float = FRAME_TIME.get(anim, 0.12)
	var info: Array = meta["anims"][anim]
	var count := int(info[1])
	while anim_time >= ft:
		anim_time -= ft
		if anim in LOOPING:
			anim_frame = (anim_frame + 1) % count
		elif anim_frame < count - 1:
			anim_frame += 1
		else:
			anim_done = true
	if anim_done and not anim in ["death", "downed"]:
		play("idle")
		info = meta["anims"][anim]
	var dir := _dir_index()
	mat.set_shader_parameter("frame", Vector2(float(info[0]) + anim_frame, float(dir)))
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		mat.set_shader_parameter("flash", clampf(flash_t * 6.0, 0.0, 1.0))


func _dir_index() -> int:
	var f := Vector3(facing.x, 0, facing.y)
	var sx := f.dot(cam_right)
	var fw := Vector3(cam_fwd.x, 0, cam_fwd.z).normalized()
	var sy := f.dot(fw)
	if sy <= 0.0:
		return 0 if sx >= 0.0 else 1
	return 3 if sx >= 0.0 else 2


func face(d: Vector2i) -> void:
	if d != Vector2i.ZERO:
		facing = d


func hit_flash(color := Color(1, 1, 1)) -> void:
	if mat:
		mat.set_shader_parameter("flash_color", color)
		flash_t = 0.2


func set_grey(v: float) -> void:
	if mat:
		mat.set_shader_parameter("grey", v)


func set_ghost(v: float) -> void:
	is_ghost = v > 0.0
	if mat:
		mat.set_shader_parameter("ghost", v)


func set_alpha(v: float) -> void:
	if mat:
		mat.set_shader_parameter("alpha", v)
	if shadow:
		shadow.visible = v > 0.2


func set_highlight(v: float, color := Color(1.0, 0.92, 0.55)) -> void:
	if mat:
		mat.set_shader_parameter("highlight", v)
		mat.set_shader_parameter("highlight_color", color)


func set_tint(c: Color) -> void:
	if mat:
		mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))


func head_offset() -> Vector3:
	## World offset of the top of the sprite (for HP bars and barks).
	if meta.is_empty():
		return Vector3(0, 1.05, 0)
	var anchor: Array = meta.get("anchor", [32, 50])
	var top_px := float(anchor[1]) - canvas * 0.405 if canvas <= 64 else float(anchor[1]) - canvas * 0.57
	return Vector3(0, top_px / PX / cos(deg_to_rad(pitch)) * cos(deg_to_rad(pitch)) * 1.0 + 0.2, 0)
