extends Node
## Music with adaptive layers and pooled sound effects.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _layer: AudioStreamPlayer
var _current := ""
var _pool: Array = []
var _cache := {}
var _fades := {}
var danger := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_layer = _make_player("Music")
	for i in 16:
		_pool.append(_make_player("SFX"))
	Settings.apply()


func _ensure_buses() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


## Music WAVs loop end to end (the generator wraps tails for seamless loops).
func _music(track: String) -> AudioStream:
	var s := _load(MUSIC_DIR + track + ".wav")
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(round(s.get_length() * s.mix_rate))
	return s


func play_music(track: String, layer_track := "", fade := 1.2) -> void:
	if track == _current:
		return
	_current = track
	var stream := _music(track)
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	if stream:
		_music_a.stream = stream
		_music_a.volume_db = -40.0
		_music_a.play()
		_fade(_music_a, 0.0, fade)
	_fade(_music_b, -60.0, fade, true)
	_cancel_fade(_layer)
	_layer.stop()
	if layer_track != "":
		var ls := _music(layer_track)
		if ls:
			_layer.stream = ls
			_layer.volume_db = -60.0
			_layer.play(_music_a.get_playback_position())


func stop_music(fade := 1.0) -> void:
	_current = ""
	for p in [_music_a, _music_b, _layer]:
		_fade(p, -60.0, fade, true)


## One fade per player: starting a new one cancels the old, so a fade-out still
## running (e.g. stop_music before a scene change) can't stop the next track.
func _fade(p: AudioStreamPlayer, db: float, time: float, stop_after := false) -> void:
	_cancel_fade(p)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, time)
	if stop_after:
		tw.tween_callback(p.stop)
	_fades[p] = tw


func _cancel_fade(p: AudioStreamPlayer) -> void:
	var tw: Tween = _fades.get(p)
	if tw and tw.is_valid():
		tw.kill()
	_fades.erase(p)


func set_danger(v: float) -> void:
	danger = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	if _layer.playing:
		var target := lerpf(-40.0, 0.0, danger)
		_layer.volume_db = move_toward(_layer.volume_db, target, delta * 20.0)


func sfx(name: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	var stream := _load(SFX_DIR + name + ".wav")
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.volume_db = volume_db
			p.play()
			return


## A short babbled line (no words): kind is talk, shout or hurt.
func voice(kind: String, pitch := 1.0, volume_db := -5.0) -> void:
	var stream := _load(SFX_DIR + "voice_" + kind + ".wav")
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch * randf_range(0.97, 1.03)
			p.volume_db = volume_db
			p.play()
			return


func duck(amount_db := -18.0, time := 1.5) -> void:
	## A short, silent moment (member death).
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	var tw := create_tween()
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), linear_to_db(Settings.music_volume), linear_to_db(Settings.music_volume) + amount_db, 0.15)
	tw.tween_interval(time)
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), linear_to_db(Settings.music_volume) + amount_db, linear_to_db(Settings.music_volume), 1.2)
