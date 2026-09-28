class_name TavernView
extends Node3D
## The guild hub: a cut-away tavern diorama lit by the hearth at night.
## Facilities are clickable hotspots that grow with their level; members
## idle around the room and recruits wait at the bar.

signal hotspot_hovered(id: String)

const W := 13
const H := 10
const WALL_H := 2.7
const WALL_T := 0.3
const MOON := Color(0.5, 0.64, 1.0)

## id -> [name, anchor for the floating label]
const HOTSPOTS := {
	"board": ["Quest Board", Vector3(10.0, 2.1, 0.3)],
	"hearth": ["Hearth · Roster", Vector3(5.6, 2.9, 0.6)],
	"recruiter": ["Bar · Recruiter", Vector3(1.8, 1.6, 7.2)],
	"library": ["Library", Vector3(2.0, 2.4, 0.4)],
	"memorial": ["Memorial", Vector3(0.3, 2.2, 3.4)],
	"ledger": ["Guild Ledger", Vector3(7.6, 1.5, 1.0)],
	"training": ["Training Grounds", Vector3(11.9, 1.7, 2.6)],
	"forge": ["Forge · Stash", Vector3(11.6, 1.3, 6.6)],
	"nursery": ["Nursery", Vector3(9.0, 1.1, 8.8)],
	"barracks": ["Barracks", Vector3(4.2, 1.1, 8.8)],
	"door": ["The Realm · Factions", Vector3(0.2, 2.3, 9.3)],
}

var map_view: BattleMapView
var wv: WorldView
var campaign: Campaign
var grid: BattleGrid
var hot_meshes := {}     # id -> Array[MeshInstance3D]
var hot_boxes := {}      # id -> Array[AABB]
var walls := {}          # side -> Node3D
var member_views := {}   # member id -> UnitView
var recruit_views := {}  # recruit index -> UnitView
var idle_spots: Array = []
var trainers: Array = []
var hover_id := ""
var rng := RandomNumberGenerator.new()
var _t := 0.0


func build(p_campaign: Campaign, p_wv: WorldView) -> void:
	campaign = p_campaign
	wv = p_wv
	rng.seed = 4242
	grid = BattleGrid.new(W, H)
	grid.biome = "town"
	grid.region = "carrow"
	for c in grid.all_cells():
		grid.t(c)["ground"] = "planks"
	map_view = BattleMapView.new()
	add_child(map_view)
	map_view.build(grid, wv, 6, false)
	map_view.set_grid_alpha(0.0)
	_night()
	_build_walls()
	_build_room()
	_build_facilities()
	wv.bounds = Rect2(0, 0, W, H)
	var bv := wv.basis_vectors()
	wv.focus(Vector3(W / 2.0, 0.6, H / 2.0 + 0.4) - bv["right"] * 1.6, true)
	refresh_people()
	update_walls()


# ---------------------------------------------------------------- lighting
func _night() -> void:
	var env := map_view.environment
	map_view.set_mist(Color(0.16, 0.13, 0.21), 1.0)
	env.ambient_light_color = Color(0.44, 0.34, 0.56)
	env.ambient_light_energy = 0.62
	map_view.sun.light_color = Color(0.62, 0.66, 0.95)
	map_view.sun.light_energy = 0.55
	map_view.sun.look_at_from_position(Vector3(W + 6, 11, H + 3), Vector3(W / 2.0, 0, H / 2.0), Vector3.UP)
	map_view.sun.shadow_enabled = true


func _omni(pos: Vector3, color: Color, rng_: float, energy: float, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = rng_
	l.light_energy = energy
	l.omni_attenuation = 1.1
	l.shadow_enabled = shadows
	l.shadow_bias = 0.08
	add_child(l)
	return l


# ---------------------------------------------------------------- walls
func _build_walls() -> void:
	var mat := PropLib.material("tavern")
	# north (z=0) and south (z=H) run along x; west (x=0) and east (x=W) along z
	walls["n"] = _wall_node(Vector3(-WALL_T, 0, -WALL_T), W + 2 * WALL_T, false, mat, [7.7], [])
	walls["s"] = _wall_node(Vector3(-WALL_T, 0, H), W + 2 * WALL_T, false, mat, [3.5, 9.5], [])
	walls["w"] = _wall_node(Vector3(-WALL_T, 0, 0), H, true, mat, [5.3], [])
	walls["e"] = _wall_node(Vector3(W, 0, 0), H, true, mat, [3.0, 7.0], [])
	for side in walls:
		add_child(walls[side])


## A timber-framed plank wall with a stone footing, built as one mesh.
func _wall_node(origin: Vector3, length: float, along_z: bool, mat: Material, windows: Array, _doors: Array) -> Node3D:
	var node := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = hash(origin)
	var box := func(a: float, b: float, y0: float, y1: float, t0: float, t1: float, slot: int, jit: float) -> void:
		# a..b along the wall, t0..t1 across it (relative to origin)
		var p0: Vector3
		var p1: Vector3
		if along_z:
			p0 = origin + Vector3(t0, y0, a)
			p1 = origin + Vector3(t1, y1, b)
		else:
			p0 = origin + Vector3(a, y0, t0)
			p1 = origin + Vector3(b, y1, t1)
		_box(st, p0, p1, slot, jit)
	# stone footing
	var x := 0.0
	while x < length - 0.01:
		var w := minf(r.randf_range(0.3, 0.55), length - x)
		box.call(x + 0.01, x + w - 0.01, 0.0, 0.36, -0.02, WALL_T + 0.02, 0 if r.randf() < 0.7 else 1, r.randf())
		x += w
	# planks (skipping window openings)
	x = 0.0
	while x < length - 0.01:
		var pw := minf(0.25, length - x)
		var in_window := false
		for wx in windows:
			if x + pw > float(wx) - 0.5 and x < float(wx) + 0.5:
				in_window = true
		if in_window:
			box.call(x, x + pw, 0.36, 1.0, 0.03, WALL_T - 0.03, 2, r.randf())
			box.call(x, x + pw, 1.95, WALL_H - 0.15, 0.03, WALL_T - 0.03, 2, r.randf())
		else:
			box.call(x, x + pw, 0.36, WALL_H - 0.15, 0.03, WALL_T - 0.03, 2, r.randf_range(0.1, 0.9))
		x += pw
	# rails, posts and top beam
	box.call(0.0, length, 1.0, 1.1, -0.01, WALL_T + 0.01, 3, 0.5)
	box.call(0.0, length, WALL_H - 0.15, WALL_H, -0.02, WALL_T + 0.02, 3, 0.4)
	var px := 0.0
	while px <= length:
		var cx := clampf(px, 0.11, length - 0.11)
		box.call(cx - 0.11, cx + 0.11, 0.0, WALL_H, -0.04, WALL_T + 0.04, 3, r.randf())
		px += 3.25
	# window frames
	for wx in windows:
		var c := float(wx)
		box.call(c - 0.55, c + 0.55, 0.92, 1.02, -0.05, WALL_T + 0.05, 3, 0.3)
		box.call(c - 0.55, c + 0.55, 1.95, 2.05, -0.05, WALL_T + 0.05, 3, 0.3)
		box.call(c - 0.55, c - 0.45, 1.0, 1.95, -0.05, WALL_T + 0.05, 3, 0.3)
		box.call(c + 0.45, c + 0.55, 1.0, 1.95, -0.05, WALL_T + 0.05, 3, 0.3)
		box.call(c - 0.03, c + 0.03, 1.0, 1.95, WALL_T * 0.5 - 0.03, WALL_T * 0.5 + 0.03, 3, 0.3)
		box.call(c - 0.45, c + 0.45, 1.45, 1.51, WALL_T * 0.5 - 0.03, WALL_T * 0.5 + 0.03, 3, 0.3)
		# moonlit panes
		box.call(c - 0.45, c + 0.45, 1.0, 1.95, WALL_T * 0.5 - 0.01, WALL_T * 0.5 + 0.01, 11, 0.5)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m: ShaderMaterial = mat.duplicate()
	m.set_shader_parameter("glow_override", Color(MOON.r * 0.55, MOON.g * 0.55, MOON.b * 0.7, 1.0))
	m.set_shader_parameter("glow_energy", 0.9)
	mi.material_override = m
	node.add_child(mi)
	for wx in windows:
		var c := float(wx)
		var inside := Vector3(WALL_T + 0.6, 1.5, c) if along_z else Vector3(c, 1.5, WALL_T + 0.6)
		if origin.x >= W - 0.1 and along_z:
			inside = Vector3(-0.6, 1.5, c)
		if origin.z >= H - 0.1 and not along_z:
			inside = Vector3(c, 1.5, -0.6)
		var l := OmniLight3D.new()
		l.position = origin + inside
		l.light_color = MOON
		l.omni_range = 3.2
		l.light_energy = 0.7
		node.add_child(l)
	return node


func _box(st: SurfaceTool, p0: Vector3, p1: Vector3, slot: int, jit: float) -> void:
	var col := Color((slot + 0.5) / 16.0, jit, 1.0)
	var c := [Vector3(p0.x, p0.y, p0.z), Vector3(p1.x, p0.y, p0.z), Vector3(p1.x, p0.y, p1.z), Vector3(p0.x, p0.y, p1.z),
		Vector3(p0.x, p1.y, p0.z), Vector3(p1.x, p1.y, p0.z), Vector3(p1.x, p1.y, p1.z), Vector3(p0.x, p1.y, p1.z)]
	var faces := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [3, 0, 4, 7], [1, 2, 6, 5]]
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var d: Vector3 = c[f[2]]
		var e: Vector3 = c[f[3]]
		for v in [a, d, b, a, e, d]:
			st.set_color(col)
			st.add_vertex(v)


## Hide the two walls nearest the camera so the room reads as a cut-away.
func update_walls() -> void:
	var y := fposmod(wv.yaw_target, 360.0)
	var back := Vector3(sin(deg_to_rad(y)), 0, cos(deg_to_rad(y)))
	walls["n"].visible = back.z > 0.01
	walls["s"].visible = back.z < -0.01
	walls["w"].visible = back.x > 0.01
	walls["e"].visible = back.x < -0.01


# ---------------------------------------------------------------- props
func _prop(id: String, pos: Vector3, rot_deg := 0.0, hotspot := "", scale := 1.0) -> MeshInstance3D:
	var mi := PropLib.instance(id, "tavern", rng, hotspot != "")
	if mi == null:
		return null
	mi.position = pos
	mi.rotation.y = deg_to_rad(rot_deg)
	mi.scale = Vector3.ONE * scale
	add_child(mi)
	if hotspot != "":
		if not hot_meshes.has(hotspot):
			hot_meshes[hotspot] = []
		hot_meshes[hotspot].append(mi)
	return mi


func _build_room() -> void:
	# hearth, emblem and seating
	_prop("fireplace", Vector3(5.6, 0, 0.32), 0, "hearth")
	_prop("emblem", Vector3(5.6, 2.05, 0.62), 0, "hearth", 0.8)
	_omni(Vector3(5.6, 0.7, 1.1), Color(1.0, 0.6, 0.32), 5.0, 1.5, true)
	_prop("bench", Vector3(5.6, 0, 1.75), 0, "hearth")
	_prop("rug", Vector3(6.2, 0, 5.0), 90)
	# tables
	for tp in [Vector3(5.0, 0, 4.4), Vector3(7.4, 0, 5.6), Vector3(5.5, 0, 6.9)]:
		_prop("table", tp, rng.randf() * 90.0)
		for k in 3:
			var a := rng.randf() * TAU
			_prop("stool", tp + Vector3(cos(a) * 0.8, 0, sin(a) * 0.8), rng.randf() * 90.0)
	_prop("chandelier", Vector3(6.2, 2.25, 5.2))
	_omni(Vector3(6.2, 2.0, 5.2), Color(1.0, 0.8, 0.52), 5.5, 0.9)
	# the bar
	_prop("bar_counter", Vector3(1.9, 0, 7.2), 90, "recruiter")
	_prop("shelf", Vector3(0.22, 0, 6.5), 90, "recruiter")
	_prop("shelf", Vector3(0.22, 0, 7.95), 90, "recruiter")
	_prop("barrel", Vector3(0.45, 0, 5.5))
	_prop("barrel", Vector3(1.1, 0, 5.3))
	_omni(Vector3(1.4, 1.6, 7.2), Color(1.0, 0.75, 0.45), 3.2, 1.0)
	# the door to the realm
	_prop("door", Vector3(0.1, 0, 9.3), 90, "door")
	_prop("signpost", Vector3(0.9, 0, 9.6), 30, "door")
	# ledger on its lectern
	_prop("lectern", Vector3(7.6, 0, 1.0), 0, "ledger")
	_omni(Vector3(7.6, 1.2, 1.3), Color(1.0, 0.88, 0.62), 1.8, 0.8)
	# the quest board
	_prop("quest_board", Vector3(10.0, 0, 0.1), 0, "board")
	_prop("crates", Vector3(8.7, 0, 0.5), 10)
	_prop("pots", Vector3(12.4, 0, 9.4))


## Facility props grow with their level; unbuilt ones are dusty clutter.
func _build_facilities() -> void:
	var lv := func(fid: String) -> int: return int(campaign.facilities.get(fid, 0))
	# library
	match lv.call("library"):
		0:
			_prop("crates", Vector3(1.4, 0, 0.5), 0, "library")
			_prop("boarded", Vector3(2.8, 0, 0.1), 0, "library")
		var l:
			_prop("bookshelf", Vector3(1.3, 0, 0.22), 0, "library")
			if l >= 2:
				_prop("bookshelf", Vector3(2.8, 0, 0.22), 0, "library")
				_prop("table", Vector3(2.2, 0, 1.8), 20, "library")
				_prop("stool", Vector3(1.5, 0, 2.2), 0, "library")
			else:
				_prop("crates", Vector3(2.8, 0, 0.5), 0, "library")
			if l >= 3:
				_prop("bookshelf", Vector3(0.22, 0, 1.25), 90, "library")
	# memorial
	if lv.call("memorial") == 0:
		_prop("boarded", Vector3(0.12, 0, 3.4), 90, "memorial")
	else:
		_prop("memorial_wall", Vector3(0.3, 0, 3.4), 90, "memorial")
		_omni(Vector3(0.9, 0.5, 3.4), Color(1.0, 0.82, 0.55), 2.2, 0.9 + 0.3 * lv.call("memorial"))
		if lv.call("memorial") >= 3:
			_prop("statue", Vector3(0.7, 0, 1.6), 90, "memorial", 0.8)
	# training grounds
	match lv.call("training"):
		0:
			_prop("stump", Vector3(11.6, 0, 2.2), 0, "training")
			_prop("crate", Vector3(12.2, 0, 1.3), 20, "training")
		var l:
			_prop("dummy", Vector3(11.6, 0, 2.2), 0, "training")
			if l >= 2:
				_prop("dummy", Vector3(12.3, 0, 3.6), 30, "training")
			if l >= 3:
				_prop("weapon_rack", Vector3(12.2, 0, 0.25), 0, "training")
			else:
				_prop("crate", Vector3(12.2, 0, 1.0), 20, "training")
	# forge
	match lv.call("forge"):
		0:
			_prop("crates", Vector3(11.6, 0, 6.6), 0, "forge")
			_prop("barrel", Vector3(12.3, 0, 7.3), 0, "forge")
		var l:
			_prop("anvil", Vector3(11.6, 0, 6.6), 90, "forge")
			_omni(Vector3(12.0, 0.7, 6.6), Color(1.0, 0.55, 0.25), 2.4, 1.0)
			_prop("barrel", Vector3(12.4, 0, 7.6), 0, "forge")
			if l >= 2:
				_prop("weapon_rack", Vector3(12.6, 0, 5.4), -90, "forge")
			if l >= 3:
				_prop("chest", Vector3(10.6, 0, 7.4), 40, "forge")
	# nursery
	match lv.call("nursery"):
		0:
			_prop("crates", Vector3(9.0, 0, 9.0), 90, "nursery")
		var l:
			_prop("bed", Vector3(8.4, 0, 8.9), 0, "nursery")
			if l >= 2:
				_prop("bed", Vector3(9.6, 0, 8.9), 0, "nursery")
			if l >= 3:
				_prop("shelf", Vector3(10.8, 0, 9.6), 180, "nursery", 0.8)
			_omni(Vector3(9.0, 1.2, 8.4), Color(1.0, 0.85, 0.65), 2.4, 0.7)
	# barracks
	var bl: int = lv.call("barracks")
	for i in bl + 1:
		_prop("bed", Vector3(3.2 + i * 1.15, 0, 8.9), 0, "barracks")
	_prop("banner", Vector3(12.9, 0, 4.3), -90, "")
	for id in hot_meshes:
		var boxes: Array = []
		for mi in hot_meshes[id]:
			boxes.append(mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else mi.transform * mi.mesh.get_aabb())
		hot_boxes[id] = boxes


# ---------------------------------------------------------------- people
func refresh_people() -> void:
	for k in member_views:
		member_views[k].queue_free()
	member_views.clear()
	for k in recruit_views:
		recruit_views[k].queue_free()
	recruit_views.clear()
	trainers.clear()
	var spots := _spots()
	var injured_spots := [Vector3(8.4, 0, 7.8), Vector3(9.6, 0, 7.8), Vector3(10.6, 0, 8.4)]
	if int(campaign.facilities["nursery"]) == 0:
		injured_spots = [Vector3(3.2, 0, 7.9), Vector3(4.4, 0, 7.9), Vector3(5.6, 0, 7.9)]
	var si := 0
	var ii := 0
	for m in campaign.roster:
		if m.status != "active":
			continue
		var uv := UnitView.new()
		add_child(uv)
		uv.setup(m.variant, m.palette, wv.pitch)
		uv.uid = m.id
		var hurt: bool = not m.injury.is_empty()
		if hurt:
			uv.position = injured_spots[ii % injured_spots.size()] + Vector3(0, 0, 0.1 * (ii / 3))
			uv.face(Vector2i(0, 1))
			uv.bandaged = true
			uv.play("idle_bandage" if uv.meta.get("anims", {}).has("idle_bandage") else "idle")
			ii += 1
		else:
			var s: Array = spots[si % spots.size()]
			uv.position = s[0] + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
			uv.face(s[1])
			if s.size() > 2 and s[2] == "train" and int(campaign.facilities["training"]) > 0:
				trainers.append(uv)
			si += 1
		member_views[m.id] = uv
	# recruits line the customer side of the bar
	for i in campaign.recruits.size():
		if i >= 5:
			break
		var r: Member = campaign.recruits[i]
		var uv := UnitView.new()
		add_child(uv)
		uv.setup(r.variant, r.palette, wv.pitch)
		uv.uid = -100 - i
		uv.position = Vector3(3.0 + (i % 2) * 0.55, 0, 5.9 + i * 0.62)
		uv.face(Vector2i(-1, 0))
		recruit_views[i] = uv


func _spots() -> Array:
	return [
		[Vector3(5.1, 0, 2.6), Vector2i(0, -1)], [Vector3(4.2, 0, 4.2), Vector2i(1, 0)], [Vector3(6.3, 0, 2.6), Vector2i(0, -1)],
		[Vector3(11.0, 0, 3.0), Vector2i(1, -1), "train"], [Vector3(8.3, 0, 5.9), Vector2i(-1, 0)], [Vector3(10.0, 0, 1.3), Vector2i(0, -1)],
		[Vector3(5.8, 0, 3.9), Vector2i(-1, 1)], [Vector3(11.4, 0, 4.2), Vector2i(1, -1), "train"], [Vector3(6.6, 0, 6.3), Vector2i(1, -1)],
		[Vector3(10.8, 0, 6.2), Vector2i(1, 0)], [Vector3(4.6, 0, 6.8), Vector2i(1, 0)], [Vector3(2.4, 0, 2.5), Vector2i(-1, -1)],
		[Vector3(7.6, 0, 2.0), Vector2i(0, -1)], [Vector3(8.0, 0, 7.2), Vector2i(-1, 0)], [Vector3(9.4, 0, 3.6), Vector2i(0, 1)],
		[Vector3(3.6, 0, 3.2), Vector2i(1, 1)],
	]


func _process(delta: float) -> void:
	_t += delta
	var bv := wv.basis_vectors()
	for k in member_views:
		member_views[k].set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
	for k in recruit_views:
		recruit_views[k].set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
	# trainers strike the dummies; others glance around now and then
	if fmod(_t, 2.4) < delta:
		for uv in trainers:
			if is_instance_valid(uv) and uv.anim == "idle":
				uv.play("attack")
	if rng.randf() < delta * 0.35 and not member_views.is_empty():
		var keys := member_views.keys()
		var uv: UnitView = member_views[keys[rng.randi() % keys.size()]]
		if not uv in trainers and not uv.bandaged and uv.anim == "idle":
			uv.face([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi() % 4])
	for uv in trainers:
		if is_instance_valid(uv) and uv.anim_done and uv.anim == "attack":
			uv.play("idle")


# ---------------------------------------------------------------- picking
## Returns ["member", id] / ["recruit", index] / ["hotspot", id] / ["", null]
func pick(mouse: Vector2) -> Array:
	var ps := wv.pixel_scale()
	var best: Array = ["", null]
	var best_depth := 1e9
	for group in [["member", member_views], ["recruit", recruit_views]]:
		var views: Dictionary = group[1]
		for k in views:
			var uv: UnitView = views[k]
			if uv.meta.is_empty():
				continue
			var feet := wv.world_to_screen(uv.global_position)
			var h: float = (float(uv.meta["anchor"][1]) - uv.canvas * 0.22) * ps
			var w: float = uv.canvas * 0.3 * ps
			if Rect2(feet.x - w / 2.0, feet.y - h, w, h + 2 * ps).has_point(mouse):
				var depth := wv.camera.global_position.distance_to(uv.global_position)
				if depth < best_depth:
					best_depth = depth
					best = [group[0], k]
	if best[0] != "":
		return best
	var ray := wv.ray(mouse)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	for id in hot_boxes:
		for box in hot_boxes[id]:
			var hit = (box as AABB).grow(0.05).intersects_ray(o, d)
			if hit != null:
				var depth := o.distance_to(hit)
				if depth < best_depth:
					best_depth = depth
					best = ["hotspot", id]
	return best


func set_hover(id: String) -> void:
	if id == hover_id:
		return
	if hover_id != "" and hot_meshes.has(hover_id):
		for mi in hot_meshes[hover_id]:
			mi.material_override.set_shader_parameter("highlight", 0.0)
	hover_id = id
	if id != "" and hot_meshes.has(id):
		for mi in hot_meshes[id]:
			mi.material_override.set_shader_parameter("highlight", 1.0)
	hotspot_hovered.emit(id)


func set_member_highlight(id: int, on: bool) -> void:
	if member_views.has(id):
		member_views[id].set_highlight(0.8 if on else 0.0)


func anchor_of(id: String) -> Vector3:
	return HOTSPOTS.get(id, ["", Vector3.ZERO])[1]
