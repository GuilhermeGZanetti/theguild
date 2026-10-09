class_name UIKit
extends RefCounted
## Small helpers to build pixel UI in code.

static var _icons := {}
static var _atlas: Dictionary = {}


static func _index() -> Dictionary:
	if _atlas.is_empty():
		_atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/ui/icons.json"))
	return _atlas


static func icon_tex(name: String) -> Texture2D:
	var key := "i:" + name
	if _icons.has(key):
		return _icons[key]
	var names: Array = _index()["icons"]
	var i := names.find(name)
	if i < 0:
		i = names.find("sword")
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/ui/icons.png")
	at.region = Rect2(i * 16, 0, 16, 16)
	_icons[key] = at
	return at


static func small_tex(name: String) -> Texture2D:
	var key := "s:" + name
	if _icons.has(key):
		return _icons[key]
	var names: Array = _index()["small"]
	var i := maxi(0, names.find(name))
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/ui/small_icons.png")
	at.region = Rect2(i * 10, 0, 10, 10)
	_icons[key] = at
	return at


static func status_tex(name: String) -> Texture2D:
	var key := "st:" + name
	if _icons.has(key):
		return _icons[key]
	var names: Array = _index()["status"]
	var i := maxi(0, names.find(name))
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/ui/status_icons.png")
	at.region = Rect2(i * 8, 0, 8, 8)
	_icons[key] = at
	return at


static func skill_icon(skill_id: String) -> Texture2D:
	return icon_tex(DB.skill(skill_id).get("icon", "sword"))


static func label(text: String, size := 10, color := UITheme.TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 24, color := UITheme.GOLD) -> Label:
	UITheme.fonts()
	var l := label(text, size, color, UITheme.title_font)
	l.add_theme_color_override("font_shadow_color", Color8(30, 16, 20))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_offset_x", 0)
	return l


static func header(text: String, size := 12, color := UITheme.GOLD) -> Label:
	UITheme.fonts()
	return label(text, size, color, UITheme.pixel_font)


static func rich(bbcode: String, width := 0.0, size := 10) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	if width > 0:
		r.custom_minimum_size.x = width
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func button(text: String, cb: Callable, style := "", min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	set_style(b, style)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func():
		Audio.sfx("ui_click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Audio.sfx("ui_hover", 0.05, -14.0))
	return b


## Skins a button with one of the btn_* textures ("" = the theme's default).
static func set_style(b: Button, style: String) -> void:
	style = style.trim_prefix("btn_")
	for state in ["normal", "hover", "pressed", "disabled"]:
		if style == "":
			b.remove_theme_stylebox_override(state)
		else:
			b.add_theme_stylebox_override(state, UITheme.tex_box("res://assets/sprites/ui/btn_%s_%s.png" % [style, state], 3, Vector4(6, 2, 6, 3)))


static func icon_button(tex: Texture2D, cb: Callable, tip := "", size := 18) -> Button:
	var b := Button.new()
	b.icon = tex
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = tip
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for s in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.pressed.connect(func():
		Audio.sfx("ui_click", 0.05, -4.0)
		cb.call())
	return b


static func tex_rect(tex: Texture2D, scale := 1.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if tex:
		r.custom_minimum_size = tex.get_size() * scale
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func panel(style := "panel", margin := Vector4(6, 5, 6, 5)) -> PanelContainer:
	var p := PanelContainer.new()
	if style != "panel":
		p.add_theme_stylebox_override("panel", UITheme.tex_box("res://assets/sprites/ui/%s.png" % style, 4, margin))
	return p


## Toggle-style list row: gold outline when selected, dimmed otherwise.
static func list_row(b: Button, selected: bool) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if selected:
		var sb := UITheme.flat(Color8(96, 66, 48), UITheme.GOLD, 1, 2)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
	b.mouse_entered.connect(func(): Audio.sfx("ui_hover", 0.05, -16.0))


static func vbox(sep := 3) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 3) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(w := 0, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0 and h == 0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func stat_row(icon_name: String, text: String, color := UITheme.TEXT, tip := "") -> HBoxContainer:
	var h := hbox(2)
	h.add_child(tex_rect(small_tex(icon_name)))
	var l := label(text, 9, color)
	h.add_child(l)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func portrait(variant: String, palette: Dictionary, bandaged := false, grey := 0.0) -> TextureRect:
	## Index portrait recoloured through the unit palette via a CanvasItem shader.
	variant = Member.fix_variant(variant)
	if not ResourceLoader.exists("res://assets/sprites/units/%s_portrait.png" % variant):
		variant = "human_warrior_m_a"
	var path := "res://assets/sprites/units/%s_portrait%s.png" % [variant, "_b" if bandaged else ""]
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/units/%s_portrait.png" % variant
	var r := TextureRect.new()
	r.texture = load(path)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size = Vector2(32, 32)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/portrait.gdshader")
	m.set_shader_parameter("palette", UnitPalette.build(palette))
	m.set_shader_parameter("grey", grey)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func bar(value: float, max_v: float, color: Color, w := 40, h := 4, back := Color8(30, 20, 28)) -> Control:
	var c := ColorRect.new()
	c.color = Color8(16, 10, 18)
	c.custom_minimum_size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = back
	bg.position = Vector2(1, 1)
	bg.size = Vector2(w - 2, h - 2)
	c.add_child(bg)
	var f := ColorRect.new()
	f.color = color
	f.position = Vector2(1, 1)
	f.size = Vector2(maxf(0, (w - 2) * clampf(value / maxf(max_v, 1), 0, 1)), h - 2)
	c.add_child(f)
	var hl := ColorRect.new()
	hl.color = color.lightened(0.35)
	hl.position = Vector2(1, 1)
	hl.size = Vector2(f.size.x, 1)
	c.add_child(hl)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


static func skulls(n: int) -> HBoxContainer:
	var h := hbox(0)
	for i in n:
		h.add_child(tex_rect(load("res://assets/sprites/ui/skull.png")))
	return h


static func stars(n: int) -> String:
	return "*".repeat(n)
