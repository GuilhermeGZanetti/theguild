class_name UITheme
extends RefCounted
## Builds the pixel-art UI theme at runtime from the generated textures.

const TEXT := Color8(238, 228, 206)
const TEXT_DIM := Color8(170, 156, 140)
const GOLD := Color8(246, 204, 96)
const RED := Color8(232, 96, 80)
const GREEN := Color8(140, 214, 120)
const BLUE := Color8(130, 176, 240)
const PURPLE := Color8(190, 150, 236)
const INK := Color8(58, 40, 32)

static var body_font: Font
static var bold_font: Font
static var italic_font: Font
static var pixel_font: Font
static var title_font: Font
static var number_font: Font
static var _theme: Theme


static func fonts() -> void:
	if body_font:
		return
	body_font = _font("res://assets/fonts/AlegreyaSans-Regular.ttf", false)
	bold_font = _font("res://assets/fonts/AlegreyaSans-Bold.ttf", false)
	italic_font = _font("res://assets/fonts/AlegreyaSans-Italic.ttf", false)
	pixel_font = _font("res://assets/fonts/PixelifySans.ttf", true)
	title_font = _font("res://assets/fonts/Jacquard12-Regular.ttf", true)
	number_font = _font("res://assets/fonts/Jersey10-Regular.ttf", true)


static func _font(path: String, pixel: bool) -> Font:
	var f: FontFile = load(path)
	if f == null:
		return ThemeDB.fallback_font
	if pixel:
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	else:
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
	f.oversampling = 0.0
	return f


static func tex_box(path: String, margin: int, content := Vector4(4, 3, 4, 3)) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	# tile the centre so the pixel texture keeps its density instead of smearing
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb


static func flat(c: Color, border := Color(0, 0, 0, 0), bw := 0, margins := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(margins)
	sb.anti_aliasing = false
	return sb


static func build() -> Theme:
	if _theme:
		return _theme
	fonts()
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 10
	var ui := "res://assets/sprites/ui/"
	# panels
	t.set_stylebox("panel", "PanelContainer", tex_box(ui + "panel.png", 4, Vector4(6, 5, 6, 5)))
	t.set_stylebox("panel", "Panel", tex_box(ui + "panel.png", 4))
	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0.05, 0.03, 0.07, 0.6))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("line_spacing", "Label", -1)
	# rich text
	t.set_font("normal_font", "RichTextLabel", body_font)
	t.set_font("bold_font", "RichTextLabel", bold_font)
	t.set_font("italics_font", "RichTextLabel", italic_font)
	t.set_font_size("normal_font_size", "RichTextLabel", 10)
	t.set_font_size("bold_font_size", "RichTextLabel", 10)
	t.set_font_size("italics_font_size", "RichTextLabel", 10)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", -1)
	# buttons
	for pair in [["normal", "btn_normal"], ["hover", "btn_hover"], ["pressed", "btn_pressed"], ["disabled", "btn_disabled"], ["focus", "btn_hover"]]:
		var sb: StyleBox = tex_box(ui + pair[1] + ".png", 3, Vector4(6, 2, 6, 3))
		if pair[0] == "focus":
			sb = StyleBoxEmpty.new()
		t.set_stylebox(pair[0], "Button", sb)
	t.set_font("font", "Button", pixel_font)
	t.set_font_size("font_size", "Button", 10)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color8(255, 244, 214))
	t.set_color("font_pressed_color", "Button", Color8(220, 206, 180))
	t.set_color("font_disabled_color", "Button", Color8(130, 122, 116))
	t.set_color("font_outline_color", "Button", Color8(30, 20, 26))
	t.set_constant("outline_size", "Button", 0)
	t.set_constant("h_separation", "Button", 3)
	# line edit
	t.set_stylebox("normal", "LineEdit", tex_box(ui + "panel_inset.png", 3, Vector4(4, 3, 4, 3)))
	t.set_stylebox("focus", "LineEdit", tex_box(ui + "panel_inset.png", 3, Vector4(4, 3, 4, 3)))
	t.set_font("font", "LineEdit", pixel_font)
	t.set_font_size("font_size", "LineEdit", 12)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD)
	# tooltips
	t.set_stylebox("panel", "TooltipPanel", tex_box(ui + "tooltip.png", 4, Vector4(5, 4, 5, 4)))
	t.set_font("font", "TooltipLabel", body_font)
	t.set_font_size("font_size", "TooltipLabel", 9)
	t.set_color("font_color", "TooltipLabel", TEXT)
	# scrollbars
	var track := flat(Color8(28, 20, 30), Color(0, 0, 0, 0), 0, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := flat(Color8(120, 96, 90), Color8(30, 20, 26), 1, 0)
	var grab_h := flat(Color8(160, 128, 110), Color8(30, 20, 26), 1, 0)
	for sbn in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbn, track)
		t.set_stylebox("grabber", sbn, grab)
		t.set_stylebox("grabber_highlight", sbn, grab_h)
		t.set_stylebox("grabber_pressed", sbn, grab_h)
	# sliders
	t.set_stylebox("slider", "HSlider", flat(Color8(28, 20, 30), Color8(12, 8, 14), 1, 2))
	t.set_stylebox("grabber_area", "HSlider", flat(Color8(180, 130, 70), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(Color8(220, 170, 90), Color(0, 0, 0, 0), 0, 2))
	# check boxes
	t.set_font("font", "CheckBox", pixel_font)
	t.set_font_size("font_size", "CheckBox", 10)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font("font", "CheckButton", pixel_font)
	t.set_font_size("font_size", "CheckButton", 10)
	# separators
	t.set_stylebox("separator", "HSeparator", flat(Color8(86, 70, 82)))
	t.set_constant("separation", "HSeparator", 4)
	t.set_constant("separation", "VBoxContainer", 3)
	t.set_constant("separation", "HBoxContainer", 3)
	# option button / popup
	t.set_stylebox("panel", "PopupMenu", tex_box(ui + "panel.png", 4, Vector4(4, 4, 4, 4)))
	t.set_font("font", "PopupMenu", pixel_font)
	t.set_font_size("font_size", "PopupMenu", 10)
	_theme = t
	return t
