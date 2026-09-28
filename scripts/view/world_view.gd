class_name WorldView
extends Control
## Pixel-perfect 3D view. The world renders into a low-resolution SubViewport
## (1 internal pixel = 1/24 world unit) that is scaled up by an integer factor.
## The camera snaps to the texel grid; the sub-texel remainder offsets the
## displayed image so scrolling stays smooth without shimmering.

signal camera_rotated

const PX := 24.0
const POST_SHADER := preload("res://shaders/post.gdshader")

@export var pitch := 30.0
var yaw := 45.0
var yaw_target := 45.0
var target := Vector3.ZERO
var target_goal := Vector3.ZERO
var world_scale := 3
var viewport: SubViewport
var display: TextureRect
var world: Node3D
var camera: Camera3D
var post: MeshInstance3D
var post_mat: ShaderMaterial
var env: WorldEnvironment
var bounds := Rect2(0, 0, 16, 16)
var _off := Vector2.ZERO
var _ui_scale := 1.0
var _internal := Vector2i(320, 180)
var shake := 0.0
var follow_speed := 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.positional_shadow_atlas_size = 1024
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 300.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	post.mesh = q
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST_SHADER
	post_mat.render_priority = -100
	post.material_override = post_mat
	post.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.position = Vector3(0, 0, -1)
	camera.add_child(post)
	display = TextureRect.new()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	_ui_scale = _compute_ui_scale()
	world_scale = clampi(roundi(_ui_scale) + Settings.world_zoom, 1, 8)
	_update_viewport()


func set_environment(e: Environment) -> void:
	if env == null:
		env = WorldEnvironment.new()
		viewport.add_child(env)
	env.environment = e


func _compute_ui_scale() -> float:
	var logical := get_viewport_rect().size
	var physical := Vector2(get_window().size)
	if logical.y <= 0:
		return 1.0
	return maxf(physical.y / logical.y, 0.25)


func _update_viewport() -> void:
	_ui_scale = _compute_ui_scale()
	var physical := Vector2(get_window().size)
	var internal := Vector2i(ceili(physical.x / world_scale), ceili(physical.y / world_scale))
	internal = internal.max(Vector2i(64, 36))
	if internal != _internal or viewport.size != internal + Vector2i(2, 2):
		_internal = internal
		viewport.size = internal + Vector2i(2, 2)
	camera.size = float(viewport.size.y) / PX


func zoom(step: int) -> void:
	world_scale = clampi(world_scale + step, maxi(1, roundi(_ui_scale) - 1), roundi(_ui_scale) + 3)
	Settings.world_zoom = world_scale - roundi(_ui_scale)
	_update_viewport()


func rotate_view(step: int) -> void:
	yaw_target += 90.0 * step


func basis_vectors() -> Dictionary:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var back := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr))
	var right := Vector3(cos(yr), 0, -sin(yr))
	var up := back.cross(right).normalized() * -1.0
	# up must point screen-up: right x back gives forward-ish; recompute robustly
	up = right.cross(back).normalized() * -1.0
	if up.y < 0:
		up = -up
	var fwd_h := Vector3(-sin(yr), 0, -cos(yr))
	return {"back": back, "right": right, "up": up, "fwd": -back, "fwd_h": fwd_h}


func focus(p: Vector3, instant := false) -> void:
	target_goal = p
	if instant:
		target = p


func _process(delta: float) -> void:
	_update_viewport()
	yaw = move_toward(yaw, yaw_target, delta * 360.0)
	if absf(yaw - yaw_target) < 0.01 and absf(yaw_target) >= 360.0:
		yaw_target = fposmod(yaw_target, 360.0)
		yaw = yaw_target
	target_goal.x = clampf(target_goal.x, bounds.position.x, bounds.end.x)
	target_goal.z = clampf(target_goal.z, bounds.position.y, bounds.end.y)
	target = target.lerp(target_goal, clampf(delta * follow_speed, 0.0, 1.0))
	var bv := basis_vectors()
	var back: Vector3 = bv["back"]
	var right: Vector3 = bv["right"]
	var up: Vector3 = bv["up"]
	var t := target
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 3.0)
		t += right * randf_range(-1, 1) * shake * 0.08 + up * randf_range(-1, 1) * shake * 0.08
	var ideal := t + back * 60.0
	var tx := 1.0 / PX
	var pr := ideal.dot(right)
	var pu := ideal.dot(up)
	var pb := ideal.dot(back)
	var sr := roundf(pr / tx) * tx
	var su := roundf(pu / tx) * tx
	camera.global_transform = Transform3D(Basis(right, up, back), right * sr + up * su + back * pb)
	_off = Vector2(-(pr - sr) / tx, (pu - su) / tx)
	var k := world_scale / _ui_scale
	display.position = (Vector2(-1, -1) + _off) * k
	display.size = Vector2(viewport.size) * k
	if absf(yaw - yaw_target) > 0.01:
		camera_rotated.emit()


func screen_to_internal(logical: Vector2) -> Vector2:
	var k := world_scale / _ui_scale
	return (logical - global_position) / k + Vector2(1, 1) - _off


func internal_to_screen(ip: Vector2) -> Vector2:
	var k := world_scale / _ui_scale
	return (ip - Vector2(1, 1) + _off) * k + global_position


func world_to_screen(p: Vector3) -> Vector2:
	return internal_to_screen(camera.unproject_position(p))


func ray(logical: Vector2) -> Array:
	var ip := screen_to_internal(logical)
	return [camera.project_ray_origin(ip), camera.project_ray_normal(ip)]


func pixel_scale() -> float:
	## logical UI pixels per internal world pixel
	return world_scale / _ui_scale


func set_hush(amount: float, vignette: float, fog := Color(0.62, 0.62, 0.66)) -> void:
	post_mat.set_shader_parameter("hush", amount)
	post_mat.set_shader_parameter("vignette", vignette)
	post_mat.set_shader_parameter("fog_color", Vector3(fog.r, fog.g, fog.b))
