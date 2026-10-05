extends GutTest


func _new(seed_value := 42) -> Campaign:
	var c := Campaign.new()
	c.new_game("Test Guild", 1, false, seed_value)
	return c


func test_new_game_roster():
	var c := _new()
	assert_eq(c.roster.size(), 4)
	var classes := []
	var skilled := 0
	for m in c.roster:
		classes.append(m.cls)
		if m.tier == 2:
			skilled += 1
	classes.sort()
	assert_eq(classes, ["mystic", "ranger", "rogue", "warrior"])
	assert_eq(skilled, 1, "exactly one Skilled starter")
	assert_between(c.board.size(), 3, 10)
	assert_gt(c.recruits.size(), 0)


func test_week_costs_wages_and_raises_hush():
	var c := _new()
	var g := c.gold
	var h := c.hush
	var wages := c.weekly_wages()
	c.board.clear()
	c.end_week()
	assert_eq(c.gold, g - wages)
	assert_eq(c.hush, h + 2)
	assert_eq(c.week, 2)


func test_ignored_breach_raises_hush():
	var c := _new()
	c.board = [c._make_mission("breach", "coast")]
	var add: int = c.board[0]["ignore"]["hush"]
	var h := c.hush
	c.end_week()
	assert_eq(c.hush, h + 2 + add)


func test_ignored_crisis_costs_power():
	var c := _new()
	c.board = [c._make_mission("crisis", "ember", "rootwardens")]
	c.end_week()
	assert_eq(int(c.factions["rootwardens"]["power"]), 4)


func test_collapse_raises_hush_and_two_collapses_lose():
	var c := _new()
	c.board.clear()
	c.factions["glass"]["power"] = 0
	var h := c.hush
	c.end_week()
	assert_true(c.factions["glass"]["collapsed"])
	assert_gte(c.hush, h + 15)
	c.factions["saltborn"]["power"] = 0
	c.board.clear()
	c.end_week()
	assert_eq(c.game_over, "factions")


func test_unpaid_wages_three_weeks_lose():
	var c := _new()
	for i in 3:
		c.gold = 0
		c.board.clear()
		c.end_week()
	assert_true(c.game_over in ["wages", "roster"])


func test_hush_100_loses():
	var c := _new()
	c.hush = 99
	c.board.clear()
	c.end_week()
	assert_eq(c.game_over, "hush")


func test_save_roundtrip():
	var c := _new()
	c.end_week()
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := Campaign.from_dict(d)
	assert_eq(c2.week, c.week)
	assert_eq(c2.gold, c.gold)
	assert_eq(c2.roster.size(), c.roster.size())
	assert_eq(c2.board.size(), c.board.size())
	assert_eq(c2.roster[0].stats(), c.roster[0].stats())


func test_story_mission_appears_week_one():
	var c := _new()
	var found := false
	for m in c.board:
		if m.get("story_id", "") == "s1":
			found = true
	assert_true(found, "The Bell-Thief is on the first board")


func test_named_recruit_event():
	var c := _new()
	var before := c.roster.size()
	var gold := c.gold
	c.resolve_event("named_hesk", 0)
	assert_eq(c.gold, gold - 60, "the event choice costs gold")
	assert_eq(c.roster.size(), before + 1, "the named recruit joins")
	var m: Member = c.roster[-1]
	assert_eq(m.name, "Old Hesk")
	assert_eq(m.race, "tidefolk")
	assert_eq(m.cls, "warrior")
	assert_true("iron_skin" in m.traits and "brave" in m.traits, "fixed traits")
	assert_eq(m.level, 5)


func _fill_barracks(c: Campaign) -> void:
	var rng := RandomNumberGenerator.new()
	while c.active_members().size() < c.roster_cap():
		c.add_member(Member.create(rng, "warrior", "human", 1, 1, c.week))


func test_owed_recruits_wait_at_the_bar_until_hired():
	var c := _new()
	_fill_barracks(c)
	c.resolve_event("named_hesk", 0)
	var hesk: Member = null
	for r in c.recruits:
		if r.name == "Old Hesk":
			hesk = r
	assert_not_null(hesk, "with the barracks full, Hesk waits in the tavern")
	assert_true(hesk.waits)
	for i in 3:
		c.board.clear()
		c.gold = 5000
		c.end_week()
	assert_true(hesk in c.recruits, "still waiting weeks later")
	c = Campaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	hesk = null
	for r in c.recruits:
		if r.name == "Old Hesk":
			hesk = r
	assert_not_null(hesk, "the wait survives a save")
	assert_true(hesk.waits)
	c.dismiss(c.active_members()[0])
	assert_eq(c.hire(hesk), "", "free to hire once there is room")
	assert_false(hesk.waits)
	assert_false(hesk in c.recruits)


func test_chain_champion_waits_when_the_barracks_are_full():
	var c := _new()
	_fill_barracks(c)
	c.factions["saltborn"]["rep"] = 3
	c.factions["saltborn"]["chain"] = 1
	var m := c._make_mission("chain", "coast", "saltborn")
	m["chain_step"] = 1
	var rep := _won(c, m, c.available_members().slice(0, 4))
	assert_string_contains(rep["recruit"], "Tidecaller")
	c.board.clear()
	c.end_week()
	var champion: Member = null
	for r in c.recruits:
		if r.cls == "tidecaller" and r.waits:
			champion = r
	assert_not_null(champion, "the champion is not lost when the week ends")
	assert_eq(champion.hire_cost, 0)
	var said: String = " ".join(rep["faction"])
	assert_string_contains(said, "As long as they stay Allied")


func test_allies_send_their_unique_class_to_the_tavern():
	var c := _new()
	c.factions["lantern"]["rep"] = 3
	var allied := 0
	var weeks := 200
	for i in weeks:
		c.roll_recruits()
		for r in c.recruits:
			assert_false(r.cls in ["tidecaller", "graftwarden", "sandreaver"], "only allies send their own class")
			if r.cls == "lanternbearer":
				assert_eq(r.race, "mothkin")
				assert_gt(r.hire_cost, 0, "an ordinary recruit: they still cost a fee")
				assert_false(r.waits, "and leaves with the week like any other")
				allied += 1
	assert_between(allied, int(weeks * 0.15), int(weeks * 0.35), "about one week in four")
	c.factions["lantern"]["rep"] = 2
	for i in 50:
		c.roll_recruits()
		for r in c.recruits:
			assert_ne(r.cls, "lanternbearer", "Trusted is not enough")


func test_conflicting_missions_cancel_each_other():
	var c := _new()
	var ma := c._make_mission("rivalry", "coast", "saltborn")
	var mb := c._make_mission("rivalry", "dunes", "glass")
	ma["conflict"] = mb["id"]
	mb["conflict"] = ma["id"]
	ma["rival"] = "glass"
	c.board = [ma, mb]
	var squad := c.available_members().slice(0, 4)
	var b := BattleFactory.build(ma, squad, c.battle_context(ma))
	b.result = "victory"
	b.over = true
	c.finish_mission(ma, b)
	assert_eq(c.board.size(), 0, "taking one rivalry mission removes the other")
	assert_eq(int(c.factions["saltborn"]["power"]), 6)
	assert_eq(int(c.factions["glass"]["power"]), 4)


func _won(c: Campaign, m: Dictionary, squad: Array) -> Dictionary:
	var b := BattleFactory.build(m, squad, c.battle_context(m))
	b.result = "victory"
	b.over = true
	c.board.append(m)
	return c.finish_mission(m, b)


func test_the_guild_shares_seven_days_a_week():
	var c := _new()
	var squad := c.available_members().slice(0, 2)
	var m1 := c._make_mission("contract", "carrow")
	m1["days"] = 3
	var m2 := c._make_mission("contract", "carrow")
	m2["days"] = 3
	var m3 := c._make_mission("contract", "carrow")
	m3["days"] = 2
	_won(c, m1, squad)
	assert_eq(c.days_left(), 4)
	# other members, same clock: who goes does not matter
	var others := c.available_members().filter(func(x): return not x in squad)
	assert_eq(c.can_launch(m2, others), "")
	_won(c, m2, others)
	assert_eq(c.days_left(), 1)
	assert_ne(c.can_launch(m3, squad), "", "a 2-day mission no longer fits the week")
	c.end_week()
	assert_eq(c.days_left(), Campaign.WEEK_DAYS, "a new week, a new seven days")


func test_mission_lengths_fit_two_to_four_a_week():
	for cat in DB.missions["categories"]:
		var d: Array = DB.missions["categories"][cat]["days"]
		assert_between(int(d[0]), 1, 4, "%s is 1-4 days" % cat)
		assert_between(int(d[1]), 1, 4, "%s is 1-4 days" % cat)
	for sid in DB.story["missions"]:
		assert_between(int(DB.story["missions"][sid]["days"]), 1, 4, "%s is 1-4 days" % sid)


func test_enemy_count_ignores_the_squad_size():
	var c := _new()
	var m := c._make_mission("contract", "carrow")
	m["objective"] = "clear"
	var counts: Array = []
	for n in [1, 4]:
		var b := BattleFactory.build(m, c.available_members().slice(0, n), c.battle_context(m))
		counts.append(b.team_units(BattleUnit.TEAM_ENEMY, false).size())
	assert_eq(counts[0], counts[1], "a lone member faces the same force as a full squad")


func test_heavy_wounds_can_injure_even_when_healed():
	assert_eq(Rules.wound_chance(10, 40), 0.0, "a quarter of the HP lost is nothing")
	assert_almost_eq(Rules.wound_chance(20, 40), 0.2, 0.001)
	assert_almost_eq(Rules.wound_chance(40, 40), 0.5, 0.001)
	assert_almost_eq(Rules.wound_chance(400, 40), 0.8, 0.001, "never certain")
	var c := _new()
	var m := c._make_mission("contract", "carrow")
	var squad := c.available_members().slice(0, 4)
	var b := BattleFactory.build(m, squad, c.battle_context(m))
	var hurt := 0
	for u in b.units:
		if u.team == BattleUnit.TEAM_PLAYER and u.member != null:
			u.hp_lost = u.max_hp() * 3   # beaten down and healed back up, again and again
	b.result = "victory"
	b.over = true
	var rep := c.finish_mission(m, b)
	for mem in squad:
		if not mem.injury.is_empty():
			hurt += 1
			assert_eq(mem.injury["kind"], "light")
			assert_eq(rep["injuries"][mem.id]["cause"], "wounds")
	assert_gt(hurt, 0, "80% each: someone in four gets hurt")


## Every member of the squad Downed in `trials` won quests; how many came home injured.
func _downed_injuries(c: Campaign, trials: int) -> int:
	var squad := c.available_members().slice(0, 4)
	var hurt := 0
	for i in trials:
		var m := c._make_mission("contract", "carrow")
		var b := BattleFactory.build(m, squad, c.battle_context(m))
		for u in b.units:
			if u.team == BattleUnit.TEAM_PLAYER and u.member != null:
				u.was_downed = true
		b.result = "victory"
		b.over = true
		c.finish_mission(m, b)
		for mem in squad:
			if not mem.injury.is_empty():
				hurt += 1
				mem.injury = {}
	return hurt


func test_top_nursery_spares_a_quarter_of_new_injuries():
	var c := _new()
	c.facilities["nursery"] = 2
	assert_eq(c.nursery_weeks(), 2)
	assert_eq(_downed_injuries(c, 2), 8, "below level 3 the Downed are always injured")
	c.facilities["nursery"] = 3
	assert_eq(c.nursery_weeks(), 2, "level 3 takes no extra week off")
	var hurt := _downed_injuries(c, 10)
	assert_between(hurt, 20, 39, "about three in four of 40 Downed are injured")


func test_battle_counts_hp_lost_through_healing():
	var c := _new()
	var m := c._make_mission("contract", "carrow")
	var b := BattleFactory.build(m, c.available_members().slice(0, 1), c.battle_context(m))
	var u: BattleUnit = b.team_units(BattleUnit.TEAM_PLAYER)[0]
	b.start()
	b._apply_damage(u, 10, null)
	b._heal(u, 10, null)
	b._apply_damage(u, 10, null)
	assert_eq(u.hp_lost, 20, "healing does not erase the wounds already taken")


func test_carried_out_corpse_stays_dead():
	var c := _new()
	var ma := c._make_mission("rivalry", "coast", "saltborn")
	ma["rival"] = "glass"
	var squad := c.available_members().slice(0, 4)
	var b := BattleFactory.build(ma, squad, c.battle_context(ma))
	var victim: BattleUnit = null
	for u in b.units:
		if u.team == BattleUnit.TEAM_PLAYER and u.member != null:
			victim = u
			break
	b.start()
	b._apply_damage(victim, victim.max_hp() * 5, null)
	assert_eq(victim.state, "dead", "overkill kills outright")
	victim.state = "recovered"   # what do_extract sets on a carried corpse
	b._finish("victory")
	assert_false(b.bonus[0]["done"], "a death breaks the no-downs bonus")
	var rep := c.finish_mission(ma, b)
	assert_eq(victim.member.status, "dead")
	assert_true(victim.member.name in rep["deaths"])
	assert_false(victim.member.name in rep["lost_items"], "carried out, so the gear comes home")


func test_simulated_campaign_runs():
	## An autopilot plays 20 weeks with AI battles to catch crashes and
	## sanity-check the economy.
	for seed_value in [7, 11]:
		var c := _new(seed_value)
		var bot := AutoPilot.new(c)
		var weeks := 0
		while c.game_over == "" and weeks < 30:
			weeks += 1
			bot.play_week(3, true)
			if weeks % 5 == 0:
				gut.p("  w%d gold %d renown %d hush %d roster %d dead %d act %d lvl %.1f story %s" % [c.week, c.gold, c.renown, c.hush, c.active_members().size(), c.dead.size(), c.act, bot._avg_level(), str(c.story_done.keys())])
		gut.p("autopilot seed %d: week %d, gold %d, renown %d, hush %d, roster %d, dead %d, over '%s', ending '%s', act %d, battles %d won %d" % [seed_value, c.week, c.gold, c.renown, c.hush, c.roster.size(), c.dead.size(), c.game_over, c.ending, c.act, bot.battles, bot.wins])
		gut.p("  facilities %s factions %s" % [str(c.facilities), str(c.factions)])
		assert_gt(weeks, 3)


func test_every_board_mission_has_a_letter():
	var c := _new(9)
	var shown := 0
	for week in 12:
		c.generate_board()
		for m in c.board:
			var l := MissionLore.letter(m, c.guild_name)
			assert_ne(String(l["body"]), "", "%s has a letter" % m["title"])
			assert_ne(String(l["client"]), "", "%s is signed" % m["title"])
			assert_false("{" in String(l["body"]), "no unfilled placeholder: %s" % l["body"])
			assert_eq(MissionLore.letter(m, c.guild_name)["body"], l["body"], "the same letter every time")
			if m["objective"] == "hunt" and m.has("elite"):
				assert_true(DB.enemies.has(m["elite"]), "the hunt names a real enemy")
			if shown < 6 and m["category"] != "story":
				shown += 1
				gut.p("  %s [%s/%s] %s %s | %s" % [m["title"], m["category"], m["objective"], l["greeting"], l["body"], l["client"]])
	for sid in ["s1", "s2", "s3", "s4", "s5", "s6", "final"]:
		assert_true(DB.story["missions"][sid].has("letter"), "%s has a hand-written letter" % sid)


func test_hunt_target_matches_the_board():
	var c := _new(5)
	var rng := RandomNumberGenerator.new()
	for i in 20:
		var m: Dictionary = c._make_mission("contract", "ember")
		m["objective"] = "hunt"
		rng.seed = i
		var picks := BattleFactory.pick_enemies(m, rng, 0, {})
		assert_eq(picks[0], m["elite"], "the hunted %s waits in the battle" % m["elite"])
