class_name GuildScreen
extends Control
## Base for the management windows opened from the guild hub. Subclasses
## fill `body` in build() and call rebuild() after changing the campaign.

var hub  # GuildHub
var params := {}
var campaign: Campaign
var body: MarginContainer
var frame: PanelContainer
var header_box: HBoxContainer


func _ready() -> void:
	campaign = hub.campaign
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_top = 22
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	frame = UIKit.panel()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 8
	frame.offset_right = -8
	frame.offset_top = 3
	frame.offset_bottom = -3
	add_child(frame)
	var v := UIKit.vbox(3)
	frame.add_child(v)
	header_box = UIKit.hbox(6)
	v.add_child(header_box)
	header_box.add_child(UIKit.title(screen_title(), 16))
	var sub := subtitle()
	if sub != "":
		var l := UIKit.label(sub, 9, UITheme.TEXT_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_END
		header_box.add_child(l)
	header_box.add_child(UIKit.spacer())
	header_extra(header_box)
	header_box.add_child(UIKit.button("Close", func(): hub.close_screen(), "", 50))
	var sep := HSeparator.new()
	v.add_child(sep)
	body = MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	build()


func screen_title() -> String:
	return ""


func subtitle() -> String:
	return ""


func header_extra(_box: HBoxContainer) -> void:
	pass


func build() -> void:
	pass


func rebuild() -> void:
	UIKit.clear(body)
	build()


## Apply a campaign action that returns an error string ("" = success).
func act(err: String, ok_text := "", rebuild_tavern := false) -> bool:
	if err != "":
		Audio.sfx("miss", 0.05, -4.0)
		hub.toast(err, UITheme.RED)
		return false
	if ok_text != "":
		hub.toast(ok_text, UITheme.GOLD)
	Audio.sfx("loot", 0.08, -4.0)
	hub.changed(rebuild_tavern)
	rebuild()
	return true


static func scroll(content: Control, min_h := 0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_h > 0:
		s.custom_minimum_size.y = min_h
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func inset(content: Control, style := "panel_inset") -> PanelContainer:
	var p := UIKit.panel(style, Vector4(4, 3, 4, 3))
	p.add_child(content)
	return p


static func hex(c: Color) -> String:
	return c.to_html(false)
