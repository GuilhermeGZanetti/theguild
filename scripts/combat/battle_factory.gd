class_name BattleFactory
extends RefCounted
## Builds battles: units from guild members and enemy data, maps, objectives.


static func member_unit(m: Member, resolve_bonus: int = 0) -> BattleUnit:
	var u := BattleUnit.new()
	u.team = BattleUnit.TEAM_PLAYER
	u.member = m
	u.member_id = m.id
	u.name = m.name
	u.st = m.stats()
	u.st["resolve"] = mini(100, int(u.st["resolve"]) + resolve_bonus)
	u.hp = int(u.st["hp"])
	u.level = m.level
	u.mods = m.mods()
	var c: Dictionary = m.class_data()
	u.basic = c["basic"]
	u.melee = c.get("melee", true)
	u.skills = [u.basic]
	for s in m.loadout:
		if not s in u.skills and u.skills.size() < 5:
			u.skills.append(s)
	u.sprite = m.variant
	u.palette = m.palette
	u.def_regen = int(u.mods.get("def_regen", 0))
	u.ai = "melee" if u.melee else "ranged"
	return u


static func enemy_unit(eid: String, skulls: int, hush_level: int, rng: RandomNumberGenerator, difficulty: int = 1) -> BattleUnit:
	var d: Dictionary = DB.enemies[eid]
	var u := BattleUnit.new()
	u.team = BattleUnit.TEAM_ENEMY
	u.enemy_id = eid
	u.name = d["name"]
	var s: Dictionary = d["stats"].duplicate()
	var k := float(skulls - 1)
	var dm: float = [0.85, 1.0, 1.15][clampi(difficulty, 0, 2)]
	var hush_m := 1.0 + 0.05 * hush_level
	s["hp"] = roundi(float(s["hp"]) * (1.0 + 0.17 * k) * dm * hush_m)
	s["attack"] = roundi(float(s["attack"]) * (1.0 + 0.14 * k) * dm * hush_m)
	s["defense"] = roundi(float(s["defense"]) * (1.0 + 0.12 * k))
	s["accuracy"] = int(s["accuracy"]) + 3 * int(k)
	s["dodge"] = int(s["dodge"]) + int(k)
	s["resolve"] = mini(100, int(s["resolve"]) + 4 * int(k))
	u.st = s
	u.hp = int(s["hp"])
	u.level = 2 * skulls - 1 + (2 if d.get("elite", false) else 0) + (4 if d.get("boss", false) else 0)
	u.skills = d.get("skills", []).duplicate()
	u.basic = u.skills[0] if not u.skills.is_empty() else "e_claw"
	u.melee = d.get("melee", false)
	u.ai = d.get("ai", "melee")
	u.elite = d.get("elite", false)
	u.boss = d.get("boss", false)
	u.hush = d.get("hush", false)
	u.floats = d.get("float", false)
	u.swims = d.get("swims", false)
	u.npc = d.get("npc", false)
	u.sprite = d["sprite"]
	u.palette = d.get("palette", {})
	u.xp_value = int(d.get("xp", 12)) + 4 * int(k)
	u.skulls = skulls
	if eid in ["lantern_thief", "quietling"]:
		u.hidden = true
	if u.boss:
		u.mods["fearless"] = 1
	return u


static func echo_unit(md: Dictionary, skulls: int, rng: RandomNumberGenerator) -> BattleUnit:
	var m := Member.from_dict(md)
	var u := member_unit(m)
	u.team = BattleUnit.TEAM_ENEMY
	u.member = null
	u.member_id = -1
	u.echo = true
	u.name = "Echo of " + m.name.split(" ")[0]
	var grey := {}
	for k in m.palette:
		var c: Array = m.palette[k]
		var l := (float(c[0]) * 0.3 + float(c[1]) * 0.59 + float(c[2]) * 0.11)
		grey[k] = [l * 0.85 + 20, l * 0.85 + 22, l * 0.85 + 30]
	u.palette = grey
	u.xp_value = 30
	u.level = m.level + 2
	u.st["hp"] = int(u.st["hp"]) + 10 * skulls
	u.hp = int(u.st["hp"])
	return u


## Build a complete battle for a mission and a squad of members.
static func build(mission: Dictionary, squad: Array, ctx: Dictionary) -> Battle:
	var b := Battle.new()
	b.rng.seed = int(mission.get("seed", 1))
	b.mission = mission
	b.skulls = int(mission.get("skulls", 1))
	b.difficulty = int(ctx.get("difficulty", 1))
	var region: String = mission.get("region", "carrow")
	var hush_level := int(mission.get("hush_map", ctx.get("region_hush", 0)))
	var objective: String = mission.get("objective", "clear")
	var gen := MapGen.new()
	var map := gen.generate(mission, b.rng, squad.size())
	b.grid = map["grid"]
	b.grid.hush = hush_level
	b.grid.time = mission.get("time", Rules.time_of_day(int(mission.get("seed", 1))))
	if b.grid.biome in ["hush", "hush_town"]:
		b.grid.time = "day"   # inside the Hush there is only grey
	b.objective = {"type": objective, "turns": int(mission.get("turns", 6)), "n": int(mission.get("caches", 3)), "found": 0}
	# --- squad
	var starts: Array = map["player_spawns"]
	for i in squad.size():
		var m: Member = squad[i]
		var u := member_unit(m, int(ctx.get("resolve_bonus", 0)))
		u.pos = starts[i % starts.size()]
		u.facing = map.get("player_facing", Vector2i(0, -1))
		b.add_unit(u)
	# --- enemies
	var enemy_list: Array = pick_enemies(mission, squad.size(), b.rng, hush_level, ctx)
	var espawns: Array = map["enemy_spawns"]
	var ei := 0
	for eid in enemy_list:
		if ei >= espawns.size():
			break
		var eu := enemy_unit(eid, b.skulls, hush_level, b.rng, b.difficulty)
		eu.pos = espawns[ei]
		eu.facing = map.get("enemy_facing", Vector2i(0, 1))
		ei += 1
		b.add_unit(eu)
		if mission.get("boss", "") == eid and not b.objective.has("target_uid"):
			b.objective["target_uid"] = eu.uid
			b.objective["target_name"] = eu.name
			eu.elite = true
	# echoes of the unrecorded dead in the final battle
	if objective == "final":
		var echoes: Array = ctx.get("echoes", [])
		for md in echoes.slice(0, 4):
			if ei >= espawns.size():
				break
			var ech := echo_unit(md, b.skulls, b.rng)
			ech.pos = espawns[ei]
			ei += 1
			b.add_unit(ech)
	# hunt target when not a named boss
	if objective == "hunt" and not b.objective.has("target_uid"):
		for u in b.units:
			if u.team == BattleUnit.TEAM_ENEMY and u.elite:
				b.objective["target_uid"] = u.uid
				b.objective["target_name"] = u.name
				break
		if not b.objective.has("target_uid"):
			for u in b.units:
				if u.team == BattleUnit.TEAM_ENEMY:
					b.objective["target_uid"] = u.uid
					b.objective["target_name"] = u.name
					u.elite = true
					break
	# reinforcements from allied factions in the final battle
	for fid in ctx.get("allied_factions", []):
		if objective != "final":
			break
		var ally_cls: String = DB.factions[fid]["unique_class"]
		var rm := Member.create(b.rng, ally_cls, DB.factions[fid]["race"], 2, 10)
		rm.name = "%s Champion" % DB.factions[fid]["short"]
		var au := member_unit(rm)
		au.npc = false
		au.team = BattleUnit.TEAM_PLAYER
		au.member = null
		au.member_id = -2
		au.objective_role = "ally"
		if starts.size() > squad.size():
			au.pos = starts[squad.size() % starts.size()]
			for c in starts:
				if b.unit_at(c) == null:
					au.pos = c
					break
			if b.unit_at(au.pos) == null or b.unit_at(au.pos) == au:
				b.add_unit(au)
	# --- objective props / units
	match objective:
		"escort":
			var vip := b.spawn_npc("villager", map["vip_spawn"], "vip", DB.missions["vips"].get(region, "the traveller").capitalize())
			vip.team = BattleUnit.TEAM_PLAYER
			b.objective["vip_name"] = vip.name
		"defense":
			var obj := b.spawn_npc("villager", map["object_spawn"], "object", DB.missions["objects"].get(region, "cart").capitalize())
			obj.team = BattleUnit.TEAM_PLAYER
			obj.st["hp"] = 60 + 20 * b.skulls
			obj.hp = int(obj.st["hp"])
			obj.st["dodge"] = 0
			obj.st["defense"] = 4
			obj.sprite = "__object_" + region
			b.objective["object_name"] = obj.name
			b.objective["object_uid"] = obj.uid
		"rescue":
			pass
	# --- waves for survive/defense/final
	if objective in ["survive", "defense"]:
		var turns := int(b.objective["turns"])
		var region_pool: Dictionary = DB.regions[region]["enemies"]
		if mission.has("enemies"):
			region_pool = mission["enemies"]
		for r in range(3, turns + 1, 2):
			var wave: Array = []
			for j in 1 + b.skulls / 2 + (1 if r > turns / 2 else 0):
				wave.append(_weighted(region_pool, b.rng))
			b.waves.append({"round": r, "enemies": wave, "spots": map["edge_spawns"].duplicate()})
	for w in b.waves:
		w["spots"].shuffle()
	# --- bonus objectives
	b.bonus = [{"id": "no_downs", "desc": "No member Downed", "done": false}]
	b.bonus.append({"id": "fast", "desc": "Finish within %d rounds" % int(mission.get("par_rounds", 8)), "done": false})
	if map.get("has_chest", false):
		b.bonus.append({"id": "chest", "desc": "Open the hidden chest", "done": false})
	for u in b.units:
		if u.elite and u.team == BattleUnit.TEAM_ENEMY and objective != "hunt" and objective != "final":
			b.bonus.append({"id": "elite", "desc": "Slay the %s" % u.name, "done": false})
			break
	b.start()
	return b


static func _weighted(pool: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var r := rng.randf() * total
	for k in pool:
		r -= float(pool[k])
		if r <= 0:
			return k
	return pool.keys()[0]


static func pick_enemies(mission: Dictionary, squad_size: int, rng: RandomNumberGenerator, hush_level: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var region: String = mission.get("region", "carrow")
	var skulls := int(mission.get("skulls", 1))
	var pool: Dictionary = mission.get("enemies", DB.regions[region]["enemies"])
	var objective: String = mission.get("objective", "clear")
	var count := squad_size - 1 + int(skulls / 2) + rng.randi_range(0, 1)
	if objective in ["survive", "defense"]:
		count = maxi(2, count - 2)
	if objective == "escort":
		count = maxi(3, count - 1)
	if mission.get("category", "") == "training":
		count = maxi(2, count - 1)
	if mission.has("boss"):
		out.append(mission["boss"])
	elif objective == "hunt" or (skulls >= 3 and rng.randf() < 0.35) or int(mission.get("elite_count", 0)) > 0:
		var elites: Array = DB.regions[region]["elite"]
		out.append(elites[rng.randi() % elites.size()])
	# Hush creatures join ordinary fights when the Hush is Fading or local hush is high
	var hush_extra := 0
	if region != "unremembered" and (int(ctx.get("hush_stage", 0)) >= 1 or hush_level >= 2):
		hush_extra = 1 + (1 if hush_level >= 3 else 0)
	if mission.has("enemies"):
		var fixed: Dictionary = mission["enemies"]
		var is_count := true
		for k in fixed:
			if float(fixed[k]) != floor(float(fixed[k])):
				is_count = false
		if is_count and mission.get("category", "") == "story":
			for k in fixed:
				for i in int(fixed[k]):
					out.append(k)
			return out
	while out.size() < count - hush_extra:
		out.append(_weighted(pool, rng))
	for i in hush_extra:
		out.append("hollow" if rng.randf() < 0.7 else "quietling")
	if ctx.get("ambush", false):
		out.append(_weighted(pool, rng))
		out.append(_weighted(pool, rng))
	return out
