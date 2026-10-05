extends Control
## Title screen: a slowly turning diorama of Carrow at dusk, the main menu,
## new game setup, save slots, settings and credits.

const DIFFICULTIES := [
	["Forgiving", "More starting gold. The downed bleed out in 4 turns; serious injuries are rarer."],
	["Standard", "The intended balance. The downed bleed out in 3 turns."],
	["Merciless", "Little gold. The downed bleed out in 2 turns; wounds are often serious."],
]
const GUILD_NAMES := ["The Lantern Company", "The Last Ledger", "The Bellwrights", "The Ink & Iron", "The Grey Wardens",
	"The Hearthbound", "The Nameless Few", "The Carrow Company"]

var wv: WorldView
var map_view: BattleMapView
var menu_box: VBoxContainer
var modal: CanvasLayer = null
var units: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_menu()
	Audio.play_music("menu")


func _build_backdrop() -> void:
	wv = WorldView.new()
	add_child(wv)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var gen := MapGen.new()
	var out := gen.generate({"region": "carrow", "objective": "clear", "seed": 31}, rng, 4)
	var grid: BattleGrid = out["grid"]
	map_view = BattleMapView.new()
	wv.world.add_child(map_view)
	map_view.build(grid, wv)
	map_view.set_grid_alpha(0.0)
	# dusk
	map_view.set_mist(Color(0.52, 0.45, 0.56), 1.0)
	map_view.environment.ambient_light_color = Color(0.5, 0.4, 0.62)
	map_view.environment.ambient_light_energy = 0.75
	map_view.sun.light_color = Color(1.0, 0.66, 0.48)
	map_view.sun.light_energy = 0.9
	map_view.update_unit_light()
	# a few guild members by a campfire near the middle
	var c := Vector2i(grid.w / 2, grid.h / 2)
	var spot := c
	for r in 6:
		var found := false
		for cc in grid.cells_in_radius(c, r):
			if grid.standable(cc) and grid.t(cc)["prop"] == "" and TerrainBuilder.top_y(grid, cc) == TerrainBuilder.top_y(grid, c):
				spot = cc
				found = true
				break
		if found:
			break
	var fire := PropLib.instance("campfire", "town")
	if fire:
		fire.position = map_view.cell_top(spot)
		map_view.add_child(fire)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.omni_range = 4.5
		l.light_energy = 2.0
		l.position = Vector3(0, 0.4, 0)
		fire.add_child(l)
	var urng := RandomNumberGenerator.new()
	urng.seed = 8
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in 4:
		var cls: String = DB.base_classes()[i]
		var m := Member.create(urng, cls, ["human", "tidefolk", "mothkin", "barkborn"][i], 1)
		var uv := UnitView.new()
		map_view.add_child(uv)
		uv.setup(m.variant, m.palette, wv.pitch)
		var d: Vector2i = dirs[i]
		uv.position = map_view.cell_top(spot) + Vector3(d.x * 0.85, 0, d.y * 0.85)
		uv.face(-d)
		units.append(uv)
	wv.bounds = Rect2(0, 0, grid.w, grid.h)
	var fp := map_view.cell_top(spot)
	wv.focus(fp + Vector3(0, 0, 0), true)
	# the camera holds still: a slow turn makes the pixel art shimmer
	wv.yaw = 20.0
	wv.yaw_target = 20.0
	var bv := wv.basis_vectors()
	for uv in units:
		uv.set_camera(deg_to_rad(wv.yaw), bv["fwd"], bv["right"])
	map_view.set_camera_yaw(wv.yaw)


func _build_menu() -> void:
	var vs := get_viewport_rect().size
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.06, 0.55)
	shade.size = Vector2(170, vs.y)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# title and tagline stay inside the shaded column, as wide as the buttons
	var title := UIKit.title("A Guilda", 42)
	title.position = Vector2(16, 22)
	add_child(title)
	var sub := UIKit.label("Write your name before the Hush forgets it.", 9, UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 138
	sub.position = Vector2(16, 70)
	add_child(sub)
	menu_box = UIKit.vbox(4)
	menu_box.position = Vector2(16, 110)
	add_child(menu_box)
	var cont := _latest_slot()
	if cont >= 0:
		var info := Game.slot_info(cont)
		var b := UIKit.button("Continue", func(): _load(cont), "btn_green", 138)
		b.tooltip_text = "%s · week %d" % [info.get("guild", "?"), int(info.get("week", 1))]
		menu_box.add_child(b)
	menu_box.add_child(UIKit.button("New Guild", _new_game_dialog, "" if cont >= 0 else "btn_green", 138))
	menu_box.add_child(UIKit.button("Load", _load_dialog, "", 138))
	menu_box.add_child(UIKit.button("Settings", func(): SettingsPanel.open(self), "", 138))
	menu_box.add_child(UIKit.button("Credits", _credits, "", 138))
	menu_box.add_child(UIKit.button("Quit", func(): get_tree().quit(), "btn_red", 138))
	var ver := UIKit.label("v1.0 · Godot %s" % Engine.get_version_info()["string"].split(".stable")[0], 8, UITheme.TEXT_DIM)
	ver.position = Vector2(16, vs.y - 14)
	add_child(ver)


func _latest_slot() -> int:
	var best := -1
	var best_t := ""
	for s in Game.SLOTS:
		var info := Game.slot_info(s)
		if info.is_empty() or info.get("corrupt", false) or info.get("over", "") != "":
			continue
		var t: String = info.get("saved_at", "")
		if best < 0 or t > best_t:
			best = s
			best_t = t
	return best


func _load(s: int) -> void:
	if Game.load_slot(s):
		Audio.sfx("ui_select")
		Scenes.go("res://scenes/guild.tscn")
	else:
		Dialogs.message(self, "Cannot load", "That save could not be read.")


# ---------------------------------------------------------------- modal helper
func _open_modal(width: int) -> VBoxContainer:
	_close_modal()
	modal = CanvasLayer.new()
	modal.layer = 40
	add_child(modal)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := UIKit.panel()
	p.custom_minimum_size.x = width
	root.add_child(p)
	var v := UIKit.vbox(4)
	p.add_child(v)
	p.set_meta("center", true)
	_center_later(p)
	return v


func _center_later(p: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(p):
		p.reset_size()
		p.position = ((get_viewport_rect().size - p.size) / 2.0).floor()


func _close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null


# ---------------------------------------------------------------- new game
var _ng := {"name": "", "difficulty": 1, "ironman": false, "slot": 0}


func _new_game_dialog() -> void:
	if _ng["name"] == "":
		_ng["name"] = GUILD_NAMES[randi() % GUILD_NAMES.size()]
		_ng["slot"] = _free_slot()
	var v := _open_modal(330)
	v.add_child(UIKit.title("Found a Guild", 20))
	v.add_child(UIKit.rich("You inherit an abandoned tavern in Carrow, an old emblem no one can identify, and a ledger of blank pages.", 318, 9))
	v.add_child(UIKit.label("Guild name", 9, UITheme.TEXT_DIM))
	var le := LineEdit.new()
	le.text = _ng["name"]
	le.max_length = 28
	le.custom_minimum_size.x = 318
	le.text_changed.connect(func(t): _ng["name"] = t)
	v.add_child(le)
	v.add_child(UIKit.label("Difficulty", 9, UITheme.TEXT_DIM))
	var dh := UIKit.hbox(3)
	for i in 3:
		var idx := i
		dh.add_child(UIKit.button(DIFFICULTIES[i][0], func():
			_ng["difficulty"] = idx
			_new_game_dialog(), "btn_blue" if _ng["difficulty"] == i else "", 104))
	v.add_child(dh)
	v.add_child(UIKit.rich("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), DIFFICULTIES[_ng["difficulty"]][1]], 318, 8))
	var iron := CheckBox.new()
	iron.text = "Ironman: one save, no reloading, every choice is final"
	iron.button_pressed = _ng["ironman"]
	iron.focus_mode = Control.FOCUS_NONE
	iron.toggled.connect(func(on): _ng["ironman"] = on)
	v.add_child(iron)
	v.add_child(UIKit.label("Save slot", 9, UITheme.TEXT_DIM))
	var sh := UIKit.hbox(3)
	for s in Game.SLOTS:
		var info := Game.slot_info(s)
		var label := "Slot %d: empty" % (s + 1) if info.is_empty() else "Slot %d: %s" % [s + 1, String(info.get("guild", "?")).left(10)]
		var ss := s
		sh.add_child(UIKit.button(label, func():
			_ng["slot"] = ss
			_new_game_dialog(), "btn_blue" if _ng["slot"] == s else "", 104))
	v.add_child(sh)
	var bh := UIKit.hbox(4)
	bh.alignment = BoxContainer.ALIGNMENT_END
	bh.add_child(UIKit.button("Cancel", _close_modal, "", 70))
	bh.add_child(UIKit.button("Begin", _start_new, "btn_green", 90))
	v.add_child(bh)


func _free_slot() -> int:
	for s in Game.SLOTS:
		if Game.slot_info(s).is_empty():
			return s
	return 0


func _start_new() -> void:
	var name := String(_ng["name"]).strip_edges()
	if name == "":
		name = "The Guild"
	var begin := func():
		Game.new_campaign(name, int(_ng["difficulty"]), bool(_ng["ironman"]), int(_ng["slot"]))
		_close_modal()
		var pages: Array = [{"title": "Prologue", "text": DB.story["intro"][0]}]
		for i in range(1, DB.story["intro"].size()):
			pages.append(DB.story["intro"][i])
		pages.append({"title": DB.story["acts"]["1"]["name"], "text": DB.story["acts"]["1"]["desc"], "big": true})
		Scenes.go("res://scenes/story.tscn", {"pages": pages, "next": "res://scenes/guild.tscn"})
	if not Game.slot_info(int(_ng["slot"])).is_empty():
		Dialogs.confirm(self, "Overwrite slot %d?" % (int(_ng["slot"]) + 1), "The guild saved there will be lost.", begin, "Overwrite")
	else:
		begin.call()


# ---------------------------------------------------------------- load
func _load_dialog() -> void:
	var v := _open_modal(330)
	v.add_child(UIKit.title("Load", 20))
	for s in Game.SLOTS:
		var info := Game.slot_info(s)
		var p := UIKit.panel("panel_inset", Vector4(5, 3, 5, 3))
		var h := UIKit.hbox(4)
		p.add_child(h)
		var iv := UIKit.vbox(0)
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(iv)
		var ss := s
		if info.is_empty():
			iv.add_child(UIKit.label("Slot %d · empty" % (s + 1), 10, UITheme.TEXT_DIM))
		elif info.get("corrupt", false):
			iv.add_child(UIKit.label("Slot %d · unreadable" % (s + 1), 10, UITheme.RED))
		else:
			iv.add_child(UIKit.label("%s" % info["guild"], 10, UITheme.GOLD, UITheme.pixel_font))
			var over: String = info.get("over", "")
			var status := "Week %d · %d members · Renown %d · Hush %d" % [int(info["week"]), int(info["members"]), int(info["renown"]), int(info["hush"])]
			if over != "":
				status = "The story has ended (%s)" % ("victory" if over == "victory" else "defeat")
			iv.add_child(UIKit.label(status, 8, UITheme.TEXT_DIM))
			iv.add_child(UIKit.label("%s%s · %s" % [["Forgiving", "Standard", "Merciless"][int(info["difficulty"])], " · Ironman" if info["ironman"] else "",
				String(info.get("saved_at", "")).replace("T", " ").left(16)], 8, UITheme.TEXT_DIM))
			var lb := UIKit.button("Load", func(): _load(ss), "btn_green", 50)
			lb.disabled = over != ""
			h.add_child(lb)
		if not info.is_empty():
			h.add_child(UIKit.button("Delete", func():
				Dialogs.confirm(self, "Delete slot %d?" % (ss + 1), "This cannot be undone.", func():
					Game.delete_slot(ss)
					_load_dialog(), "Delete"), "btn_red", 50))
		v.add_child(p)
	var bh := UIKit.hbox(4)
	bh.alignment = BoxContainer.ALIGNMENT_END
	bh.add_child(UIKit.button("Back", _close_modal, "", 70))
	v.add_child(bh)


# ---------------------------------------------------------------- credits
func _credits() -> void:
	var v := _open_modal(330)
	v.add_child(UIKit.title("Credits", 20))
	v.add_child(UIKit.rich("[color=#%s]A Guilda[/color]\nA turn-based tactics and guild management game.\n\nDesign, code, art, music and sound were generated from a design document by an AI coding agent (Claude), using Godot, Blender and Python.\n\n[color=#%s]Engine[/color]: Godot Engine (MIT License)\n[color=#%s]Tests[/color]: GUT, Godot Unit Test (MIT License)\n[color=#%s]Fonts[/color] (SIL Open Font License): Alegreya Sans by Juan Pablo del Peral / Huerta Tipográfica; Pixelify Sans by Stefie Justprince; Jacquard 12 by Sarah Cadigan-Fried; Jersey 10 by Sarah Cadigan-Fried." % [
		UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false), UITheme.GOLD.to_html(false)], 318, 9))
	var bh := UIKit.hbox(4)
	bh.alignment = BoxContainer.ALIGNMENT_END
	bh.add_child(UIKit.button("Back", _close_modal, "", 70))
	v.add_child(bh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and modal:
		_close_modal()
