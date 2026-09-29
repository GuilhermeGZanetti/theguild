extends GutTest
## Manual debugging helpers (not part of the main suite).

var rng := RandomNumberGenerator.new()


func _run(region: String, obj: String) -> Battle:
	rng.seed = hash(region + obj)
	var squad: Array = []
	var squads := [["warrior", "rogue", "ranger", "mystic"], ["warrior", "ranger", "mystic", "rogue", "warrior"]]
	for c in squads[rng.randi() % 2]:
		var m := Member.create(rng, c, "human", 1, 3)
		m.id = squad.size() + 1
		squad.append(m)
	var mission := {"region": region, "objective": obj, "skulls": 2, "seed": rng.randi(), "turns": 6, "caches": 3, "par_rounds": 8}
	var b := BattleFactory.build(mission, squad, {"difficulty": 1})
	var guard := 0
	while not b.over and guard < 900:
		guard += 1
		b.auto_step()
		b.pop_events()
	return b


func _dump(b: Battle) -> void:
	var lines: Array = []
	for y in b.grid.h:
		var row := ""
		for x in b.grid.w:
			var p := Vector2i(x, y)
			var t := b.grid.t(p)
			var ch := str(t["h"])
			if t["water"] >= 2:
				ch = "~"
			elif t["water"] == 1:
				ch = "-"
			if t["solid"]:
				ch = "#"
			if not t["obj"].is_empty():
				ch = "O"
			if t["extract"]:
				ch = "E"
			var u := b.unit_at(p)
			if u:
				ch = "P" if u.team == 0 else ("e" if u.team == 1 else "n")
				if u.state == "downed":
					ch = "d"
			row += ch
		lines.append(row)
	gut.p("\n".join(lines))
	for u in b.units:
		gut.p("%s team %d state %s pos %s role %s hidden %s hp %d" % [u.name, u.team, u.state, u.pos, u.objective_role, u.hidden, u.hp])
	gut.p("objective %s round %d result %s phase %s alerted pods %s" % [b.objective, b.round_num, b.result, b.phase, b.pods.map(func(pd): return pd["alerted"])])


func test_debug_stuck():
	for pair in [["ember", "escort"]]:
		var b := _run(pair[0], pair[1])
		gut.p("=== %s / %s over=%s" % [pair[0], pair[1], b.over])
		_dump(b)
	assert_true(true)


func test_debug_map():
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var squad: Array = []
	for c in ["warrior", "rogue", "ranger", "mystic"]:
		var m := Member.create(rng2, c, "human", 1, 3)
		m.id = squad.size() + 1
		squad.append(m)
	for obj in ["clear", "retrieve"]:
		var b := BattleFactory.build({"region": "stilts", "objective": obj, "skulls": 2, "seed": 77, "par_rounds": 8}, squad, {"difficulty": 1})
		var trail := {}
		for c in b.route:
			trail[c] = true
		var lines: Array = []
		for y in b.grid.h:
			var row := ""
			for x in b.grid.w:
				var p := Vector2i(x, y)
				var t := b.grid.t(p)
				var ch := str(t["h"])
				if t["water"] >= 2:
					ch = "~"
				elif t["water"] == 1:
					ch = "-"
				if trail.has(p):
					ch = "+"
				if t["solid"]:
					ch = "#"
				if not t["obj"].is_empty():
					ch = "O"
				if t["extract"]:
					ch = "E"
				if p == b.objective_area.get("center", Vector2i(-1, -1)):
					ch = "X"
				var u := b.unit_at(p)
				if u:
					ch = "P" if u.team == 0 else "e"
				row += ch
			lines.append(row)
		gut.p("=== %s pods %d route %d par %d" % [obj, b.pods.size(), b.route.size(), b.par_rounds])
		gut.p("\n".join(lines))
		for pd in b.pods:
			gut.p("pod units %s route %s objective %s" % [pd["units"].size(), pd["route"], pd["objective"]])
	assert_true(true)
