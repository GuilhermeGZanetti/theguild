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


func test_level_up_grants_skill_point_and_growth():
	var m := Member.create(rng, "ranger", "human", 1)
	var before := float(m.stats()["accuracy"])
	var ups := m.add_xp(5000, rng)
	assert_gt(ups.size(), 3)
	assert_eq(m.skill_points, ups.size())
	assert_gt(float(m.stats()["accuracy"]), before)


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
