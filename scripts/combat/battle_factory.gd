class_name BattleFactory
extends RefCounted
## Builds battles: units from guild members and enemy data, maps, objectives.

## Enemies before the skull and objective adjustments: sized for a full squad
## of four whatever the guild actually sends.
const BASE_ENEMIES := 4
## One more enemy for every two skulls past the first.
const ENEMIES_PER_SKULL := 0.5
## enemies.json holds 1-skull stats. Each skull past the first is about one
## member level: these keep an enemy's blows, hide and pace in step with a
## member of the same level and that level's gear.
const SKULL_HP := 0.27
const SKULL_ATTACK := 0.27
const SKULL_DEFENSE := 0.25
const SKULL_ACCURACY := 4
const SKULL_DODGE := 2
const SKULL_SPEED := 2
const SKULL_CRIT := 1
const SKULL_RESOLVE := 4
## From this many skulls a region's apex creatures (its "apex" in regions.json)
## take the place of ordinary foes: one at 6 skulls, two at 7.
const APEX_SKULLS := 6
## From 5 skulls the guild usually fields squads of five or six (the
## Barracks): foes there are tougher than the per-skull growth alone.
## Bosses keep their own tuning.
const LATE_SKULLS := 5
const LATE_HP := 1.1
const LATE_ATTACK := 1.05


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
		if not s in u.skills and u.skills.size() < Member.LOADOUT + 1:
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
	var k := maxi(0, skulls - 1)
	var dm: float = [0.85, 1.0, 1.15][clampi(difficulty, 0, 2)]
	var hush_m := 1.0 + 0.03 * hush_level
	var late: bool = skulls >= LATE_SKULLS and not d.get("boss", false)
	s["hp"] = roundi(float(s["hp"]) * (1.0 + SKULL_HP * k) * dm * hush_m * (LATE_HP if late else 1.0))
	s["attack"] = roundi(float(s["attack"]) * (1.0 + SKULL_ATTACK * k) * dm * hush_m * (LATE_ATTACK if late else 1.0))
	s["defense"] = roundi(float(s["defense"]) * (1.0 + SKULL_DEFENSE * k))
	s["accuracy"] = int(s["accuracy"]) + SKULL_ACCURACY * k
	s["dodge"] = int(s["dodge"]) + SKULL_DODGE * k
	s["speed"] = int(s["speed"]) + SKULL_SPEED * k
	s["crit"] = int(s["crit"]) + SKULL_CRIT * k
	s["resolve"] = mini(100, int(s["resolve"]) + SKULL_RESOLVE * k)
	u.st = s
	u.hp = int(s["hp"])
	# on the members' level scale: a skull-N quest is sized for level-N members
	u.level = skulls + (1 if d.get("elite", false) else 0) + (2 if d.get("boss", false) else 0)
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
	for m in d.get("mods", {}):
		u.mods[m] = d["mods"][m]
	u.def_regen = int(u.mods.get("def_regen", 0))
	u.hidden = d.get("hidden", false)
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
		if not m.palette[k] is Array:
			grey[k] = m.palette[k]
			continue
		var c: Array = m.palette[k]
		var l := (float(c[0]) * 0.3 + float(c[1]) * 0.59 + float(c[2]) * 0.11)
		grey[k] = [l * 0.85 + 20, l * 0.85 + 22, l * 0.85 + 30]
	u.palette = grey
	u.xp_value = 30
	u.level = m.level + 1
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
	# fog of war everywhere; patrolled maps for most objectives
	b.fog = true
	b.explore = map.get("explore", false)
	b.par_rounds = int(mission.get("par_rounds", 8))
	if b.explore:
		b.objective_area = map["objective_area"]
		b.route = map["route"]
		b.par_rounds += b.route.size() / 6
	# --- squad
	var starts: Array = map["player_spawns"]
	for i in squad.size():
		var m: Member = squad[i]
		var u := member_unit(m, int(ctx.get("resolve_bonus", 0)))
		u.pos = starts[i % starts.size()]
		u.facing = map.get("player_facing", Vector2i(0, -1))
		b.add_unit(u)
	# --- enemies
	# rolled from the mission alone: the map (and so the squad size) never changes the force
	var force_rng := RandomNumberGenerator.new()
	force_rng.seed = int(mission.get("seed", 1)) + 7919
	var enemy_list: Array = []
	if objective == "final":
		_spawn_pods(b, map["pods"], final_groups(mission, force_rng, ctx.get("echoes", [])), mission, hush_level)
	else:
		enemy_list = pick_enemies(mission, force_rng, hush_level, ctx)
		if b.explore:
			_place_pods(b, map["pods"], enemy_list, mission, hush_level)
			enemy_list = []
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
		var rm := Member.create(b.rng, ally_cls, DB.factions[fid]["race"], 2, DB.LEVEL_CAP)
		rm.auto_pick(b.rng)
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
			# about ten blows from the enemies of its quest
			var k := b.skulls - 1
			obj.st["hp"] = roundi(240.0 * (1.0 + SKULL_HP * k))
			obj.hp = int(obj.st["hp"])
			obj.st["dodge"] = 0
			obj.st["defense"] = roundi(8.0 * (1.0 + SKULL_DEFENSE * k))
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
			var late := r > turns / 2
			for j in 1 + (1 if late else 0) + (1 if late and b.skulls >= 5 else 0):
				wave.append(_weighted(region_pool, b.rng))
			b.waves.append({"round": r, "enemies": wave, "spots": map["edge_spawns"].duplicate()})
	for w in b.waves:
		w["spots"].shuffle()
	# --- bonus objectives
	b.bonus = [{"id": "no_downs", "desc": "No member Downed", "done": false}]
	b.bonus.append({"id": "fast", "desc": "Finish within %d rounds" % b.par_rounds, "done": false})
	if map.get("has_chest", false):
		b.bonus.append({"id": "chest", "desc": "Open the hidden chest", "done": false})
	for u in b.units:
		if u.elite and u.team == BattleUnit.TEAM_ENEMY and objective != "hunt" and objective != "final":
			b.bonus.append({"id": "elite", "desc": "Slay the %s" % u.name, "done": false})
			break
	b.start()
	return b


## Patrolled maps: the first enemy (the hunt target or an elite) and a couple
## of guards hold the objective; the rest walk the trail in small pods.
static func _place_pods(b: Battle, pod_defs: Array, enemy_list: Array, mission: Dictionary, hush_level: int) -> void:
	if pod_defs.is_empty() or enemy_list.is_empty():
		return
	var obj_i := pod_defs.size() - 1
	var groups: Array = []
	for i in pod_defs.size():
		groups.append([])
	var rest := enemy_list.duplicate()
	groups[obj_i].append(rest.pop_front())
	for i in (2 if rest.size() >= 4 else 1):
		if not rest.is_empty():
			groups[obj_i].append(rest.pop_back())
	# pods of two or three: use as many trail stations as that takes, spread out
	var used: Array = []
	var k := mini(obj_i, maxi(1, rest.size() / 2))
	for j in k:
		used.append(floori((j + 0.5) * obj_i / float(k)))
	var gi := 0
	while not rest.is_empty():
		if used.is_empty():
			groups[obj_i].append(rest.pop_front())
			continue
		groups[used[gi % used.size()]].append(rest.pop_front())
		gi += 1
	_spawn_pods(b, pod_defs, groups, mission, hush_level)


## Puts each group at its pod's station (the last one guards the objective).
## A group entry is an enemy id, or {"echo": member dict} for an Echo of the
## guild's unrecorded dead.
static func _spawn_pods(b: Battle, pod_defs: Array, groups: Array, mission: Dictionary, hush_level: int) -> void:
	if pod_defs.is_empty():
		return
	while groups.size() < pod_defs.size():
		groups.push_front([])
	while groups.size() > pod_defs.size():
		var extra: Array = groups.pop_front()   # fewer stations: the nearest groups merge
		groups[0].append_array(extra)
	# a crowded station sends its extra enemies to the nearest one with room
	for i in pod_defs.size():
		while groups[i].size() > pod_defs[i]["cells"].size():
			var dest := -1
			for d in range(1, pod_defs.size()):
				for j in [i - d, i + d]:
					if dest < 0 and j >= 0 and j < pod_defs.size() and groups[j].size() < pod_defs[j]["cells"].size():
						dest = j
			if dest < 0:
				break
			groups[dest].append(groups[i].pop_back())
	for i in pod_defs.size():
		var cells: Array = pod_defs[i]["cells"]
		var uids: Array = []
		var ci := 0
		for entry in groups[i]:
			while ci < cells.size() and b.unit_at(cells[ci]) != null:
				ci += 1
			if ci >= cells.size():
				break
			var eu: BattleUnit
			if entry is Dictionary:
				eu = echo_unit(entry["echo"], b.skulls, b.rng)
			else:
				# the last stand's pods may fight a skull below its boss ("pods": {"skulls"})
				var sk := b.skulls if entry == mission.get("boss", "") else int(mission.get("pods", {}).get("skulls", b.skulls))
				eu = enemy_unit(entry, sk, hush_level, b.rng, b.difficulty)
				if mission.get("objective", "") == "final" and _is_apex(entry):
					# the realm's apex creatures, taken by the Hush
					eu.palette = faded(eu.palette)
					eu.hush = true
			eu.pos = cells[ci]
			ci += 1
			eu.facing = Vector2i(0, 1)
			eu.alerted = false
			eu.pod = b.pods.size()
			b.add_unit(eu)
			uids.append(eu.uid)
			if not entry is Dictionary and mission.get("boss", "") == entry and not b.objective.has("target_uid"):
				b.objective["target_uid"] = eu.uid
				b.objective["target_name"] = eu.name
				eu.elite = true
		if not uids.is_empty():
			b.pods.append({"units": uids, "alerted": false, "route": pod_defs[i]["route"], "wp": 0, "objective": pod_defs[i]["objective"]})


## The last stand: every pod on the way to the Heart holds two of the realm's
## apex creatures taken by the Hush (a brute and a striker) and one or two Hush
## foes ("pods" in the story mission); the Unnamed waits with the last pod.
## Echoes of the unrecorded dead take the striker's place (a fallen member is
## about as dangerous), beside the Unnamed first and then back down the trail,
## so many dead do not swell the force.
static func final_groups(mission: Dictionary, rng: RandomNumberGenerator, echoes: Array) -> Array:
	var spec: Dictionary = mission.get("pods", {})
	var brutes: Array = []
	var strikers: Array = []
	for r in DB.regions:
		for eid in DB.regions[r].get("apex", {}):
			if int(DB.enemies[eid]["stats"]["hp"]) >= 70:
				brutes.append(eid)
			else:
				strikers.append(eid)
	brutes.sort()
	strikers.sort()
	_shuffle(brutes, rng)
	_shuffle(strikers, rng)
	var hush_n: Array = spec.get("hush", [1, 2])
	var pool: Dictionary = spec.get("hush_pool", {"hollow": 7, "quietling": 3})
	var groups: Array = []
	for i in int(spec.get("count", 4)):
		var g: Array = [brutes[i % brutes.size()], strikers[i % strikers.size()]]
		for j in rng.randi_range(int(hush_n[0]), int(hush_n[-1])):
			g.append(_weighted(pool, rng))
		groups.append(g)
	if mission.has("boss"):
		groups[-1].push_front(mission["boss"])
	var gi := groups.size() - 1
	for md in echoes:
		if gi < 0:
			break
		var g: Array = groups[gi]
		for k in g.size():
			if g[k] is String and strikers.has(g[k]):
				g[k] = {"echo": md}
				break
		gi -= 1
	return groups


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _is_apex(eid: String) -> bool:
	for r in DB.regions:
		if DB.regions[r].get("apex", {}).has(eid):
			return true
	return false


## A palette drained most of the way to grey, as the Hush leaves what it takes.
static func faded(palette: Dictionary, amount := 0.8) -> Dictionary:
	var out := {}
	for slot in UnitPalette.SLOTS:
		var c := UnitPalette.to_color(palette.get(slot, UnitPalette.DEFAULTS[slot]))
		var l := c.r8 * 0.3 + c.g8 * 0.59 + c.b8 * 0.11
		var grey := [l * 0.85 + 20, l * 0.85 + 22, l * 0.85 + 30]
		out[slot] = [roundi(lerpf(c.r8, grey[0], amount)), roundi(lerpf(c.g8, grey[1], amount)), roundi(lerpf(c.b8, grey[2], amount))]
	return out


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


## The enemy force depends on the mission alone: sending fewer members never
## makes a fight smaller.
static func pick_enemies(mission: Dictionary, rng: RandomNumberGenerator, hush_level: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var region: String = mission.get("region", "carrow")
	var skulls := int(mission.get("skulls", 1))
	var pool: Dictionary = mission.get("enemies", DB.regions[region]["enemies"])
	var objective: String = mission.get("objective", "clear")
	var count := BASE_ENEMIES + roundi(ENEMIES_PER_SKULL * (skulls - 1)) + rng.randi_range(0, 1)
	if MapGen.is_explore(mission):
		count += 1   # spread over several pods that rarely fight all at once
	if objective in ["survive", "defense"]:
		count = maxi(2, count - 2 - (skulls - 1) / 3)   # the waves bring the rest
	if objective == "escort":
		count = maxi(3, count - 1)
	if mission.get("category", "") == "training":
		count = maxi(2, count - 1)
	if mission.has("boss"):
		out.append(mission["boss"])
	elif objective == "hunt" or rng.randf() < 0.1 * (skulls - 2) or int(mission.get("elite_count", 0)) > 0:
		var elites: Array = DB.regions[region]["elite"]
		var pick: String = elites[rng.randi() % elites.size()]
		# the hunt target named on the board is the one waiting at the end of the trail
		if objective == "hunt" and DB.enemies.has(mission.get("elite", "")):
			pick = mission["elite"]
		out.append(pick)
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
			if objective != "final":
				_add_apex(out, region, skulls, rng)
			return out
	while out.size() < count - hush_extra:
		out.append(_weighted(pool, rng))
	if mission.get("category", "") != "training":
		_add_apex(out, region, skulls, rng)
	for i in hush_extra:
		if i == 0 and skulls >= APEX_SKULLS:
			out.append(_weighted(DB.regions["unremembered"]["apex"], rng))
		else:
			out.append("hollow" if rng.randf() < 0.7 else "quietling")
	if ctx.get("ambush", false):
		out.append(_weighted(pool, rng))
		out.append(_weighted(pool, rng))
	return out


## Swaps ordinary foes of the region for its apex creatures on the hardest quests.
static func _add_apex(out: Array, region: String, skulls: int, rng: RandomNumberGenerator) -> void:
	var apex: Dictionary = DB.regions.get(region, {}).get("apex", {})
	var n := skulls - APEX_SKULLS + 1
	if apex.is_empty() or n <= 0:
		return
	var ordinary: Array = []
	for i in out.size():
		if DB.regions[region]["enemies"].has(out[i]):
			ordinary.append(i)
	for j in mini(n, ordinary.size()):
		var i: int = ordinary[rng.randi() % ordinary.size()]
		ordinary.erase(i)
		out[i] = _weighted(apex, rng)
