class_name GuildHub
extends Control
## The guild between missions: the tavern diorama, the resource bar,
## facility screens, the week cycle and pending events.

const SCREENS := {
	"board": "res://scripts/guild/screens/board_screen.gd",
	"roster": "res://scripts/guild/screens/roster_screen.gd",
	"recruit": "res://scripts/guild/screens/recruit_screen.gd",
	"facilities": "res://scripts/guild/screens/facilities_screen.gd",
	"stash": "res://scripts/guild/screens/stash_screen.gd",
	"realm": "res://scripts/guild/screens/realm_screen.gd",
	"ledger": "res://scripts/guild/screens/ledger_screen.gd",
	"memorial": "res://scripts/guild/screens/memorial_screen.gd",
	"squad": "res://scripts/guild/screens/squad_screen.gd",
}
const HOTSPOT_SCREEN := {
	"board": ["board", {}], "hearth": ["roster", {}], "recruiter": ["recruit", {}], "library": ["roster", {"tab": "skills"}],
	"memorial": ["memorial", {}], "ledger": ["ledger", {}], "training": ["facilities", {"focus": "training"}],
	"forge": ["stash", {}], "nursery": ["facilities", {"focus": "nursery"}], "barracks": ["facilities", {"focus": "barracks"}],
	"door": ["realm", {}],
}

var campaign: Campaign
var wv: WorldView
var tavern: TavernView
var top_bar: PanelContainer
var res_box: HBoxContainer
var hush_bar: Control
var hover_label: PanelContainer
var hover_text: RichTextLabel
var hint_label: RichTextLabel
var screen_layer: Control
var screen: Control = null
var corner: HBoxContainer
var keys_label: Label
var last_mouse := Vector2(-1, -1)
var busy := false
var _hover_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	campaign = Game.campaign
	if campaign == null:
		# launched directly (editor or dev shot): make a throwaway guild
		campaign = Campaign.new()
		campaign.new_game("The Lantern Company", 1, false, 99)
		Game.campaign = campaign
	wv = WorldView.new()
	add_child(wv)
	_build_tavern()
	_build_hud()
	refresh()
	Audio.play_music("guild")
	await get_tree().process_frame
	await _after_arrival()


func _build_tavern() -> void:
	if tavern:
		tavern.queue_free()
	tavern = TavernView.new()
	wv.world.add_child(tavern)
	tavern.build(campaign, wv)
	tavern.hotspot_hovered.connect(func(_id): pass)


## Rebuild props after a facility upgrade (keeps the camera where it is).
func rebuild_tavern() -> void:
	var t := wv.target_goal
	for c in wv.world.get_children():
		c.queue_free()
	tavern = TavernView.new()
	wv.world.add_child(tavern)
	tavern.build(campaign, wv)
	wv.focus(t, true)


# ====================================================================== HUD
func _build_hud() -> void:
	top_bar = UIKit.panel()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 22
	add_child(top_bar)
	res_box = UIKit.hbox(8)
	top_bar.add_child(res_box)
	# navigation (left side, vertical)
	var nav := UIKit.vbox(2)
	nav.position = Vector2(4, 28)
	add_child(nav)
	for entry in [["board", "Quest Board", "mark"], ["roster", "Roster", "rally"], ["recruit", "Recruits", "knight"],
			["facilities", "Facilities", "bulwark"], ["stash", "Forge & Stash", "sunder"], ["realm", "The Realm", "beacon"],
			["ledger", "Ledger", "quill"], ["memorial", "Memorial", "memory"]]:
		var id: String = entry[0]
		var b := UIKit.button(" " + entry[1], func(): open_screen(id), "", 104)
		b.icon = UIKit.icon_tex(entry[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("nav", id)
		nav.add_child(b)
	# end week and menu
	corner = UIKit.hbox(4)
	add_child(corner)
	var menu := UIKit.button("Menu", _open_menu, "", 50)
	corner.add_child(menu)
	var ew := UIKit.button("End Week", _end_week_pressed, "btn_green", 96)
	ew.icon = UIKit.small_tex("week")
	corner.add_child(ew)
	# story hint
	var hp := UIKit.panel()
	hp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hp.position = Vector2(4, -24)
	add_child(hp)
	hint_label = UIKit.rich("", 330, 9)
	hp.add_child(hint_label)
	hint_label.set_meta("panel", hp)
	# hover label
	hover_label = UIKit.panel("tooltip", Vector4(5, 3, 5, 3))
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.visible = false
	add_child(hover_label)
	hover_text = UIKit.rich("", 0, 9)
	hover_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	hover_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.add_child(hover_text)
	keys_label = UIKit.label("Q/E rotate · Wheel zoom · WASD pan", 8, UITheme.TEXT_DIM)
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(keys_label)
	screen_layer = Control.new()
	screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen_layer)


func refresh() -> void:
	UIKit.clear(res_box)
	var em := UIKit.tex_rect(load("res://assets/sprites/ui/emblem_guild_16.png"))
	res_box.add_child(em)
	res_box.add_child(UIKit.header(campaign.guild_name, 11))
	res_box.add_child(UIKit.label("Week %d · %s" % [campaign.week, DB.story["acts"][str(campaign.act)]["name"].split(":")[0]], 9, UITheme.TEXT_DIM))
	res_box.add_child(UIKit.spacer())
	res_box.add_child(UIKit.stat_row("gold", "%d" % campaign.gold, UITheme.GOLD,
		"Gold. Weekly wages: %d" % campaign.weekly_wages()))
	res_box.add_child(UIKit.stat_row("renown", "%d · %s" % [campaign.renown, Rules.rank_name(campaign.rank())], UITheme.TEXT,
		"Renown. Unlocks better recruits, harder missions and facility levels."))
	res_box.add_child(UIKit.stat_row("materials", "%d" % campaign.materials, UITheme.TEXT, "Materials, used by the Forge."))
	res_box.add_child(UIKit.stat_row("roster", "%d/%d" % [campaign.active_members().size(), campaign.roster_cap()], UITheme.TEXT,
		"Members / barracks capacity"))
	var hb := UIKit.hbox(2)
	hb.add_child(UIKit.tex_rect(UIKit.small_tex("hush")))
	var stage := campaign.hush_stage()
	var hc := UITheme.PURPLE.lerp(UITheme.RED, clampf(stage / 4.0, 0, 1))
	var bar := UIKit.bar(campaign.hush, 100, hc, 50, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	hb.add_child(UIKit.label("%d · %s" % [campaign.hush, Rules.hush_stage_name(stage)], 9, hc))
	hb.tooltip_text = "The Hush: %d/100. It rises every week and when missions are ignored. At 100, the realm is forgotten." % campaign.hush
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	res_box.add_child(hb)
	var hint := campaign.story_hint()
	var avail := campaign.available_members().size()
	var txt := "[color=#%s]%s[/color]" % [UITheme.GOLD.to_html(false), hint] if hint != "" else ""
	txt += ("\n" if txt != "" else "") + "[color=#%s]%d of %d days left · %d member%s ready · %d mission%s on the board[/color]" % [UITheme.TEXT_DIM.to_html(false),
		campaign.days_left(), Campaign.WEEK_DAYS, avail, "" if avail == 1 else "s", campaign.board.size(), "" if campaign.board.size() == 1 else "s"]
	hint_label.text = txt
	var vs := get_viewport_rect().size
	var hp: Control = hint_label.get_meta("panel")
	hp.reset_size()
	hp.position = Vector2(4, vs.y - hp.size.y - 4)
	corner.reset_size()
	corner.position = vs - corner.size - Vector2(4, 4)
	keys_label.size = Vector2(220, 12)
	keys_label.position = Vector2(vs.x - 224, corner.position.y - 13)
	# nav badges
	for b in get_tree().get_nodes_in_group("nav_badge"):
		b.queue_free()
	for n in find_children("*", "Button", true, false):
		if n.has_meta("nav"):
			var badge := _badge_for(n.get_meta("nav"))
			if badge != "":
				var l := UIKit.label(badge, 8, UITheme.GOLD, UITheme.pixel_font)
				l.add_to_group("nav_badge")
				l.position = Vector2(n.custom_minimum_size.x - 10, 1)
				n.add_child(l)


func _badge_for(id: String) -> String:
	match id:
		"roster":
			for m in campaign.roster:
				if m.pending_picks() > 0:
					return "+"
		"recruit":
			if not campaign.recruits.is_empty():
				return str(campaign.recruits.size())
		"board":
			return str(campaign.board.size())
		"memorial":
			if int(campaign.facilities["memorial"]) > 0:
				for d in campaign.dead:
					if not d.get("memorial", false):
						return "!"
	return ""


# ====================================================================== input & hover
func _unhandled_input(event: InputEvent) -> void:
	if Dialogs.open > 0:
		return
	if screen != null or busy:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and screen != null:
			close_screen()
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				wv.zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				wv.zoom(-1)
			MOUSE_BUTTON_LEFT:
				_click()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				wv.rotate_view(-1)
				tavern.update_walls()
			KEY_E:
				wv.rotate_view(1)
				tavern.update_walls()
			KEY_ESCAPE:
				_open_menu()


func _process(_delta: float) -> void:
	if screen != null or busy:
		if hover_label.visible:
			hover_label.visible = false
			tavern.set_hover("")
		return
	var pan := Vector2.ZERO
	if Input.is_action_pressed("cam_left"): pan.x -= 1
	if Input.is_action_pressed("cam_right"): pan.x += 1
	if Input.is_action_pressed("cam_up"): pan.y -= 1
	if Input.is_action_pressed("cam_down"): pan.y += 1
	if pan != Vector2.ZERO:
		var bv := wv.basis_vectors()
		wv.target_goal += (bv["right"] * pan.x - bv["fwd_h"] * pan.y) * _delta * 6.0
	_update_hover()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		last_mouse = (event as InputEventMouse).position


func _mouse() -> Vector2:
	return last_mouse if last_mouse.x >= 0 else get_viewport().get_mouse_position()


func _mouse_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null


func _update_hover() -> void:
	var mp := _mouse()
	var r: Array = ["", null] if _mouse_over_ui() else tavern.pick(mp)
	var key := "%s:%s" % [r[0], str(r[1])]
	if key != _hover_key:
		_hover_key = key
		for id in tavern.member_views:
			tavern.set_member_highlight(id, r[0] == "member" and r[1] == id)
		for k in tavern.recruit_views:
			tavern.recruit_views[k].set_highlight(0.8 if r[0] == "recruit" and r[1] == k else 0.0)
		tavern.set_hover(r[1] if r[0] == "hotspot" else "")
		if r[0] == "":
			hover_label.visible = false
		else:
			hover_text.text = _hover_bbcode(r)
			hover_label.visible = true
			if r[0] == "hotspot":
				Audio.sfx("ui_hover", 0.05, -12.0)
	if hover_label.visible:
		hover_label.reset_size()
		var pos := mp + Vector2(10, 8)
		if r[0] == "hotspot":
			pos = wv.world_to_screen(tavern.anchor_of(r[1])) - Vector2(hover_label.size.x / 2.0, hover_label.size.y + 2)
		var vs := get_viewport_rect().size
		hover_label.position = pos.clamp(Vector2(2, 24), vs - hover_label.size - Vector2(2, 2)).floor()


func _hover_bbcode(r: Array) -> String:
	var gold := UITheme.GOLD.to_html(false)
	var dim := UITheme.TEXT_DIM.to_html(false)
	match r[0]:
		"member":
			var m := campaign.member(r[1])
			if m == null:
				return ""
			var s := "[color=#%s]%s[/color]\nLv %d %s" % [gold, m.name, m.level, m.class_name_full()]
			if not m.injury.is_empty():
				s += "\n[color=#%s]Injured: %d week%s[/color]" % [UITheme.RED.to_html(false), int(m.injury["weeks"]), "" if int(m.injury["weeks"]) == 1 else "s"]
			elif m.days_used > 0:
				s += "\n[color=#%s]Out %d day%s this week[/color]" % [dim, m.days_used, "" if m.days_used == 1 else "s"]
			if m.pending_picks() > 0:
				s += "\n[color=#%s]%d new skill%s to choose[/color]" % [UITheme.GREEN.to_html(false), m.pending_picks(), "" if m.pending_picks() == 1 else "s"]
			return s
		"recruit":
			var m: Member = campaign.recruits[r[1]]
			return "[color=#%s]%s[/color]\nLv %d %s · looking for work\n[color=#%s]Hire: %d gold[/color]" % [gold, m.name, m.level, m.class_name_full(), dim, m.hire_cost]
		"hotspot":
			var id: String = r[1]
			var name: String = TavernView.HOTSPOTS[id][0]
			var fid := id
			if DB.facilities.has(fid):
				var lvl := int(campaign.facilities[fid])
				var ls := "Not built" if lvl == 0 else "Level %d" % lvl
				return "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [gold, name, dim, ls]
			if id == "forge":
				var lvl := int(campaign.facilities["forge"])
				return "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [gold, name, dim, "Not built" if lvl == 0 else "Level %d" % lvl]
			return "[color=#%s]%s[/color]" % [gold, name]
	return ""


func _click() -> void:
	var mp := _mouse()
	if _mouse_over_ui():
		return
	var r := tavern.pick(mp)
	match r[0]:
		"member":
			open_screen("roster", {"member": r[1]})
		"recruit":
			open_screen("recruit", {"index": r[1]})
		"hotspot":
			var s: Array = HOTSPOT_SCREEN.get(r[1], ["", {}])
			if s[0] != "":
				open_screen(s[0], s[1])


# ====================================================================== screens
func open_screen(id: String, params := {}) -> void:
	if busy:
		return
	close_screen(false)
	var script: GDScript = load(SCREENS[id])
	screen = script.new()
	screen.hub = self
	screen.params = params
	screen_layer.add_child(screen)
	Audio.sfx("page", 0.1, -10.0)


func close_screen(refresh_all := true) -> void:
	if screen != null:
		screen.queue_free()
		screen = null
	if refresh_all:
		refresh()
		tavern.refresh_people()


## Screens call this after changing the campaign.
func changed(rebuild := false) -> void:
	refresh()
	if rebuild:
		rebuild_tavern()
	else:
		tavern.refresh_people()
	Game.save()


func toast(text: String, color := UITheme.TEXT) -> void:
	var l := UIKit.label(text, 10, color, UITheme.pixel_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vs := get_viewport_rect().size
	l.size = Vector2(vs.x, 14)
	l.position = Vector2(0, vs.y * 0.18)
	l.z_index = 20
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


# ====================================================================== week & events
func _end_week_pressed() -> void:
	if busy:
		return
	var ignored: Array = []
	for m in campaign.board:
		var ig: Dictionary = m.get("ignore", {})
		if ig.has("hush"):
			ignored.append("• %s: Hush +%d" % [m["title"], int(ig["hush"])])
		elif ig.has("power"):
			ignored.append("• %s: %s Power -1" % [m["title"], DB.factions[m["faction"]]["short"]])
		elif ig.get("story", false):
			ignored.append("• %s: Hush +3, Renown -3" % m["title"])
	var text := "Wages due: [color=#%s]%d gold[/color] (you have %d)." % [UITheme.GOLD.to_html(false), campaign.weekly_wages(), campaign.gold]
	if campaign.weekly_wages() > campaign.gold:
		text += "\n[color=#%s]You cannot pay everyone. Unpaid members may leave.[/color]" % UITheme.RED.to_html(false)
	if not ignored.is_empty():
		text += "\n\nMissions left on the board will expire:\n" + "\n".join(ignored)
	text += "\n\nThe Hush grows by 2 each week."
	Dialogs.confirm(self, "End Week %d?" % campaign.week, text, _do_end_week, "End Week")


func _do_end_week() -> void:
	busy = true
	close_screen(false)
	Audio.sfx("bell_far", 0.0, -2.0)
	Scenes.flash(Color(0.05, 0.04, 0.07, 1.0), 0.9)
	var rep := campaign.end_week()
	Game.save()
	rebuild_tavern()
	refresh()
	await get_tree().create_timer(0.5).timeout
	await _week_report(rep)
	await _process_events()
	busy = false
	_check_game_over()


func _week_report(rep: Dictionary) -> void:
	var g := UITheme.GOLD.to_html(false)
	var r := UITheme.RED.to_html(false)
	var gr := UITheme.GREEN.to_html(false)
	var lines: Array = []
	if rep["paid"]:
		lines.append("Wages paid: [color=#%s]%d gold[/color]." % [g, rep["wages"]])
	else:
		lines.append("[color=#%s]Wages unpaid! (%d week%s in a row)[/color]" % [r, campaign.unpaid_weeks, "" if campaign.unpaid_weeks == 1 else "s"])
	for s in rep["ignored"]:
		lines.append("[color=#%s]%s[/color]" % [r, s])
	for n in rep["left"]:
		lines.append("[color=#%s]%s left the guild.[/color]" % [r, n])
	for n in rep["healed"]:
		lines.append("[color=#%s]%s has recovered.[/color]" % [gr, n])
	if int(rep["training"]) > 0:
		lines.append("%d member%s trained at home." % [rep["training"], "" if int(rep["training"]) == 1 else "s"])
	for f in rep["collapsed"]:
		lines.append("[color=#%s]The %s collapsed![/color]" % [r, DB.factions[f]["name"]])
	lines.append("The Hush: %d → [color=#%s]%d[/color]." % [rep["hush_before"], UITheme.PURPLE.to_html(false), rep["hush_after"]])
	lines.append("New recruits wait at the bar. The board has %d new missions." % campaign.board.size())
	var done := [false]
	Dialogs.message(self, "Week %d ends" % rep["week"], "\n".join(lines), func(): done[0] = true, "Onward")
	while not done[0]:
		await get_tree().process_frame
	if int(rep["stage_after"]) > int(rep["stage_before"]):
		var ev: String = DB.events["hush_stages"].get(Rules.hush_stage_name(int(rep["stage_after"])).to_lower(), "")
		if ev != "":
			Audio.sfx("hush", 0.0, 0.0)
			done[0] = false
			Dialogs.message(self, "The Hush deepens", ev, func(): done[0] = true)
			while not done[0]:
				await get_tree().process_frame


func _process_events() -> void:
	while not campaign.pending_events.is_empty():
		var ev: Dictionary = campaign.pending_events.pop_front()
		var done := [false]
		match ev.get("kind", ""):
			"random":
				var data: Dictionary = DB.events["random"].get(ev["id"], {})
				if data.is_empty():
					continue
				var choices: Array = []
				for i in data["choices"].size():
					var ch: Dictionary = data["choices"][i]
					var cost := int(ch.get("cost", {}).get("gold", 0))
					var pick := _event_choice.bind(ev["id"], i, data["title"], done)
					choices.append([ch["label"], pick, "", cost <= campaign.gold])
				Dialogs.choice(self, data["title"], data["text"], choices)
			"war":
				var a: String = ev["a"]
				var b: String = ev["b"]
				var side_a := _war_choice.bind(a, b, done)
				var side_b := _war_choice.bind(b, a, done)
				Dialogs.choice(self, ev["title"], ev["text"], [
					["Side with the %s" % DB.factions[a]["name"], side_a, "btn_blue"],
					["Side with the %s" % DB.factions[b]["name"], side_b, "btn_blue"],
				])
			_:
				Dialogs.message(self, ev.get("title", "News"), ev.get("text", ""), func(): done[0] = true)
		while not done[0]:
			await get_tree().process_frame
		refresh()
	Game.save()


func _event_choice(ev_id: String, idx: int, title: String, done: Array) -> void:
	var res := campaign.resolve_event(ev_id, idx)
	refresh()
	Dialogs.message(self, title, res, func(): done[0] = true)


func _war_choice(winner: String, loser: String, done: Array) -> void:
	campaign.resolve_war(winner, loser)
	done[0] = true


func _after_arrival() -> void:
	busy = true
	if not campaign.tutorial_seen.get("hub", false):
		campaign.tutorial_seen["hub"] = true
		var done := [false]
		Dialogs.message(self, "The Old Tavern",
			"This is your guild. Click the [color=#%s]Quest Board[/color] to choose missions, the [color=#%s]hearth[/color] to see your members and the [color=#%s]bar[/color] to hire recruits.\n\nEach week every member has 7 days. Missions take days; injured members rest. When you are done, [color=#%s]End Week[/color]: wages are paid, the board refreshes, and the Hush creeps closer.\n\nLeft on the board, strategic missions cost the realm. You can never do everything." % [
			UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false)],
			func(): done[0] = true, "Understood", 300)
		while not done[0]:
			await get_tree().process_frame
		Game.save()
	await _process_events()
	busy = false
	_check_game_over()


func _check_game_over() -> void:
	if campaign.game_over != "":
		Game.save()
		Scenes.go("res://scenes/ending.tscn")


# ====================================================================== menu
func _open_menu() -> void:
	if busy:
		return
	Dialogs.choice(self, campaign.guild_name, "Week %d · %s%s" % [campaign.week, ["Forgiving", "Standard", "Merciless"][campaign.difficulty],
		" · Ironman" if campaign.ironman else ""], [
		["Resume", func(): pass, ""],
		["Settings", func(): SettingsPanel.open(self), ""],
		["Save & Quit to Title", _quit_to_title, ""],
		["Save & Exit Game", _quit_game, "btn_red"],
	], 180)


func _quit_to_title() -> void:
	Game.save()
	Scenes.go("res://scenes/title.tscn")


func _quit_game() -> void:
	Game.save()
	get_tree().quit()
