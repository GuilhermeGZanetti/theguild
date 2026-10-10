extends "res://scripts/combat/battle_scene.gd"
## The battle scene as the trailer films it (scripts/trailer/trailer.gd):
## plays a staged script instead of the turn loop, or lets the AI fight on
## both sides; ignores the real mouse and never leaves when the fight ends.

var staged: Callable              # func(scene) awaited instead of the turn loop
var clean := false                # only floating text, health bars and banners
var fake_mouse := Vector2(-1, -1) # where the director's cursor points (canvas)
var cam_lock := false             # hold the camera on cam_goal
var cam_goal := Vector3.ZERO


func _loop() -> void:
	# the mission banner of _ready: keep its title, drop the objective line
	hud.sub_banner.text = ""
	if clean:
		for c in hud.get_children():
			if not c in [hud.float_layer, hud.bars_layer, hud.banner, hud.sub_banner]:
				c.visible = false
	if staged.is_valid():
		await staged.call(self)
		return
	await super()


func _process(delta: float) -> void:
	super(delta)
	if cam_lock:
		wv.target_goal = cam_goal


func _input(_event: InputEvent) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _mouse() -> Vector2:
	return fake_mouse if fake_mouse.x >= 0 else Vector2(-9999, -9999)


## Notable moments go to stdout with their frame, to find highlights in long takes.
func _play_one(e: Dictionary) -> void:
	if e["t"] in ["skill", "hit", "miss", "death", "downed", "alert", "objective", "bark", "status", "heal"]:
		var u: BattleUnit = battle.unit(int(e.get("uid", -1)))
		var extra := ""
		match e["t"]:
			"skill": extra = e.get("name", "")
			"hit": extra = "%d%s" % [int(e["dmg"]), " CRIT" if e.get("crit", false) else ""]
			"status": extra = e.get("id", "")
			"bark": extra = e.get("text", "")
		print("TRAILER_EVENT %d %s %s %s" % [Engine.get_frames_drawn(), e["t"], u.name if u else "-", extra])
	await super(e)


func _on_battle_end() -> void:
	if ended:
		return
	ended = true
	state = "over"
	_refresh_all()
	await _wait(0.6)
	if battle.result == "victory":
		Audio.sfx("victory")
		hud.show_banner("Victory", battle.mission.get("title", ""), UITheme.GOLD, 2.2)


# ---------------------------------------------------------------- staging
func place(u: BattleUnit, cell: Vector2i, facing := Vector2i.ZERO) -> void:
	u.pos = cell
	view_cell[u.uid] = cell
	var uv: UnitView = views[u.uid]
	uv.position = map_view.unit_pos(cell)
	uv.visible = true
	view_gone.erase(u.uid)
	if facing != Vector2i.ZERO:
		u.facing = facing
		uv.face(facing)


## Takes a unit out of the shot (and out of the rules).
func remove(u: BattleUnit) -> void:
	u.state = "dead"
	u.hp = 0
	u.pos = Vector2i(-100 - u.uid, -100)
	views[u.uid].visible = false
	view_gone[u.uid] = true


func face_to(u: BattleUnit, cell: Vector2i) -> void:
	var d := cell - u.pos
	var f := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	u.facing = f
	views[u.uid].face(f)


## Uses a skill whatever the turn order says, then plays what happened.
func act(u: BattleUnit, skill_id: String, cell: Vector2i) -> bool:
	u.acted = false
	u.moved = false
	u.cds.erase(skill_id)
	battle.current = u
	turn_unit = u
	var ok := battle.use_skill(u, skill_id, cell)
	if not ok:
		push_warning("TRAILER act failed: %s %s -> %s" % [u.name, skill_id, cell])
	await _play(battle.pop_events())
	hud.update_bars(battle, views)
	return ok


func walk(u: BattleUnit, cell: Vector2i) -> void:
	u.acted = false
	u.moved = false
	battle.current = u
	turn_unit = u
	if not battle.do_move(u, cell):
		push_warning("TRAILER walk failed: %s -> %s" % [u.name, cell])
	await _play(battle.pop_events())


func hold(t: float) -> void:
	await get_tree().create_timer(t).timeout
