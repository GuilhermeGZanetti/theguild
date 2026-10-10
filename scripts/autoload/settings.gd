extends Node
## Player preferences, stored in user://settings.cfg.

const PATH := "user://settings.cfg"

var fullscreen := true
var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.8
var combat_speed := 1.0
var edge_pan := false
var show_grid := true
var screen_shake := true
var world_zoom := 0


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	combat_speed = cfg.get_value("game", "combat_speed", combat_speed)
	edge_pan = cfg.get_value("game", "edge_pan", edge_pan)
	show_grid = cfg.get_value("game", "show_grid", show_grid)
	screen_shake = cfg.get_value("game", "screen_shake", screen_shake)
	world_zoom = cfg.get_value("game", "world_zoom", world_zoom)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("game", "combat_speed", combat_speed)
	cfg.set_value("game", "edge_pan", edge_pan)
	cfg.set_value("game", "show_grid", show_grid)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "world_zoom", world_zoom)
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)
