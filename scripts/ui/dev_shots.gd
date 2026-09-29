extends Control
## Developer screenshot harness: --shot=<name> renders a scene and saves
## tools/_cache/shots/<name>.png, then quits. Used to check visuals headlessly.

var shot := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot = Scenes.params.get("shot", "battle_coast")
	var parts := shot.split("_")
	match parts[0]:
		"battle":
			var when := "night" if "night" in parts else ("dusk" if "dusk" in parts else "day")
			await _battle(parts[1] if parts.size() > 1 else "coast", "far" in parts, when, "map" in parts, parts[2] if parts.size() > 2 and parts[2] in MapGen.EXPLORE + ["survive", "defense"] else "clear")
		"scene":
			await _scene(parts[1] if parts.size() > 1 else "battle")
		"screen":
			await _screen("_".join(parts.slice(1)) if parts.size() > 1 else "roster")
		"input":
			await _input_test()
		"autoplay":
			await _autoplay(parts[1] if parts.size() > 1 else "clear")
		"lineup":
			await _lineup(parts[1] if parts.size() > 1 else "")
		_:
			pass
	await _save()
	get_tree().quit()


func _battle(region: String, far := false, when := "day", whole := false, obj := "clear") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var squad: Array = []
	for c in ["warrior", "rogue", "ranger", "mystic"]:
		var m := Member.create(rng, c, ["human", "tidefolk", "mothkin", "khepri"][squad.size()], 1, 3)
		m.id = squad.size() + 1
		squad.append(m)
	var mission := {"region": region, "objective": obj, "skulls": 2, "seed": 77, "par_rounds": 8, "time": when}
	var b := BattleFactory.build(mission, squad, {"difficulty": 1})
	var wv := WorldView.new()
	add_child(wv)
	var mv := BattleMapView.new()
	wv.world.add_child(mv)
	mv.build(b.grid, wv)
	if b.fog:
		mv.setup_fog(b.route)
		mv.set_fog(b.seen, b.vis, true)
	var views := []
	for u in b.units:
		var uv := UnitView.new()
		mv.add_child(uv)
		uv.setup(u.sprite, u.palette, wv.pitch, region)
		uv.set_tint(mv.unit_tint())
		uv.position = mv.unit_pos(u.pos)
		uv.face(u.facing)
		uv.visible = b.is_seen(u) or whole
		views.append(uv)
	wv.focus(Vector3(b.grid.w / 2.0, 0.5, b.grid.h / 2.0 + 1.5), true)
	if whole:
		wv.world_scale = 1
		wv._update_viewport()
		wv.focus(Vector3(b.grid.w / 2.0, 0.5, b.grid.h / 2.0), true)
	elif far:
		wv.world_scale = 2
		wv.focus(Vector3(b.grid.w / 2.0, 0.5, b.grid.h / 2.0), true)
	for i in 30:
		var bv := wv.basis_vectors()
		for uv in views:
			uv.set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
		mv.set_camera_yaw(wv.yaw)
		await get_tree().process_frame


## Every race in every look, in its game palette, on a small plaza.
func _lineup(only: String) -> void:
	# one row per race with genders alternating, or both genders of one race ("lineup_human")
	var rows: Array = []
	if only == "":
		for r in ["tidefolk", "mothkin", "barkborn", "khepri"]:
			rows.append([r, ""])
	else:
		rows = [[only, "m"], [only, "f"]]
	var faction := {"tidefolk": "tidecaller", "mothkin": "lanternbearer", "barkborn": "graftwarden", "khepri": "sandreaver"}
	var g := BattleGrid.new(26, 26)
	g.biome = "town"
	for c in g.all_cells():
		g.t(c)["ground"] = "cobble" if (c.x + c.y) % 5 else "grass"
	var wv := WorldView.new()
	add_child(wv)
	var mv := BattleMapView.new()
	wv.world.add_child(mv)
	mv.build(g, wv)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var views := []
	for r in rows.size():
		var race: String = rows[r][0]
		var looks: Array = ["warrior", "rogue", "ranger", "mystic"]
		if faction.has(race):
			looks.append(faction[race])
		for i in looks.size():
			var m := Member.create(rng, looks[i], race, 1, 2)
			m.gender = rows[r][1] if rows[r][1] != "" else ["m", "f"][(i + r) % 2]
			m.pick_look(rng)
			var uv := UnitView.new()
			mv.add_child(uv)
			uv.setup(m.variant, m.palette, wv.pitch)
			# rows run left to right on screen (yaw 45: screen right is +x -z)
			uv.position = mv.unit_pos(Vector2i(3 + i * 2 + r * 4, 11 - i * 2 + r * 4))
			uv.face(Vector2i(1, 1))
			views.append(uv)
	wv.focus(Vector3(7.0 + rows.size() * 1.5, 0.6, 7.0 + rows.size() * 1.5), true)
	if rows.size() > 2:
		wv.world_scale = maxi(1, wv.world_scale - 1)
	for i in 40:
		var bv := wv.basis_vectors()
		for uv in views:
			uv.set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
		await get_tree().process_frame


func _campaign() -> void:
	var c := Campaign.new()
	c.new_game("The Lantern Company", 1, false, 21)
	c.tutorial_seen["hub"] = true
	for fid in ["library", "forge", "memorial", "training", "nursery", "recruiter"]:
		c.facilities[fid] = 1 + (1 if fid in ["forge", "training"] else 0)
	c.roster[1].injure("serious", c.rng, 0.0)
	var extra := Member.create(c.rng, "ranger", "mothkin", 2, 5)
	c.add_member(extra)
	c.roster[0].add_xp(400, c.rng)
	c.dead.append(Member.create(c.rng, "rogue", "khepri", 1, 3).to_dict())
	c.dead[0]["death"] = {"week": 1, "mission": "The Bell-Thief", "cause": "Slain"}
	c.gold = 900
	c.renown = 70
	c.materials = 20
	c.hush = 31
	c.inventory.append(Items.weapon("sword", 2))
	c.inventory.append(Items.armor("light", 1))
	c.chronicle.append({"week": 1, "text": "The guild took its first contract."})
	Game.campaign = c


func _screen(which: String) -> void:
	_campaign()
	var inst: Node = load("res://scenes/guild.tscn").instantiate()
	add_child(inst)
	await get_tree().create_timer(1.5).timeout
	if which != "hub":
		var p := {}
		if which == "squad":
			p = {"mission": int(Game.campaign.board[0]["id"])}
		if which == "nursery":
			which = "facilities"
			p = {"focus": "nursery"}
		# board_letter: a generated letter (first non-story quest); board_map: the map tab
		var board_view := ""
		if which.begins_with("board_"):
			board_view = which.trim_prefix("board_")
			which = "board"
		inst.open_screen(which, p)
		if board_view != "":
			var s = inst.screen
			if board_view == "map":
				s.view = "map"
			for m in Game.campaign.board:
				if m["category"] != "story":
					s.selected = int(m["id"])
					break
			s.rebuild()
	await get_tree().create_timer(1.0).timeout


func _scene(which: String) -> void:
	if which in ["guild", "report"]:
		_campaign()
	if which == "report":
		Game.squad_ids = [1, 2, 3]
		var m: Member = Game.campaign.roster[0]
		Game.last_report = {"mission": Game.campaign.board[0], "result": "victory", "grade": "A", "gold": 180, "renown": 22, "xp": {1: 120, 2: 90, 3: 90},
			"levels": {1: [{"level": m.level, "gains": {"hp": 4, "attack": 1}}]}, "injuries": {2: {"kind": "light", "weeks": 1, "permanent": ""}},
			"deaths": [], "items": [Items.trinket("lucky_coin")], "materials": 4, "hush": -3, "faction": ["Saltborn: Power +1, Reputation +1"],
			"story": "", "recruit": "", "lost_items": [], "traits": {3: "survivor"},
			"bonus": [{"desc": "No member Downed", "done": false}, {"desc": "Finish within 8 rounds", "done": true}]}
	if which == "story":
		Scenes.params = {"pages": [{"title": "Prologue", "text": DB.story["intro"][0]}], "next": "res://scenes/title.tscn"}
	if which == "ending":
		_campaign()
		Game.campaign.game_over = "victory"
		Game.campaign.ending = "lantern"
	var inst: Node = load("res://scenes/%s.tscn" % which).instantiate()
	add_child(inst)
	if which == "battle":
		var t := 0.0
		while t < 25.0 and inst.state != "player":
			await get_tree().process_frame
			t += get_process_delta_time()
		await get_tree().create_timer(0.8).timeout
		# hover a tile two steps ahead of the active unit
		if inst.active:
			var target: Vector2i = inst.active.pos + Vector2i(1, -2)
			for c in inst.reach:
				if Rules.distance(c, inst.active.pos) == 3 and not inst.reach[c].get("pass_only", false):
					target = c
					break
			var sp: Vector2 = inst.wv.world_to_screen(inst.map_view.cell_top(target))
			inst.mouse_override = sp
			await get_tree().process_frame
			inst._update_hover()
		await get_tree().create_timer(0.5).timeout
	elif which == "ending":
		await get_tree().create_timer(1.0).timeout
		for i in 6:
			inst.index += 1
			inst._show_page()
		await get_tree().create_timer(1.5).timeout
	else:
		await get_tree().create_timer(3.5).timeout


## A patrolled battle playing itself, captured every few seconds.
func _autoplay(obj: String) -> void:
	Game.autoplay = true
	Settings.combat_speed = 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var squad: Array = []
	for c in ["warrior", "rogue", "ranger", "mystic"]:
		var m := Member.create(rng, c, "human", 1, 3)
		m.id = squad.size() + 1
		m.auto_pick(rng)
		squad.append(m)
	Game.battle = BattleFactory.build({"region": "carrow", "objective": obj, "skulls": 2, "seed": 99, "par_rounds": 8, "title": "Patrol"}, squad, {"difficulty": 1})
	var inst: Node = load("res://scenes/battle.tscn").instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().create_timer(9.0).timeout
		await _save_as("autoplay_%s_%d" % [obj, i])
	Game.battle = null
	Game.autoplay = false


## Real mouse events through the GUI: a battle click must move the active unit
## and attack an adjacent enemy; a hub click must open the facility screen.
func _input_test() -> void:
	var ok := true
	var inst: Node = load("res://scenes/battle.tscn").instantiate()
	add_child(inst)
	var t := 0.0
	while t < 25.0 and inst.state != "player":
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(0.6).timeout
	while Dialogs.open > 0:
		for c in inst.get_children():
			if c is CanvasLayer:
				c.queue_free()
		await get_tree().process_frame
	var u: BattleUnit = inst.active
	var start := u.pos
	var target := Vector2i(-1, -1)
	for c in inst.reach:
		if c != start and not inst.reach[c].get("pass_only", false) and Rules.distance(c, start) >= 2:
			target = c
			break
	var sp: Vector2 = inst.wv.world_to_screen(inst.map_view.cell_top(target))
	await _mouse_to(sp)
	print("INPUT hover cell ", inst.hover_cell, " target ", target)
	ok = ok and inst.hover_cell == target
	await _click(sp)
	t = 0.0
	while u.pos == start and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("INPUT move: ", start, " -> ", u.pos)
	ok = ok and u.pos == target
	await get_tree().create_timer(0.5).timeout
	await _save_as("input_battle")
	inst.queue_free()
	await get_tree().process_frame
	_campaign()
	var hub: Node = load("res://scenes/guild.tscn").instantiate()
	add_child(hub)
	await get_tree().create_timer(1.5).timeout
	var bp: Vector2 = hub.wv.world_to_screen(Vector3(10.0, 1.2, 0.2))
	await _mouse_to(bp)
	print("INPUT hub hover: ", hub.tavern.hover_id)
	await _click(bp)
	await get_tree().create_timer(0.5).timeout
	var opened: bool = hub.screen != null
	print("INPUT hub click opened a screen: ", opened)
	ok = ok and opened
	print("INPUT result: ", "PASS" if ok else "FAIL")


func _pick_at(inst: Node, p: Vector2) -> Array:
	inst.mouse_override = p
	var r: Array = inst.pick()
	inst.mouse_override = Vector2(-1, -1)
	return r


func _mouse_to(logical: Vector2) -> void:
	var k := Vector2(get_window().size) / get_viewport_rect().size
	var ev := InputEventMouseMotion.new()
	ev.position = logical * k
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	for i in 3:
		await get_tree().process_frame


func _click(logical: Vector2) -> void:
	var k := Vector2(get_window().size) / get_viewport_rect().size
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = logical * k
		ev.global_position = ev.position
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _save_as(name: String) -> void:
	var old := shot
	shot = name
	await _save()
	shot = old


func _save() -> void:
	while Scenes.busy:
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/_cache/shots"))
	img.save_png(ProjectSettings.globalize_path("res://tools/_cache/shots/%s.png" % shot))
