class_name Dialogs
extends RefCounted
## Modal pixel dialogs.

static var open := 0   # number of dialogs on screen; scenes ignore hotkeys while > 0


static func _modal(parent: Node) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := UIKit.panel()
	root.add_child(p)
	var v := UIKit.vbox(5)
	p.add_child(v)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(root)
	open += 1
	layer.tree_exiting.connect(func(): open = maxi(0, open - 1))
	parent.add_child(layer)
	return [layer, p, v]


static func _center(p: Control) -> void:
	p.reset_size()
	var vs := p.get_viewport_rect().size
	p.position = ((vs - p.size) / 2.0).floor()


static func confirm(parent: Node, title: String, text: String, ok: Callable, ok_label := "Confirm", cancel_label := "Cancel") -> void:
	var m := _modal(parent)
	var v: VBoxContainer = m[2]
	v.add_child(UIKit.header(title, 12))
	var body := UIKit.rich(text, 240, 10)
	v.add_child(body)
	var h := UIKit.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(UIKit.button(cancel_label, func(): m[0].queue_free(), "", 70))
	h.add_child(UIKit.button(ok_label, func():
		m[0].queue_free()
		ok.call(), "btn_green", 70))
	v.add_child(h)
	await parent.get_tree().process_frame
	_center(m[1])


static func message(parent: Node, title: String, text: String, done := Callable(), button := "Continue", width := 260) -> void:
	var m := _modal(parent)
	var v: VBoxContainer = m[2]
	v.add_child(UIKit.header(title, 12))
	v.add_child(UIKit.rich(text, width, 10))
	var h := UIKit.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(UIKit.button(button, func():
		m[0].queue_free()
		if done.is_valid():
			done.call(), "btn_green", 80))
	v.add_child(h)
	await parent.get_tree().process_frame
	_center(m[1])


## choices: Array of [label, Callable, style]
static func choice(parent: Node, title: String, text: String, choices: Array, width := 280) -> void:
	var m := _modal(parent)
	var v: VBoxContainer = m[2]
	v.add_child(UIKit.header(title, 12))
	v.add_child(UIKit.rich(text, width, 10))
	for c in choices:
		var b := UIKit.button(c[0], func():
			m[0].queue_free()
			c[1].call(), c[2] if c.size() > 2 else "", width)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if c.size() > 3 and not c[3]:
			b.disabled = true
		v.add_child(b)
	await parent.get_tree().process_frame
	_center(m[1])
