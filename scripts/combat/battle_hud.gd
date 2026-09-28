class_name BattleHUD
extends Control
## Combat HUD: timeline, objective, unit panel, action bar, hit previews,
## floating combat text, HP/Defense bars and barks.

signal action_pressed(kind: String, arg: String)
signal menu_pressed

var scene  # BattleScene
var timeline_box: HBoxContainer
var round_label: Label
var obj_title: Label
var obj_text: RichTextLabel
var unit_panel: PanelContainer
var action_box: HBoxContainer
var action_hint: Label
var preview: PanelContainer
var preview_body: VBoxContainer
var info: PanelContainer
var info_body: VBoxContainer
var float_layer: Control
var bars_layer: Control
var banner: Label
var sub_banner: Label
var log_box: VBoxContainer
var bars := {}
var _log_lines: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_layer = Control.new()
	bars_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bars_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bars_layer)
	float_layer = Control.new()
	float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(float_layer)
	_build_timeline()
	_build_objective()
	_build_unit_panel()
	_build_actions()
	_build_log()
	_build_preview()
	_build_banner()
	var mb := UIKit.button("Menu", func(): menu_pressed.emit())
	mb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mb.position = Vector2(-44, 4)
	mb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(mb)
	var hint := UIKit.label("Q/E rotate · Wheel zoom · WASD pan", 8, UITheme.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(-150, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size.x = 146
	add_child(hint)


# ------------------------------------------------------------------ timeline
func _build_timeline() -> void:
	var p := UIKit.panel("panel", Vector4(4, 3, 4, 3))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.position.y = 3
	add_child(p)
	var h := UIKit.hbox(4)
	p.add_child(h)
	round_label = UIKit.header("Round 1", 10)
	round_label.custom_minimum_size.x = 48
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(round_label)
	timeline_box = UIKit.hbox(2)
	h.add_child(timeline_box)
	p.resized.connect(func(): p.position.x = (size.x - p.size.x) / 2.0)


func refresh_timeline(b: Battle) -> void:
	UIKit.clear(timeline_box)
	var seen_current := false
	for entry in b.timeline_preview(10):
		var u: BattleUnit = b.unit(entry[0])
		if u == null:
			continue
		var is_cur: bool = b.current == u and not seen_current
		if is_cur:
			seen_current = true
		timeline_box.add_child(_timeline_entry(u, is_cur))
	await get_tree().process_frame
	var p: Control = timeline_box.get_parent().get_parent()
	p.position.x = (size.x - p.size.x) / 2.0


func _timeline_entry(u: BattleUnit, current: bool) -> Control:
	var frame := PanelContainer.new()
	var col := Color8(70, 110, 190) if u.team == BattleUnit.TEAM_PLAYER else Color8(190, 70, 60)
	if u.npc:
		col = Color8(90, 170, 90)
	if current:
		col = Color8(246, 204, 96)
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color8(24, 16, 26), col, 1, 1))
	var por := _portrait(u)
	por.custom_minimum_size = Vector2(20, 20) if not current else Vector2(24, 24)
	frame.add_child(por)
	frame.tooltip_text = "%s%s" % [u.name, " (Downed)" if u.state == "downed" else ""]
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	if u.state == "downed":
		por.modulate = Color(1, 0.5, 0.5)
	return frame


func _portrait(u: BattleUnit) -> TextureRect:
	var sprite := u.sprite
	if sprite.begins_with("__object_"):
		var r := UIKit.tex_rect(UIKit.icon_tex("shield"))
		return r
	var por := UIKit.portrait(sprite, u.palette, false, 0.9 if u.echo else 0.0)
	var at := AtlasTexture.new()
	at.atlas = por.texture
	at.region = Rect2(4, 2, 24, 24)
	por.texture = at
	return por


# ------------------------------------------------------------------ objective
func _build_objective() -> void:
	var p := UIKit.panel()
	p.position = Vector2(4, 4)
	p.custom_minimum_size = Vector2(168, 0)
	add_child(p)
	var v := UIKit.vbox(1)
	p.add_child(v)
	obj_title = UIKit.header("", 10)
	obj_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_title.custom_minimum_size.x = 156
	v.add_child(obj_title)
	obj_text = UIKit.rich("", 156, 9)
	v.add_child(obj_text)


func refresh_objective(b: Battle) -> void:
	obj_title.text = b.mission.get("title", "Battle")
	var t := "[color=#f6cc60]>[/color] %s" % b.objective_text()
	if b.objective.get("type", "") in ["survive", "defense"]:
		t += "  [color=#aa9c8c](round %d)[/color]" % b.round_num
	for bo in b.bonus:
		var mark := "[color=#8cd678]v[/color]" if bo.get("done", false) else "[color=#aa9c8c]o[/color]"
		t += "\n%s [color=#aa9c8c]%s[/color]" % [mark, bo["desc"]]
	var has_ext := false
	for c in b.grid.all_cells():
		if b.grid.t(c)["extract"]:
			has_ext = true
			break
	if has_ext:
		t += "\n[color=#78c878]Extraction[/color] [color=#aa9c8c]zone: step on it and Extract to leave.[/color]"
	obj_text.text = t
	round_label.text = "Round %d" % b.round_num


# ------------------------------------------------------------------ unit panel
func _build_unit_panel() -> void:
	unit_panel = UIKit.panel()
	unit_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_panel.position = Vector2(4, -4)
	unit_panel.custom_minimum_size = Vector2(176, 0)
	add_child(unit_panel)


func refresh_unit(u: BattleUnit) -> void:
	UIKit.clear(unit_panel)
	if u == null:
		unit_panel.visible = false
		return
	unit_panel.visible = true
	var h := UIKit.hbox(4)
	unit_panel.add_child(h)
	var por_frame := PanelContainer.new()
	por_frame.add_theme_stylebox_override("panel", UITheme.tex_box("res://assets/sprites/ui/frame_gold.png", 4, Vector4(3, 3, 3, 3)))
	var por := _portrait(u)
	por.custom_minimum_size = Vector2(32, 32)
	if por.texture is AtlasTexture:
		por.texture = (por.texture as AtlasTexture).atlas
	por_frame.add_child(por)
	h.add_child(por_frame)
	var v := UIKit.vbox(1)
	h.add_child(v)
	var nm := UIKit.header(u.name, 10, UITheme.TEXT)
	v.add_child(nm)
	var sub := ""
	if u.member:
		sub = "Lv %d %s" % [u.member.level, u.member.class_name_full()]
	elif u.echo:
		sub = "Echo of the fallen"
	elif u.boss:
		sub = "Boss"
	elif u.elite:
		sub = "Elite · Lv %d" % u.level
	else:
		sub = "Lv %d" % u.level
	v.add_child(UIKit.label(sub, 9, UITheme.TEXT_DIM))
	var hp_row := UIKit.hbox(2)
	hp_row.add_child(UIKit.tex_rect(UIKit.small_tex("hp")))
	hp_row.add_child(UIKit.bar(u.hp, u.max_hp(), Color8(214, 72, 64) if u.team != 0 else Color8(110, 200, 100), 70, 6))
	hp_row.add_child(UIKit.label("%d/%d" % [u.hp, u.max_hp()], 9))
	v.add_child(hp_row)
	var def_row := UIKit.hbox(2)
	def_row.add_child(UIKit.tex_rect(UIKit.small_tex("defense")))
	def_row.add_child(UIKit.bar(u.defense_now(), maxf(u.max_def(), 1), Color8(110, 150, 220), 70, 4))
	def_row.add_child(UIKit.label("%d/%d" % [roundi(u.defense_now()), roundi(u.max_def())], 9))
	v.add_child(def_row)
	var stats := UIKit.hbox(5)
	for pair in [["accuracy", "accuracy"], ["dodge", "dodge"], ["crit", "crit"], ["move", "move"], ["speed", "speed"]]:
		stats.add_child(UIKit.stat_row(pair[0], str(roundi(u.stat(pair[1]))), UITheme.TEXT, DB.STAT_NAMES[pair[1]]))
	v.add_child(stats)
	if not u.statuses.is_empty():
		var sh := UIKit.hbox(2)
		for s in u.statuses:
			var sd: Dictionary = DB.statuses.get(s["id"], {})
			var ic := UIKit.tex_rect(UIKit.status_tex(s["id"]))
			ic.tooltip_text = "%s (%d): %s" % [sd.get("name", s["id"]), int(s["dur"]), sd.get("desc", "")]
			sh.add_child(ic)
			sh.add_child(UIKit.label(sd.get("name", s["id"]), 8, DB.color_of(sd.get("color", [200, 200, 200]))))
		v.add_child(sh)


# ------------------------------------------------------------------ actions
func _build_actions() -> void:
	var p := UIKit.panel("panel", Vector4(4, 3, 4, 3))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.position.y = -4
	add_child(p)
	var v := UIKit.vbox(2)
	p.add_child(v)
	action_hint = UIKit.label("", 9, UITheme.TEXT_DIM)
	action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(action_hint)
	action_box = UIKit.hbox(2)
	v.add_child(action_box)
	p.resized.connect(func(): p.position.x = (size.x - p.size.x) / 2.0)


func refresh_actions(b: Battle, u: BattleUnit, mode: String, selected: String) -> void:
	UIKit.clear(action_box)
	var p: Control = action_box.get_parent().get_parent()
	if u == null or u.team != BattleUnit.TEAM_PLAYER or not u.active() or u.objective_role == "ally":
		p.visible = false
		return
	p.visible = true
	var key := 1
	for s in u.skills:
		var sd := DB.skill(s)
		var can := b.can_use(u, s)
		var btn := _action_button(UIKit.skill_icon(s), "%s%s\n%s%s" % [sd.get("name", s), "  [%d]" % key,
			sd.get("desc", ""), ("\nCooldown %d" % int(sd.get("cd", 0))) if int(sd.get("cd", 0)) > 0 else ""],
			func(): action_pressed.emit("skill", s), can, selected == s, u.cooldown(s) if s not in u.erased else -1)
		action_box.add_child(btn)
		key += 1
	for e in u.erased:
		pass
	action_box.add_child(UIKit.spacer(4, 1))
	action_box.add_child(_action_button(UIKit.icon_tex("defend"), "Defend  [F]\n+20 Dodge and a better chance of critical defense until your next turn. Ends the turn.",
		func(): action_pressed.emit("defend", ""), not u.acted))
	action_box.add_child(_action_button(UIKit.icon_tex("overwatch"), "Overwatch  [V]\nAttack the first enemy that moves within range (-10 hit). Ends the turn.",
		func(): action_pressed.emit("overwatch", ""), not u.acted and not u.npc and not u.basic.is_empty()))
	action_box.add_child(_action_button(UIKit.icon_tex("wait"), "Wait  [T]\nAct later in the timeline.",
		func(): action_pressed.emit("wait", ""), not u.moved and not u.acted))
	# contextual
	for o in b.allies_of(u, false, false):
		if b.can_stabilize(u, o):
			action_box.add_child(_action_button(UIKit.icon_tex("stabilize"), "Stabilize %s  [G]\nStop an adjacent Downed ally from bleeding out." % o.name,
				func(): action_pressed.emit("stabilize", str(o.uid)), true))
			break
	for o in b.units:
		if b.can_carry(u, o):
			action_box.add_child(_action_button(UIKit.icon_tex("carry"), "Carry %s  [C]\nPick up a fallen ally (-2 Movement). Bring them to the extraction zone to save them or their gear." % o.name,
				func(): action_pressed.emit("carry", str(o.uid)), true))
			break
	var it := b.interact_targets(u)
	if not it.is_empty():
		var kind: String = b.grid.t(it[0])["obj"].get("kind", "")
		var label: String = {"cache": "Recover cache", "chest": "Open chest", "page": "Take ledger page", "captive": "Free captive"}.get(kind, "Interact")
		action_box.add_child(_action_button(UIKit.icon_tex("interact"), "%s  [R]" % label, func(): action_pressed.emit("interact", ""), true))
	if b.can_extract(u):
		action_box.add_child(_action_button(UIKit.icon_tex("extract"), "Extract  [X]\nLeave the battlefield. Members who extract survive even if the mission fails.",
			func(): action_pressed.emit("extract", ""), true))
	action_box.add_child(UIKit.spacer(4, 1))
	var end := UIKit.button("End Turn", func(): action_pressed.emit("end", ""), "btn_green" if false else "", 0)
	end.tooltip_text = "End this unit's turn  [Space]"
	action_box.add_child(end)
	var moved := "Moved" if u.moved else "Move: %d" % b.move_budget(u)
	var acted := "Acted" if u.acted else "Action ready"
	if mode == "target" and selected != "":
		action_hint.text = "%s: choose a target · Right-click to cancel" % DB.skill(selected).get("name", selected)
	else:
		action_hint.text = "%s · %s · %s" % [u.name, moved, acted]


func _action_button(tex: Texture2D, tip: String, cb: Callable, enabled: bool, selected := false, cooldown := 0) -> Control:
	var frame := PanelContainer.new()
	var col := Color8(246, 204, 96) if selected else Color8(20, 14, 22)
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color8(20, 14, 22), col, 1, 1))
	var b := UIKit.icon_button(tex, cb, tip, 18)
	b.disabled = not enabled
	if not enabled:
		b.modulate = Color(0.45, 0.42, 0.45)
	frame.add_child(b)
	if cooldown != 0:
		var l := UIKit.label(str(cooldown) if cooldown > 0 else "X", 9, UITheme.GOLD if cooldown > 0 else UITheme.RED, UITheme.number_font)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(l)
		if cooldown < 0:
			b.tooltip_text += "\n[Erased by the Hush]"
	return frame


# ------------------------------------------------------------------ log
func _build_log() -> void:
	log_box = UIKit.vbox(0)
	log_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	log_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.position = Vector2(-164, -6)
	log_box.custom_minimum_size.x = 160
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_box)


func log_line(text: String, color := UITheme.TEXT_DIM) -> void:
	_log_lines.append([text, color])
	if _log_lines.size() > 6:
		_log_lines.pop_front()
	UIKit.clear(log_box)
	for i in _log_lines.size():
		var l := UIKit.label(_log_lines[i][0], 8, _log_lines[i][1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size.x = 160
		l.modulate.a = 0.45 + 0.55 * float(i + 1) / _log_lines.size()
		log_box.add_child(l)


# ------------------------------------------------------------------ previews
func _build_preview() -> void:
	preview = UIKit.panel("tooltip", Vector4(5, 4, 5, 4))
	preview.visible = false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	preview_body = UIKit.vbox(1)
	preview.add_child(preview_body)
	info = UIKit.panel("panel", Vector4(5, 4, 5, 4))
	info.visible = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	info_body = UIKit.vbox(1)
	info.add_child(info_body)


func show_preview(pv: Dictionary, at: Vector2) -> void:
	UIKit.clear(preview_body)
	if pv.is_empty() or pv.get("targets", []).is_empty():
		preview.visible = false
		return
	var sd := DB.skill(pv["skill"])
	preview_body.add_child(UIKit.header(sd.get("name", ""), 10))
	for row in pv["targets"]:
		var b := UIKit.vbox(0)
		var line := "[b]%s[/b]" % row["name"]
		if row.has("hit"):
			var hc: int = row["hit"]
			var col := "#8cd678" if hc >= 70 else ("#f6cc60" if hc >= 40 else "#e86050")
			line += "   [color=%s][b]%d%%[/b][/color] hit   [color=#f6cc60]%d%%[/color] crit" % [col, hc, row["crit"]]
			line += "\n[color=#e8e0cc]Damage %d-%d[/color]" % [row["dmg_min"], row["dmg_max"]]
			if int(row.get("hits", 1)) > 1:
				line += " x%d" % int(row["hits"])
			var mods: Array = []
			if row.get("ranged", false):
				if int(row["cover"]) == 1:
					mods.append("[color=#82b0f0]Half cover -20[/color]")
				elif int(row["cover"]) == 2:
					mods.append("[color=#82b0f0]Full cover -40[/color]")
			if row.get("flank", false):
				mods.append("[color=#f6cc60]Flanking +15[/color]")
			if row.get("high", false):
				mods.append("[color=#8cd678]High ground +10[/color]")
			if int(row.get("beyond", 0)) > 0:
				mods.append("[color=#e86050]Range -%d[/color]" % (10 * int(row["beyond"])))
			if not mods.is_empty():
				line += "\n" + "  ".join(mods)
		if row.has("heal"):
			line += "   [color=#8cd678]Heal %d[/color]" % int(row["heal"])
		if row.has("statuses"):
			for st in row["statuses"]:
				var sd2: Dictionary = DB.statuses.get(st[0], {})
				line += "\n[color=#c896ec]%s[/color] %d%%" % [sd2.get("name", st[0]), st[1]]
		b.add_child(UIKit.rich(line, 170, 9))
		preview_body.add_child(b)
	preview.visible = true
	preview.reset_size()
	var pos := at + Vector2(14, -preview.size.y / 2.0)
	pos.x = minf(pos.x, size.x - preview.size.x - 4)
	pos.y = clampf(pos.y, 30, size.y - preview.size.y - 40)
	preview.position = pos


func hide_preview() -> void:
	preview.visible = false


func show_info(u: BattleUnit, at: Vector2, b: Battle) -> void:
	UIKit.clear(info_body)
	if u == null:
		info.visible = false
		return
	info_body.add_child(UIKit.header(u.name, 10, UITheme.RED if u.team == BattleUnit.TEAM_ENEMY else UITheme.BLUE))
	var t := "HP %d/%d   Def %d   Dodge %d   Acc %d" % [u.hp, u.max_hp(), roundi(u.defense_now()), roundi(u.stat("dodge")), roundi(u.stat("accuracy"))]
	t += "\nMove %d   Range %d   Speed %d   Resolve %d" % [roundi(u.stat("move")), roundi(u.stat("range")), roundi(u.stat("speed")), roundi(u.stat("resolve"))]
	info_body.add_child(UIKit.label(t, 8, UITheme.TEXT))
	if u.team == BattleUnit.TEAM_ENEMY:
		var names: Array = []
		for s in u.skills:
			names.append(DB.skill(s).get("name", s))
		info_body.add_child(UIKit.label("Skills: " + ", ".join(names), 8, UITheme.TEXT_DIM))
		var cov := b.grid.cover_dirs(u.pos)
		if not cov.is_empty():
			info_body.add_child(UIKit.label("In cover", 8, UITheme.BLUE))
	if u.state == "downed":
		info_body.add_child(UIKit.label("Downed: %s" % ("stabilized" if u.stabilized else "bleeds out in %d turns" % u.bleed), 8, UITheme.RED))
	for s in u.statuses:
		var sd: Dictionary = DB.statuses.get(s["id"], {})
		info_body.add_child(UIKit.label("%s (%d) %s" % [sd.get("name", s["id"]), int(s["dur"]), sd.get("desc", "")], 8, DB.color_of(sd.get("color", [200, 200, 200]))))
	info.visible = true
	info.reset_size()
	var pos := at + Vector2(14, 10)
	pos.x = minf(pos.x, size.x - info.size.x - 4)
	pos.y = minf(pos.y, size.y - info.size.y - 50)
	info.position = pos


func hide_info() -> void:
	info.visible = false


# ------------------------------------------------------------------ floating text & bars
func float_text(world_pos: Vector3, text: String, color: Color, big := false) -> void:
	var l := UIKit.label(text, 16 if big else 10, color, UITheme.number_font if text.is_valid_int() or big else UITheme.pixel_font)
	l.add_theme_color_override("font_outline_color", Color8(24, 14, 22))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	float_layer.add_child(l)
	l.reset_size()
	var p: Vector2 = scene.wv.world_to_screen(world_pos)
	# stack texts that pop at the same spot within a moment of each other
	var now := Time.get_ticks_msec()
	var stack := 0
	for c in float_layer.get_children():
		if c != l and c is Label and c.has_meta("born") and now - int(c.get_meta("born")) < 450 and (c.get_meta("anchor") as Vector2).distance_to(p) < 24:
			stack += 1
	l.set_meta("born", now)
	l.set_meta("anchor", p)
	l.position = p - Vector2(l.size.x / 2.0, l.size.y + stack * 11) + Vector2(randf_range(-4, 4), 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 22, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if big:
		l.scale = Vector2(1.4, 1.4)
		l.pivot_offset = l.size / 2.0
		tw.tween_property(l, "scale", Vector2.ONE, 0.25)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)


func bark(world_pos: Vector3, text: String, color := UITheme.TEXT) -> void:
	var p := UIKit.panel("parchment", Vector4(4, 2, 4, 3))
	var l := UIKit.label(text, 9, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = mini(160, 8 + text.length() * 4)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_layer.add_child(p)
	p.reset_size()
	var sp: Vector2 = scene.wv.world_to_screen(world_pos)
	p.position = sp - Vector2(p.size.x / 2.0, p.size.y + 6)
	p.position.x = clampf(p.position.x, 4, size.x - p.size.x - 4)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6 + text.length() * 0.035)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


func update_bars(b: Battle, views: Dictionary) -> void:
	for uid in views:
		var u: BattleUnit = b.unit(uid)
		var uv: UnitView = views[uid]
		var show: bool = u != null and (u.state == "active" or u.state == "downed") and u.carried_by < 0 and not u.hidden and uv.visible
		if not show:
			if bars.has(uid):
				bars[uid].queue_free()
				bars.erase(uid)
			continue
		if not bars.has(uid):
			var c := Control.new()
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bars_layer.add_child(c)
			bars[uid] = c
		var holder: Control = bars[uid]
		var key := "%d/%d/%d/%d/%s/%d" % [u.hp, u.max_hp(), roundi(u.defense_now()), roundi(u.max_def()), u.state, u.statuses.size()]
		if holder.get_meta("key", "") != key:
			holder.set_meta("key", key)
			UIKit.clear(holder)
			var w := 22 if not (u.elite or u.boss) else 34
			var col := Color8(110, 200, 100) if u.team == BattleUnit.TEAM_PLAYER else Color8(214, 72, 64)
			if u.npc:
				col = Color8(120, 200, 200)
			var hb := UIKit.bar(u.hp, u.max_hp(), col, w, 4)
			holder.add_child(hb)
			if u.max_def() > 0:
				var db := UIKit.bar(u.defense_now(), u.max_def(), Color8(120, 160, 230), w, 3)
				db.position = Vector2(0, 4)
				holder.add_child(db)
			var x := 0
			for s in u.statuses:
				if s["id"] in ["overwatch", "defending"] or x > 3:
					continue
				var ic := UIKit.tex_rect(UIKit.status_tex(s["id"]))
				ic.position = Vector2(x * 8, -9)
				holder.add_child(ic)
				x += 1
			if u.state == "downed":
				var dl := UIKit.label("DOWNED %d" % u.bleed if not u.stabilized else "STABLE", 8, UITheme.RED if not u.stabilized else UITheme.GOLD, UITheme.pixel_font)
				dl.position = Vector2(-4, -12)
				holder.add_child(dl)
			holder.set_meta("w", w)
		var top: Vector3 = uv.global_position + Vector3(0, 0, 0)
		var sp: Vector2 = scene.wv.world_to_screen(top)
		var px: float = scene.wv.pixel_scale()
		var h_px: float = (float(uv.meta.get("anchor", [32, 50])[1]) - (uv.canvas * 0.2 if uv.canvas <= 64 else uv.canvas * 0.35)) if not uv.meta.is_empty() else 40.0
		if u.state == "downed":
			h_px = 14
		holder.position = sp - Vector2(float(holder.get_meta("w", 22)) / 2.0, h_px * px + 4)


# ------------------------------------------------------------------ banner
func _build_banner() -> void:
	banner = UIKit.title("", 36)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	sub_banner = UIKit.header("", 12, UITheme.TEXT)
	sub_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub_banner.position.y += 28
	sub_banner.modulate.a = 0.0
	sub_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_banner)


func show_banner(text: String, sub := "", color := UITheme.GOLD, hold := 1.2) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	sub_banner.text = sub
	banner.reset_size()
	sub_banner.reset_size()
	banner.position.x = (size.x - banner.size.x) / 2.0
	sub_banner.position.x = (size.x - sub_banner.size.x) / 2.0
	banner.position.y = size.y * 0.32
	sub_banner.position.y = banner.position.y + banner.size.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(sub_banner, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(hold)
	tw.chain().set_parallel(true)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.tween_property(sub_banner, "modulate:a", 0.0, 0.4)
