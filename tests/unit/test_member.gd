extends GutTest

var rng := RandomNumberGenerator.new()


func before_each():
	rng.seed = 1234


func test_create_member_has_class_stats():
	var m := Member.create(rng, "warrior", "human", 1)
	var s := m.stats()
	assert_gt(int(s["hp"]), 40)
	assert_eq(int(s["range"]), 1)
	assert_true(m.skills.has("shield_bash"))
	assert_between(m.traits.size(), 1, 3)
	assert_ne(m.variant, "")


func test_tier_scales_stats():
	var lo := 0.0
	var hi := 0.0
	for i in 20:
		lo += float(Member.create(rng, "rogue", "human", 0).stats()["attack"])
		hi += float(Member.create(rng, "rogue", "human", 3).stats()["attack"])
	assert_gt(hi, lo, "genius recruits hit harder than mediocre ones")


func test_level_up_opens_a_tree_row_and_grows():
	var m := Member.create(rng, "ranger", "human", 1)
	var before := float(m.stats()["accuracy"])
	var ups := m.add_xp(DB.xp_to_next(1) + DB.xp_to_next(2) + DB.xp_to_next(3), rng)
	assert_eq(ups.size(), 3)
	assert_eq(m.level, 4)
	assert_eq(m.pending_picks(), 3, "one skill choice per level gained")
	assert_gt(float(m.stats()["accuracy"]), before)


func test_xp_curve_is_one_three_five_seven_quests():
	for l in range(1, 5):
		assert_eq(DB.xp_to_next(l), DB.QUEST_XP * (2 * l - 1))
	# one ordinary quest's share for a full squad levels a recruit exactly once
	assert_eq(Rules.xp_share(1, 4, 4), DB.QUEST_XP)


func test_every_class_has_two_nine_skill_trees():
	for cid in DB.classes:
		var rows := DB.tree_rows(cid)
		assert_eq(rows.size(), 9, "%s has 9 rows" % cid)
		for i in rows.size():
			assert_eq(rows[i].size(), 2, "%s row %d has one skill per branch" % [cid, i + 2])
			for s in rows[i]:
				assert_eq(int(DB.skill(s).get("level", 0)), i + 2, "%s sits in row %d" % [s, i + 2])
				assert_eq(DB.skill(s).get("class", ""), cid)


func test_one_skill_per_row():
	var m := Member.create(rng, "warrior", "human", 1, 3)
	var pair := m.row_skills(2)
	assert_eq(m.pick(pair[0]), "")
	assert_ne(m.pick(pair[1]), "", "the other skill of the row is locked out")
	assert_ne(m.pick(m.tree_rows()[2][0]), "", "rows above the level are locked")
	assert_eq(m.pick(m.row_skills(3)[1]), "", "branches can be mixed across rows")
	assert_eq(m.pending_picks(), 0)
	assert_eq(m.swap_pick(2), "")
	assert_true(pair[1] in m.skills and not pair[0] in m.skills, "retraining swaps the row")


func test_capstone_grants_title():
	var m := Member.create(rng, "mystic", "human", 1, DB.LEVEL_CAP)
	m.auto_pick(rng, "restoration")
	assert_eq(m.pending_picks(), 0)
	var cap := m.row_pick(DB.LEVEL_CAP)
	assert_eq(m.subclass, DB.classes["mystic"]["branches"][DB.branch_of(cap)]["title"])
	assert_true(m.loadout.size() <= Member.LOADOUT)


func test_old_saves_migrate_to_the_new_curve():
	var m := Member.create(rng, "rogue", "human", 1, 1)
	var d := m.to_dict()
	d["level"] = 9
	d.erase("prog")
	d["xp"] = 0
	d["skills"] = d["skills"] + ["poisoned_blade", "shadowstep", "flurry"]
	var old := Member.from_dict(d)
	assert_between(old.level, 2, 4, "old level 9 is a handful of quests")
	assert_eq(old.prog, Member.PROGRESSION)
	assert_false("poisoned_blade" in old.skills and "shadowstep" in old.skills, "never two skills of one row")


func test_level_cap():
	var m := Member.create(rng, "mystic", "human", 1)
	m.add_xp(999999, rng)
	assert_eq(m.level, DB.LEVEL_CAP)


func test_traits_never_conflict():
	for i in 200:
		var m := Member.create(rng, "warrior", "human", rng.randi() % 4)
		for pair in Member.CONFLICTS:
			assert_false(pair[0] in m.traits and pair[1] in m.traits, "conflicting traits %s" % str(pair))


func test_injury_and_nursery():
	var m := Member.create(rng, "warrior", "human", 1)
	m.traits = []
	var r := m.injure("light", rng, 0.0)
	assert_eq(int(r["weeks"]), 1)
	m.injure("serious", rng, 0.5)
	assert_between(int(m.injury["weeks"]), 1, 2)


func test_racial_traits_apply():
	var t := Member.create(rng, "warrior", "tidefolk", 1)
	assert_eq(int(t.mods().get("water_dodge", 0)), 10)
	var mk := Member.create(rng, "warrior", "mothkin", 1)
	assert_eq(int(mk.mods().get("sight", 0)), 3)


func test_serialization_roundtrip():
	var m := Member.create(rng, "rogue", "khepri", 2, 5)
	var d := m.to_dict()
	var m2 := Member.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(m2.name, m.name)
	assert_eq(m2.level, m.level)
	assert_eq(m2.stats()["attack"], m.stats()["attack"])
	assert_eq(m2.traits, m.traits)


func test_every_class_look_has_both_gendered_sprites():
	for race in Member.PLAYABLE:
		for cls in DB.classes:
			var c: Dictionary = DB.classes[cls]
			if c.has("race") and c["race"] != race:
				continue
			for g in ["m", "f"]:
				var v := Member.look_variant(race, c["look"], g)
				assert_true(DB.units.has(v), "sprite for " + v)


func test_members_get_a_gender_and_matching_sprite():
	var seen := {}
	for i in 30:
		var m := Member.create(rng, "warrior", "tidefolk", 1)
		assert_true(m.gender in ["m", "f"])
		assert_eq(m.variant, "tidefolk_warrior_" + m.gender)
		seen[m.gender] = true
	assert_eq(seen.size(), 2, "both genders are rolled")
	var h := Member.create(rng, "rogue", "human", 1)
	assert_true(h.variant.begins_with("human_rogue_%s_" % h.gender))


func test_old_saves_migrate_to_gendered_sprites():
	var m := Member.create(rng, "rogue", "human", 1)
	var d := m.to_dict()
	d.erase("gender")
	d["variant"] = "human_rogue_b"
	var back := Member.from_dict(d)
	assert_eq(back.variant, "human_rogue_m_a")
	assert_eq(back.gender, "m")
	assert_eq(Member.fix_variant("tidefolk_warrior"), "tidefolk_warrior_m")
	assert_eq(Member.fix_variant("mothkin_lanternbearer"), "mothkin_lanternbearer_f")
	assert_eq(Member.fix_variant("human_mystic_c"), "human_mystic_f_b")
	assert_eq(Member.fix_variant("khepri_rogue_f"), "khepri_rogue_f")
	assert_eq(Member.fix_variant("toad_brute"), "toad_brute")
