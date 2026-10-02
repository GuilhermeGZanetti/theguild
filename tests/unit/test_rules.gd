extends GutTest


func test_turn_delay_matches_gdd():
	assert_almost_eq(Rules.turn_delay(50), 10.0, 0.001)
	assert_almost_eq(Rules.turn_delay(30), 12.5, 0.001)
	assert_true(Rules.turn_delay(80) < Rules.turn_delay(20), "faster units act sooner")


func test_hit_chance_is_clamped():
	assert_eq(Rules.hit_chance(200, 0, 0, false, false), 95)
	assert_eq(Rules.hit_chance(10, 90, 2, false, false), 5)


func test_hit_chance_modifiers():
	# 70 acc vs 10 dodge = 60
	assert_eq(Rules.hit_chance(70, 10, 0, false, false), 60)
	assert_eq(Rules.hit_chance(70, 10, 1, false, false), 40, "half cover -20")
	assert_eq(Rules.hit_chance(70, 10, 2, false, false), 20, "full cover -40")
	assert_eq(Rules.hit_chance(70, 10, 0, true, false), 70, "high ground +10")
	assert_eq(Rules.hit_chance(70, 10, 0, false, true), 75, "flank +15")
	assert_eq(Rules.hit_chance(70, 10, 0, false, false, 2), 40, "-10 per tile beyond optimal")


func test_status_chance_formula():
	# Base + 5 x (Lvl_att - Lvl_tgt) - Resolve/4
	assert_eq(Rules.status_chance(60, 3, 1, 40), 60 + 10 - 10)
	assert_eq(Rules.status_chance(10, 1, 9, 100), 5, "clamped to 5")
	assert_eq(Rules.status_chance(100, 1, 9, 100), 100, "guaranteed effects stay guaranteed")


func test_defense_subtracts_and_wears():
	var r := Rules.apply_defense(20.0, 8.0)
	assert_eq(r["damage"], 12)
	assert_almost_eq(float(r["wear"]), 20.0 * Rules.ARMOR_WEAR, 0.001)
	var r2 := Rules.apply_defense(5.0, 30.0)
	assert_eq(r2["damage"], 1, "a hit always deals at least 1")
	var r3 := Rules.apply_defense(20.0, 8.0, 0.5)
	assert_eq(r3["damage"], 16, "pierce ignores part of Defense")


func test_raw_damage_variance():
	assert_almost_eq(Rules.raw_damage(20, 1.0, 1.0), 22.0, 0.001)
	assert_almost_eq(Rules.raw_damage(20, 1.0, -1.0), 18.0, 0.001)


func test_grades():
	assert_eq(Rules.grade(false, 3, 3, 1, 10, 0, 0), "D")
	assert_eq(Rules.grade(true, 3, 3, 4, 8, 0, 0), "S")
	assert_true(Rules.grade(true, 0, 3, 20, 8, 2, 3) in ["C", "D"])


func test_hush_stages():
	assert_eq(Rules.hush_stage(0), 0)
	assert_eq(Rules.hush_stage(25), 1)
	assert_eq(Rules.hush_stage(50), 2)
	assert_eq(Rules.hush_stage(75), 3)
	assert_eq(Rules.hush_stage(100), 4)


func test_skulls_follow_the_calendar():
	assert_almost_eq(Rules.expected_level(1), 1.0, 0.001)
	assert_between(Rules.expected_level(5), 4.0, 4.5, "two quests a week: level 4 by week 5")
	assert_almost_eq(Rules.expected_level(30), float(Rules.MAX_SKULLS), 0.001, "never past the level cap")
	for week in range(1, 31):
		var lo := Rules.quest_skulls(week, 0.0)
		var mid := Rules.quest_skulls(week, 0.5)
		var hi := Rules.quest_skulls(week, 0.99)
		assert_true(lo <= mid and mid <= hi, "easier rolls give fewer skulls")
		assert_between(lo, 1, Rules.MAX_SKULLS)
		assert_between(hi, 1, Rules.MAX_SKULLS)
		assert_lte(hi - mid, 1, "at most one skull past the week's level")
	assert_eq(Rules.quest_skulls(1, 0.5), 1, "week one: one-skull quests for level-1 members")
	assert_eq(Rules.quest_skulls(16, 0.5), Rules.MAX_SKULLS, "the end of a campaign: level-7 danger")
	assert_lte(Rules.quest_skulls(16, 0.0), 5, "late weeks still post easier quests")
