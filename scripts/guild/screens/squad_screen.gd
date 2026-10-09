extends GuildScreen
## Squad selection: pick who goes, check loadouts, then march out.

var mission := {}
var picked: Array = []


func screen_title() -> String:
	return "Assemble Squad"


func subtitle() -> String:
	mission = campaign.mission_by_id(int(params.get("mission", -1)))
	if mission.is_empty():
		return ""
	return "%s · %d days (the guild has %d left) · up to %d members" % [mission["title"], int(mission["days"]), campaign.days_left(), campaign.squad_cap()]


func build() -> void:
	mission = campaign.mission_by_id(int(params.get("mission", -1)))
	if mission.is_empty():
		body.add_child(UIKit.label("That mission is gone.", 10))
		return
	if picked.is_empty() and not params.has("touched"):
		params["touched"] = true
		# preselect the healthiest available members, one per class first
		var pool: Array = campaign.available_members()
		pool.sort_custom(func(a, b): return a.level > b.level)
		var classes := {}
		for m in pool:
			if picked.size() < campaign.squad_cap() and not classes.has(m.cls):
				picked.append(m)
				classes[m.cls] = true
		for m in pool:
			if picked.size() < campaign.squad_cap() and not m in picked:
				picked.append(m)
	var h := UIKit.hbox(6)
	body.add_child(h)
	var list := UIKit.vbox(2)
	for m in campaign.roster:
		list.add_child(_row(m))
	var sc := scroll(list)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sc)
	# summary
	var side := UIKit.vbox(4)
	side.custom_minimum_size.x = 180
	h.add_child(side)
	side.add_child(UIKit.header("The Squad (%d/%d)" % [picked.size(), campaign.squad_cap()], 11))
	var faces := HFlowContainer.new()
	faces.custom_minimum_size.x = 176
	for m in picked:
		faces.add_child(MemberCard.portrait(m, 24))
	side.add_child(faces)
	var od: Dictionary = DB.missions["objectives"].get(mission["objective"], {})
	side.add_child(UIKit.rich("[color=#%s]%s[/color]\n%s" % [hex(UITheme.GOLD), od.get("name", "Final"), load("res://scripts/guild/screens/board_screen.gd").objective_text(mission)], 176, 9))
	side.add_child(UIKit.skulls(int(mission["skulls"])))
	var diff: String = ["Forgiving: the downed bleed out in 4 turns.", "Standard: the downed bleed out in 3 turns.", "Merciless: the downed bleed out in 2 turns."][campaign.difficulty]
	side.add_child(UIKit.rich("[color=#%s]%s\nDeath is permanent.[/color]" % [hex(UITheme.TEXT_DIM), diff], 176, 8))
	if mission.get("faction", "") != "" and int(campaign.factions[mission["faction"]]["rep"]) <= -2:
		side.add_child(UIKit.rich("[color=#%s]The %s are hostile to the guild. Expect an ambush.[/color]" % [hex(UITheme.RED), DB.factions[mission["faction"]]["short"]], 176, 9))
	side.add_child(UIKit.spacer(0, 0))
	var err := campaign.can_launch(mission, picked)
	var go := UIKit.button("March Out", _launch, "btn_green", 176)
	go.disabled = err != ""
	go.tooltip_text = err
	side.add_child(go)
	if err != "":
		side.add_child(UIKit.label(err, 8, UITheme.RED))
	side.add_child(UIKit.button("Back to the Board", func(): hub.open_screen("board"), "", 176))


func _row(m: Member) -> Control:
	var ok := m.is_available()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = m in picked
	UIKit.list_row(b, m in picked)
	b.disabled = not ok
	b.custom_minimum_size = Vector2(390, 30)
	var h := UIKit.hbox(4)
	h.position = Vector2(3, 2)
	b.add_child(h)
	h.add_child(MemberCard.row(m, 180))
	var s := m.stats()
	var st := UIKit.label("HP %d  Atk %d  Def %d" % [int(s["hp"]), int(s["attack"]), int(s["defense"])], 8, UITheme.TEXT_DIM)
	st.custom_minimum_size.x = 96
	h.add_child(st)
	for sk in m.loadout:
		h.add_child(MemberCard.skill_icon(sk, 16))
	for c in h.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ok:
		b.tooltip_text = "Injured."
		b.modulate = Color(0.7, 0.7, 0.7)
	var mm := m
	b.pressed.connect(func():
		if mm in picked:
			picked.erase(mm)
		elif picked.size() < campaign.squad_cap():
			picked.append(mm)
		else:
			hub.toast("The squad is full.", UITheme.RED)
		Audio.sfx("cloth", 0.1, -8.0)
		rebuild())
	return b


func _launch() -> void:
	var err := campaign.can_launch(mission, picked)
	if err != "":
		hub.toast(err, UITheme.RED)
		return
	var go := func():
		Game.start_battle(mission, picked)
		Audio.stop_music(0.6)
		Audio.sfx("battle_start", 0.0, -2.0)
		Scenes.go("res://scenes/battle.tscn")
	var march := func():
		if campaign.ironman:
			Dialogs.confirm(hub, "March out?", "Ironman: the battle is saved as it starts. Quitting mid-battle abandons the mission.", go, "March Out")
		else:
			go.call()
	# the last stand is balanced for a guild with allies beside it
	if mission.get("story_id", "") == "final" and campaign.allied_factions().is_empty():
		Dialogs.confirm(hub, "The Final Battle", "This is the final battle! But you don't have any allies. Are you sure you want to fight alone? The Hush is strong here.",
			march, "Fight Alone")
	else:
		march.call()
