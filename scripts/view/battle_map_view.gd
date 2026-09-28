class_name BattleMapView
extends Node3D
## Builds the 3D scene of a battle map: environment, sun, terrain, water,
## props, decoration and dynamic lights. The board is surrounded by a skirt
## of countryside that dissolves into drifting mist.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const GLOW_PROPS := {"lantern_post": [Vector3(0.3, 1.13, 0), Color(1.0, 0.78, 0.45), 3.4], "campfire": [Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.3), 4.0],
	"shrine": [Vector3(0, 0.7, 0), Color(1.0, 0.8, 0.5), 2.6], "hut": [Vector3(0.55, 1.05, -0.62), Color(1.0, 0.75, 0.4), 2.8],
	"house": [Vector3(0.7, 0.9, -1.0), Color(1.0, 0.76, 0.42), 2.8], "chest": [Vector3(0, 0.3, -0.2), Color(1.0, 0.85, 0.5), 1.4],
	"page": [Vector3(0, 0.6, 0), Color(0.9, 0.9, 1.0), 2.0]}
const BIOME_LOOK := {
	"town": {"mist": Color(0.5, 0.5, 0.6), "sky": Color(0.10, 0.09, 0.13), "ambient": Color(0.46, 0.44, 0.62), "sun": Color(1.0, 0.93, 0.78), "sun_e": 1.25, "amb_e": 0.95},
	"hush_town": {"mist": Color(0.64, 0.64, 0.68), "sky": Color(0.13, 0.13, 0.15), "ambient": Color(0.5, 0.5, 0.58), "sun": Color(0.9, 0.9, 0.92), "sun_e": 1.0, "amb_e": 1.0},
	"coast": {"mist": Color(0.52, 0.6, 0.67), "sky": Color(0.09, 0.12, 0.15), "ambient": Color(0.46, 0.5, 0.66), "sun": Color(1.0, 0.95, 0.82), "sun_e": 1.3, "amb_e": 0.95},
	"jungle": {"mist": Color(0.44, 0.54, 0.52), "sky": Color(0.07, 0.11, 0.1), "ambient": Color(0.4, 0.5, 0.58), "sun": Color(1.0, 0.95, 0.72), "sun_e": 1.2, "amb_e": 0.95},
	"autumn": {"mist": Color(0.58, 0.5, 0.52), "sky": Color(0.11, 0.08, 0.08), "ambient": Color(0.52, 0.42, 0.56), "sun": Color(1.0, 0.86, 0.62), "sun_e": 1.25, "amb_e": 0.95},
	"desert": {"mist": Color(0.66, 0.57, 0.55), "sky": Color(0.13, 0.09, 0.09), "ambient": Color(0.5, 0.4, 0.56), "sun": Color(1.0, 0.88, 0.72), "sun_e": 1.12, "amb_e": 0.9},
	"hush": {"mist": Color(0.72, 0.72, 0.75), "sky": Color(0.16, 0.16, 0.18), "ambient": Color(0.56, 0.56, 0.62), "sun": Color(0.86, 0.86, 0.9), "sun_e": 0.9, "amb_e": 1.05},
}

var grid: BattleGrid
var biome := "town"
var prop_biome := "town"
var terrain: MeshInstance3D
var water: MeshInstance3D
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var props := {}          # cell -> MeshInstance3D
var objects := {}        # cell -> Node3D (chests, caches, pages, captives)
var deco_nodes: Array = []
var sun: DirectionalLight3D
var environment: Environment
var tall_props: Array = []
var rng := RandomNumberGenerator.new()
var hush_level := 0
var view_grid: BattleGrid   # the board plus its skirt (render only)
var pad := 0
var mist_color := Color(0.5, 0.5, 0.6)
var wv_ref: WorldView
var time := "day"
var light_boost := 1.0
var skirt_deco: Array = []

const SKIRT_PROPS := {
	"town": {"tree": 5, "bush": 4, "rock_s": 2, "stump": 1, "house": 2},
	"hush_town": {"tree_dead": 3, "rock_s": 2, "wall_broken": 2, "bush": 1, "house": 1},
	"coast": {"palm": 4, "rock_s": 3, "rock_l": 2, "bush": 2},
	"jungle": {"tree": 7, "bush": 5, "rock_s": 1, "stump": 1},
	"autumn": {"tree": 8, "bush": 3, "rock_l": 1, "stump": 1, "mushrooms": 1},
	"desert": {"cactus": 3, "rock_s": 3, "rock_l": 3, "tree_dead": 1, "column_broken": 1},
	"hush": {"tree_dead": 3, "rock_s": 3, "rock_l": 2, "column_broken": 1},
}
const SKIRT_DECO := {
	"town": ["flowers", "tuft", "tuft"], "hush_town": ["pebbles", "tuft"], "coast": ["shells", "tuft", "pebbles"],
	"jungle": ["fern", "tuft", "flowers"], "autumn": ["leaves", "tuft", "mushroom"], "desert": ["pebbles", "tuft", "bones"],
	"hush": ["pebbles", "ash"],
}
const SMALL_PROPS := ["bush", "rock_s", "stump", "mushrooms"]


func build(g: BattleGrid, wv: WorldView, p_pad := 9, skirt_props := true) -> void:
	grid = g
	wv_ref = wv
	pad = p_pad
	view_grid = TerrainBuilder.padded(g, pad, g.w * 131 + g.h * 7 + hash(g.biome)) if pad > 0 else g
	biome = g.biome
	prop_biome = biome
	hush_level = g.hush
	rng.seed = g.w * 7919 + g.h * 31 + hash(biome)
	var look: Dictionary = BIOME_LOOK.get(biome, BIOME_LOOK["town"]).duplicate()
	time = g.time
	_time_of_day(look)
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	mist_color = look["mist"]
	environment.background_color = mist_color if pad > 0 else look["sky"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = look["ambient"]
	environment.ambient_light_energy = look["amb_e"]
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = false
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.05
	environment.set_glow_level(0, 1.0)
	environment.set_glow_level(1, 0.6)
	wv.set_environment(environment)
	sun = DirectionalLight3D.new()
	sun.light_color = look["sun"]
	sun.light_energy = look["sun_e"] * 1.4
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-6, 9, 2) if time == "day" else Vector3(-9, 5, 3), Vector3(0, 0, 0), Vector3.UP)
	_build_terrain()
	_build_water()
	_build_props()
	_build_objects()
	if skirt_props:
		_build_skirt()
	_build_deco()
	wv.bounds = Rect2(0, 0, g.w, g.h)
	set_mist(mist_color, 1.0 if pad > 0 else 0.0)
	set_hush(float(hush_level))


## Dusk warms and lowers the sun; night swaps it for moonlight, darkens the
## mist and makes lanterns and fires carry the scene.
func _time_of_day(look: Dictionary) -> void:
	match time:
		"dusk":
			look["sun"] = Color(1.0, 0.64, 0.44)
			look["sun_e"] = look["sun_e"] * 0.78
			look["ambient"] = Color(0.52, 0.38, 0.56)
			look["amb_e"] = look["amb_e"] * 0.85
			look["mist"] = look["mist"].lerp(Color(0.5, 0.36, 0.42), 0.55)
			light_boost = 1.3
		"night":
			look["sun"] = Color(0.56, 0.64, 1.0)
			look["sun_e"] = look["sun_e"] * 0.42
			look["ambient"] = Color(0.3, 0.34, 0.62)
			look["amb_e"] = look["amb_e"] * 0.72
			look["mist"] = look["mist"].lerp(Color(0.12, 0.14, 0.26), 0.7)
			light_boost = 1.8


## Unit sprites are unlit: tint them to the hour so they sit in the scene.
func unit_tint() -> Color:
	return {"dusk": Color(1.0, 0.9, 0.84), "night": Color(0.72, 0.78, 1.0)}.get(time, Color.WHITE)


func _build_terrain() -> void:
	terrain = MeshInstance3D.new()
	terrain.mesh = TerrainBuilder.build_terrain(view_grid, pad == 0)
	terrain.position = Vector3(-pad, 0, -pad)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = TERRAIN_SHADER
	var atlas: Texture2D = load("res://assets/textures/ground_%s.png" % biome)
	terrain_mat.set_shader_parameter("atlas", atlas)
	terrain_mat.set_shader_parameter("splat", TerrainBuilder.splat_texture(view_grid))
	terrain_mat.set_shader_parameter("noise_tex", load("res://assets/textures/noise.png"))
	var gm := TerrainBuilder.meta()
	terrain_mat.set_shader_parameter("cliff_index", int(gm["biomes"][biome]["cliff_index"]))
	terrain_mat.set_shader_parameter("map_size", Vector2(view_grid.w, view_grid.h))
	terrain_mat.set_shader_parameter("map_origin", Vector2(-pad, -pad))
	terrain_mat.set_shader_parameter("play_rect", Vector4(0, 0, grid.w, grid.h))
	terrain.material_override = terrain_mat
	add_child(terrain)


func _build_water() -> void:
	var m := TerrainBuilder.build_water(view_grid, pad == 0)
	if m == null:
		return
	water = MeshInstance3D.new()
	water.mesh = m
	water.position = Vector3(-pad, 0, -pad)
	water_mat = ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("noise_tex", load("res://assets/textures/noise.png"))
	water_mat.set_shader_parameter("shore", TerrainBuilder.shore_texture(view_grid))
	water_mat.set_shader_parameter("map_size", Vector2(view_grid.w, view_grid.h))
	water_mat.set_shader_parameter("map_origin", Vector2(-pad, -pad))
	var wc: Array = TerrainBuilder.meta()["biomes"][biome]["water"]
	water_mat.set_shader_parameter("water_color", Color8(wc[0], wc[1], wc[2]))
	if biome == "hush":
		water_mat.set_shader_parameter("water_color", Color(0.36, 0.36, 0.4))
		water_mat.set_shader_parameter("opacity", 0.97)
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func cell_top(p: Vector2i) -> Vector3:
	return Vector3(p.x + 0.5, TerrainBuilder.top_y(grid, p), p.y + 0.5)


func unit_pos(p: Vector2i) -> Vector3:
	var tl := grid.t(p)
	var y := TerrainBuilder.top_y(grid, p)
	if int(tl["water"]) > 0:
		y = TerrainBuilder.water_y(grid, p) - 0.12
	return Vector3(p.x + 0.5, y, p.y + 0.5)


func _build_props() -> void:
	for p in grid.all_cells():
		var tl := grid.t(p)
		var id: String = tl["prop"]
		if id == "" or id.ends_with("_part"):
			continue
		var mi := PropLib.instance(id, prop_biome, rng)
		if mi == null:
			continue
		var base := cell_top(p)
		var rot := 0.0
		var scale := 1.0
		match id:
			"tree", "rock_s", "rock_l", "boulder", "bush", "stump", "mushrooms", "reeds", "coral", "cactus", "pots", "tree_dead", "palm":
				rot = rng.randf() * TAU
				scale = rng.randf_range(0.88, 1.12)
			"wall", "wall_broken", "fence":
				rot = _wall_rotation(p, id)
			"house", "hut", "arch":
				var sz: Array = tl.get("size", [2, 2])
				base = Vector3(p.x + float(sz[0]) / 2.0, base.y, p.y + float(sz[1]) / 2.0)
				if id == "house":
					mi.scale = Vector3(float(sz[0]) / 3.0, 1.0, float(sz[1]) / 2.0)
			_:
				rot = float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.15, 0.15)
		mi.position = base
		mi.rotation.y = rot
		if not id in ["house", "hut", "arch"]:
			mi.scale = Vector3.ONE * scale
		add_child(mi)
		props[p] = mi
		if id in ["tree", "palm", "house", "hut", "arch", "wall", "pillar", "statue", "shrine", "boulder", "rock_l", "tent", "boat", "crates", "bell", "doorframe"]:
			mi.material_override = PropLib.material(prop_biome).duplicate()
			tall_props.append([p, mi])
		if GLOW_PROPS.has(id):
			_add_light(mi, GLOW_PROPS[id])


func _wall_rotation(p: Vector2i, id: String) -> float:
	var horiz := 0
	var vert := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
		if grid.inb(p + d) and grid.t(p + d)["prop"] in ["wall", "wall_broken", "fence"]:
			horiz += 1
	for d in [Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.inb(p + d) and grid.t(p + d)["prop"] in ["wall", "wall_broken", "fence"]:
			vert += 1
	if vert > horiz:
		return PI * 0.5
	if horiz == vert:
		return PI * 0.5 * float(rng.randi() % 2)
	return 0.0


func _add_light(parent: Node3D, spec: Array) -> void:
	var l := OmniLight3D.new()
	l.position = spec[0]
	l.light_color = spec[1]
	if biome in ["hush", "hush_town"]:
		l.light_color = Color(0.85, 0.85, 1.0)
	l.omni_range = spec[2] * (1.0 + (light_boost - 1.0) * 0.45)
	l.light_energy = 1.6 * light_boost
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	parent.add_child(l)


func _build_objects() -> void:
	for p in grid.all_cells():
		var obj: Dictionary = grid.t(p)["obj"]
		if obj.is_empty():
			continue
		var id: String = {"cache": "cache", "chest": "chest", "page": "page", "captive": "stake"}.get(obj.get("kind", ""), "")
		if id == "":
			continue
		var mi := PropLib.instance(id, prop_biome, rng)
		if mi == null:
			continue
		mi.position = cell_top(p)
		mi.rotation.y = rng.randf() * TAU if id != "stake" else 0.0
		add_child(mi)
		objects[p] = mi
		if GLOW_PROPS.has(id):
			_add_light(mi, GLOW_PROPS[id])
		if id == "cache" or id == "page":
			var marker := _beacon(Color(1.0, 0.85, 0.4) if id == "cache" else Color(0.8, 0.85, 1.0))
			mi.add_child(marker)


func _beacon(c: Color) -> Node3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 1.8
	l.light_energy = 1.2
	l.position = Vector3(0, 0.8, 0)
	return l


func remove_object(p: Vector2i) -> void:
	if objects.has(p):
		var n: Node3D = objects[p]
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3(1.2, 0.2, 1.2), 0.25)
		tw.tween_callback(n.queue_free)
		objects.erase(p)


func _build_deco() -> void:
	var tex: Texture2D = load("res://assets/textures/deco.png")
	var dmeta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/deco.json"))
	var names: Array = dmeta["names"]
	var gm := TerrainBuilder.meta()
	var grass: Array = gm["biomes"][biome]["grass"]
	var gcol := Color8(grass[0], grass[1], grass[2])
	var accents := {"town": Color(0.92, 0.45, 0.4), "coast": Color(1.0, 0.7, 0.65), "jungle": Color(0.98, 0.5, 0.66), "autumn": Color(0.9, 0.45, 0.18),
		"desert": Color(0.9, 0.62, 0.45), "hush": Color(0.85, 0.85, 0.88), "hush_town": Color(0.8, 0.8, 0.82)}
	var accent: Color = accents.get(biome, Color(0.9, 0.4, 0.4))
	var mm_by := {}
	var spots: Array = []   # [cell in board coordinates, deco name, ground y]
	for p in grid.all_cells():
		var d: String = grid.t(p)["deco"]
		if d != "" and grid.t(p)["water"] == 0:
			spots.append([p, d, TerrainBuilder.top_y(grid, p)])
	spots.append_array(skirt_deco)
	for sp in spots:
		var p: Vector2i = sp[0]
		var d: String = sp[1]
		var idx := names.find(d)
		if idx < 0:
			continue
		if not mm_by.has(idx):
			mm_by[idx] = []
		for k in (2 if d in ["tuft", "fern", "leaves", "pebbles"] else 1):
			var off := Vector3(rng.randf_range(0.15, 0.85), 0, rng.randf_range(0.15, 0.85))
			mm_by[idx].append(Vector3(p.x, sp[2], p.y) + off)
	var stretch := 1.0 / cos(deg_to_rad(wv_ref.pitch if wv_ref else 30.0))
	for idx in mm_by:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/deco.gdshader")
		mat.set_shader_parameter("sheet", tex)
		mat.set_shader_parameter("cell", float(idx))
		mat.set_shader_parameter("cells", float(names.size()))
		mat.set_shader_parameter("grass", gcol)
		mat.set_shader_parameter("accent", accent)
		var q := QuadMesh.new()
		q.size = Vector2(16.0 / 24.0, 16.0 / 24.0 * stretch)
		q.center_offset = Vector3(0, 16.0 / 24.0 * stretch * 0.5 - 0.06, 0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = q
		var pts: Array = mm_by[idx]
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		deco_nodes.append(mmi)


## Scatter nature props and ground decoration over the skirt.
func _build_skirt() -> void:
	if pad == 0:
		return
	var srng := RandomNumberGenerator.new()
	srng.seed = rng.seed + 99
	var table: Dictionary = SKIRT_PROPS.get(biome, SKIRT_PROPS["town"])
	var decos: Array = SKIRT_DECO.get(biome, ["tuft"])
	var used := {}
	var off := Vector2i(pad, pad)
	for q in view_grid.all_cells():
		var p := q - off
		if grid.inb(p) or used.has(q):
			continue
		var tl := view_grid.t(q)
		if int(tl["water"]) > 0:
			continue
		var e := Vector2i(clampi(p.x, 0, grid.w - 1), clampi(p.y, 0, grid.h - 1))
		var d := maxi(absi(p.x - e.x), absi(p.y - e.y))
		var y := TerrainBuilder.top_y(view_grid, q)
		var roll := srng.randf()
		if (d == 1 and roll < 0.07) or (d >= 2 and roll < 0.17):
			var id := _pick(table, srng)
			if d == 1 and not id in SMALL_PROPS:
				id = "bush"
			if id == "house":
				if d < 3 or not _skirt_free(q, Vector2i(3, 2), y, used):
					continue
				for dx in 3:
					for dz in 2:
						used[q + Vector2i(dx, dz)] = true
				_skirt_prop("house", Vector3(p.x + 1.5, y, p.y + 1.0), float(srng.randi() % 2) * PI, 1.0, p, srng)
				continue
			used[q] = true
			var jitter := Vector3(srng.randf_range(-0.2, 0.2), 0, srng.randf_range(-0.2, 0.2))
			_skirt_prop(id, Vector3(p.x + 0.5, y, p.y + 0.5) + jitter, srng.randf() * TAU, srng.randf_range(0.85, 1.2), p, srng)
		elif srng.randf() < 0.3:
			skirt_deco.append([p, decos[srng.randi() % decos.size()], y])


func _skirt_free(q: Vector2i, size: Vector2i, y: float, used: Dictionary) -> bool:
	for dx in size.x:
		for dz in size.y:
			var c := q + Vector2i(dx, dz)
			if not view_grid.inb(c) or used.has(c) or grid.inb(c - Vector2i(pad, pad)):
				return false
			if int(view_grid.t(c)["water"]) > 0 or absf(TerrainBuilder.top_y(view_grid, c) - y) > 0.01:
				return false
	return true


func _skirt_prop(id: String, pos: Vector3, rot: float, scale: float, cell: Vector2i, srng: RandomNumberGenerator) -> void:
	var tall := not id in SMALL_PROPS
	var mi := PropLib.instance(id, prop_biome, srng, tall)
	if mi == null:
		return
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * scale
	add_child(mi)
	if tall:
		tall_props.append([cell, mi])


func _pick(table: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0
	for k in table:
		total += int(table[k])
	var n := r.randi() % total
	for k in table:
		n -= int(table[k])
		if n < 0:
			return k
	return table.keys()[0]


## Mist that hides everything beyond the board (0 turns it off).
func set_mist(c: Color, amount: float) -> void:
	mist_color = c
	if pad > 0:
		environment.background_color = c
	var noise: Texture2D = load("res://assets/textures/noise.png")
	var mats: Array = [wv_ref.post_mat] if wv_ref else []
	if water_mat:
		mats.append(water_mat)
	var lin := c.srgb_to_linear()   # the shaders work in linear light
	for m in mats:
		m.set_shader_parameter("mist", amount)
		m.set_shader_parameter("mist_color", Vector3(lin.r, lin.g, lin.b))
		m.set_shader_parameter("map_rect", Vector4(0, 0, grid.w, grid.h))
		m.set_shader_parameter("mist_noise", noise)


func set_camera_yaw(yaw_deg: float) -> void:
	for n in deco_nodes:
		n.material_override.set_shader_parameter("yaw", deg_to_rad(yaw_deg))


func set_hush(level: float) -> void:
	## local Hush 0-5: maps lose saturation as the Hush rises
	var d := clampf(level / 5.0, 0.0, 1.0) * 0.85
	if biome == "hush":
		d = 0.92
	terrain_mat.set_shader_parameter("desaturate", d)
	if water_mat:
		water_mat.set_shader_parameter("desaturate", d)
	PropLib.material(prop_biome).set_shader_parameter("desaturate", d)
	for tp in tall_props:
		tp[1].material_override.set_shader_parameter("desaturate", d)
	for n in deco_nodes:
		n.material_override.set_shader_parameter("desaturate", d)


func set_grid_alpha(a: float) -> void:
	terrain_mat.set_shader_parameter("grid_alpha", a)


## Fade tall props that stand in front of the given cells (units, cursor).
func update_fades(cells: Array, fwd_h: Vector3) -> void:
	for tp in tall_props:
		var p: Vector2i = tp[0]
		var mi: MeshInstance3D = tp[1]
		var f := 0.0
		for c in cells:
			var d := Vector3(p.x - c.x, 0, p.y - c.y)
			# prop is between the camera and the cell: behind the cell along -fwd
			var along := -d.dot(fwd_h)
			var side := absf(d.dot(Vector3(fwd_h.z, 0, -fwd_h.x)))
			if along > 0.2 and along < 2.8 and side < 1.3:
				f = 1.0
		var cur: float = mi.material_override.get_shader_parameter("fade")
		mi.material_override.set_shader_parameter("fade", move_toward(cur, f, 0.12))
