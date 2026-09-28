class_name FX
extends Node3D
## Lightweight pixel effects: projectiles, bursts, spell lights and
## persistent terrain effects (smoke, flood, thorns, traps, fire, sanctuary).

const COLORS := {
	"slash": Color(1, 1, 0.9), "stab": Color(1, 1, 0.9), "blunt": Color(1, 0.9, 0.7), "crush": Color(1, 0.8, 0.6),
	"arrow": Color(0.9, 0.8, 0.6), "arrow_pierce": Color(1, 0.95, 0.7), "knife": Color(0.85, 0.9, 1), "rock": Color(0.7, 0.6, 0.5),
	"harpoon": Color(0.7, 0.9, 1), "bolt_arcane": Color(0.7, 0.8, 1), "bolt_fire": Color(1, 0.55, 0.2), "bolt_frost": Color(0.7, 0.95, 1),
	"bolt_light": Color(1, 0.92, 0.6), "bolt_spirit": Color(0.8, 0.6, 1), "lightning": Color(1, 1, 0.6), "heal": Color(0.5, 1, 0.6),
	"heal_wave": Color(0.5, 1, 0.6), "cleanse": Color(0.7, 1, 1), "ward": Color(0.6, 0.8, 1), "buff": Color(1, 0.9, 0.5),
	"shout": Color(1, 0.8, 0.5), "poison": Color(0.6, 0.95, 0.3), "poison_cloud": Color(0.55, 0.9, 0.3), "sting": Color(0.9, 0.5, 1),
	"smoke": Color(0.8, 0.8, 0.85), "shadow": Color(0.45, 0.35, 0.6), "water": Color(0.4, 0.8, 1), "flood": Color(0.3, 0.7, 1),
	"roots": Color(0.55, 0.8, 0.3), "sand": Color(0.95, 0.8, 0.55), "slash_glass": Color(0.7, 1, 1), "glass": Color(0.7, 1, 1),
	"whirl": Color(1, 1, 0.9), "claw": Color(1, 0.9, 0.9), "bite": Color(1, 0.8, 0.8), "fear": Color(0.6, 0.4, 0.8),
	"hush": Color(0.75, 0.75, 0.8), "hush_wave": Color(0.8, 0.8, 0.85), "mark": Color(1, 0.4, 0.3), "trap": Color(0.7, 0.7, 0.7),
	"light_burst": Color(1, 0.95, 0.7), "flame_wave": Color(1, 0.55, 0.2), "inferno": Color(1, 0.5, 0.15), "volley": Color(0.9, 0.8, 0.6),
	"sanctuary": Color(1, 0.95, 0.6), "burn": Color(1, 0.5, 0.2), "bleed": Color(0.9, 0.2, 0.2), "drown": Color(0.3, 0.6, 1),
	"impact": Color(1, 1, 1),
}
const RANGED := ["arrow", "arrow_pierce", "knife", "rock", "harpoon", "bolt_arcane", "bolt_fire", "bolt_frost", "bolt_light", "bolt_spirit", "lightning", "volley"]
const LIGHTED := ["bolt_fire", "bolt_frost", "bolt_light", "bolt_arcane", "bolt_spirit", "lightning", "heal", "heal_wave", "flame_wave", "inferno",
	"light_burst", "sanctuary", "cleanse", "ward", "hush_wave"]

var map_view: BattleMapView
var terrain_nodes := {}
var _mat_cache := {}


func _pixel_mat(c: Color, billboard := true) -> StandardMaterial3D:
	var key := str(c) + str(billboard)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 5
	m.no_depth_test = false
	_mat_cache[key] = m
	return m


func _px(c: Color, size := 2.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size / 24.0, size / 24.0)
	mi.mesh = q
	mi.material_override = _pixel_mat(c).duplicate()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func color_of(kind: String) -> Color:
	return COLORS.get(kind, Color(1, 1, 1))


func burst(pos: Vector3, kind: String, count := 10, spread := 0.55, up := 0.6, time := 0.45) -> void:
	var c := color_of(kind)
	for i in count:
		var p := _px(c.lerp(Color.WHITE, randf() * 0.3), 2.0 if randf() < 0.7 else 3.0)
		add_child(p)
		p.global_position = pos
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0) * up, randf_range(-1, 1)).normalized() * randf_range(0.3, 1.0) * spread
		var tw := p.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "global_position", pos + dir + Vector3(0, up * 0.3, 0), time * randf_range(0.7, 1.2)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p.material_override, "albedo_color:a", 0.0, time)
		tw.chain().tween_callback(p.queue_free)


func rise(pos: Vector3, kind: String, count := 12) -> void:
	var c := color_of(kind)
	for i in count:
		var p := _px(c, 2.0)
		add_child(p)
		var start := pos + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.6), randf_range(-0.35, 0.35))
		p.global_position = start
		var tw := p.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "global_position", start + Vector3(0, randf_range(0.6, 1.2), 0), 0.8).set_delay(i * 0.03)
		tw.tween_property(p.material_override, "albedo_color:a", 0.0, 0.8).set_delay(i * 0.03)
		tw.chain().tween_callback(p.queue_free)


func flash_light(pos: Vector3, kind: String, energy := 2.2, time := 0.5, radius := 3.5) -> void:
	var l := OmniLight3D.new()
	l.light_color = color_of(kind)
	l.omni_range = radius
	l.light_energy = energy
	add_child(l)
	l.global_position = pos + Vector3(0, 0.8, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


## Travels from a to b; returns the flight time so the caller can await it.
func projectile(a: Vector3, b: Vector3, kind: String) -> float:
	var c := color_of(kind)
	var dist := a.distance_to(b)
	var t := clampf(dist / 14.0, 0.12, 0.45) / Settings.combat_speed
	var head := _px(c, 3.0)
	add_child(head)
	head.global_position = a
	var arc := 0.0
	if kind in ["arrow", "arrow_pierce", "rock", "volley", "knife"]:
		arc = minf(1.2, dist * 0.12)
	var trail: Array = []
	for i in 3:
		var tp := _px(c.darkened(0.2 + i * 0.15), 2.0)
		add_child(tp)
		tp.global_position = a
		trail.append(tp)
	var light: OmniLight3D = null
	if kind in LIGHTED:
		light = OmniLight3D.new()
		light.light_color = c
		light.omni_range = 2.5
		light.light_energy = 1.8
		head.add_child(light)
	var tw := head.create_tween()
	tw.tween_method(func(f: float):
		var p := a.lerp(b, f) + Vector3(0, sin(f * PI) * arc, 0)
		head.global_position = p
		for i in trail.size():
			var ff := maxf(0.0, f - 0.06 * (i + 1))
			trail[i].global_position = a.lerp(b, ff) + Vector3(0, sin(ff * PI) * arc, 0)
		, 0.0, 1.0, t)
	tw.tween_callback(func():
		head.queue_free()
		for tp in trail:
			tp.queue_free())
	return t


func lightning(a: Vector3, b: Vector3) -> void:
	var steps := 8
	var prev := a
	for i in range(1, steps + 1):
		var f := float(i) / steps
		var p := a.lerp(b, f) + (Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)) if i < steps else Vector3.ZERO)
		for k in 3:
			var q := _px(Color(1, 1, 0.7), 2.0)
			add_child(q)
			q.global_position = prev.lerp(p, k / 3.0)
			var tw := q.create_tween()
			tw.tween_property(q.material_override, "albedo_color:a", 0.0, 0.35)
			tw.tween_callback(q.queue_free)
		prev = p
	flash_light(b, "lightning", 3.0, 0.35)


# ---------------------------------------------------------------- terrain fx
func add_terrain(cells: Array, kind: String) -> void:
	for c in cells:
		remove_terrain_cell(c)
		var node := Node3D.new()
		add_child(node)
		var base := map_view.cell_top(c)
		node.global_position = base
		match kind:
			"smoke":
				for i in 5:
					var puff := _px(Color(0.82, 0.82, 0.88, 0.8), 10.0)
					node.add_child(puff)
					puff.position = Vector3(randf_range(-0.3, 0.3), 0.3 + randf() * 0.5, randf_range(-0.3, 0.3))
					var tw := puff.create_tween().set_loops()
					tw.tween_property(puff, "position:y", puff.position.y + 0.15, 1.2 + randf())
					tw.tween_property(puff, "position:y", puff.position.y, 1.2 + randf())
			"flood":
				var q := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(1, 1)
				q.mesh = pm
				q.material_override = _pixel_mat(Color(0.3, 0.65, 0.95, 0.55), false)
				q.position.y = 0.06
				node.add_child(q)
			"thorns":
				for i in 4:
					var sp := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.0
					cm.bottom_radius = 0.06
					cm.height = 0.45
					cm.radial_segments = 4
					sp.mesh = cm
					sp.material_override = PropLib.material(map_view.prop_biome)
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(0.35, 0.5, 0.2)
					sp.material_override = mat
					sp.position = Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
					sp.rotation = Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
					node.add_child(sp)
			"trap":
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.16
				tm.outer_radius = 0.22
				tm.rings = 8
				tm.ring_segments = 4
				ring.mesh = tm
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.6, 0.62, 0.66)
				ring.material_override = m
				ring.position.y = 0.03
				node.add_child(ring)
			"fire":
				for i in 6:
					var f := _px(Color(1.0, 0.55 + randf() * 0.3, 0.15), 4.0)
					node.add_child(f)
					f.position = Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
					var tw := f.create_tween().set_loops()
					tw.tween_property(f, "position:y", 0.5 + randf() * 0.3, 0.4 + randf() * 0.3)
					tw.tween_property(f, "position:y", 0.1, 0.01)
				var l := OmniLight3D.new()
				l.light_color = Color(1, 0.55, 0.2)
				l.omni_range = 2.4
				l.light_energy = 1.4
				l.position.y = 0.4
				node.add_child(l)
			"sanctuary":
				var q := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(0.96, 0.96)
				q.mesh = pm
				q.material_override = _pixel_mat(Color(1.0, 0.92, 0.55, 0.35), false)
				q.position.y = 0.04
				node.add_child(q)
				var l := OmniLight3D.new()
				l.light_color = Color(1, 0.9, 0.6)
				l.omni_range = 1.6
				l.light_energy = 0.8
				l.position.y = 0.5
				node.add_child(l)
		terrain_nodes[c] = node


func remove_terrain_cell(c: Vector2i) -> void:
	if terrain_nodes.has(c):
		terrain_nodes[c].queue_free()
		terrain_nodes.erase(c)
