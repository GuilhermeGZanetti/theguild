class_name BattleScene
extends Control
## Plays a Battle: turn loop, player input, AI turns and event animation.

signal turn_finished

const C_MOVE := Color(0.22, 0.45, 1.0, 0.3)
const C_MOVE_B := Color(0.35, 0.62, 1.0, 1.0)
const C_ZOC := Color(1.0, 0.55, 0.2, 0.22)
const C_ENEMY := Color(1.0, 0.3, 0.25, 0.16)
const C_ENEMY_B := Color(1.0, 0.45, 0.35, 0.85)
const C_ALLY := Color(0.4, 1.0, 0.5, 0.18)
const C_ALLY_B := Color(0.55, 1.0, 0.6, 0.85)
const C_TILE := Color(1.0, 0.85, 0.35, 0.14)
const C_AOE := Color(1.0, 0.8, 0.3, 0.38)
const C_EXTRACT := Color(0.35, 0.95, 0.45, 0.2)
const BARKS_START := ["For the guild!", "Stay close.", "Let's end this quick.", "Eyes open.", "Remember the ledger.", "Together, then."]
const BARKS_KILL := ["One less.", "Down you go!", "Next!", "That's for Carrow.", "Stay down."]
const BARKS_HURT := ["Argh!", "I'm hit!", "Just a scratch...", "Watch it!"]
const BARKS_DOWN := ["Someone... help...", "Can't... stand...", "Tell them... I tried..."]
const BARKS_ALLY_DOWN := ["Hold on, I'm coming!", "No! Get up!", "Man down!"]
# each people has its own way of saying things
const RACE_BARKS := {
	"tidefolk": {"start": ["The tide's with us.", "Hold fast!"], "kill": ["Back to the deep!", "Sunk."], "hurt": ["Just saltwater...", "Rough seas!"],
		"down": ["The water... is cold...", "Remember... my ship..."], "ally_down": ["Hold fast, I'm coming!", "Not to the deep, not today!"]},
	"mothkin": {"start": ["Lanterns up.", "Everything is being recorded."], "kill": ["Recorded.", "Filed away."], "hurt": ["My wings!", "Ow! Ink everywhere..."],
		"down": ["Keep... my light...", "Write... my name..."], "ally_down": ["I won't forget you. Get up!", "Stay in the light!"]},
	"barkborn": {"start": ["Every season ends.", "Roots deep."], "kill": ["Return to the soil.", "Fall like leaves."], "hurt": ["Only bark.", "Sap and splinters!"],
		"down": ["Plant me... somewhere warm...", "Winter... already?"], "ally_down": ["Not yet. Not this season!", "Grow back, friend!"]},
	"khepri": {"start": ["Let's make this profitable.", "Watch the cargo."], "kill": ["Paid in full.", "Deal closed."], "hurt": ["Shell's holding!", "That'll cost you!"],
		"down": ["Worth... every coin...", "Tell the caravan..."], "ally_down": ["Nobody leaves without their share!", "Up! You owe me!"]},
}
const VOICE_PITCH := {"human": 1.0, "tidefolk": 0.9, "mothkin": 1.28, "barkborn": 0.78, "khepri": 1.12}

var battle: Battle
var wv: WorldView
var map_view: BattleMapView
var overlay: TileOverlay
var fx: FX
var hud: BattleHUD
var views := {}
var state := "busy"
var mode := "move"
var selected_skill := ""
var reach := {}
var hover_cell := Vector2i(-1, -1)
var hover_uid := -1
var active: BattleUnit = null
var cover_icons: Array = []
var menu: Control = null
var dragging := false
var drag_last := Vector2.ZERO
var ended := false
var mouse_override := Vector2(-1, -1)   # developer captures
var last_mouse := Vector2(-1, -1)       # canvas position of the latest mouse event


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the root must not swallow mouse events: clicks on the world reach _unhandled_input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle = Game.battle
	if battle == null:
		_build_test_battle()
	wv = WorldView.new()
	add_child(wv)
	map_view = BattleMapView.new()
	wv.world.add_child(map_view)
	map_view.build(battle.grid, wv)
	overlay = TileOverlay.new()
	map_view.add_child(overlay)
	overlay.setup(map_view)
	fx = FX.new()
	fx.map_view = map_view
	map_view.add_child(fx)
	for u in battle.units:
		_spawn_view(u)
	var ext: Array = []
	for c in battle.grid.all_cells():
		if battle.grid.t(c)["extract"]:
			ext.append(c)
	overlay.show_cells("extract", ext, C_EXTRACT, Color(0.4, 1.0, 0.5, 0.8))
	hud = BattleHUD.new()
	hud.scene = self
	add_child(hud)
	hud.action_pressed.connect(_on_action)
	hud.menu_pressed.connect(_open_menu)
	hud.refresh_objective(battle)
	var focus := Vector3.ZERO
	var n := 0
	for u in battle.units:
		if u.team == BattleUnit.TEAM_PLAYER:
			focus += map_view.unit_pos(u.pos)
			n += 1
	wv.focus(focus / maxf(n, 1) + Vector3(0, 0, -2), true)
	map_view.set_grid_alpha(0.1 if Settings.show_grid else 0.0)
	_music()
	await get_tree().process_frame
	hud.show_banner(battle.mission.get("title", "Battle"), battle.objective_text(), UITheme.GOLD, 1.6)
	Audio.sfx("battle_start", 0.0, -2.0)
	_loop()


func _build_test_battle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var squad: Array = []
	for c in ["warrior", "rogue", "ranger", "mystic"]:
		var m := Member.create(rng, c, "human", 1, 4)
		m.id = squad.size() + 1
		for s in m.learnable_skills():
			if m.skill_points > 0 and int(DB.skill(s).get("level", 1)) <= m.level:
				m.learn(s)
				m.skill_points -= 1
		squad.append(m)
	var region: String = ["coast", "stilts", "ember", "dunes", "carrow"][rng.randi() % 5]
	var mission := {"region": region, "objective": "clear", "skulls": 2, "seed": rng.randi(), "title": "Skirmish", "par_rounds": 8}
	battle = BattleFactory.build(mission, squad, {"difficulty": 1})


func _music() -> void:
	var biome := battle.grid.biome
	if battle.objective.get("type", "") == "final":
		Audio.play_music("final", "final_layer")
	elif biome in ["hush", "hush_town"]:
		Audio.play_music("hush_battle", "combat_layer")
	else:
		Audio.play_music("combat", "combat_layer")


func _spawn_view(u: BattleUnit) -> UnitView:
	var uv := UnitView.new()
	map_view.add_child(uv)
	uv.setup(u.sprite, u.palette, wv.pitch, battle.grid.region)
	uv.set_tint(map_view.unit_tint())
	uv.uid = u.uid
	uv.position = map_view.unit_pos(u.pos)
	uv.face(u.facing)
	if u.echo:
		uv.set_ghost(0.4)
		uv.set_grey(0.85)
	if u.hidden:
		uv.visible = false
	if u.state == "dead":
		uv.play("death")
		uv.visible = false
	views[u.uid] = uv
	return uv


# ====================================================================== turn loop
func _loop() -> void:
	await get_tree().create_timer(1.2).timeout
	while not battle.over:
		var u := battle.next_turn()
		await _play(battle.pop_events())
		if battle.over or u == null:
			break
		if battle.current != u:
			continue
		if _player_controls(u):
			_begin_player_turn(u)
			await turn_finished
		else:
			_focus_unit(u)
			hud.refresh_unit(u)
			await get_tree().create_timer(0.3 / Settings.combat_speed).timeout
			battle.ai.take_turn(u)
			await _play(battle.pop_events())
		_refresh_all()
	_on_battle_end()


func _player_controls(u: BattleUnit) -> bool:
	return u.team == BattleUnit.TEAM_PLAYER and u.objective_role != "ally" and not Game.autoplay


func _begin_player_turn(u: BattleUnit) -> void:
	active = u
	state = "player"
	mode = "move"
	selected_skill = ""
	_focus_unit(u)
	if randf() < 0.12 and u.member:
		_bark(u, "start", BARKS_START)
	_refresh_player()
	if Game.campaign != null and not Game.campaign.tutorial_seen.get("battle", false) and not Game.autoplay:
		Game.campaign.tutorial_seen["battle"] = true
		var g := UITheme.GOLD.to_html(false)
		Dialogs.message(self, "Your first fight",
			("Each turn a member may [color=#%s]move[/color] (blue tiles) and take [color=#%s]one action[/color].\n\n" +
			"• Click a blue tile to move. Hovering shows the path, cover and attacks of opportunity.\n" +
			"• Click an enemy to attack, or pick a skill below (keys 1-6). Hit and crit chances show before you commit.\n" +
			"• Orange tiles are enemy zones of control: stepping in stops you; leaving provokes a free attack.\n" +
			"• A member at 0 HP is [color=#%s]Downed[/color] and bleeds out. Stabilize them (G) or carry them (C) to the green extraction zone.\n\n" +
			"Q/E rotate the camera, the mouse wheel zooms, Space ends the turn.") % [g, g, UITheme.RED.to_html(false)],
			Callable(), "To battle", 320)


func _refresh_player() -> void:
	if active == null:
		return
	reach = battle.reachable(active) if not active.moved else {}
	_refresh_all()
	_update_hover()


func _refresh_all() -> void:
	hud.refresh_timeline(battle)
	hud.refresh_objective(battle)
	if state == "player" and active:
		hud.refresh_unit(active)
		hud.refresh_actions(battle, active, mode, selected_skill)
		for uid in views:
			views[uid].set_highlight(0.8 if uid == active.uid else 0.0)
	else:
		hud.refresh_actions(battle, null, mode, "")
		for uid in views:
			views[uid].set_highlight(0.0)
	_draw_ranges()
	var hurt := 0.0
	var n := 0
	for u in battle.units:
		if u.team == BattleUnit.TEAM_PLAYER and not u.npc:
			n += 1
			if u.state != "active":
				hurt += 1.0
			else:
				hurt += 1.0 - float(u.hp) / u.max_hp()
	Audio.set_danger(clampf(hurt / maxf(n, 1) * 1.6, 0.0, 1.0))


func _end_player_turn() -> void:
	state = "busy"
	overlay.clear("move")
	overlay.clear("range")
	overlay.clear("aoe")
	overlay.clear("path")
	overlay.clear("zoc")
	hud.hide_preview()
	_clear_cover_icons()
	active = null
	turn_finished.emit()


func _after_action() -> void:
	if active == null:
		return
	if battle.over or battle.current != active or not active.active():
		_end_player_turn()
		return
	if active.moved and active.acted:
		battle.end_turn(active)
		await _play(battle.pop_events())
		_end_player_turn()
		return
	mode = "move"
	selected_skill = ""
	state = "player"
	_refresh_player()


# ====================================================================== actions
func _on_action(kind: String, arg: String) -> void:
	if state != "player" or active == null:
		return
	var u := active
	match kind:
		"skill":
			if not battle.can_use(u, arg):
				return
			var s := DB.skill(arg)
			if s.get("target", "") == "self":
				await _do(func(): battle.use_skill(u, arg, u.pos))
				return
			mode = "target"
			selected_skill = arg
			_refresh_all()
			_update_hover()
			Audio.sfx("ui_select", 0.05, -6.0)
		"defend":
			await _do(func(): battle.do_defend(u))
		"overwatch":
			await _do(func(): battle.do_overwatch(u))
		"wait":
			await _do(func(): battle.do_wait(u))
		"end":
			await _do(func(): battle.end_turn(u))
		"stabilize":
			await _do(func(): battle.do_stabilize(u, battle.unit(int(arg))))
		"carry":
			await _do(func(): battle.do_carry(u, battle.unit(int(arg))))
		"extract":
			await _do(func(): battle.do_extract(u))
		"interact":
			var it := battle.interact_targets(u)
			if not it.is_empty():
				await _do(func(): battle.do_interact(u, it[0]))


func _do(f: Callable) -> void:
	state = "busy"
	hud.hide_preview()
	overlay.clear("path")
	overlay.clear("aoe")
	_clear_cover_icons()
	f.call()
	await _play(battle.pop_events())
	await _after_action()


# ====================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if Dialogs.open > 0:
		return
	if menu != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_menu()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			wv.zoom(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			wv.zoom(-1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			drag_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode == "target":
				mode = "move"
				selected_skill = ""
				_refresh_player()
	elif event is InputEventMouseMotion:
		if dragging:
			var d: Vector2 = (event as InputEventMouseMotion).position - drag_last
			drag_last = (event as InputEventMouseMotion).position
			var bv := wv.basis_vectors()
			var ps := wv.pixel_scale() * UnitView.PX
			wv.target_goal -= bv["right"] * d.x / ps + bv["fwd_h"] * (-d.y) / ps / sin(deg_to_rad(wv.pitch))
		_update_hover()
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_Q:
			wv.rotate_view(-1)
			Audio.sfx("ui_hover", 0.0, -8.0)
		KEY_E:
			wv.rotate_view(1)
			Audio.sfx("ui_hover", 0.0, -8.0)
		KEY_ESCAPE:
			if mode == "target":
				mode = "move"
				selected_skill = ""
				_refresh_player()
			else:
				_open_menu()
		KEY_SPACE:
			_on_action("end", "")
		KEY_F:
			_on_action("defend", "")
		KEY_V:
			_on_action("overwatch", "")
		KEY_T:
			_on_action("wait", "")
		KEY_X:
			_on_action("extract", "")
		KEY_R:
			_on_action("interact", "")
		KEY_G, KEY_C:
			if active:
				for o in battle.units:
					if e.keycode == KEY_G and battle.can_stabilize(active, o):
						_on_action("stabilize", str(o.uid))
						return
					if e.keycode == KEY_C and battle.can_carry(active, o):
						_on_action("carry", str(o.uid))
						return
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if active:
				var i: int = e.keycode - KEY_1
				if i < active.skills.size():
					_on_action("skill", active.skills[i])
		KEY_HOME:
			if active:
				_focus_unit(active)


func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if menu == null:
		if Input.is_action_pressed("cam_left"):
			pan.x -= 1
		if Input.is_action_pressed("cam_right"):
			pan.x += 1
		if Input.is_action_pressed("cam_up"):
			pan.y -= 1
		if Input.is_action_pressed("cam_down"):
			pan.y += 1
		if Settings.edge_pan:
			var mp := _mouse()
			var vs := get_viewport_rect().size
			if mp.x < 4: pan.x -= 1
			if mp.x > vs.x - 4: pan.x += 1
			if mp.y < 4: pan.y -= 1
			if mp.y > vs.y - 4: pan.y += 1
	var bv := wv.basis_vectors()
	if pan != Vector2.ZERO:
		wv.target_goal += (bv["right"] * pan.x - bv["fwd_h"] * pan.y) * delta * 9.0
		wv.target = wv.target.lerp(wv.target_goal, 0.5)
	for uid in views:
		views[uid].set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
	map_view.set_camera_yaw(wv.yaw)
	var cells: Array = []
	for u in battle.units:
		if u.team == BattleUnit.TEAM_PLAYER and u.alive():
			cells.append(u.pos)
		elif u.alive() and not u.hidden and u.team == BattleUnit.TEAM_ENEMY and Rules.chebyshev(u.pos, hover_cell) <= 1:
			cells.append(u.pos)
	if hover_cell != Vector2i(-1, -1):
		cells.append(hover_cell)
	map_view.update_fades(cells, bv["fwd_h"])
	hud.update_bars(battle, views)
	if not cover_icons.is_empty():
		_place_cover_icons()


func _focus_unit(u: BattleUnit) -> void:
	if u and views.has(u.uid):
		wv.focus(views[u.uid].global_position)


# ---------------------------------------------------------------- picking
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		last_mouse = (event as InputEventMouse).position


func _mouse() -> Vector2:
	if mouse_override.x >= 0:
		return mouse_override
	return last_mouse if last_mouse.x >= 0 else get_viewport().get_mouse_position()


func pick() -> Array:
	## [cell, unit_uid]
	var mp := _mouse()
	var best_uid := -1
	var best_depth := 1e9
	var ps := wv.pixel_scale()
	for uid in views:
		var u: BattleUnit = battle.unit(uid)
		var uv: UnitView = views[uid]
		if u == null or not uv.visible or not u.alive() or u.carried_by >= 0 or uv.meta.is_empty():
			continue
		var feet := wv.world_to_screen(uv.global_position)
		var h: float = (float(uv.meta["anchor"][1]) - (uv.canvas * 0.22 if uv.canvas <= 64 else uv.canvas * 0.3)) * ps
		var w: float = uv.canvas * 0.34 * ps
		if u.state == "downed":
			h = 10 * ps
		var r := Rect2(feet.x - w / 2.0, feet.y - h, w, h + 2 * ps)
		if r.has_point(mp):
			var depth := wv.camera.global_position.distance_to(uv.global_position)
			if depth < best_depth:
				best_depth = depth
				best_uid = uid
	if best_uid >= 0:
		return [battle.unit(best_uid).pos, best_uid]
	var ray := wv.ray(mp)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var levels := {}
	for c in battle.grid.all_cells():
		levels[snappedf(TerrainBuilder.top_y(battle.grid, c), 0.01)] = true
	var ys := levels.keys()
	ys.sort()
	ys.reverse()
	for y in ys:
		if absf(d.y) < 0.0001:
			break
		var t: float = (float(y) - o.y) / d.y
		var p := o + d * t
		var c := Vector2i(floori(p.x), floori(p.z))
		if battle.grid.inb(c) and absf(TerrainBuilder.top_y(battle.grid, c) - float(y)) < 0.02:
			var ou := battle.unit_at(c)
			return [c, ou.uid if ou and views.has(ou.uid) and views[ou.uid].visible else -1]
	return [Vector2i(-1, -1), -1]


func _update_hover() -> void:
	var r := pick()
	hover_cell = r[0]
	hover_uid = r[1]
	overlay.show_cursor(hover_cell, Color(1, 1, 1, 0.85) if hover_cell != Vector2i(-1, -1) else Color(0, 0, 0, 0))
	var mp := _mouse()
	var hu: BattleUnit = battle.unit(hover_uid) if hover_uid >= 0 else null
	if state != "player" or active == null:
		hud.hide_preview()
		if hu:
			hud.show_info(hu, mp, battle)
		else:
			hud.hide_info()
		return
	overlay.clear("path")
	overlay.clear("aoe")
	_clear_cover_icons()
	hud.hide_preview()
	hud.hide_info()
	if mode == "target":
		var targets := battle.valid_targets(active, selected_skill)
		if hover_cell in targets:
			var cells := battle.aoe_cells(active, selected_skill, hover_cell)
			overlay.show_cells("aoe", cells, C_AOE, Color(1, 0.85, 0.4, 0.9))
			hud.show_preview(battle.preview(active, selected_skill, hover_cell), mp)
		elif hu:
			hud.show_info(hu, mp, battle)
		return
	# move mode
	if hu and hu.hostile_to(active) and hover_cell in battle.valid_targets(active, active.basic) and battle.can_use(active, active.basic):
		overlay.show_cells("aoe", [hover_cell], C_AOE, Color(1, 0.4, 0.3, 0.9))
		hud.show_preview(battle.preview(active, active.basic, hover_cell), mp)
		return
	if hu and hu != active:
		hud.show_info(hu, mp, battle)
	if reach.has(hover_cell) and hover_cell != active.pos and not reach[hover_cell].get("pass_only", false):
		var path := battle.path_to(active, hover_cell, reach)
		var aoo := battle.aoo_attackers(active, path)
		var danger: Array = []
		if not aoo.is_empty():
			danger.append(active.pos)
		overlay.show_path(path, Color(1, 1, 1, 0.9) if aoo.is_empty() else Color(1, 0.6, 0.4, 0.95), danger)
		_show_cover_icons(hover_cell, aoo.size())


func _click() -> void:
	if state != "player" or active == null:
		return
	var r := pick()
	var cell: Vector2i = r[0]
	var u := active
	if cell == Vector2i(-1, -1):
		return
	if mode == "target":
		if cell in battle.valid_targets(u, selected_skill):
			var s := selected_skill
			await _do(func(): battle.use_skill(u, s, cell))
		return
	var hu: BattleUnit = battle.unit(r[1]) if r[1] >= 0 else null
	if hu and hu.hostile_to(u) and battle.can_use(u, u.basic) and cell in battle.valid_targets(u, u.basic):
		await _do(func(): battle.use_skill(u, u.basic, cell))
		return
	if reach.has(cell) and cell != u.pos and not reach[cell].get("pass_only", false):
		await _do(func(): battle.do_move(u, cell))


# ---------------------------------------------------------------- ranges & cover
func _draw_ranges() -> void:
	overlay.clear("move")
	overlay.clear("range")
	overlay.clear("zoc")
	if state != "player" or active == null:
		return
	if mode == "target":
		var s := DB.skill(selected_skill)
		var cells := battle.valid_targets(active, selected_skill)
		var tgt: String = s.get("target", "enemy")
		if tgt in ["tile", "empty_tile"]:
			overlay.show_cells("range", cells, C_TILE, Color(1, 0.85, 0.4, 0.7))
		elif tgt in ["ally", "ally_or_self"]:
			overlay.show_cells("range", cells, C_ALLY, C_ALLY_B)
		else:
			var rr := battle.skill_range(active, s, active.pos)
			var area := battle.grid.cells_in_radius(active.pos, rr[2])
			var inr: Array = []
			for c in area:
				var d := Rules.distance(active.pos, c)
				if d >= rr[0] and d <= rr[2] and (s.get("range", {}).get("kind", "") != "melee" or Rules.chebyshev(active.pos, c) == 1):
					inr.append(c)
			overlay.show_cells("range", inr, C_ENEMY, C_ENEMY_B)
		return
	if not reach.is_empty():
		var cells: Array = []
		var zoc: Array = []
		for c in reach:
			if reach[c].get("pass_only", false) or c == active.pos:
				continue
			cells.append(c)
			if reach[c]["zoc"]:
				zoc.append(c)
		overlay.show_cells("move", cells, C_MOVE, C_MOVE_B)
		overlay.show_cells("zoc", zoc, C_ZOC, Color(1, 0.6, 0.25, 0.0))


func _show_cover_icons(cell: Vector2i, aoo: int) -> void:
	for pair in battle.grid.cover_dirs(cell):
		var d: Vector2i = pair[0]
		var tex := UIKit.small_tex("cover_full" if pair[1] >= 2 else "cover_half")
		var r := UIKit.tex_rect(tex)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_meta("world", map_view.cell_top(cell) + Vector3(d.x * 0.45, 0.35, d.y * 0.45))
		hud.float_layer.add_child(r)
		cover_icons.append(r)
	if aoo > 0:
		var r := UIKit.tex_rect(UIKit.small_tex("aoo"))
		r.tooltip_text = "Leaving this zone of control provokes an attack of opportunity."
		r.set_meta("world", map_view.cell_top(active.pos) + Vector3(0, 1.6, 0))
		hud.float_layer.add_child(r)
		cover_icons.append(r)
		var l := UIKit.label("Attack of opportunity!", 8, UITheme.RED, UITheme.pixel_font)
		l.set_meta("world", map_view.cell_top(active.pos) + Vector3(0, 1.9, 0))
		hud.float_layer.add_child(l)
		cover_icons.append(l)
	_place_cover_icons()


func _place_cover_icons() -> void:
	for r in cover_icons:
		if is_instance_valid(r):
			var p := wv.world_to_screen(r.get_meta("world"))
			r.position = p - r.size / 2.0


func _clear_cover_icons() -> void:
	for r in cover_icons:
		if is_instance_valid(r):
			r.queue_free()
	cover_icons.clear()


# ====================================================================== event playback
func _head(u: BattleUnit) -> Vector3:
	if views.has(u.uid):
		var uv: UnitView = views[u.uid]
		var h := 1.5 if uv.canvas <= 64 else 2.3
		return uv.global_position + Vector3(0, h, 0)
	return map_view.unit_pos(u.pos) + Vector3(0, 1.5, 0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t / Settings.combat_speed).timeout


func _play(evs: Array) -> void:
	for e in evs:
		await _play_one(e)


func _play_one(e: Dictionary) -> void:
	var u: BattleUnit = battle.unit(int(e.get("uid", -1))) if e.has("uid") else null
	var uv: UnitView = views.get(int(e.get("uid", -1)), null)
	match e["t"]:
		"turn":
			if u and uv and uv.visible and u.state == "active":
				_focus_unit(u)
			hud.refresh_timeline(battle)
		"move":
			if uv:
				await _walk(uv, u, e["path"], e.get("fast", false), e.get("knock", false))
		"face":
			if uv:
				uv.face(e["dir"])
		"anim":
			if uv:
				uv.play(e["anim"])
				await _wait(0.2)
		"skill":
			await _play_skill(e, u, uv)
		"hit":
			await _play_hit(e, u, uv)
		"miss":
			if uv:
				uv.play("dodge")
				hud.float_text(_head(u), "Miss", UITheme.TEXT_DIM)
				Audio.sfx("miss")
				hud.log_line("%s dodges." % u.name)
			await _wait(0.22)
		"status":
			if u and uv:
				var sd: Dictionary = DB.statuses.get(e["id"], {})
				if not e["id"] in ["overwatch", "defending", "silenced"]:
					hud.float_text(_head(u) + Vector3(0, 0.3, 0), sd.get("name", e["id"]), DB.color_of(sd.get("color", [220, 220, 220])))
					Audio.sfx("status_bad" if sd.get("bad", true) else "buff", 0.05, -4.0)
					if sd.get("bad", true):
						hud.log_line("%s: %s" % [u.name, sd.get("name", e["id"])], DB.color_of(sd.get("color", [220, 220, 220])))
				await _wait(0.12)
		"heal":
			if u and uv:
				hud.float_text(_head(u), "+%d" % int(e["amount"]), UITheme.GREEN)
				fx.rise(uv.global_position, "heal")
				Audio.sfx("heal", 0.05)
			await _wait(0.2)
		"revive":
			if u and uv:
				uv.play("idle")
				hud.float_text(_head(u), "Back on their feet!", UITheme.GREEN)
				fx.rise(uv.global_position, "heal", 18)
				Audio.sfx("revive")
				hud.log_line("%s is back up." % u.name, UITheme.GREEN)
			await _wait(0.4)
		"downed":
			if u and uv:
				uv.play("downed")
				hud.float_text(_head(u), "DOWNED", UITheme.RED, true)
				Audio.sfx("downed")
				hud.log_line("%s is down!" % u.name, UITheme.RED)
				_bark(u, "down", BARKS_DOWN)
				wv.shake = 1.0 if Settings.screen_shake else 0.0
				for a in battle.allies_of(u, false):
					if a.member and randf() < 0.5:
						await _wait(0.5)
						_bark(a, "ally_down", BARKS_ALLY_DOWN)
						break
			await _wait(0.7)
		"death":
			await _play_death(e, u, uv)
		"bleed":
			if u:
				hud.float_text(_head(u) + Vector3(0, -0.8, 0), "Bleeding out: %d" % int(e["left"]), UITheme.RED)
				Audio.sfx("heartbeat")
			await _wait(0.5)
		"float":
			if u:
				var col := UITheme.TEXT
				match e.get("kind", ""):
					"bad": col = UITheme.RED
					"good": col = UITheme.GREEN
					"warn": col = UITheme.GOLD
				hud.float_text(_head(u) + Vector3(0, 0.25, 0), e["text"], col)
			await _wait(0.3)
		"bark":
			if u:
				hud.bark(_head(u), e["text"])
				Audio.sfx("bell_far", 0.0, -8.0)
			await _wait(1.6)
		"teleport":
			if uv:
				fx.burst(uv.global_position + Vector3(0, 0.5, 0), e.get("fx", "shadow"), 14)
				uv.set_alpha(0.0)
				Audio.sfx("teleport")
				await _wait(0.15)
				uv.position = map_view.unit_pos(e["to"])
				fx.burst(uv.global_position + Vector3(0, 0.5, 0), e.get("fx", "shadow"), 14)
				uv.set_alpha(1.0)
			await _wait(0.2)
		"terrain":
			fx.add_terrain(e["cells"], e["kind"])
			Audio.sfx({"smoke": "smoke", "flood": "water", "thorns": "roots", "trap": "trap", "fire": "fire", "sanctuary": "heal"}.get(e["kind"], "cast"), 0.05, -3.0)
			await _wait(0.2)
		"terrain_end":
			for c in e["cells"]:
				fx.remove_terrain_cell(c)
		"spawn":
			if u:
				var nv := _spawn_view(u)
				nv.set_alpha(0.0)
				var tw := nv.create_tween()
				tw.tween_method(func(a): nv.set_alpha(a), 0.0, 1.0, 0.4)
				fx.burst(nv.global_position + Vector3(0, 0.5, 0), "hush" if u.hush else "smoke", 16)
				Audio.sfx("spawn", 0.05, -3.0)
			await _wait(0.3)
		"reveal":
			if uv:
				uv.visible = true
				fx.burst(uv.global_position + Vector3(0, 0.5, 0), "smoke", 12)
				hud.float_text(_head(u), "Revealed!", UITheme.GOLD)
				Audio.sfx("reveal")
			await _wait(0.3)
		"extract":
			if uv:
				Audio.sfx("extract")
				fx.rise(uv.global_position, "heal", 16)
				var tw := uv.create_tween()
				tw.set_parallel(true)
				tw.tween_property(uv, "position:y", uv.position.y + 1.2, 0.5)
				tw.tween_method(func(a): uv.set_alpha(a), 1.0, 0.0, 0.5)
				await tw.finished
				uv.visible = false
				if u:
					hud.log_line("%s extracted." % u.name, UITheme.GREEN)
		"carry":
			var body: BattleUnit = battle.unit(int(e["body"]))
			if body and views.has(body.uid):
				views[body.uid].visible = false
				hud.float_text(_head(u), "Carrying %s" % body.name.split(" ")[0], UITheme.TEXT)
				Audio.sfx("cloth")
			await _wait(0.3)
		"drop":
			if uv:
				uv.visible = true
				uv.position = map_view.unit_pos(e["pos"])
		"interact":
			map_view.remove_object(e["cell"])
			var kind: String = e.get("kind", "")
			Audio.sfx({"cache": "loot", "chest": "chest", "page": "page", "captive": "rope"}.get(kind, "loot"))
			fx.rise(map_view.cell_top(e["cell"]), "light_burst" if kind == "page" else "buff", 14)
			await _wait(0.4)
		"objective":
			hud.show_banner("", e["text"], UITheme.GOLD, 1.4)
			hud.log_line(e["text"], UITheme.GOLD)
			hud.refresh_objective(battle)
			Audio.sfx("objective")
			await _wait(0.6)
		"round":
			hud.refresh_objective(battle)
		"def":
			if u and float(e.get("gain", 0)) > 0:
				hud.float_text(_head(u), "Defense restored", UITheme.BLUE)
				fx.rise(uv.global_position if uv else Vector3.ZERO, "ward", 10)
				Audio.sfx("buff")
			await _wait(0.2)
		"armor_break":
			if u:
				hud.float_text(_head(u) + Vector3(0, 0.3, 0), "Armor broken -%d" % roundi(float(e["loss"])), UITheme.BLUE)
				Audio.sfx("armor_break")
				fx.burst(_head(u) - Vector3(0, 0.6, 0), "impact", 10)
			await _wait(0.2)
		"statuses", "status_end", "end_turn", "start":
			pass
		"rename":
			if u:
				u.name = e["name"]
		"end":
			pass


func _walk(uv: UnitView, u: BattleUnit, path: Array, fast: bool, knock: bool) -> void:
	if knock:
		uv.play("hit")
	elif not uv.anim in ["downed", "death"]:
		uv.play("walk", false)
	var step_t := (0.07 if fast else 0.17) / Settings.combat_speed
	for c in path:
		var target := map_view.unit_pos(c)
		var from := uv.position
		var d: Vector2i = c - Vector2i(roundi(from.x - 0.5), roundi(from.z - 0.5))
		if not knock:
			uv.face(Vector2i(signi(d.x), signi(d.y)) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y)))
		var hop := absf(target.y - from.y) > 0.1
		var tw := uv.create_tween()
		tw.tween_method(func(f: float):
			var p := from.lerp(target, f)
			if hop:
				p.y += sin(f * PI) * 0.25
			uv.position = p, 0.0, 1.0, step_t * (1.3 if hop else 1.0))
		await tw.finished
		if not knock and randf() < 0.5:
			Audio.sfx("step", 0.15, -14.0)
		if u.team == BattleUnit.TEAM_PLAYER or not (u.hidden):
			wv.focus(uv.global_position)
	if not knock and uv.anim == "walk":
		uv.play("idle")


func _play_skill(e: Dictionary, u: BattleUnit, uv: UnitView) -> void:
	if uv == null or u == null:
		return
	var kind: String = e.get("fx", "slash")
	var target_pos := map_view.unit_pos(e["target"])
	var tgt_unit := battle.unit_at(e["target"], true)
	if tgt_unit and views.has(tgt_unit.uid):
		target_pos = views[tgt_unit.uid].global_position
	uv.play(e.get("anim", "attack"))
	var name: String = e.get("name", "")
	if name != "":
		hud.float_text(_head(u) + Vector3(0, 0.35, 0), name, UITheme.GOLD)
		hud.log_line("%s uses %s." % [u.name, name], UITheme.TEXT)
	var cast: bool = e.get("anim", "attack") == "cast"
	Audio.sfx(_skill_sfx(kind, cast), 0.08, -2.0)
	if cast:
		fx.flash_light(uv.global_position, kind, 1.8, 0.6)
	await _wait(0.2)
	if kind in FX.RANGED and uv.global_position.distance_to(target_pos) > 1.6:
		var from := uv.global_position + Vector3(0, 0.7, 0)
		var to := target_pos + Vector3(0, 0.6, 0)
		if kind == "lightning":
			fx.lightning(from, to)
			await _wait(0.12)
		else:
			var t := fx.projectile(from, to, kind)
			await get_tree().create_timer(t).timeout
	elif kind in ["heal", "heal_wave", "cleanse", "ward", "buff", "shout", "light_burst", "sanctuary", "hush_wave", "mark", "fear"]:
		fx.rise(target_pos, kind, 12)
		await _wait(0.1)
	elif kind in ["flame_wave", "inferno", "poison_cloud", "volley", "flood", "roots", "sand", "smoke", "water"]:
		for c in battle.aoe_cells(u, e["skill"], e["target"]) if u.alive() else []:
			fx.burst(map_view.cell_top(c) + Vector3(0, 0.3, 0), kind, 5, 0.4, 1.0)
		await _wait(0.15)
	else:
		await _wait(0.08)


func _skill_sfx(kind: String, cast: bool) -> String:
	match kind:
		"arrow", "arrow_pierce", "volley": return "bow"
		"knife", "rock": return "throw"
		"bolt_fire", "flame_wave", "inferno": return "fire"
		"bolt_frost": return "frost"
		"lightning": return "lightning"
		"heal", "heal_wave", "cleanse", "sanctuary": return "heal_cast"
		"poison", "poison_cloud", "sting": return "poison"
		"water", "flood", "harpoon": return "water"
		"roots": return "roots"
		"hush", "hush_wave": return "hush"
		"shout": return "shout"
	return "cast" if cast else "swing"


func _play_hit(e: Dictionary, u: BattleUnit, uv: UnitView) -> void:
	if u == null or uv == null:
		return
	var dmg := int(e["dmg"])
	var crit: bool = e.get("crit", false)
	var dot: String = e.get("dot", "")
	if dot != "":
		hud.float_text(_head(u), str(dmg), DB.color_of(DB.statuses.get(dot, {}).get("color", [230, 120, 90])))
		uv.hit_flash(DB.color_of(DB.statuses.get(dot, {}).get("color", [230, 120, 90])))
		Audio.sfx({"poison": "poison", "burn": "fire", "bleed": "bleed", "trap": "trap", "drown": "water"}.get(dot, "hit"), 0.1, -4.0)
		hud.log_line("%s takes %d (%s)." % [u.name, dmg, dot], UITheme.TEXT_DIM)
		await _wait(0.25)
		return
	if u.state == "active" or u.state == "downed":
		uv.play("hit")
	uv.hit_flash(Color(1, 1, 1) if not crit else Color(1, 0.9, 0.4))
	fx.burst(uv.global_position + Vector3(0, 0.55, 0), e.get("fx", "slash"), 12 if crit else 7)
	var absorbed := int(e.get("absorbed", 0))
	if crit:
		hud.float_text(_head(u) + Vector3(0, 0.3, 0), "CRIT!", UITheme.GOLD, true)
		Audio.sfx("crit")
		if Settings.screen_shake:
			wv.shake = 1.4
	elif absorbed > dmg:
		Audio.sfx("block")
	else:
		Audio.sfx("hit")
	if e.get("crit_def", false):
		hud.float_text(_head(u) + Vector3(0, 0.5, 0), "Braced!", UITheme.BLUE)
	hud.float_text(_head(u), str(dmg), UITheme.RED if u.team == BattleUnit.TEAM_PLAYER else Color8(255, 236, 200), crit)
	var src: BattleUnit = battle.unit(int(e.get("src", -1)))
	hud.log_line("%s hits %s for %d%s." % [src.name if src else "?", u.name, dmg, " (crit)" if crit else ""], UITheme.TEXT)
	if u.member and randf() < 0.1 and u.state == "active":
		_bark(u, "hurt", BARKS_HURT)
	await _wait(0.28 if crit else 0.2)


## A short spoken line over a member's head, in their people's idiom half the
## time, with a voice chirp pitched to their race and to them.
func _bark(u: BattleUnit, kind: String, common: Array) -> void:
	var race: String = u.member.race if u.member else "human"
	var lines: Array = common
	var own: Array = RACE_BARKS.get(race, {}).get(kind, [])
	if not own.is_empty() and randf() < 0.5:
		lines = own
	hud.bark(_head(u), lines[randi() % lines.size()])
	var voice: String = {"hurt": "hurt", "down": "hurt", "kill": "shout", "ally_down": "shout"}.get(kind, "talk")
	var pitch: float = VOICE_PITCH.get(race, 1.0) * (0.92 + 0.16 * float(posmod(u.member.id * 37 if u.member else 0, 11)) / 10.0)
	Audio.voice(voice, pitch)


func _play_death(e: Dictionary, u: BattleUnit, uv: UnitView) -> void:
	if u == null or uv == null:
		return
	uv.play("death")
	var member_death := u.team == BattleUnit.TEAM_PLAYER and u.member != null
	var src: BattleUnit = battle.unit(int(e.get("src", -1)))
	if member_death:
		Audio.duck(-26.0, 1.4)
		Audio.sfx("death_sting")
		hud.show_banner(u.name, "has fallen", UITheme.RED, 1.4)
		hud.log_line("%s has died." % u.name, UITheme.RED)
		await _wait(1.6)
	else:
		Audio.sfx("death" if not u.hush else "hush", 0.08)
		hud.log_line("%s is slain." % u.name, UITheme.TEXT_DIM)
		if src and src.member and randf() < 0.18:
			_bark(src, "kill", BARKS_KILL)
		await _wait(0.5)
		var tw := uv.create_tween()
		tw.tween_method(func(a): uv.set_alpha(a), 1.0, 0.0, 0.6)
		tw.tween_callback(func(): uv.visible = false)
	if member_death:
		uv.set_grey(0.7)


# ====================================================================== end & menu
func _on_battle_end() -> void:
	if ended:
		return
	ended = true
	state = "over"
	_refresh_all()
	await _wait(0.6)
	match battle.result:
		"victory":
			Audio.stop_music(0.5)
			Audio.sfx("victory")
			hud.show_banner("Victory", battle.mission.get("title", ""), UITheme.GOLD, 2.2)
		"retreat":
			Audio.stop_music(0.5)
			Audio.sfx("defeat")
			hud.show_banner("Retreat", "The mission failed, but the living are home.", UITheme.TEXT, 2.2)
		"failed":
			Audio.stop_music(0.5)
			Audio.sfx("defeat")
			hud.show_banner("Mission Failed", "The objective was lost.", UITheme.RED, 2.2)
		_:
			Audio.stop_music(0.5)
			Audio.sfx("defeat")
			hud.show_banner("Defeat", "No one is left standing.", UITheme.RED, 2.2)
	await get_tree().create_timer(3.0).timeout
	if Game.battle == battle and Game.campaign != null:
		Game.finish_battle()
		Scenes.go("res://scenes/report.tscn")
	else:
		Scenes.go("res://scenes/title.tscn")


func _open_menu() -> void:
	if menu != null:
		return
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(dim)
	var p := UIKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(p)
	var v := UIKit.vbox(4)
	p.add_child(v)
	v.add_child(UIKit.title("Paused", 24))
	v.add_child(UIKit.button("Resume", _close_menu, "", 150))
	v.add_child(UIKit.button("Settings", func(): SettingsPanel.open(self), "", 150))
	var ironman := Game.campaign != null and Game.campaign.ironman
	var r := UIKit.button("Sound the Retreat", func():
		_close_menu()
		_confirm("Sound the retreat?", "Members standing in the extraction zone escape. Everyone else on the field is left behind. The mission fails.", func():
			battle.abandon()
			await _play(battle.pop_events())
			if active:
				_end_player_turn()
			), "btn_red", 150)
	v.add_child(r)
	v.add_child(UIKit.label("Retreat: only members on the green\nextraction tiles make it out.", 8, UITheme.TEXT_DIM))
	if Game.campaign != null and not ironman:
		v.add_child(UIKit.button("Quit to Title", func(): _confirm("Quit to title?", "The battle will be lost. Your last save is kept.", func(): Scenes.go("res://scenes/title.tscn")), "", 150))
	elif Game.campaign != null:
		v.add_child(UIKit.button("Save & Quit", func(): _confirm("Quit (Ironman)?", "Ironman: leaving mid-battle abandons the mission when you return.", func():
			Game.save()
			Scenes.go("res://scenes/title.tscn")), "", 150))
	add_child(menu)
	p.reset_size()
	p.position = (get_viewport_rect().size - p.size) / 2.0


func _close_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null


func _confirm(title: String, text: String, ok: Callable) -> void:
	Dialogs.confirm(self, title, text, ok)
