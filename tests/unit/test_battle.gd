extends GutTest

var rng := RandomNumberGenerator.new()


func _flat_battle(w := 10, h := 10) -> Battle:
	var b := Battle.new()
	b.rng.seed = 7
	b.grid = BattleGrid.new(w, h)
	b.objective = {"type": "clear"}
	return b


func _warrior(team: int, pos: Vector2i) -> BattleUnit:
	rng.seed = 99
	var m := Member.create(rng, "warrior", "human", 1)
	m.traits = []
	var u := BattleFactory.member_unit(m)
	u.team = team
	u.pos = pos
	if team != BattleUnit.TEAM_PLAYER:
		u.member = null
	return u


func test_entering_zoc_ends_movement():
	var b := _flat_battle()
	var p := b.add_unit(_warrior(0, Vector2i(2, 5)))
	b.add_unit(_warrior(1, Vector2i(5, 5)))
	var reach := b.reachable(p)
	assert_true(reach.has(Vector2i(4, 5)), "can step into the ZOC")
	assert_true(reach[Vector2i(4, 5)]["zoc"], "tile is in ZOC")
	assert_false(reach.has(Vector2i(6, 4)) and reach[Vector2i(6, 4)]["cost"] <= 4 and not _has_non_zoc_route(b, p, Vector2i(6, 4)), "cannot walk through a ZOC")


func test_run_doubles_move_and_spends_the_action():
	var b := _flat_battle(20, 20)
	var p := b.add_unit(_warrior(0, Vector2i(0, 0)))
	b.add_unit(_warrior(1, Vector2i(19, 19)))
	b.start()
	b._begin_turn(p)
	var mv := b.move_budget(p)
	var reach := b.reachable_with_run(p)
	var walk := Vector2i(mv, 0)
	var run := Vector2i(mv * 2, 0)
	assert_false(b.is_run(p, reach, walk), "within the move budget is a walk")
	assert_true(b.is_run(p, reach, run), "beyond it is a run")
	assert_false(reach.has(Vector2i(mv * 2 + 1, 0)), "run is capped at double")
	assert_true(b.do_move(p, run))
	assert_eq(p.pos, run)
	assert_true(p.acted, "running uses the action")


func test_walk_keeps_the_action_and_no_run_after_acting():
	var b := _flat_battle(20, 20)
	var p := b.add_unit(_warrior(0, Vector2i(0, 0)))
	b.add_unit(_warrior(1, Vector2i(19, 19)))
	b.start()
	b._begin_turn(p)
	var mv := b.move_budget(p)
	assert_true(b.do_move(p, Vector2i(mv, 0)))
	assert_false(p.acted, "a normal move leaves the action")
	b._begin_turn(p)
	p.acted = true
	assert_false(b.do_move(p, Vector2i(mv + 1, mv)), "can't run once the action is spent")


func _has_non_zoc_route(b: Battle, u: BattleUnit, dest: Vector2i) -> bool:
	var reach := b.reachable(u)
	var path := b.path_to(u, dest, reach)
	for i in range(0, path.size() - 1):
		if reach[path[i]]["zoc"]:
			return false
	return not path.is_empty()


func test_leaving_zoc_triggers_attack_of_opportunity():
	var b := _flat_battle()
	var p := b.add_unit(_warrior(0, Vector2i(4, 5)))
	var e := b.add_unit(_warrior(1, Vector2i(5, 5)))
	var reach := b.reachable(p)
	var path := b.path_to(p, Vector2i(2, 5), reach)
	assert_eq(path.size(), 2)
	var aoo := b.aoo_attackers(p, path)
	assert_eq(aoo.size(), 1)
	assert_eq(aoo[0], e)


func test_cover_depends_on_direction():
	var g := BattleGrid.new(10, 10)
	g.t(Vector2i(5, 4))["cover"] = 2
	g.t(Vector2i(5, 4))["solid"] = true
	assert_eq(g.cover_from(Vector2i(5, 5), Vector2i(5, 0)), 2, "wall between target and attacker")
	assert_eq(g.cover_from(Vector2i(5, 5), Vector2i(5, 9)), 0, "attacker behind the target")
	assert_eq(g.cover_from(Vector2i(5, 5), Vector2i(5, 6)), 0, "melee range ignores cover")


func test_downed_members_bleed_out():
	var b := _flat_battle()
	var p := b.add_unit(_warrior(0, Vector2i(2, 2)))
	b.add_unit(_warrior(1, Vector2i(8, 8)))
	b.start()
	p.hp = 1
	b._apply_damage(p, 3, null)
	assert_eq(p.state, "downed")
	for i in 5:
		b._begin_turn(p)
	assert_eq(p.state, "dead")


func test_overkill_kills_outright():
	var b := _flat_battle()
	var p := b.add_unit(_warrior(0, Vector2i(2, 2)))
	b.add_unit(_warrior(1, Vector2i(8, 8)))
	b.start()
	p.hp = 5
	b._apply_damage(p, p.max_hp(), null)
	assert_eq(p.state, "dead")


func test_stabilize_stops_bleeding():
	var b := _flat_battle()
	var p := b.add_unit(_warrior(0, Vector2i(2, 2)))
	var q := b.add_unit(_warrior(0, Vector2i(3, 2)))
	b.add_unit(_warrior(1, Vector2i(8, 8)))
	b.start()
	p.hp = 1
	b._apply_damage(p, 3, null)
	assert_true(b.do_stabilize(q, p))
	for i in 5:
		b._begin_turn(p)
	assert_eq(p.state, "downed")


func test_full_ai_battles_finish():
	var squads := [["warrior", "rogue", "ranger", "mystic"], ["warrior", "ranger", "mystic", "rogue", "warrior"]]
	var results := {}
	for biome_region in ["carrow", "coast", "stilts", "ember", "dunes", "unremembered"]:
		for obj in ["clear", "hunt", "retrieve", "survive", "defense", "escort", "rescue"]:
			rng.seed = hash(biome_region + obj)
			var squad: Array = []
			for c in squads[rng.randi() % 2]:
				var m := Member.create(rng, c, "human", 1, 3)
				m.id = squad.size() + 1
				squad.append(m)
			var mission := {"region": biome_region, "objective": obj, "skulls": 2, "seed": rng.randi(), "turns": 6, "caches": 3, "par_rounds": 8}
			var b := BattleFactory.build(mission, squad, {"difficulty": 1})
			var guard := 0
			while not b.over and guard < 600:
				guard += 1
				var u := b.next_turn()
				if u == null:
					break
				if b.over:
					break
				if b.current == u:
					b.ai.take_turn(u)
				b.pop_events()
			assert_true(b.over, "battle %s/%s finished (turns %d)" % [biome_region, obj, guard])
			results[b.result] = int(results.get(b.result, 0)) + 1
	gut.p("AI vs AI results: %s" % str(results))
