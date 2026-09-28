extends Node
## Developer smoke test that drives the real scenes end to end:
## new guild -> hub -> story mission -> auto-played battle -> report ->
## story page -> hub -> end of week. Saves a screenshot at each step to
## tools/_cache/shots/flow_*.png and prints FLOW lines. (--shot=flow)

var shots := 0
var failures: Array = []


func run() -> void:
	var tree := get_tree()
	Game.new_campaign("Smoke Test Company", 1, false, 2)
	Game.campaign.tutorial_seen["hub"] = true
	Game.autoplay = true
	Settings.combat_speed = 4.0
	Scenes.go("res://scenes/guild.tscn")
	await _settle(2.0)
	_check(tree.current_scene is GuildHub, "hub loaded")
	await _shot("hub")
	var hub: GuildHub = tree.current_scene
	hub.open_screen("board")
	await _settle(0.8)
	await _shot("board")
	var mission := {}
	for m in Game.campaign.board:
		if m["category"] == "story":
			mission = m
	_check(not mission.is_empty(), "story mission on the board")
	hub.open_screen("squad", {"mission": int(mission["id"])})
	await _settle(0.8)
	await _shot("squad")
	var squad: Array = hub.screen.picked
	_check(squad.size() >= 3, "squad preselected (%d)" % squad.size())
	hub.screen._launch()
	await _settle(3.0)
	_check(tree.current_scene is BattleScene, "battle loaded")
	await _shot("battle_start")
	# let the AI fight it out
	var t := 0.0
	var mid_shot := false
	while tree.current_scene is BattleScene and t < 240.0:
		await tree.create_timer(0.5).timeout
		t += 0.5
		if not mid_shot and t > 8.0:
			mid_shot = true
			await _shot("battle_mid")
	print("FLOW battle took %.0fs, result %s" % [t, Game.last_report.get("result", "?")])
	await _settle(2.5)
	_check(tree.current_scene.scene_file_path.ends_with("report.tscn"), "report loaded")
	await _shot("report")
	tree.current_scene._continue()
	await _settle(2.0)
	await _shot("after_report")
	# click through story pages if any
	var guard := 0
	while not tree.current_scene is GuildHub and guard < 20:
		guard += 1
		if tree.current_scene.has_method("_advance"):
			tree.current_scene._advance()
			tree.current_scene._advance()
		await _settle(0.8)
	_check(tree.current_scene is GuildHub, "back at the hub")
	await _settle(1.5)
	await _shot("hub_after")
	hub = tree.current_scene
	var week := Game.campaign.week
	var rep := Game.campaign.end_week()
	hub.refresh()
	hub.rebuild_tavern()
	_check(Game.campaign.week == week + 1, "week advanced")
	print("FLOW week report: ", rep["wages"], " wages, hush ", rep["hush_before"], "->", rep["hush_after"])
	await _settle(1.0)
	await _shot("week2")
	Game.save()
	_check(Game.load_slot(2), "save loads")
	print("FLOW done, failures: ", failures.size(), " ", failures)
	Game.delete_slot(2)
	tree.quit(0 if failures.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	print("FLOW %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures.append(what)


func _settle(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
	while Scenes.busy:
		await get_tree().process_frame


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	shots += 1
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/_cache/shots"))
	img.save_png(ProjectSettings.globalize_path("res://tools/_cache/shots/flow_%d_%s.png" % [shots, name]))
