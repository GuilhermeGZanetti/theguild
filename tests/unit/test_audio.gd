extends GutTest
## These tests wait real time for tweens; while they wait, GUT's own panel logs
## font errors in headless runs, which have nothing to do with audio.

var _engine_errors_were


func before_all():
	_engine_errors_were = gut.error_tracker.treat_engine_errors_as
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func after_all():
	gut.error_tracker.treat_engine_errors_as = _engine_errors_were


func after_each():
	Audio.stop_music(0.0)
	await wait_seconds(0.1)


func test_battle_music_survives_the_march_out_fade():
	# The squad screen stops the music and the battle starts its own track
	# while that fade-out is still running (scene fade is 0.35 s).
	Audio.play_music("guild")
	await wait_seconds(0.2)
	Audio.stop_music(0.6)
	await wait_seconds(0.35)
	Audio.play_music("combat", "combat_layer")
	await wait_seconds(1.0)
	assert_true(Audio._music_a.playing, "combat track still playing after the old fade-out ends")
	assert_eq(Audio._music_a.stream, Audio._music("combat"))
	assert_true(Audio._layer.playing, "danger layer still playing")


func test_every_region_biome_has_battle_music_and_layer():
	var biomes := ["hush_town"]
	for r in DB.regions.values():
		biomes.append(r.get("biome", "town"))
	for b in biomes:
		var track := Audio.battle_track(b)
		assert_true(ResourceLoader.exists(Audio.MUSIC_DIR + track + ".wav"), "%s -> %s" % [b, track])
		assert_true(ResourceLoader.exists(Audio.MUSIC_DIR + track + "_layer.wav"), "%s -> %s_layer" % [b, track])
	assert_ne(Audio.battle_track("coast"), Audio.battle_track("desert"), "biomes get their own track")


func test_crossfade_still_stops_the_old_track():
	Audio.play_music("guild")
	await wait_seconds(0.2)
	Audio.play_music("menu", "", 0.3)
	await wait_seconds(0.6)
	assert_true(Audio._music_a.playing)
	assert_false(Audio._music_b.playing, "previous track faded out and stopped")
