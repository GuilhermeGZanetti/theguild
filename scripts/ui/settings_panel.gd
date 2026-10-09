class_name SettingsPanel
extends RefCounted
## Settings window shared by the title screen, the guild and battles.


static func open(parent: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	parent.add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := UIKit.panel()
	root.add_child(p)
	var v := UIKit.vbox(4)
	p.add_child(v)
	v.add_child(UIKit.title("Settings", 24))
	v.add_child(_slider("Master volume", Settings.master_volume, func(x): Settings.master_volume = x; Settings.apply()))
	v.add_child(_slider("Music", Settings.music_volume, func(x): Settings.music_volume = x; Settings.apply()))
	v.add_child(_slider("Sound effects", Settings.sfx_volume, func(x):
		Settings.sfx_volume = x
		Settings.apply()
		Audio.sfx("ui_click")))
	var sp := HBoxContainer.new()
	sp.add_child(UIKit.label("Combat speed", 10))
	sp.add_child(UIKit.spacer())
	var speeds := [1.0, 1.5, 2.0]
	var speed_btns: Array = []
	var mark_speed := func():
		for i in speed_btns.size():
			UIKit.set_style(speed_btns[i], "btn_green" if is_equal_approx(Settings.combat_speed, speeds[i]) else "")
	for s in speeds:
		var b := UIKit.button("x%s" % str(s), func():
			Settings.combat_speed = s
			Settings.save_settings()
			mark_speed.call(), "", 34)
		speed_btns.append(b)
		sp.add_child(b)
	mark_speed.call()
	v.add_child(sp)
	v.add_child(_check("Fullscreen", Settings.fullscreen, func(x): Settings.fullscreen = x; Settings.apply()))
	v.add_child(_check("Show tile grid", Settings.show_grid, func(x): Settings.show_grid = x))
	v.add_child(_check("Screen shake", Settings.screen_shake, func(x): Settings.screen_shake = x))
	v.add_child(_check("Pan at screen edges", Settings.edge_pan, func(x): Settings.edge_pan = x))
	v.add_child(UIKit.button("Done", func():
		Settings.save_settings()
		layer.queue_free(), "btn_green", 220))
	await parent.get_tree().process_frame
	p.reset_size()
	p.position = ((root.get_viewport_rect().size - p.size) / 2.0).floor()


static func _slider(label: String, value: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := UIKit.label(label, 10)
	l.custom_minimum_size.x = 100
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(110, 10)
	s.value_changed.connect(cb)
	h.add_child(s)
	return h


static func _check(label: String, value: bool, cb: Callable) -> Control:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c
