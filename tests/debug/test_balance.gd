extends GutTest
## Batch battle statistics for tuning (run manually).

var rng := RandomNumberGenerator.new()


func _squad(level: int, size := 4) -> Array:
	var squad: Array = []
	var classes := ["warrior", "rogue", "ranger", "mystic", "warrior", "ranger"]
	for i in size:
		var m := Member.create(rng, classes[i], "human", 1, level)
		m.id = i + 1
		m.auto_pick(rng)
		squad.append(m)
	return squad


func _batch(label: String, mission: Dictionary, level: int, n := 24, size := 4) -> void:
	var res := {}
	var rounds := 0.0
	var downs := 0.0
	var deaths := 0.0
	var enemies := 0.0
	for i in n:
		rng.seed = 1000 + i * 17
		var m := mission.duplicate(true)
		m["seed"] = rng.randi()
		var b := BattleFactory.build(m, _squad(level, size), {"difficulty": 1})
		for u in b.units:
			if u.team == 1:
				enemies += 1
		AutoPilot.run_battle(b)
		res[b.result] = int(res.get(b.result, 0)) + 1
		rounds += b.round_num
		downs += b.downs
		deaths += b.deaths
	gut.p("%-28s lvl %d: %s  rounds %.1f downs %.2f deaths %.2f enemies %.1f" % [label, level, str(res), rounds / n, downs / n, deaths / n, enemies / n])


func test_balance_table():
	_batch("s1 bell thief", {"region": "carrow", "objective": "hunt", "skulls": 1, "boss": "brigand_captain", "enemies": {"brigand": 2, "brigand_archer": 1}, "category": "story", "par_rounds": 8}, 1)
	_batch("carrow clear sk1", {"region": "carrow", "objective": "clear", "skulls": 1, "par_rounds": 8}, 1)
	_batch("coast clear sk2", {"region": "coast", "objective": "clear", "skulls": 2, "par_rounds": 8}, 3)
	_batch("ember clear sk3", {"region": "ember", "objective": "clear", "skulls": 3, "par_rounds": 8}, 5, 20, 5)
	_batch("dunes clear sk4", {"region": "dunes", "objective": "clear", "skulls": 4, "par_rounds": 8}, 8, 20, 5)
	_batch("stilts defense sk2", {"region": "stilts", "objective": "defense", "skulls": 2, "turns": 7, "par_rounds": 8}, 3)
	_batch("unrem clear sk5", {"region": "unremembered", "objective": "clear", "skulls": 5, "par_rounds": 8}, 12, 16, 6)
	assert_true(true)
