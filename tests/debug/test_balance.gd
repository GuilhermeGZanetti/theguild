extends GutTest
## Balance tables for tuning (run manually, prints only):
##   godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit -gtest=res://tests/debug/test_balance.gd
## The targets: a skull-N quest is a hard fight for four level-N members;
## Rangers and Mystics drop in 1-3 hits, a Guardian Warrior takes 3-5, and
## an ordinary enemy takes 4-6 hits from a member of its level.

var rng := RandomNumberGenerator.new()

const CLASSES := ["warrior", "rogue", "ranger", "mystic"]
## The region a squad of this level is usually sent to.
const REGION_AT := {1: "carrow", 2: "coast", 3: "stilts", 4: "ember", 5: "dunes", 6: "coast", 7: "unremembered"}


## Gear a member of this level usually carries: Worn at 1-2, Steel at 3-4,
## Masterwork at 5-6, Relic at 7.
static func gear_tier(level: int) -> int:
	return clampi(1 + (level - 1) / 2, 1, 4)


func _gear(m: Member) -> void:
	var t := gear_tier(m.level)
	m.equipment["weapon"] = Items.weapon(m.class_data()["weapon_family"], t)
	m.equipment["armor"] = Items.armor(m.class_data()["armor_family"], t)


## An average Normal member: average potential, no traits.
func _reference(cls: String, level: int, branch := "", race := "human") -> Member:
	var m := Member.create(rng, cls, race, 1, 1)
	m.traits = []
	for k in Member.GROWTH_STATS:
		m.potential[k] = 2
	for i in level - 1:
		m._level_up(rng)
	m.auto_pick(rng, branch)
	if branch != "":
		# auto_pick strays from the branch now and then: the table wants it pure
		for row in m.tree_rows().size():
			var cur := m.row_pick(row + 2)
			if cur != "" and DB.branch_of(cur) != branch:
				m.swap_pick(row + 2)
	_gear(m)
	return m


func _squad(level: int, size := 4) -> Array:
	var squad: Array = []
	for i in size:
		var m := Member.create(rng, CLASSES[i % CLASSES.size()], "human", 1, level)
		m.id = i + 1
		m.auto_pick(rng)
		_gear(m)
		squad.append(m)
	return squad


## Basic attacks from `att` until `o` drops, at average damage, no crits.
func _hits(att: BattleUnit, o: BattleUnit) -> int:
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


func test_hits_table():
	for level in [1, 2, 3, 4, 5, 6, 7]:
		rng.seed = 4242 + level
		var cols := {"warrior": _reference("warrior", level, "warlord"), "guardian": _reference("warrior", level, "guardian"),
			"rogue": _reference("rogue", level), "ranger": _reference("ranger", level), "mystic": _reference("mystic", level)}
		var units := {}
		var head := "skull %d vs level %d   " % [level, level]
		for k in cols:
			units[k] = BattleFactory.member_unit(cols[k])
			var u: BattleUnit = units[k]
			head += "%-9s" % ("%s %d/%d" % [k.substr(0, 4), u.max_hp(), int(u.max_def())])
		gut.p(head + "  | hits to kill it: war rog ran mys | it hits ranger%%")
		for eid in DB.enemies:
			var d: Dictionary = DB.enemies[eid]
			if d.get("npc", false) or d.get("boss", false):
				continue
			var e := BattleFactory.enemy_unit(eid, level, 0, rng, 1)
			var row := "  %-20s" % ("%s %d/%d/%d" % [eid.substr(0, 12), e.max_hp(), int(e.max_def()), int(e.stat("attack"))])
			for k in cols:
				row += "%-9d" % _hits(e, units[k])
			row += "  |                 "
			for k in ["warrior", "rogue", "ranger", "mystic"]:
				row += "%-4d" % _hits(units[k], e)
			var ranger: BattleUnit = units["ranger"]
			row += "| %d%%  spd %d vs %d" % [Rules.hit_chance(e.stat("accuracy"), ranger.stat("dodge"), 0, false, false), int(e.stat("speed")), int(ranger.stat("speed"))]
			gut.p(row)
	assert_true(true)


func _batch(label: String, mission: Dictionary, level: int, n := 16, size := 4, ctx := {}) -> void:
	var res := {}
	var rounds := 0.0
	var downs := 0.0
	var deaths := 0.0
	var enemies := 0.0
	var first := 0.0
	var firsts := 0.0
	for i in n:
		rng.seed = 1000 + i * 17 + level * 101
		var m := mission.duplicate(true)
		m["seed"] = rng.randi()
		var c := ctx.duplicate()
		c["difficulty"] = 1
		var b := BattleFactory.build(m, _squad(level, size), c)
		for u in b.units:
			if u.team == BattleUnit.TEAM_ENEMY:
				enemies += 1
		# who acts in the first turns of combat
		var seen := 0
		var guard := 0
		while not b.over and guard < 900:
			guard += 1
			b.auto_step()
			for e in b.pop_events():
				if seen < 4 and e.get("t", "") == "turn" and not e.get("quiet", false):
					var u := b.unit(int(e["uid"]))
					if u != null and not u.npc:
						seen += 1
						firsts += 1
						if u.team == BattleUnit.TEAM_ENEMY:
							first += 1
		if not b.over:
			b._finish("retreat")
		res[b.result] = int(res.get(b.result, 0)) + 1
		rounds += b.round_num
		downs += b.downs
		deaths += b.deaths
	var wins := float(res.get("victory", 0)) / n
	gut.p("%-22s lvl %d: win %3d%%  downs %.2f deaths %.2f rounds %4.1f enemies %4.1f enemy-first %2d%%  %s" % [label, level, roundi(wins * 100), downs / n, deaths / n, rounds / n, enemies / n, roundi(100.0 * first / maxf(firsts, 1)), str(res)])


## Filters for running slices in parallel processes: BAL_LEVELS="1,2",
## BAL_OBJ="clear,hunt,defense", BAL_REGIONS="carrow,coast", BAL_OFFSETS="0"
## (skulls minus level), BAL_N="12", BAL_SIZE="5" (squad size; the Barracks
## sends five from level 2 and six from level 3).
func _env_list(key: String, fallback: Array) -> Array:
	var v := OS.get_environment(key)
	if v == "":
		return fallback
	var out: Array = []
	for p in v.split(","):
		out.append(int(p) if p.is_valid_int() else p)
	return out


func test_battle_table():
	var n := int(_env_list("BAL_N", [12])[0])
	var size := int(_env_list("BAL_SIZE", [4])[0])
	for level in _env_list("BAL_LEVELS", [1, 2, 3, 4, 5, 6, 7]):
		for obj in _env_list("BAL_OBJ", ["clear", "hunt", "defense"]):
			for region in _env_list("BAL_REGIONS", [REGION_AT[level]]):
				for off in _env_list("BAL_OFFSETS", [-1, 0, 1] if obj == "clear" else [0]):
					var sk: int = level + off
					if sk < 1 or sk > Rules.MAX_SKULLS:
						continue
					var m := {"region": region, "objective": obj, "skulls": sk, "par_rounds": 8, "turns": 5 + (sk + 1) / 2}
					_batch("%s %s sk%d x%d" % [region, obj, sk, size], m, level, n, size)
	assert_true(true)


func test_story_table():
	var size := int(_env_list("BAL_SIZE", [4])[0])
	for sid in _env_list("BAL_STORY", ["s1", "s2", "s3", "s4", "s5", "s6", "final"]):
		var s: Dictionary = DB.story["missions"][sid]
		var m := {"region": s["region"], "objective": s["objective"], "skulls": int(s["skulls"]), "category": "story",
			"turns": int(s.get("turns", 6)), "caches": int(s.get("caches", 3)), "par_rounds": 9,
			"hush_map": int(s.get("hush_map", 0))}
		for k in ["boss", "enemies", "biome", "elite_count"]:
			if s.has(k):
				m[k] = s[k]
		_batch("story %s x%d" % [sid, size], m, int(s["skulls"]), 12, size)
		if sid == "final":
			_batch("story final, 1 ally x%d" % size, m, int(s["skulls"]), 12, size, {"allied_factions": ["saltborn"]})
	assert_true(true)


## Every class tree side by side. Squads of four trees drawn so each tree
## fights equally often (pure branch, average potential, the five
## highest-level active skills carried), against a quest of their level, in
## every region and objective. Prints one TREE line of sums per tree so slices
## run in parallel can be merged: BAL_LEVELS="3,5,7" BAL_N="96" (battles per
## level) BAL_PARTS="2" BAL_PART="0". SKILL lines count each skill's uses.
const TREE_REGIONS := ["carrow", "coast", "stilts", "ember", "dunes", "unremembered"]
const TREE_KEYS := ["dealt", "ff", "taken", "blocked", "dodged", "healed", "kills", "cc", "buffs"]


func _tree_member(cls: String, branch: String, level: int, id: int) -> Member:
	var m := _reference(cls, level, branch, DB.classes[cls].get("race", "human"))
	m.id = id
	var acts := m.active_skills()
	acts.sort_custom(func(a, b): return int(DB.skill(a).get("level", 1)) > int(DB.skill(b).get("level", 1)))
	m.loadout = acts.slice(0, Member.LOADOUT)
	return m


func test_tree_table():
	var trees: Array = []
	for cls in DB.classes:
		for br in DB.classes[cls]["branches"]:
			trees.append("%s/%s" % [cls, br])
	var n := int(_env_list("BAL_N", [64])[0])
	var parts := int(_env_list("BAL_PARTS", [1])[0])
	var part := int(_env_list("BAL_PART", [0])[0])
	var per := trees.size() / 4
	for level in _env_list("BAL_LEVELS", [3, 5, 7]):
		var sums := {}
		for tr in trees:
			sums[tr] = {"n": 0, "wins": 0, "downed": 0, "dead": 0}
		for i in n:
			if i % parts != part:
				continue
			# one shuffle of every tree feeds `per` battles
			var perm := trees.duplicate()
			var shuf := RandomNumberGenerator.new()
			shuf.seed = 7000 + level * 131 + (i / per) * 17
			for k in range(perm.size() - 1, 0, -1):
				var j := shuf.randi_range(0, k)
				var tmp = perm[k]
				perm[k] = perm[j]
				perm[j] = tmp
			var picks: Array = perm.slice((i % per) * 4, (i % per) * 4 + 4)
			rng.seed = 9000 + level * 101 + i * 13
			var squad: Array = []
			for k in picks.size():
				var parts_tr: PackedStringArray = picks[k].split("/")
				squad.append(_tree_member(parts_tr[0], parts_tr[1], level, k + 1))
			var m := {"region": TREE_REGIONS[(i / 3) % TREE_REGIONS.size()], "objective": ["clear", "hunt", "defense"][i % 3],
				"skulls": level, "par_rounds": 8, "turns": 5 + (level + 1) / 2, "seed": rng.randi()}
			var b := BattleFactory.build(m, squad, {"difficulty": 1})
			var guard := 0
			while not b.over and guard < 1500:
				guard += 1
				b.auto_step()
				b.pop_events()
			if not b.over:
				b._finish("retreat")
			for u in b.units:
				if u.team != BattleUnit.TEAM_PLAYER or u.npc or not u.member in squad:
					continue
				var tr: String = picks[squad.find(u.member)]
				var row: Dictionary = sums[tr]
				row["n"] += 1
				row["wins"] += 1 if b.result == "victory" else 0
				row["downed"] += 1 if u.was_downed else 0
				row["dead"] += 1 if u.state == "dead" else 0
				for k in TREE_KEYS:
					var v: int = u.hp_lost if k == "taken" else int(u.tally.get(k, 0))
					row[k] = int(row.get(k, 0)) + v
				for k in u.tally:
					if k.begins_with("use:"):
						row[k] = int(row.get(k, 0)) + int(u.tally[k])
		for tr in trees:
			var row: Dictionary = sums[tr]
			var line := "TREE|%d|%s|%d|%d|%d|%d" % [level, tr, row["n"], row["wins"], row["downed"], row["dead"]]
			for k in TREE_KEYS:
				line += "|%d" % int(row.get(k, 0))
			gut.p(line)
			for k in row:
				if k.begins_with("use:"):
					gut.p("SKILL|%d|%s|%s|%d" % [level, tr, k.substr(4), int(row[k])])
	assert_true(true)
