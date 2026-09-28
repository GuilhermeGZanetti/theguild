extends Node
## Scene switching with a pixel fade, plus a parameter bag for the next scene.

var params := {}
var _layer: CanvasLayer
var _fade: ColorRect
var busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.05, 0.04, 0.07, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


func go(path: String, p_params := {}) -> void:
	if busy:
		return
	busy = true
	params = p_params
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.45)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false


func flash(color := Color(1, 1, 1, 0.6), time := 0.25) -> void:
	_fade.color = color
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, time)
