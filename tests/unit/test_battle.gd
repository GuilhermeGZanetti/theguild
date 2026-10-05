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


func test_walk_then_run_on_to_the_run_band():
	var b := _flat_battle(20, 20)
	var p := b.add_unit(_warrior(0, Vector2i(0, 0)))
	b.add_unit(_warrior(1, Vector2i(19, 19)))
	b.start()
	b._begin_turn(p)
	var mv := b.move_budget(p)
	assert_true(b.do_move(p, Vector2i(2, 0)))
	assert_false(p.acted, "the walk keeps the action")
	assert_eq(b.run_budget(p), mv * 2 - 2, "and the rest of the run")
	var reach := b.reachable_with_run(p)
	assert_true(reach.has(Vector2i(mv * 2, 0)), "the run band is still in reach")
	assert_false(reach.has(Vector2i(mv * 2 + 1, 0)), "but no further than a single run")
	assert_true(b.is_run(p, reach, Vector2i(3, 0)), "any step after the walk is a run")
	assert_true(b.do_move(p, Vector2i(mv * 2, 0)))
	assert_true(p.acted, "running on spends the action")
	assert_eq(b.run_budget(p), 0, "and there is no third leg")
	b._begin_turn(p)
	assert_true(b.do_move(p, Vector2i(mv * 2 - 2, 0)))
	p.acted = true
	assert_eq(b.run_budget(p), 0, "acting after the walk gives up the run")


## A wall of full cover down column x = 3 with one gap at (3, 5).
func _walled_battle() -> Battle:
	var b := _flat_battle()
	for y in 10:
		var tl := b.grid.t(Vector2i(3, y))
		tl["solid"] = y != 5
		tl["cover"] = 2 if y != 5 else 0
	return b


func test_vault_half_cover_onto_a_free_tile():
	var b := _walled_battle()
	var gap := b.grid.t(Vector2i(3, 5))
	gap["solid"] = true
	gap["cover"] = 1
	var p := b.add_unit(_warrior(0, Vector2i(2, 5)))
	b.add_unit(_warrior(1, Vector2i(9, 0)))
	var reach := b.reachable(p)
	assert_true(reach.has(Vector2i(4, 5)), "vaults the half cover")
	assert_eq(int(reach[Vector2i(4, 5)]["cost"]), 2, "for the obstacle's tile and the landing")
	assert_eq(b.path_to(p, Vector2i(5, 5), reach), [Vector2i(4, 5), Vector2i(5, 5)])
	var ally := b.add_unit(_warrior(0, Vector2i(4, 5)))
	assert_false(b.reachable(p).has(Vector2i(5, 5)), "needs a free tile to land on")
	ally.pos = Vector2i(7, 7)
	gap["cover"] = 2
	assert_false(b.reachable(p).has(Vector2i(4, 5)), "full cover cannot be vaulted")
	gap["cover"] = 1
	b.start()
	b._begin_turn(p)
	assert_true(b.do_move(p, Vector2i(5, 5)))
	assert_eq(p.pos, Vector2i(5, 5))


func test_walk_over_a_downed_ally():
	var b := _walled_battle()
	var p := b.add_unit(_warrior(0, Vector2i(2, 5)))
	var body := b.add_unit(_warrior(0, Vector2i(3, 5)))
	body.state = "downed"
	b.add_unit(_warrior(1, Vector2i(9, 0)))
	var reach := b.reachable(p)
	assert_true(reach[Vector2i(3, 5)].get("pass_only", false), "no standing on the body")
	assert_eq(int(reach[Vector2i(4, 5)]["cost"]), 2, "but the tile beyond is in reach")


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


func _mystic(pos: Vector2i) -> BattleUnit:
	rng.seed = 41
	var m := Member.create(rng, "mystic", "human", 1, 3)
	m.traits = []
	var u := BattleFactory.member_unit(m)
	u.team = BattleUnit.TEAM_PLAYER
	u.pos = pos
	return u


func _ranger(pos: Vector2i) -> BattleUnit:
	rng.seed = 23
	var m := Member.create(rng, "ranger", "human", 1)
	m.traits = []
	var u := BattleFactory.member_unit(m)
	u.team = BattleUnit.TEAM_PLAYER
	u.pos = pos
	return u


func test_high_ground_adds_a_tile_of_reach_per_level():
	var b := _flat_battle(16, 5)
	var r := b.add_unit(_ranger(Vector2i(0, 2)))
	var shoot := DB.skill("shoot")
	var mx: int = b.skill_range(r, shoot, r.pos)[2]
	var foe := b.add_unit(_warrior(1, Vector2i(mx + 2, 2)))
	b.start()
	assert_false(foe.pos in b.valid_targets(r, "shoot"), "out of reach on flat ground")
	b.grid.t(r.pos)["h"] = 1
	assert_false(foe.pos in b.valid_targets(r, "shoot"), "one level up is one tile short")
	b.grid.t(r.pos)["h"] = 2
	assert_true(foe.pos in b.valid_targets(r, "shoot"), "two levels up reach two tiles further")
	var ctx := b.attack_context(r, foe, shoot, shoot["effects"][0])
	assert_eq(int(ctx["beyond"]), mx + 2 - (int(r.stat("range")) + 2), "optimal range grows too")
	b.grid.t(foe.pos)["h"] = 1
	assert_false(foe.pos in b.valid_targets(r, "shoot"), "only the difference in height counts")
	# area spells, heals and fixed ranges reach further too, teleports do not
	var m := b.add_unit(_mystic(Vector2i(0, 0)))
	b.grid.t(m.pos)["h"] = 2
	var far := Vector2i(b.skill_range(m, DB.skill("firebolt"), m.pos)[2] + 2, 0)
	assert_true(far in b.valid_targets(m, "firebolt"), "a fireball from the hill lands further")
	var ally := b.add_unit(_warrior(0, Vector2i(int(DB.skill("mend")["range"]["max"]) + 2, 0)))
	assert_true(ally.pos in b.valid_targets(m, "mend"), "a heal from the hill reaches further")
	var step := Vector2i(int(DB.skill("shadowstep")["range"]["max"]) + 1, 1)
	assert_false(step in b.valid_targets(m, "shadowstep"), "a teleport does not")


func test_area_spells_always_land_and_burn_allies_too():
	var b := _flat_battle(12, 12)
	var caster := b.add_unit(_mystic(Vector2i(3, 5)))
	var ally := b.add_unit(_warrior(0, Vector2i(6, 5)))
	var downed := b.add_unit(_warrior(0, Vector2i(8, 4)))
	var foe_a := b.add_unit(_warrior(1, Vector2i(7, 5)))
	var foe_b := b.add_unit(_warrior(1, Vector2i(7, 6)))
	b.start()
	downed.state = "downed"
	var hit := b.affected(caster, "firebolt", Vector2i(7, 5))
	assert_true(ally in hit and foe_a in hit and foe_b in hit, "the blast hits whoever stands in it")
	assert_false(downed in hit, "a Downed ally is spared")
	assert_false(caster in hit)
	var pv := b.preview(caster, "firebolt", Vector2i(7, 5))
	for row in pv["targets"]:
		assert_eq(int(row["hit"]), 100, "always hits")
		assert_eq(int(row["crit"]), 0, "never crits")
		assert_eq(row.get("ally", false), int(row["uid"]) == ally.uid, "the ally is flagged in the preview")
		assert_gt(int(row["dmg_max"]), 2 * int(row["dmg_min"]), "a wide swing")
	# no misses over many casts, and every roll inside the previewed range
	var lo := 9999
	var hi := 0
	var pv_foe: Dictionary = {}
	for row in pv["targets"]:
		if int(row["uid"]) == foe_a.uid:
			pv_foe = row
	for i in 40:
		foe_a.hp = foe_a.max_hp()
		foe_a.def_cur = foe_a.max_def()
		var before := foe_a.hp
		assert_true(b._resolve_damage(caster, foe_a, DB.skill("firebolt"), DB.skill("firebolt")["effects"][0]))
		var dmg := before - foe_a.hp
		lo = mini(lo, dmg)
		hi = maxi(hi, dmg)
	assert_between(lo, int(pv_foe["dmg_min"]), int(pv_foe["dmg_max"]))
	assert_between(hi, int(pv_foe["dmg_min"]), int(pv_foe["dmg_max"]))
	assert_gt(hi, lo, "damage varies")
	b._begin_turn(caster)
	assert_true(b.use_skill(caster, "firebolt", Vector2i(7, 5)))
	assert_lt(ally.hp, ally.max_hp(), "the ally got burned too")
	assert_eq(caster.kills, 0)


func test_arcane_focus_cuts_the_low_rolls():
	var b := _flat_battle(12, 12)
	var caster := b.add_unit(_mystic(Vector2i(3, 5)))
	b.add_unit(_warrior(1, Vector2i(7, 5)))
	b.start()
	var plain: Dictionary = b.preview(caster, "firebolt", Vector2i(7, 5))["targets"][0]
	caster.mods["spread_floor"] = 1.0
	var focused: Dictionary = b.preview(caster, "firebolt", Vector2i(7, 5))["targets"][0]
	assert_gt(int(focused["dmg_min"]), int(plain["dmg_min"]))
	assert_eq(int(focused["dmg_max"]), int(plain["dmg_max"]))


func test_ai_avoids_burning_its_friends():
	var b := _flat_battle(12, 12)
	var caster := b.add_unit(_mystic(Vector2i(3, 5)))
	var ally := b.add_unit(_warrior(0, Vector2i(7, 4)))
	var foe := b.add_unit(_warrior(1, Vector2i(7, 5)))
	b.start()
	var with_ally := b.ai.eval_skill(caster, "firebolt", Vector2i(7, 5), caster.pos)
	ally.pos = Vector2i(1, 1)
	var clear := b.ai.eval_skill(caster, "firebolt", Vector2i(7, 5), caster.pos)
	assert_lt(with_ally, clear * 0.5, "an ally in the blast makes the spell a poor choice")
	assert_true(foe.alive())


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


func test_exploring_members_walk_on_after_seeing_an_enemy():
	var b := _explore_battle()
	var p: BattleUnit = b.explore_units()[0]
	b.explore_select(p)
	# blind patrols: nobody gets spotted, so only seeing them could stop the walk
	for o in b.units:
		if o.team == BattleUnit.TEAM_ENEMY:
			b._add_status(o, "blind", 9, 0, null)
	var reach := b.reachable_with_run(p)
	var dest := p.pos
	for c in reach:
		if not reach[c].get("pass_only", false) and int(reach[c]["cost"]) <= b.move_budget(p) \
				and int(reach[c]["cost"]) > int(reach[dest]["cost"]):
			dest = c
	var path := b.path_to(p, dest, reach)
	assert_gt(path.size(), 1, "the member has somewhere to walk")
	# an enemy hidden in the fog that comes into view before the walk ends
	var e: BattleUnit = b.unit(b.pods[0]["units"][0])
	var start := p.pos
	var hide := Vector2i(-1, -1)
	for k in path.size() - 1:
		p.pos = path[k]
		for c in b._cells_seen_from(p):
			if not b.vis.has(c) and not c in path and b.grid.standable(c) and b.unit_at(c) == null:
				hide = c
				break
		if hide != Vector2i(-1, -1):
			break
	p.pos = start
	assert_ne(hide, Vector2i(-1, -1), "found a fogged cell the walk reveals")
	e.pos = hide
	assert_false(b.is_seen(e), "the enemy starts unseen")
	b.pop_events()
	assert_true(b.do_move(p, dest))
	assert_true(b.is_seen(e), "the walk revealed the enemy")
	assert_eq(p.pos, dest, "the member keeps walking to the chosen tile")
	assert_eq(b.phase, "explore", "seeing an unaware pod does not start combat")
	var floats: Array = []
	for ev in b.pop_events():
		if ev["t"] == "float":
			floats.append(ev["text"])
	assert_true("Enemy spotted!" in floats, "the sighting is still announced")


## The farthest tile `p` can walk to this turn, and the way there.
func _long_walk(b: Battle, p: BattleUnit) -> Array:
	var reach := b.reachable_with_run(p)
	var dest := p.pos
	for c in reach:
		if not reach[c].get("pass_only", false) and int(reach[c]["cost"]) <= b.move_budget(p) \
				and int(reach[c]["cost"]) > int(reach[dest]["cost"]):
			dest = c
	return [dest, b.path_to(p, dest, reach)]


func test_a_spotted_member_still_finishes_the_walk():
	var b := _explore_battle()
	var p: BattleUnit = b.explore_units()[0]
	b.explore_select(p)
	var e: BattleUnit = b.unit(b.pods[0]["units"][0])
	# an unaware patrol close enough to spot the member's first step
	var spot := Vector2i(-1, -1)
	for c in b.grid.cells_in_radius(p.pos, 4):
		if Rules.chebyshev(c, p.pos) >= 3 and b.grid.standable(c) and b.unit_at(c) == null and b.grid.los(c, p.pos):
			spot = c
			break
	assert_ne(spot, Vector2i(-1, -1))
	e.pos = spot
	var walk := _long_walk(b, p)
	var dest: Vector2i = walk[0]
	assert_gt(walk[1].size(), 1, "the member has somewhere to walk")
	assert_true(b.do_move(p, dest))
	assert_eq(b.phase, "combat", "the patrol spotted the member")
	assert_eq(p.pos, dest, "but the member still walks to the chosen tile")


func test_seeing_a_new_enemy_in_combat_does_not_stop_the_walk():
	var b := _explore_battle()
	var p: BattleUnit = b.explore_units()[0]
	for o in b.units:
		if o.team == BattleUnit.TEAM_ENEMY:
			b._add_status(o, "blind", 9, 0, null)
	b._start_combat()
	var walk := _long_walk(b, p)
	var dest: Vector2i = walk[0]
	var path: Array = walk[1]
	assert_gt(path.size(), 1)
	# an enemy hidden in the fog that comes into view halfway
	var e: BattleUnit = b.unit(b.pods[0]["units"][0])
	var start := p.pos
	var hide := Vector2i(-1, -1)
	for k in path.size() - 1:
		p.pos = path[k]
		for c in b._cells_seen_from(p):
			if not b.vis.has(c) and not c in path and b.grid.standable(c) and b.unit_at(c) == null:
				hide = c
				break
		if hide != Vector2i(-1, -1):
			break
	p.pos = start
	assert_ne(hide, Vector2i(-1, -1), "found a fogged cell the walk reveals")
	e.pos = hide
	assert_true(b.do_move(p, dest))
	assert_true(b.is_seen(e), "the walk revealed the enemy")
	assert_eq(p.pos, dest, "the member keeps walking to the chosen tile")


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


## A Normal member with average potential, no traits, every skill row taken
## from one branch and the gear of its level (Worn, then Steel at 3,
## Masterwork at 5 and Relic at 7).
func _reference(cls: String, level: int, branch := "") -> BattleUnit:
	rng.seed = 4242 + level
	var m := Member.create(rng, cls, "human", 1)
	m.traits = []
	for k in Member.GROWTH_STATS:
		m.potential[k] = 2
	for i in level - 1:
		m._level_up(rng)
	if branch == "":
		branch = m.class_data()["branches"].keys()[0]
	for row in m.open_rows():
		for s in m.row_skills(row):
			if DB.branch_of(s) == branch:
				m.pick(s)
	var t := clampi(1 + (level - 1) / 2, 1, 4)
	m.equipment["weapon"] = Items.weapon(m.class_data()["weapon_family"], t)
	m.equipment["armor"] = Items.armor(m.class_data()["armor_family"], t)
	return BattleFactory.member_unit(m)


## Basic attacks of average damage, no crits, until `o` drops.
func _hits_to_drop(att: BattleUnit, o: BattleUnit) -> int:
	var eff: Dictionary = DB.skill(att.basic)["effects"][0]
	var hp := float(o.max_hp())
	var d := o.max_def()
	var n := 0
	while hp > 0.0 and n < 40:
		var r := Rules.apply_defense(att.stat("attack") * float(eff.get("mult", 1.0)), d, float(eff.get("pierce", 0.0)))
		hp -= float(r["damage"])
		d -= float(r["wear"])
		n += 1
	return n


func test_a_quest_of_n_skulls_hits_like_level_n():
	## The blows of a skull-N brigand against level-N members, and back.
	for level in [1, 3, 5, 7]:
		var e := BattleFactory.enemy_unit("brigand", level, 0, rng, 1)
		for cls in ["ranger", "mystic"]:
			assert_between(_hits_to_drop(e, _reference(cls, level)), 1, 3, "a level-%d %s falls in 1-3 hits" % [level, cls])
		assert_between(_hits_to_drop(e, _reference("warrior", level, "guardian")), 3, 7, "a level-%d Guardian takes 3-7 hits" % level)
		assert_between(_hits_to_drop(_reference("warrior", level, "warlord"), e), 3, 5, "the brigand takes 3-5 hits at skull %d" % level)
