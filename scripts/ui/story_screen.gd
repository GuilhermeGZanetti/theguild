extends Control
## Story pages on parchment: the prologue, mission outros and act titles.
## params: {"pages": [String | {title, text, big}], "next": scene path, "music": track}

var pages: Array = []
var index := -1
var next_scene := "res://scenes/guild.tscn"
var title_label: Label
var text_label: RichTextLabel
var page_panel: PanelContainer
var hint: Label
var typing: Tween
var motes: Array = []
var leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages = Scenes.params.get("pages", [])
	next_scene = Scenes.params.get("next", next_scene)
	if Scenes.params.has("music"):
		Audio.play_music(Scenes.params["music"])
	var bg := ColorRect.new()
	bg.color = Color8(18, 13, 22)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# drifting grey motes: the Hush at the edge of the page
	for i in 40:
		var m := ColorRect.new()
		m.size = Vector2(1, 1) * (1 + randi() % 2)
		m.color = Color(0.7, 0.7, 0.76, randf_range(0.08, 0.3))
		m.position = Vector2(randf() * 640, randf() * 360)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		motes.append([m, randf_range(3, 10), randf() * TAU])
	var vs := get_viewport_rect().size
	var em := UIKit.tex_rect(load("res://assets/sprites/ui/emblem_guild_32.png"))
	em.position = Vector2(vs.x / 2.0 - 16, 14)
	em.modulate = Color(1, 1, 1, 0.8)
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(em)
	page_panel = UIKit.panel("parchment", Vector4(18, 14, 18, 14))
	page_panel.custom_minimum_size = Vector2(380, 150)
	page_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_panel)
	var v := UIKit.vbox(6)
	page_panel.add_child(v)
	title_label = UIKit.title("", 20, Color8(110, 50, 36))
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	text_label = UIKit.rich("", 344, 11)
	text_label.add_theme_color_override("default_color", UITheme.INK)
	text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	v.add_child(text_label)
	hint = UIKit.label("Click to continue", 8, UITheme.TEXT_DIM, UITheme.pixel_font)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(vs.x, 12)
	hint.position = Vector2(0, vs.y - 18)
	add_child(hint)
	var skip := UIKit.button("Skip", _finish, "", 44)
	skip.position = Vector2(vs.x - 50, vs.y - 24)
	add_child(skip)
	if pages.is_empty():
		_finish()
		return
	_next()


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for m in motes:
		var r: ColorRect = m[0]
		r.position.y -= delta * float(m[1])
		r.position.x += sin(t * 0.7 + float(m[2])) * delta * 4.0
		if r.position.y < -2:
			r.position.y = 362
			r.position.x = randf() * 640
	hint.modulate.a = 0.5 + 0.5 * sin(t * 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish()


func _advance() -> void:
	if typing and typing.is_running():
		typing.kill()
		text_label.visible_ratio = 1.0
		return
	_next()


func _next() -> void:
	index += 1
	if index >= pages.size():
		_finish()
		return
	var p = pages[index]
	var title := ""
	var text := ""
	var big := false
	if p is String:
		text = p
	else:
		title = p.get("title", "")
		text = p.get("text", "")
		big = p.get("big", false)
	title_label.text = title
	title_label.visible = title != ""
	title_label.add_theme_font_size_override("font_size", 28 if big else 20)
	text_label.text = "[center]%s[/center]" % text
	text_label.visible_ratio = 0.0
	page_panel.reset_size()
	var vs := get_viewport_rect().size
	page_panel.position = ((vs - page_panel.size) / 2.0 + Vector2(0, 8)).floor()
	page_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(page_panel, "modulate:a", 1.0, 0.35)
	typing = create_tween()
	typing.tween_interval(0.25)
	typing.tween_property(text_label, "visible_ratio", 1.0, clampf(text.length() * 0.022, 0.6, 4.0))
	Audio.sfx("page", 0.1, -6.0)


func _finish() -> void:
	if leaving:
		return
	leaving = true
	Scenes.go(next_scene)
