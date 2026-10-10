extends Control
## Trailer director: --trailer=<shot> stages one shot of the game trailer,
## prints TRAILER_MARK lines (frame numbers) around the footage and quits.
## tools/trailer/make.py films every shot with Movie Maker and edits them.
##
## Shots are either dioramas (a map, units and a camera move, no HUD), staged
## fights (TrailerBattle playing a script of actions), autoplay fights with the
## full HUD, or the guild's own screens.

const TrailerBattle := preload("res://scripts/trailer/trailer_battle.gd")
const CREEP_SHADER := """
shader_type canvas_item;
// The Hush closing in: grey dithered on the world's pixel grid from the edges.
uniform float amount = 0.0;
uniform vec3 fog_color : source_color = vec3(0.62, 0.62, 0.66);
uniform float px = 3.0;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float time_k = 0.0;
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / px);
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c * vec2(1.45, 1.0)) / 0.87;
	float n = texture(noise_tex, cell / 160.0 + vec2(time_k * 0.01, 0.0)).r;
	float edge = r + (n - 0.5) * 0.45;
	float cov = clamp((edge - (1.05 - amount * 1.35)) / 0.22, 0.0, 1.0);
	ivec2 p = ivec2(mod(cell, 4.0));
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float th = (bayer[p.y * 4 + p.x] + 0.5) / 16.0;
	COLOR = vec4(fog_color, cov > th ? 1.0 : 0.0);
}
"""

var shot := ""
var layer: CanvasLayer
var cursor: Node2D = null
# the current diorama
var wv: WorldView = null
var mv: BattleMapView = null
var fx: FX = null
var views: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seed(20261009)
	# the player's own settings must not change the footage (and are never saved)
	Settings.fullscreen = false
	Settings.world_zoom = 0
	Settings.combat_speed = 1.0
	Settings.edge_pan = false
	Settings.screen_shake = true
	Settings.show_grid = false
	Settings.master_volume = 1.0
	Settings.sfx_volume = 1.0
	Settings.music_volume = 0.0   # the trailer has its own score
	Settings.apply()
	get_viewport().gui_disable_input = true
	layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	shot = Scenes.params.get("shot", "")
	while Scenes.busy:
		await get_tree().process_frame
	var parts := shot.split("_")
	if has_method("shot_" + shot):
		await call("shot_" + shot)
	elif parts[0] == "play" and parts.size() >= 5:
		await play(parts[1], parts[2], parts[3], int(parts[4]), float(parts[5]) if parts.size() > 5 else 45.0)
	else:
		push_error("TRAILER unknown shot " + shot)
	mark("end")
	await get_tree().process_frame
	get_tree().quit()


func _process(_delta: float) -> void:
	if wv and is_instance_valid(wv) and not views.is_empty():
		var bv := wv.basis_vectors()
		for uv in views:
			if is_instance_valid(uv):
				uv.set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
		if mv:
			mv.set_camera_yaw(wv.yaw)


func mark(name: String) -> void:
	print("TRAILER_MARK %s %d" % [name, Engine.get_frames_drawn()])


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ====================================================================== helpers
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A member of the given class, race and look, at a level, with its skill
## picks made (prefer: the subclass tree to favour) and an optional loadout.
func member(rng: RandomNumberGenerator, cls: String, race: String, gender: String, level: int, prefer := "", loadout: Array = []) -> Member:
	var m := Member.create(rng, cls, race, 2, level)
	if gender != "":
		m.gender = gender
		m.name = Member.random_name(rng, race, gender)
		m.pick_look(rng)
	m.auto_pick(rng, prefer)
	if not loadout.is_empty():
		m.loadout = loadout.duplicate()
	return m


func squad_of(specs: Array, level: int, s: int) -> Array:
	var rng := _rng(s)
	var out: Array = []
	for sp in specs:
		var m := member(rng, sp[0], sp[1], sp[2], level, sp[3] if sp.size() > 3 else "", sp[4] if sp.size() > 4 else [])
		m.id = out.size() + 1
		out.append(m)
	return out


## A map in a WorldView with no battle: the diorama shots.
func diorama(mission: Dictionary, time := "day", scale := 3, prep: Callable = Callable()) -> BattleGrid:
	wv = WorldView.new()
	add_child(wv)
	var out := MapGen.new().generate(mission, _rng(int(mission.get("seed", 1))), 4)
	var grid: BattleGrid = out["grid"]
	grid.time = time
	grid.hush = int(mission.get("hush_map", 0))
	if prep.is_valid():
		prep.call(grid)
	mv = BattleMapView.new()
	wv.world.add_child(mv)
	mv.build(grid, wv)
	mv.set_grid_alpha(0.0)
	fx = FX.new()
	fx.map_view = mv
	mv.add_child(fx)
	wv.world_scale = scale
	return grid


func unit_view(sprite: String, palette: Dictionary, cell: Vector2i, facing: Vector2i, region := "") -> UnitView:
	var uv := UnitView.new()
	mv.add_child(uv)
	uv.setup(sprite, palette, wv.pitch, region)
	uv.position = mv.unit_pos(cell)
	uv.face(facing)
	views.append(uv)
	return uv


func enemy_view(eid: String, cell: Vector2i, facing: Vector2i) -> UnitView:
	var d: Dictionary = DB.enemies[eid]
	return unit_view(d["sprite"], d.get("palette", {}), cell, facing)


## Clears a round plaza on the map: no props (nor buildings reaching into it),
## no water, one height, cobbles in the middle.
func plaza(g: BattleGrid, c: Vector2i, r: int, ground := "cobble") -> void:
	var h := g.height(c)
	for p in g.cells_in_radius(c, r + 4):
		if not g.inb(p):
			continue
		var tl := g.t(p)
		var d := Vector2(p - c).length()
		var big: bool = tl["prop"] in ["house", "hut", "arch", "bell_tower"] or String(tl["prop"]).ends_with("_part")
		if d <= r + 0.5 or (big and d <= r + 3.5):
			tl["prop"] = ""
		if d <= r + 0.5:
			tl["h"] = h
			tl["water"] = 0
			if d <= r - 0.5:
				tl["ground"] = ground


## A flat open patch: every cell within r of the result stands at one height
## with no prop or water. Searched outward from near.
func open_spot(g: BattleGrid, r: int, near: Vector2i, b: Battle = null) -> Vector2i:
	var best := near
	for rad in range(0, maxi(g.w, g.h)):
		for c in g.cells_in_radius(near, rad):
			if maxi(absi(c.x - near.x), absi(c.y - near.y)) != rad:
				continue
			var m := r + 3
			if c.x < m or c.y < m or c.x >= g.w - m or c.y >= g.h - m:
				continue
			var ok := true
			for p in g.cells_in_radius(c, r):
				if not g.inb(p) or not g.standable(p) or g.t(p)["prop"] != "" or int(g.t(p)["water"]) > 0 \
						or g.height(p) != g.height(c) or (b != null and b.unit_at(p, true) != null):
					ok = false
					break
			if ok:
				return c
	return best


## Linear camera move with easing; tb (a TrailerBattle) keeps its lock in step.
func pan(w: WorldView, from: Vector3, to: Vector3, dur: float, curve := -1.8, tb = null) -> void:
	var t := 0.0
	while t < dur:
		var p := from.lerp(to, ease(t / dur, curve))
		w.target = p
		w.target_goal = p
		if tb:
			tb.cam_goal = p
		await get_tree().process_frame
		t += get_process_delta_time()
	w.target = to
	w.target_goal = to
	if tb:
		tb.cam_goal = to


## Walks a unit view through cells without any rules (diorama shots).
func stroll(uv: UnitView, cells: Array, step_t := 0.32) -> void:
	uv.play("walk", false)
	for c in cells:
		var target := mv.unit_pos(c)
		var from := uv.position
		var d: Vector2i = c - Vector2i(roundi(from.x - 0.5), roundi(from.z - 0.5))
		uv.face(Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y)))
		var tw := uv.create_tween()
		tw.tween_property(uv, "position", target, step_t)
		await tw.finished
	uv.play("idle")


func fade_in_view(uv: UnitView, t := 0.6, burst := "hush") -> void:
	uv.set_alpha(0.0)
	uv.visible = true
	if fx and burst != "":
		fx.burst(uv.global_position + Vector3(0, 0.4, 0), burst, 14)
	var tw := uv.create_tween()
	tw.tween_method(func(a): uv.set_alpha(a), 0.0, 1.0, t)


func black(alpha := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(r)
	return r


# ---------------------------------------------------------------- cursor
func show_cursor(at: Vector2) -> void:
	if cursor == null:
		cursor = Node2D.new()
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 11), Vector2(3, 8), Vector2(5, 12), Vector2(7, 11), Vector2(5, 7), Vector2(9, 7)])
		var shade := Polygon2D.new()
		shade.polygon = pts
		shade.color = Color(0.08, 0.05, 0.1, 0.9)
		shade.position = Vector2(1, 1)
		cursor.add_child(shade)
		var line := Line2D.new()
		line.points = pts
		line.closed = true
		line.width = 1.0
		line.default_color = Color(0.1, 0.06, 0.12)
		var body := Polygon2D.new()
		body.polygon = pts
		body.color = Color(1.0, 0.97, 0.88)
		cursor.add_child(body)
		cursor.add_child(line)
		layer.add_child(cursor)
	cursor.position = at
	cursor.visible = true


func cursor_to(at: Vector2, dur: float, on_move: Callable = Callable()) -> void:
	var from := cursor.position
	var t := 0.0
	while t < dur:
		cursor.position = from.lerp(at, ease(t / dur, -2.2))
		if on_move.is_valid():
			on_move.call(cursor.position)
		await get_tree().process_frame
		t += get_process_delta_time()
	cursor.position = at
	if on_move.is_valid():
		on_move.call(at)


func click_pulse() -> void:
	Audio.sfx("ui_click", 0.02, -4.0)
	var tw := cursor.create_tween()
	tw.tween_property(cursor, "scale", Vector2(0.8, 0.8), 0.06)
	tw.tween_property(cursor, "scale", Vector2(1, 1), 0.1)


# ---------------------------------------------------------------- staged fights
## A battle for a staged shot. setup(b) runs before the scene exists: remove
## enemies, spawn the cast, move the squad. Returns the scene, not yet added.
func staged(mission: Dictionary, squad: Array, setup: Callable, clean := true) -> TrailerBattle:
	mission = mission.duplicate()
	mission["title"] = ""
	var b := BattleFactory.build(mission, squad, {"difficulty": 1})
	b.fog = false
	b.explore = false
	b.phase = "combat"
	setup.call(b)
	b.pop_events()
	for u in b.units:
		u.alerted = true
	Game.battle = b
	Settings.combat_speed = 1.35
	var tb: TrailerBattle = TrailerBattle.new()
	tb.clean = clean
	return tb


## Clears every enemy of the generated battle out of the rules.
func clear_enemies(b: Battle) -> void:
	for u in b.units.duplicate():
		if u.team != BattleUnit.TEAM_PLAYER:
			b.units.erase(u)


func squad_unit(b: Battle, i: int) -> BattleUnit:
	var n := 0
	for u in b.units:
		if u.team == BattleUnit.TEAM_PLAYER and u.member != null:
			if n == i:
				return u
			n += 1
	return null


## The valid target of a skill that catches the most hostiles in its area.
func best_target(b: Battle, u: BattleUnit, skill_id: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := -1
	for c in b.valid_targets(u, skill_id):
		var n := 0
		for o in b.affected(u, skill_id, c):
			if o.hostile_to(u):
				n += 1
			elif o.team == u.team:
				n -= 2
		if n > best_n:
			best_n = n
			best = c
	return best


func sure_hit(u: BattleUnit, crit := false) -> void:
	u.st["accuracy"] = 400
	if crit:
		u.st["crit"] = 100


func lock(tb: TrailerBattle, at: Vector3, scale := 3) -> void:
	tb.cam_lock = true
	tb.cam_goal = at
	tb.wv.target = at
	tb.wv.target_goal = at
	tb.wv.world_scale = scale


## Locks the camera on the middle of a cast of units (at chest height).
func frame(tb: TrailerBattle, cast: Array, scale := 5, nudge := Vector3.ZERO) -> void:
	var sum := Vector3.ZERO
	for u in cast:
		sum += tb.map_view.unit_pos(u.pos)
	lock(tb, sum / maxf(cast.size(), 1) + Vector3(0, 0.55, 0) + nudge, scale)


## Every unit of the battle that is still in it.
func cast_of(b: Battle) -> Array:
	return b.units.filter(func(u): return u.alive() and u.pos.x >= 0)


## A bigger bang than the game's own: a flash of light, a shower of sparks and a shake.
func boom(tb: TrailerBattle, at: Vector3, kind: String, count := 40) -> void:
	tb.fx.flash_light(at + Vector3(0, 0.6, 0), kind, 5.0, 0.9, 7.0)
	tb.fx.burst(at + Vector3(0, 0.4, 0), kind, count, 1.3, 1.4, 0.8)
	tb.wv.shake = 1.6


# ====================================================================== shots
## Opening: Carrow at dusk and the Great Bell on its square. "crack" marks the
## moment the bell breaks (a white flash and a shake).
func shot_bell() -> void:
	var k := {}
	var g := diorama({"region": "carrow", "objective": "survive", "seed": 31}, "dusk", 4, func(gg: BattleGrid):
		var cc := Vector2i(gg.w / 2, gg.h / 2)
		k["c"] = cc
		plaza(gg, cc, 3)
		for d in [Vector2i(-3, 0), Vector2i(0, -3), Vector2i(3, 0), Vector2i(0, 3)]:
			gg.t(cc + d)["prop"] = "lantern_post")
	var c: Vector2i = k["c"]
	print("TRAILER_INFO grid ", g.w, "x", g.h, " bell ", c)
	var bell := PropLib.instance("bell", "town")
	bell.position = mv.cell_top(c)
	bell.scale = Vector3.ONE * 2.8
	mv.add_child(bell)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.72, 0.42)
	glow.omni_range = 6.0
	glow.light_energy = 2.0
	glow.position = mv.cell_top(c) + Vector3(0.8, 2.4, 1.2)
	mv.add_child(glow)
	# townsfolk gathered on the square, looking up at it
	var rng := _rng(5)
	for i in 3:
		var m := Member.create(rng, ["warrior", "ranger", "mystic"][i], ["human", "tidefolk", "mothkin"][i], 1)
		var d: Vector2i = [Vector2i(2, 1), Vector2i(1, 2), Vector2i(-1, 2)][i]
		unit_view(m.variant, m.palette, c + d, Vector2i(-1, 0) if i == 0 else Vector2i(0, -1))
	var bv := wv.basis_vectors()
	var to: Vector3 = mv.cell_top(c) + Vector3(0, 1.2, 0) - bv["fwd_h"] * 0.6
	var from: Vector3 = to - bv["fwd_h"] * 5.0 + bv["right"] * 1.2
	from = clamp_in(g, from)
	wv.focus(from, true)
	await frames(8)
	mark("in")
	await pan(wv, from, to, 6.5, -1.6)
	await wait(0.6)
	mark("crack")
	wv.shake = 2.5
	Scenes.flash(Color(1, 1, 1, 0.9), 0.5)
	var tw := bell.create_tween()
	tw.tween_property(bell, "rotation:z", 0.12, 0.08)
	tw.tween_property(bell, "rotation:z", -0.07, 0.1)
	tw.tween_property(bell, "rotation:z", 0.0, 0.25)
	await wait(1.6)
	mark("out")


## Keeps a camera target inside the board (WorldView clamps it there anyway).
func clamp_in(g: BattleGrid, p: Vector3, margin := 1.0) -> Vector3:
	return Vector3(clampf(p.x, margin, g.w - margin), p.y, clampf(p.z, margin, g.h - margin))


## A warm land going grey: the Hush closes in from the edges, the colour drains
## and the Hollows come out of it.
func shot_creep() -> void:
	var g := diorama({"region": "ember", "objective": "survive", "seed": 12}, "day", 4)
	var c := open_spot(g, 1, Vector2i(g.w / 2, g.h / 2))
	print("TRAILER_INFO grid ", g.w, "x", g.h, " spot ", c)
	var rng := _rng(9)
	var folk := []
	for i in 2:
		var m := Member.create(rng, ["graftwarden", "ranger"][i], ["barkborn", "human"][i], 1)
		folk.append(unit_view(m.variant, m.palette, c + [Vector2i(0, 1), Vector2i(1, 0)][i], Vector2i(1, 1)))
	var hollows := []
	for d in [Vector2i(-3, -2), Vector2i(3, -3), Vector2i(-4, 1), Vector2i(2, 2)]:
		var cell: Vector2i = c + d
		if not g.inb(cell) or not g.standable(cell):
			continue
		var hv := enemy_view("hollow", cell, Vector2i(0, 0) - Vector2i(signi(d.x), signi(d.y)))
		hv.visible = false
		hollows.append([hv, d])
	var at := clamp_in(g, mv.cell_top(c) + Vector3(0, 0.6, 0))
	wv.focus(at, true)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CREEP_SHADER
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", load("res://assets/textures/noise.png"))
	mat.set_shader_parameter("px", float(wv.world_scale))
	rect.material = mat
	layer.add_child(rect)
	await frames(8)
	mark("in")
	var dur := 7.0
	var t := 0.0
	var spawned := 0
	var bv := wv.basis_vectors()
	while t < dur:
		var k := t / dur
		mat.set_shader_parameter("amount", ease(k, 1.8) * 0.95)
		mat.set_shader_parameter("time_k", t)
		mv.set_hush(5.0 * clampf(k * 1.4 - 0.2, 0.0, 1.0))
		wv.set_hush(clampf(k * 1.3 - 0.3, 0.0, 0.8), 0.0)
		var p: Vector3 = at.lerp(at - bv["fwd_h"] * 0.8, ease(k, -1.5))
		wv.target = p
		wv.target_goal = p
		if spawned < hollows.size() and k > 0.28 + spawned * 0.1:
			var hv: UnitView = hollows[spawned][0]
			fade_in_view(hv, 0.8)
			var d: Vector2i = hollows[spawned][1]
			var step := Vector2i(-signi(d.x), -signi(d.y))
			var path := []
			for n in 2:
				var nc: Vector2i = c + d + step * (n + 1)
				if g.inb(nc) and g.standable(nc):
					path.append(nc)
			stroll(hv, path, 0.8)
			spawned += 1
		if k > 0.5:
			for f in folk:
				f.set_grey(clampf((k - 0.5) * 2.2, 0.0, 0.9))
		await get_tree().process_frame
		t += get_process_delta_time()
	await wait(0.4)
	mark("out")


## Inside the Hush: a grey procession of the forgotten.
func shot_grey() -> void:
	var g := diorama({"region": "unremembered", "objective": "survive", "seed": 44, "hush_map": 5}, "day", 4)
	var c := open_spot(g, 2, Vector2i(g.w / 2, g.h / 2))
	print("TRAILER_INFO grid ", g.w, "x", g.h, " spot ", c)
	var cast := [["nameless_monument", Vector2i(-3, -3)], ["hollow", Vector2i(-1, -3)], ["hollow", Vector2i(-3, -1)],
		["quietling", Vector2i(-1, -1)], ["hollow", Vector2i(-2, 0)], ["paper_wraith", Vector2i(0, -3)], ["hollow", Vector2i(-4, -1)],
		["unwritten", Vector2i(-2, -2)]]
	var walkers := []
	for e in cast:
		var cell: Vector2i = c + e[1]
		if not g.inb(cell):
			continue
		walkers.append([enemy_view(e[0], cell, Vector2i(1, 1)), cell, e[0]])
	# an Echo: a fallen member, greyed and half there
	var rng := _rng(77)
	var em := Member.create(rng, "ranger", "mothkin", 2, 4)
	var echo := unit_view(em.variant, em.palette, c + Vector2i(1, -1), Vector2i(1, 1))
	echo.set_ghost(0.45)
	echo.set_grey(0.85)
	var at := clamp_in(g, mv.cell_top(c) + Vector3(0, 0.6, 0))
	var bv := wv.basis_vectors()
	wv.focus(at, true)
	wv.set_hush(0.2, 0.6)
	await frames(8)
	mark("in")
	for w in walkers:
		var cell: Vector2i = w[1]
		var n := 3 if w[2] != "nameless_monument" else 2
		var path := []
		for i in n:
			var nc: Vector2i = cell + Vector2i(i + 1, i + 1) - Vector2i(0, (i + 1) % 2)
			if not g.inb(nc):
				break
			path.append(nc)
		stroll(w[0], path, 1.1 if w[2] == "nameless_monument" else 0.8)
	await pan(wv, at - bv["fwd_h"] * -0.6, clamp_in(g, at - bv["fwd_h"] * 1.0), 6.0, -1.4)
	mark("out")


func _tavern(c: Campaign, scale: int) -> TavernView:
	Game.campaign = c
	wv = WorldView.new()
	add_child(wv)
	var tv := TavernView.new()
	wv.world.add_child(tv)
	tv.build(c, wv)
	wv.world_scale = scale
	return tv


## The tavern as it is inherited: empty, boarded, dark.
func shot_tavern_empty() -> void:
	var c := Campaign.new()
	c.new_game("The Lantern Company", 1, false, 21)
	c.roster.clear()
	c.recruits.clear()
	for fid in c.facilities:
		c.facilities[fid] = 0
	_tavern(c, 4)
	var bv := wv.basis_vectors()
	var at := wv.target
	await frames(8)
	mark("in")
	await pan(wv, at + bv["right"] * 1.2 - bv["fwd_h"] * 0.6, at - bv["right"] * 0.8 + bv["fwd_h"] * 0.2, 5.0, -1.5)
	mark("out")


## The same tavern full of life: every facility built, a roster of all peoples.
func shot_tavern_full() -> void:
	var c := Campaign.new()
	c.new_game("The Lantern Company", 1, false, 21)
	for fid in c.facilities:
		c.facilities[fid] = 3 if fid in ["forge", "training", "library", "memorial"] else 2
	var rng := _rng(13)
	c.roster.clear()
	var cast := [["warrior", "human"], ["tidecaller", "tidefolk"], ["lanternbearer", "mothkin"], ["graftwarden", "barkborn"],
		["sandreaver", "khepri"], ["ranger", "human"], ["mystic", "mothkin"], ["rogue", "khepri"], ["warrior", "barkborn"], ["mystic", "tidefolk"]]
	for e in cast:
		c.add_member(Member.create(rng, e[0], e[1], 2, 3))
	_tavern(c, 4)
	var bv := wv.basis_vectors()
	var at := wv.target
	await frames(8)
	mark("in")
	await pan(wv, at - bv["right"] * 1.0 + bv["fwd_h"] * 0.5, at + bv["right"] * 1.6 - bv["fwd_h"] * 0.3, 6.0, -1.5)
	mark("out")


## The peoples of Ambral, one hero each, on Carrow's square in the sun.
func shot_peoples() -> void:
	var k := {}
	var g := diorama({"region": "carrow", "objective": "survive", "seed": 8}, "day", 5, func(gg: BattleGrid):
		var cc := Vector2i(gg.w / 2, gg.h / 2)
		k["c"] = cc
		plaza(gg, cc, 4))
	var c: Vector2i = k["c"]
	print("TRAILER_INFO grid ", g.w, "x", g.h, " spot ", c)
	var rng := _rng(21)
	var cast := [["warrior", "human", "m"], ["tidecaller", "tidefolk", "f"], ["lanternbearer", "mothkin", "f"],
		["graftwarden", "barkborn", "m"], ["sandreaver", "khepri", "f"]]
	var heroes := []
	for i in cast.size():
		var e: Array = cast[i]
		var m := Member.create(rng, e[0], e[1], 2, 4)
		m.gender = e[2]
		m.pick_look(rng)
		# a row across the screen: screen right is +x -z
		var cell := c + Vector2i(-2 + i, 2 - i)
		heroes.append(unit_view(m.variant, m.palette, cell, Vector2i(1, 1)))
	var bv := wv.basis_vectors()
	var mid := mv.cell_top(c) + Vector3(0, 0.7, 0)
	var from: Vector3 = mid - bv["right"] * 1.6
	var to: Vector3 = mid + bv["right"] * 1.6
	wv.focus(from, true)
	await frames(8)
	mark("in")
	pan(wv, from, to, 6.0, 1.0)
	for i in heroes.size():
		await wait(0.6 if i > 0 else 0.4)
		var anim := "cast" if i % 2 else "attack"
		heroes[i].play(anim)
		fx.rise(heroes[i].global_position, ["buff", "heal", "light_burst", "roots", "sand"][i], 10)
		Audio.sfx(["swing", "water", "cast", "roots", "swing"][i], 0.05, -6.0)
	await wait(3.0)
	mark("out")


## One of the four factions at home: three of its people on open ground in
## their region, the one in the middle working its people's art.
func _faction(region: String, time: String, s: int, race: String, cast: Array, art: String, sound: String, ground := "") -> void:
	var g := diorama({"region": region, "objective": "survive", "seed": s}, time, 6)
	var c := open_spot(g, 2, Vector2i(g.w / 2, g.h / 2))
	print("TRAILER_INFO grid ", g.w, "x", g.h, " spot ", c)
	var rng := _rng(s * 7 + 1)
	# a row across the screen (screen right is +x -z), the outer two turned to the middle
	var cells := [Vector2i(0, 0), Vector2i(-1, 1), Vector2i(1, -1)]
	var facing := [Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)]
	var heroes := []
	for i in cast.size():
		var e: Array = cast[i]
		var m := member(rng, e[0], race, e[1], 3)
		heroes.append(unit_view(m.variant, m.palette, c + cells[i], facing[i]))
	var bv := wv.basis_vectors()
	var mid := mv.cell_top(c) + Vector3(0, 0.6, 0)
	var from := clamp_in(g, mid - bv["right"] * 0.6 + bv["fwd_h"] * 0.25)
	var to := clamp_in(g, mid + bv["right"] * 0.6)
	wv.focus(from, true)
	await frames(8)
	mark("in")
	pan(wv, from, to, 3.4, 1.0)
	await wait(0.3)
	heroes[0].play("cast")
	fx.rise(heroes[0].global_position, art, 24)
	fx.burst(heroes[0].global_position + Vector3(0, 0.5, 0), art, 30, 1.0, 0.9, 0.7)
	fx.flash_light(heroes[0].global_position, art, 3.0, 0.9, 4.0)
	if ground != "":
		var around := []
		for p in g.cells_in_radius(c, 2):
			if g.inb(p) and g.standable(p) and not p in [c, c + cells[1], c + cells[2]]:
				around.append(p)
		fx.add_terrain(around, ground)
	Audio.sfx(sound, 0.05, -4.0)
	await wait(0.45)
	heroes[1].play("attack")
	await wait(0.25)
	heroes[2].play("cast")
	await wait(2.4)
	mark("out")


## The Saltborn Compact: Tidefolk sailors on the Coast of the Drowned Bells.
func shot_faction_saltborn() -> void:
	await _faction("coast", "dusk", 61, "tidefolk", [["tidecaller", "f"], ["warrior", "m"], ["ranger", "f"]], "water", "water", "flood")


## The Lantern Conclave: Mothkin archivists on the Lampwick Stilts at night.
func shot_faction_lantern() -> void:
	await _faction("stilts", "night", 62, "mothkin", [["lanternbearer", "f"], ["mystic", "m"], ["rogue", "f"]], "light_burst", "cast", "sanctuary")


## The Rootwardens: Barkborn of the Ember Wood, in its endless autumn.
func shot_faction_rootwardens() -> void:
	await _faction("ember", "day", 63, "barkborn", [["graftwarden", "m"], ["warrior", "f"], ["ranger", "m"]], "roots", "roots", "thorns")


## The Glass Caravans: Khepri merchants of the Sunken Dunes.
func shot_faction_glass() -> void:
	await _faction("dunes", "dusk", 64, "khepri", [["sandreaver", "f"], ["rogue", "m"], ["mystic", "f"]], "glass", "swing")


# ---------------------------------------------------------------- the guild's screens
func _campaign() -> Campaign:
	var c := Campaign.new()
	c.new_game("The Lantern Company", 1, false, 21)
	c.tutorial_seen["hub"] = true
	for fid in ["library", "forge", "memorial", "training", "nursery", "recruiter"]:
		c.facilities[fid] = 1 + (1 if fid in ["forge", "training"] else 0)
	var rng := _rng(4)
	for e in [["tidecaller", "tidefolk"], ["lanternbearer", "mothkin"], ["graftwarden", "barkborn"], ["sandreaver", "khepri"]]:
		c.add_member(Member.create(rng, e[0], e[1], 2, 2))
	c.gold = 900
	c.renown = 70
	c.materials = 20
	c.hush = 31
	Game.campaign = c
	return c


## The quest board: letters from the four factions, one after another.
func shot_board() -> void:
	_campaign()
	var hub: Node = load("res://scenes/guild.tscn").instantiate()
	add_child(hub)
	await wait(1.2)
	hub.open_screen("board")
	await frames(10)
	show_cursor(Vector2(330, 300))
	mark("in")
	await wait(0.4)
	for i in [1, 2, 4]:
		var cards: Array = []
		for b in hub.screen.find_children("*", "Button", true, false):
			if b.toggle_mode:
				cards.append(b)
		if i >= cards.size():
			break
		var target: Vector2 = cards[i].get_global_rect().get_center() + Vector2(40, 2)
		await cursor_to(target, 0.45)
		click_pulse()
		cards[i].pressed.emit()
		await wait(1.25)
	mark("out")


func shot_squad() -> void:
	var c := _campaign()
	var hub: Node = load("res://scenes/guild.tscn").instantiate()
	add_child(hub)
	await wait(1.2)
	var mid := -1
	for m in c.board:
		if m["category"] != "story":
			mid = int(m["id"])
			break
	hub.open_screen("squad", {"mission": mid})
	await frames(10)
	mark("in")
	await wait(3.0)
	mark("out")


## A player's turn as it looks in play: the move tiles, a skill picked, the
## hit chance on the target, and the shot.
func shot_turn() -> void:
	var sq := squad_of([["ranger", "human", "f", "marksman", ["aimed_shot", "volley", "headshot"]], ["warrior", "barkborn", "m"],
		["mystic", "mothkin", "f"], ["rogue", "khepri", "m"]], 4, 31)
	var k := {}
	var tb := staged({"region": "coast", "objective": "survive", "skulls": 4, "seed": 61, "time": "day"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		var ranger := squad_unit(b, 0)
		k["ranger"] = ranger
		ranger.pos = spot + Vector2i(-2, 2)
		squad_unit(b, 1).pos = spot + Vector2i(-1, 0)
		squad_unit(b, 2).pos = spot + Vector2i(-3, 1)
		squad_unit(b, 3).pos = spot + Vector2i(0, 3)
		k["foe"] = b.spawn_enemy("reef_raider", spot + Vector2i(2, -2))
		b.spawn_enemy("stinger", spot + Vector2i(3, 0))
		b.spawn_enemy("reef_harpooner", spot + Vector2i(1, -4))
		ranger.facing = Vector2i(1, -1), false)
	tb.staged = func(s: TrailerBattle):
		var spot: Vector2i = k["spot"]
		var ranger: BattleUnit = k["ranger"]
		var foe: BattleUnit = k["foe"]
		lock(s, s.map_view.cell_top(spot) + Vector3(0, 0, 0.5), 3)
		s.battle.current = ranger
		s.turn_unit = ranger
		s._begin_player_turn(ranger)
		await frames(6)
		mark("in")
		var mouse := func(p: Vector2):
			s.fake_mouse = p
			s._update_hover()
		show_cursor(s.wv.world_to_screen(s.map_view.cell_top(spot + Vector2i(-3, 3))))
		mouse.call(cursor.position)
		await wait(0.3)
		await cursor_to(s.wv.world_to_screen(s.map_view.cell_top(spot + Vector2i(-1, 2))), 0.7, mouse)
		await wait(0.6)
		# pick Aimed Shot and aim at the raider
		s._on_action("skill", "aimed_shot")
		await wait(0.35)
		await cursor_to(s.wv.world_to_screen(s.map_view.cell_top(foe.pos) + Vector3(0, 0.5, 0)), 0.65, mouse)
		await wait(1.3)
		mark("click")
		click_pulse()
		await s._click()
		await wait(1.2)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## Mystic's Meteor on a pack in the Ember Wood at dusk, then a Volley.
func shot_meteor() -> void:
	var sq := squad_of([["mystic", "human", "f", "elemental", ["meteor", "firebolt", "flame_wave"]], ["ranger", "mothkin", "m", "", ["volley"]],
		["warrior", "barkborn", "m"], ["rogue", "khepri", "f"]], 6, 41)
	var k := {}
	var tb := staged({"region": "ember", "objective": "survive", "skulls": 5, "seed": 23, "time": "dusk"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		k["mystic"] = squad_unit(b, 0)
		k["ranger"] = squad_unit(b, 1)
		squad_unit(b, 0).pos = spot + Vector2i(-3, 2)
		squad_unit(b, 1).pos = spot + Vector2i(-2, 3)
		squad_unit(b, 2).pos = spot + Vector2i(-1, 1)
		squad_unit(b, 3).pos = spot + Vector2i(-3, 0)
		for e in [["masked_spirit", Vector2i(2, -2)], ["rot_deer", Vector2i(3, -1)], ["masked_spirit", Vector2i(2, -1)], ["rot_deer", Vector2i(1, -2)], ["spirit_elder", Vector2i(3, -3)]]:
			var eu := b.spawn_enemy(e[0], spot + e[1])
			eu.facing = Vector2i(-1, 1)
			if e[0] != "spirit_elder":
				eu.hp = int(eu.hp * 0.35)
		sure_hit(squad_unit(b, 1)))
	tb.staged = func(s: TrailerBattle):
		frame(s, cast_of(s.battle), 5, Vector3(0.3, 0, -0.3))
		await frames(10)
		mark("in")
		await wait(0.6)
		mark("meteor")
		var tgt := best_target(s.battle, k["mystic"], "meteor")
		get_tree().create_timer(0.2).timeout.connect(func(): boom(s, s.map_view.cell_top(tgt), "inferno", 60))
		await s.act(k["mystic"], "meteor", tgt)
		await wait(0.5)
		mark("volley")
		await s.act(k["ranger"], "volley", best_target(s.battle, k["ranger"], "volley"))
		await wait(1.0)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## A Warrior's Blitz: three leaps, three foes.
func shot_blitz() -> void:
	var sq := squad_of([["warrior", "human", "m", "warlord", ["blitz", "cleave"]], ["ranger", "tidefolk", "f"],
		["mystic", "mothkin", "m"], ["rogue", "khepri", "f"]], 6, 52)
	var k := {}
	var tb := staged({"region": "carrow", "objective": "survive", "skulls": 5, "seed": 99, "time": "day"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		var war := squad_unit(b, 0)
		k["war"] = war
		war.pos = spot + Vector2i(-2, 0)
		squad_unit(b, 1).pos = spot + Vector2i(-3, 2)
		squad_unit(b, 2).pos = spot + Vector2i(-4, 0)
		squad_unit(b, 3).pos = spot + Vector2i(-3, -2)
		for d in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(3, 2)]:
			var eu := b.spawn_enemy("brigand", spot + d)
			eu.facing = Vector2i(-1, 0)
			eu.hp = int(eu.hp * 0.5)
			if not k.has("first"):
				k["first"] = eu
		b.spawn_enemy("brigand_archer", spot + Vector2i(4, -2))
		sure_hit(war, true))
	tb.staged = func(s: TrailerBattle):
		frame(s, cast_of(s.battle), 5, Vector3(0.5, 0, -0.5))
		await frames(10)
		mark("in")
		await wait(0.5)
		mark("blitz")
		await s.act(k["war"], "blitz", k["first"].pos)
		await wait(1.2)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## A Tidecaller drowns the shallows: Tsunami into a pack of stingers.
func shot_tsunami() -> void:
	var sq := squad_of([["tidecaller", "tidefolk", "f", "tides", ["tsunami", "tidal_wave"]], ["warrior", "human", "m"],
		["ranger", "mothkin", "f"], ["mystic", "human", "m"]], 6, 63)
	var k := {}
	var tb := staged({"region": "coast", "objective": "survive", "skulls": 5, "seed": 14, "time": "day"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		k["tide"] = squad_unit(b, 0)
		squad_unit(b, 0).pos = spot + Vector2i(-1, 1)
		squad_unit(b, 1).pos = spot + Vector2i(-2, 0)
		squad_unit(b, 2).pos = spot + Vector2i(-2, 3)
		squad_unit(b, 3).pos = spot + Vector2i(-3, 1)
		for e in [["stinger", Vector2i(1, -1)], ["stinger", Vector2i(2, -1)], ["reef_raider", Vector2i(1, 0)], ["stinger", Vector2i(2, 0)], ["reef_harpooner", Vector2i(3, -2)]]:
			var eu := b.spawn_enemy(e[0], spot + e[1])
			eu.facing = Vector2i(-1, 0)
			eu.hp = int(eu.hp * 0.45)
		sure_hit(squad_unit(b, 0)))
	tb.staged = func(s: TrailerBattle):
		frame(s, cast_of(s.battle), 5, Vector3(0.4, 0, -0.4))
		await frames(10)
		mark("in")
		await wait(0.5)
		mark("tsunami")
		await s.act(k["tide"], "tsunami", best_target(s.battle, k["tide"], "tsunami"))
		await wait(1.3)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## A Sandreaver in the middle of the pack: Thousand Shards.
func shot_shards() -> void:
	var sq := squad_of([["sandreaver", "khepri", "m", "glass", ["thousand_shards", "glass_flurry"]], ["warrior", "human", "f"],
		["ranger", "tidefolk", "m"], ["mystic", "mothkin", "f"]], 7, 74)
	var k := {}
	var tb := staged({"region": "dunes", "objective": "survive", "skulls": 6, "seed": 35, "time": "day"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		var reaver := squad_unit(b, 0)
		k["reaver"] = reaver
		reaver.pos = spot
		squad_unit(b, 1).pos = spot + Vector2i(-3, 1)
		squad_unit(b, 2).pos = spot + Vector2i(-4, 3)
		squad_unit(b, 3).pos = spot + Vector2i(-3, -2)
		for e in [["glass_scorpion", Vector2i(1, 0)], ["toad_bandit", Vector2i(0, -1)], ["glass_scorpion", Vector2i(-1, -1)], ["toad_bandit", Vector2i(1, 1)], ["toad_slinger", Vector2i(2, -2)], ["glass_scorpion", Vector2i(0, 2)]]:
			var eu := b.spawn_enemy(e[0], spot + e[1])
			eu.hp = int(eu.hp * 0.4)
		sure_hit(reaver, true))
	tb.staged = func(s: TrailerBattle):
		var spot: Vector2i = k["spot"]
		var reaver: BattleUnit = k["reaver"]
		for u in s.battle.units:
			if u.team == BattleUnit.TEAM_ENEMY:
				s.face_to(u, reaver.pos)
		frame(s, [reaver], 5)
		await frames(10)
		mark("in")
		await wait(0.5)
		mark("shards")
		await s.act(reaver, "thousand_shards", reaver.pos)
		await wait(1.3)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## The cost: a member is Downed by an Ashen Huntress, then falls for good.
func shot_fall() -> void:
	var sq := squad_of([["warrior", "human", "m", "", ["shield_bash"]], ["rogue", "khepri", "f"], ["ranger", "mothkin", "f"],
		["mystic", "tidefolk", "m"]], 6, 85)
	var k := {}
	var tb := staged({"region": "ember", "objective": "survive", "skulls": 6, "seed": 51, "time": "dusk"}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		var victim := squad_unit(b, 2)
		k["victim"] = victim
		victim.mods.erase("lucky")
		victim.mods.erase("carapace")
		victim.member.name = "Ilsa Venn"
		victim.name = "Ilsa Venn"
		victim.pos = spot
		squad_unit(b, 0).pos = spot + Vector2i(-2, 1)
		squad_unit(b, 1).pos = spot + Vector2i(-3, 3)
		squad_unit(b, 3).pos = spot + Vector2i(-1, 3)
		victim.hp = 6
		var hunter := b.spawn_enemy("ashen_huntress", spot + Vector2i(3, -2))
		k["hunter"] = hunter
		b.spawn_enemy("mourning_oak", spot + Vector2i(4, 0))
		sure_hit(hunter, false))
	tb.staged = func(s: TrailerBattle):
		var spot: Vector2i = k["spot"]
		var victim: BattleUnit = k["victim"]
		var hunter: BattleUnit = k["hunter"]
		s.face_to(hunter, victim.pos)
		s.face_to(victim, hunter.pos)
		frame(s, [victim, hunter], 5)
		await frames(10)
		mark("in")
		await wait(0.5)
		mark("shot1")
		await s.act(hunter, "e_ash_arrow", victim.pos)
		print("TRAILER_STATE victim ", victim.state, " hp ", victim.hp)
		await wait(1.2)
		mark("shot2")
		if victim.state == "downed":
			await s.act(hunter, "e_ash_arrow", victim.pos)
		print("TRAILER_STATE victim ", victim.state, " hp ", victim.hp)
		await wait(2.4)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## The Heart of the Hush: the Unnamed among her Echoes speaks, then strikes.
func shot_unnamed() -> void:
	var sq := squad_of([["lanternbearer", "mothkin", "f", "light", ["dawn", "judgement"]], ["warrior", "human", "m"],
		["ranger", "tidefolk", "f"], ["graftwarden", "barkborn", "m"]], 7, 96)
	var k := {}
	var tb := staged({"region": "unremembered", "objective": "survive", "skulls": 7, "seed": 66, "hush_map": 5}, sq, func(b: Battle):
		clear_enemies(b)
		var spot := open_spot(b.grid, 3, Vector2i(b.grid.w / 2, b.grid.h / 2), b)
		k["spot"] = spot
		k["light"] = squad_unit(b, 0)
		squad_unit(b, 0).pos = spot + Vector2i(-2, 2)
		squad_unit(b, 1).pos = spot + Vector2i(-1, 1)
		squad_unit(b, 2).pos = spot + Vector2i(-3, 3)
		squad_unit(b, 3).pos = spot + Vector2i(0, 2)
		k["boss"] = b.spawn_enemy("the_unnamed", spot + Vector2i(2, -2))
		var rng := _rng(3)
		for i in 2:
			var em := Member.create(rng, ["rogue", "warrior"][i], ["human", "khepri"][i], 2, 5)
			var eu := BattleFactory.echo_unit(em.to_dict(), 7, rng)
			eu.pos = spot + [Vector2i(3, 0), Vector2i(0, -3)][i]
			b.add_unit(eu)
		b.spawn_enemy("nameless_monument", spot + Vector2i(4, -3))
		sure_hit(k["boss"])
		k["boss"].st["attack"] = int(k["boss"].st["attack"]) * 3)
	tb.staged = func(s: TrailerBattle):
		var spot: Vector2i = k["spot"]
		var boss: BattleUnit = k["boss"]
		for u in s.battle.units:
			if u.team == BattleUnit.TEAM_ENEMY:
				s.face_to(u, spot + Vector2i(-1, 1))
		frame(s, cast_of(s.battle), 5, Vector3(0.6, 0, -0.6))
		s.wv.set_hush(0.1, 0.25)
		await frames(10)
		mark("in")
		await wait(0.4)
		s.hud.bark(s._head(boss), "Say my name. I have waited twenty years for someone to say it.")
		Audio.sfx("bell_far", 0.0, -6.0)
		mark("bark")
		await wait(2.6)
		mark("strike")
		await s.act(boss, "e_grief_wave", best_target(s.battle, boss, "e_grief_wave"))
		await wait(0.4)
		mark("dawn")
		await s.act(k["light"], "dawn", k["light"].pos)
		await wait(1.2)
		k["done"] = true
		mark("out")
	add_child(tb)
	while not k.get("done", false):
		await get_tree().process_frame


## Carrow at dusk behind the closing title (the title screen without its menu).
func shot_title_bg() -> void:
	var t: Node = load("res://scenes/title.tscn").instantiate()
	add_child(t)
	await frames(2)
	for ch in t.get_children():
		if ch is CanvasItem and not ch is WorldView:
			ch.visible = false
	var w: WorldView = t.wv
	var at := w.target
	var bv := w.basis_vectors()
	await frames(8)
	mark("in")
	await pan(w, at - bv["right"] * 0.8, at + bv["right"] * 0.6, 10.0, 1.0)
	mark("out")


# ---------------------------------------------------------------- autoplay
## A real fight played by the AI on both sides, with the full HUD:
## play_<region>_<time>_<objective>_<seed>[_<seconds>].
func play(region: String, time: String, objective: String, s: int, seconds: float) -> void:
	Game.autoplay = true
	Settings.combat_speed = 1.25
	Settings.show_grid = true
	var races := ["human", "tidefolk", "mothkin", "barkborn", "khepri"]
	var rng := _rng(s)
	var specs := [["warrior", races[rng.randi() % 5], ""], ["ranger", races[rng.randi() % 5], ""], ["mystic", races[rng.randi() % 5], "", "evocation"],
		["rogue", races[rng.randi() % 5], ""]]
	var sq := squad_of(specs, 4, s)
	var mission := {"region": region, "objective": objective, "skulls": 4, "seed": s, "par_rounds": 8, "time": time,
		"title": DB.regions[region]["places"][s % 8]}
	if region == "unremembered":
		mission["hush_map"] = 4
	Game.battle = BattleFactory.build(mission, sq, {"difficulty": 1})
	var tb: TrailerBattle = TrailerBattle.new()
	add_child(tb)
	await frames(2)
	mark("in")
	var t := 0.0
	while t < seconds and not tb.ended:
		await get_tree().process_frame
		t += get_process_delta_time()
	await wait(2.5)
	mark("out")
	Game.autoplay = false
