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


func test_conflicting_missions_cancel_each_other():
	var c := _new()
	var ma := c._make_mission("rivalry", "coast", "saltborn")
	var mb := c._make_mission("rivalry", "dunes", "glass")
	ma["conflict"] = mb["id"]
	mb["conflict"] = ma["id"]
	ma["rival"] = "glass"
	c.board = [ma, mb]
	var squad := c.available_members(1).slice(0, 4)
	var b := BattleFactory.build(ma, squad, c.battle_context(ma))
	b.result = "victory"
	b.over = true
	c.finish_mission(ma, b)
	assert_eq(c.board.size(), 0, "taking one rivalry mission removes the other")
	assert_eq(int(c.factions["saltborn"]["power"]), 6)
	assert_eq(int(c.factions["glass"]["power"]), 4)


func test_carried_out_corpse_stays_dead():
	var c := _new()
	var ma := c._make_mission("rivalry", "coast", "saltborn")
	ma["rival"] = "glass"
	var squad := c.available_members(1).slice(0, 4)
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
		var picks := BattleFactory.pick_enemies(m, 4, rng, 0, {})
		assert_eq(picks[0], m["elite"], "the hunted %s waits in the battle" % m["elite"])
