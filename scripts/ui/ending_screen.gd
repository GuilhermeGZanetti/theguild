extends Control
## The end of a campaign: the ending text for the faction that shaped the
## realm (or the way the guild fell), then the guild's final ledger.

var campaign: Campaign
var pages: Array = []
var index := 0
var text_label: RichTextLabel
var title_label: Label
var stage := "pages"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	campaign = Game.campaign
	if campaign == null:
		Scenes.go("res://scenes/title.tscn")
		return
	var victory := campaign.game_over == "victory"
	var data: Dictionary
	if victory:
		data = DB.story["endings"].get(campaign.ending, DB.story["endings"]["none"])
	else:
		data = DB.story["defeat"].get(campaign.game_over, DB.story["defeat"]["hush"])
	pages = data.get("text", [])
	var bg := ColorRect.new()
	bg.color = Color8(16, 12, 20) if victory else Color8(12, 12, 14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vs := get_viewport_rect().size
	title_label = UIKit.title(data.get("title", "The End"), 36, UITheme.GOLD if victory else Color8(180, 180, 190))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size = Vector2(vs.x, 40)
	title_label.position = Vector2(0, 40)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)
	text_label = UIKit.rich("", 420, 11)
	text_label.position = Vector2((vs.x - 420) / 2.0, 120)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	Audio.play_music("final" if victory else "menu")
	if not victory:
		Audio.sfx("bell_far", 0.0, 0.0)
	_show_page()


func _show_page() -> void:
	if index >= pages.size():
		_summary()
		return
	text_label.text = "[center]%s[/center]" % pages[index]
	text_label.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(text_label, "visible_ratio", 1.0, clampf(String(pages[index]).length() * 0.025, 0.8, 4.0))


func _gui_input(event: InputEvent) -> void:
	if stage == "pages" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if text_label.visible_ratio < 1.0:
			text_label.visible_ratio = 1.0
			return
		index += 1
		Audio.sfx("page", 0.1, -6.0)
		_show_page()


func _summary() -> void:
	stage = "summary"
	text_label.visible = false
	var vs := get_viewport_rect().size
	var p := UIKit.panel("parchment", Vector4(16, 12, 16, 12))
	p.custom_minimum_size.x = 400
	add_child(p)
	var v := UIKit.vbox(4)
	p.add_child(v)
	var ink := UITheme.INK
	var t := UIKit.title(campaign.guild_name, 22, Color8(110, 50, 36))
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s: Dictionary = campaign.stats
	var lines: Array = [
		"%d weeks · %d missions, %d won · %d enemies slain" % [campaign.week, int(s["missions"]), int(s["victories"]), int(s["kills"])],
		"Renown %d (%s) · the Hush stood at %d" % [campaign.renown, Rules.rank_name(campaign.rank()), campaign.hush],
	]
	if campaign.game_over == "victory":
		lines.append("[i]Her name was %s.[/i]" % DB.story.get("unnamed_name", "Maren Ashgrove"))
	var names: Array = []
	for d in campaign.dead:
		names.append(d.get("name", "?") + ("" if d.get("memorial", false) else "*"))
	if not names.is_empty():
		lines.append("\n[b]The fallen[/b]\n" + ", ".join(names))
		lines.append("[color=#%s](* never carved into the Memorial)[/color]" % Color8(120, 90, 70).to_html(false))
	var survivors: Array = []
	for m in campaign.roster:
		survivors.append("%s (Lv %d %s)" % [m.name, m.level, m.class_name_full()])
	if not survivors.is_empty():
		lines.append("\n[b]Still standing[/b]\n" + ", ".join(survivors))
	var r := UIKit.rich("[center][color=#%s]%s[/color][/center]" % [ink.to_html(false), "\n".join(lines)], 368, 9)
	v.add_child(r)
	var h := UIKit.hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UIKit.button("Return to Title", func(): Scenes.go("res://scenes/title.tscn"), "btn_green", 130))
	v.add_child(h)
	await get_tree().process_frame
	p.reset_size()
	p.position = ((vs - p.size) / 2.0 + Vector2(0, 20)).floor()
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.6)
