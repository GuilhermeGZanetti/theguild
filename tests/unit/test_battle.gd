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
			while not b.over and guard < 900:
				guard += 1
				b.auto_step()
				b.pop_events()
			assert_true(b.over, "battle %s/%s finished (turns %d)" % [biome_region, obj, guard])
			results[b.result] = int(results.get(b.result, 0)) + 1
	gut.p("AI vs AI results: %s" % str(results))


# ---------------------------------------------------------------- exploration
func _explore_battle(obj := "clear", region := "carrow") -> Battle:
	rng.seed = hash(region + obj + "explore")
	var squad: Array = []
	for c in ["warrior", "rogue", "ranger", "mystic"]:
		var m := Member.create(rng, c, "human", 1, 3)
		m.id = squad.size() + 1
		squad.append(m)
	var mission := {"region": region, "objective": obj, "skulls": 2, "seed": 1234, "turns": 6, "caches": 3, "par_rounds": 8}
	return BattleFactory.build(mission, squad, {"difficulty": 1})


func test_patrolled_maps_start_unseen_in_the_fog():
	for obj in ["clear", "hunt", "retrieve", "rescue", "escort"]:
		var b := _explore_battle(obj)
		assert_true(b.fog and b.explore, "%s is a patrolled map" % obj)
		assert_eq(b.phase, "explore", "%s starts exploring" % obj)
		assert_gt(b.grid.w * b.grid.h, 700, "%s map is big" % obj)
		assert_gt(b.pods.size(), 1, "%s has several pods" % obj)
		assert_false(b.vis.is_empty(), "the squad sees around itself")
		for u in b.units:
			if u.team == BattleUnit.TEAM_ENEMY:
				assert_false(u.alerted, "%s starts unaware" % u.name)
				assert_false(b.is_seen(u), "%s starts hidden in the fog" % u.name)
		assert_true(b.next_turn() == null, "no timeline while exploring")


func test_trail_leads_from_the_landing_to_the_objective():
	for obj in ["clear", "retrieve", "escort"]:
		var b := _explore_battle(obj, "stilts")
		var start: Vector2i = b.route[0]
		var goal: Vector2i = b.objective_area["center"]
		assert_lt(Rules.chebyshev(b.route[-1], goal), 3, "the trail ends at the clearing")
		assert_gt(Rules.chebyshev(start, goal), 20, "the objective is far from the landing")
		var field := b.distance_field([goal])
		for c in b.route:
			assert_true(field.has(c), "trail cell %s is walkable to the objective" % str(c))


func test_hunt_target_waits_in_the_objective_area():
	var b := _explore_battle("hunt")
	var tgt := b.unit(int(b.objective["target_uid"]))
	assert_not_null(tgt)
	assert_lt(Rules.chebyshev(tgt.pos, b.objective_area["center"]), 5, "the quarry guards the far clearing")
	var pod: Dictionary = b.pods[tgt.pod]
	assert_true(pod["objective"], "in the objective pod")


func test_being_spotted_starts_combat_for_that_pod_only():
	var b := _explore_battle()
	var e: BattleUnit = b.unit(b.pods[0]["units"][0])
	var p: BattleUnit = null
	for u in b.units:
		if u.team == BattleUnit.TEAM_PLAYER and not u.npc:
			p = u
			break
	for c in b.grid.cells_in_radius(e.pos, 2):
		if b.grid.standable(c) and b.unit_at(c) == null and Rules.chebyshev(c, e.pos) >= 1:
			p.pos = c
			break
	b.update_vision(p)
	b.explore_select(p)
	assert_true(b._detection_step(p), "an enemy that close spots the member")
	b._process_alerts()
	assert_eq(b.phase, "combat")
	assert_true(b.pods[0]["alerted"])
	for i in range(1, b.pods.size()):
		assert_false(b.pods[i]["alerted"], "pod %d keeps patrolling" % i)
	# the interrupted member finishes its turn, then only awake units take turns
	b.end_turn(p)
	for i in 20:
		var u := b.next_turn()
		if u == null:
			break
		assert_false(u.team == BattleUnit.TEAM_ENEMY and not u.alerted, "dormant enemies never act")
		b.end_turn(u)
	# with the awake pod gone the squad explores again
	for uid in b.pods[0]["units"]:
		var o := b.unit(uid)
		if o.alive():
			b._kill(o, null, "test")
	b.current = null
	assert_null(b.next_turn())
	assert_eq(b.phase, "explore", "back to exploring once the pod is dead")


func test_unaware_targets_are_flanked():
	var b := _explore_battle()
	var e: BattleUnit = b.unit(b.pods[0]["units"][0])
	var p: BattleUnit = b.team_units(BattleUnit.TEAM_PLAYER)[0]
	var s := DB.skill(p.basic)
	var eff: Dictionary = s["effects"][0]
	var unaware := b.attack_context(p, e, s, eff, e.pos + Vector2i(0, 1))
	e.alerted = true
	var aware := b.attack_context(p, e, s, eff, e.pos + Vector2i(0, 1))
	assert_true(unaware["flank"])
	assert_gt(unaware["hit"], aware["hit"] - 1, "ambushes hit at least as often")


func test_defense_and_survive_keep_one_fight_under_fog():
	for obj in ["survive", "defense"]:
		var b := _explore_battle(obj)
		assert_true(b.fog, "%s has fog of war" % obj)
		assert_false(b.explore, "%s is a single fight" % obj)
		assert_eq(b.phase, "combat")


func test_final_battle_has_no_fog():
	var b := _explore_battle("final", "unremembered")
	assert_false(b.fog)
	assert_false(b.explore)
