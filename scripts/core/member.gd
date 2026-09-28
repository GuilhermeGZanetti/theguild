class_name Member
extends RefCounted
## A guild member: class, race, level, stats, growth, traits, skills,
## equipment, injuries and history. Serializable with to_dict/from_dict.

const CLOTH := [[64, 124, 170], [186, 70, 64], [82, 140, 86], [206, 150, 60], [120, 80, 150], [70, 150, 150], [180, 100, 60], [150, 60, 90], [92, 104, 136], [196, 176, 128], [60, 90, 150], [170, 50, 50]]
const CLOTH2 := [[70, 60, 80], [92, 70, 60], [60, 70, 92], [122, 100, 80], [140, 60, 50], [52, 82, 70], [176, 164, 142], [96, 56, 72]]
const LEATHER := [[126, 84, 54], [100, 70, 50], [140, 100, 62], [84, 62, 52]]
const WOOD := [[146, 98, 58], [120, 80, 50], [170, 122, 72]]
const CAPE := [[84, 128, 72], [110, 70, 50], [70, 90, 120], [130, 60, 60]]
const FEATURE := {
	"human": [[200, 150, 90]], "tidefolk": [[90, 190, 200], [120, 170, 220], [100, 200, 170]],
	"mothkin": [[200, 172, 120], [164, 142, 196], [220, 200, 160]], "barkborn": [[120, 170, 80], [200, 120, 60]],
	"khepri": [[60, 52, 74], [70, 130, 110], [150, 90, 40]],
}
const GLOW := {"mystic": [[130, 236, 255], [206, 150, 255], [255, 170, 120]], "lanternbearer": [[255, 214, 110]], "sandreaver": [[150, 232, 240]], "tidecaller": [[150, 240, 230]]}
const PALETTE_VERSION := 2   # bump when race palettes change: older saves are repainted
const CONFLICTS := [["tough", "frail"], ["swift", "sluggish"], ["frugal", "greedy"], ["fast_learner", "dullard"], ["brave", "coward"], ["hardy", "slow_healer"], ["keen", "clumsy"]]
const GROWTH_STATS := ["hp", "defense", "dodge", "speed", "crit", "attack", "accuracy", "resolve"]

var id := 0
var name := ""
var race := "human"
var cls := "warrior"
var subclass := ""
var level := 1
var xp := 0
var tier := 1
var base := {}
var grown := {}
var potential := {}
var traits: Array = []
var skills: Array = []
var loadout: Array = []
var skill_points := 0
var equipment := {"weapon": {}, "armor": {}, "trinket": {}}
var injury := {}
var days_used := 0
var history := {"quests": 0, "kills": 0, "near_deaths": 0, "joined": 1, "downed": 0}
var variant := ""
var palette := {}
var status := "active"
var death := {}
var memorial := false
var reveal := 2
var bio := ""
var hire_cost := 0


# ------------------------------------------------------------------ creation
static func create(rng: RandomNumberGenerator, p_cls: String, p_race: String, p_tier: int, p_level: int = 1, week: int = 1) -> Member:
	var m := Member.new()
	m.cls = p_cls
	m.race = p_race
	m.tier = clampi(p_tier, 0, 3)
	var c: Dictionary = DB.classes[p_cls]
	var b: Dictionary = c["base"]
	var add_acc: int = [-5, 0, 4, 8][m.tier]
	var add_dodge: int = [-3, 0, 2, 4][m.tier]
	var add_res: int = [-5, 0, 5, 10][m.tier]
	var add_crit: int = [-2, 0, 2, 4][m.tier]
	var add_speed: int = [-3, 0, 3, 6][m.tier]
	for k in DB.STATS:
		var v: float = float(b.get(k, 0))
		match k:
			"hp", "attack", "defense":
				v = v * DB.TIER_MULT[m.tier] * rng.randf_range(0.95, 1.05)
			"accuracy":
				v += add_acc + rng.randi_range(-3, 3)
			"dodge":
				v += add_dodge + rng.randi_range(-2, 2)
			"resolve":
				v += add_res + rng.randi_range(-4, 4)
			"crit":
				v += add_crit + rng.randi_range(-1, 1)
			"speed":
				v += add_speed + rng.randi_range(-3, 3)
		m.base[k] = v
		m.grown[k] = 0.0
	var bias: Array = c.get("potential_bias", [])
	for k in GROWTH_STATS:
		var r := rng.randf() + m.tier * 0.09 + (0.3 if k in bias else 0.0)
		m.potential[k] = 1 if r < 0.38 else (2 if r < 0.86 else 3)
	m.roll_traits(rng)
	if p_race == "human":
		pass
	var start: String = c.get("start_skill", "")
	if start != "":
		m.skills.append(start)
		m.loadout.append(start)
	for p in c.get("passives", []):
		m.skills.append(p)
	m.equipment["weapon"] = Items.weapon(c["weapon_family"], 1)
	m.equipment["armor"] = Items.armor(c["armor_family"], 1)
	m.name = random_name(rng, p_race)
	m.history["joined"] = week
	m.pick_look(rng)
	for i in range(1, p_level):
		m.xp = 0
		m._level_up(rng)
	m.hire_cost = m.compute_hire_cost()
	return m


static func random_name(rng: RandomNumberGenerator, p_race: String) -> String:
	var n: Dictionary = DB.names.get(p_race, DB.names["human"])
	var first: Array = n["first"]
	var last: Array = n["last"]
	return "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]


func roll_traits(rng: RandomNumberGenerator) -> void:
	traits.clear()
	var count := 1
	var r := rng.randf()
	if r > 0.45:
		count = 2
	if r > 0.85:
		count = 3
	var good_chance: float = [0.3, 0.5, 0.65, 0.8][tier]
	var pool_good: Array = []
	var pool_bad: Array = []
	for t in DB.traits:
		var d: Dictionary = DB.traits[t]
		if d.get("special", false) or d.get("injury", false) or int(d.get("weight", 0)) <= 0:
			continue
		if d["good"]:
			pool_good.append(t)
		else:
			pool_bad.append(t)
	var tries := 0
	while traits.size() < count and tries < 40:
		tries += 1
		var pool: Array = pool_good if rng.randf() < good_chance else pool_bad
		var t: String = pool[rng.randi() % pool.size()]
		if t in traits or _conflicts(t):
			continue
		traits.append(t)


func _conflicts(t: String) -> bool:
	for pair in CONFLICTS:
		if t in pair:
			for o in pair:
				if o != t and o in traits:
					return true
	return false


func add_trait(t: String) -> bool:
	if t in traits or _conflicts(t):
		return false
	traits.append(t)
	return true


func pick_look(rng: RandomNumberGenerator) -> void:
	var c: Dictionary = DB.classes[cls]
	var look: String = c["look"]
	if race == "human" and look in ["warrior", "rogue", "ranger", "mystic"]:
		variant = "human_%s_%s" % [look, ["a", "b", "c"][rng.randi() % 3]]
	else:
		variant = "%s_%s" % [race, look]
	paint(rng)


## Colours for the sprite: race and look palettes from races.json (the concept
## art colours) on top of the shared clothing lists.
func paint(rng: RandomNumberGenerator) -> void:
	var rd: Dictionary = DB.races[race]
	var look: String = DB.classes[cls]["look"]
	var pick := func(arr: Array) -> Array: return arr[rng.randi() % arr.size()]
	palette = {
		"skin": pick.call(rd["skin"]), "skin2": pick.call(rd["skin2"]), "hair": pick.call(rd["hair"]),
		"eyes": [38, 28, 48], "cloth1": pick.call(CLOTH), "cloth2": pick.call(CLOTH2),
		"leather": pick.call(LEATHER), "wood": pick.call(WOOD), "cape": pick.call(CAPE),
		"feature": pick.call(FEATURE.get(race, FEATURE["human"])), "white": [236, 230, 218],
		"glow": pick.call(GLOW.get(cls, [[130, 236, 255]])), "bandage": [242, 236, 224],
	}
	var rp: Dictionary = rd.get("palette", {})
	for k in rp:
		palette[k] = pick.call(rp[k])
	var lp: Dictionary = rd.get("looks", {}).get(look, {})
	for k in lp:
		palette[k] = pick.call(lp[k])
	palette["v"] = PALETTE_VERSION
	refresh_gear_colors()


func refresh_gear_colors() -> void:
	var at := Items.tier_of(equipment.get("armor", {})) if not equipment.get("armor", {}).is_empty() else 1
	var wt := Items.tier_of(equipment.get("weapon", {})) if not equipment.get("weapon", {}).is_empty() else 1
	palette["metal"] = DB.items["tier_metal"][clampi(maxi(at, wt) - 1, 0, 3)]
	palette["trim"] = DB.items["tier_trim"][clampi(wt - 1, 0, 3)]
	var arm: Dictionary = equipment.get("armor", {})
	if arm.get("kind", "") == "unique":
		match arm["id"]:
			"coral_armor": palette["metal"] = [240, 130, 120]
			"barkskin": palette["metal"] = [120, 92, 62]


# ------------------------------------------------------------------ stats
func class_data() -> Dictionary:
	return DB.classes[cls]


func all_passives() -> Array:
	var out: Array = []
	for s in skills:
		if DB.skill(s).get("passive", false):
			out.append(s)
	if subclass != "":
		var sc: Dictionary = DB.subclasses[subclass]
		if not sc["passive"] in out:
			out.append(sc["passive"])
	return out


func mods() -> Dictionary:
	var m := {}
	var add := func(d: Dictionary) -> void:
		for k in d:
			m[k] = m.get(k, 0) + d[k]
	for t in traits:
		add.call(DB.traits.get(t, {}).get("mods", {}))
	var rd: Dictionary = DB.races.get(race, {})
	add.call(rd.get("mods", {}))
	add.call(rd.get("stat", {}))
	for p in all_passives():
		add.call(DB.skill(p).get("mods", {}))
	for slot_name in equipment:
		add.call(Items.mods_of(equipment[slot_name]))
	return m


func stats() -> Dictionary:
	var s := {}
	for k in DB.STATS:
		s[k] = float(base.get(k, 0)) + float(grown.get(k, 0))
	if subclass != "":
		var sb: Dictionary = DB.subclasses[subclass].get("stat", {})
		for k in sb:
			s[k] += sb[k]
	for slot_name in equipment:
		var st := Items.stats_of(equipment[slot_name])
		for k in st:
			s[k] = s.get(k, 0) + st[k]
	var m := mods()
	for k in DB.STATS:
		if m.has(k):
			s[k] += m[k]
	s["hp"] *= 1.0 + m.get("hp_pct", 0.0)
	s["defense"] *= 1.0 + m.get("def_pct", 0.0)
	for k in DB.STATS:
		if k == "move":
			s[k] = clampi(roundi(s[k]), 2, 8)
		elif k == "range":
			s[k] = clampi(roundi(s[k]), 1, 9)
		else:
			s[k] = clampi(roundi(s[k]), 0, 100 if k != "hp" else 400)
	return s


func wage() -> int:
	var w: float = class_data().get("wage", 12)
	w *= DB.TIER_WAGE[tier]
	w *= 1.0 + 0.09 * (level - 1)
	w *= 1.0 + float(mods().get("wage_pct", 0.0))
	return maxi(3, roundi(w))


func compute_hire_cost() -> int:
	return roundi(wage() * 4.0 + level * 10)


func is_available() -> bool:
	return status == "active" and injury.is_empty()


func days_left() -> int:
	return 7 - days_used


func xp_needed() -> int:
	return DB.xp_to_next(level)


func tier_name() -> String:
	return DB.TIERS[tier]


func class_name_full() -> String:
	var n: String = class_data()["name"]
	if subclass != "":
		n = DB.subclasses[subclass]["name"]
	return n


func sprite_id() -> String:
	return variant


# ------------------------------------------------------------------ progression
## Adds XP and returns an Array of level-up dictionaries {level, gains}.
func add_xp(amount: int, rng: RandomNumberGenerator) -> Array:
	var ups: Array = []
	if level >= DB.LEVEL_CAP:
		return ups
	var mult := 1.0 + float(mods().get("xp_pct", 0.0))
	xp += roundi(amount * mult)
	while level < DB.LEVEL_CAP and xp >= xp_needed():
		xp -= xp_needed()
		ups.append(_level_up(rng))
	if level >= DB.LEVEL_CAP:
		xp = 0
	return ups


func _level_up(rng: RandomNumberGenerator) -> Dictionary:
	level += 1
	skill_points += 1
	var g: Dictionary = class_data()["growth"]
	var gains := {}
	for k in GROWTH_STATS:
		var amt: float = float(g.get(k, 0.0)) * DB.TIER_GROWTH[tier] * DB.POTENTIAL_MULT[int(potential.get(k, 2))]
		var whole := floori(amt)
		if rng.randf() < amt - whole:
			whole += 1
		if whole > 0:
			grown[k] = float(grown.get(k, 0.0)) + whole
			gains[k] = whole
	return {"level": level, "gains": gains}


func can_pick_subclass() -> bool:
	return subclass == "" and level >= DB.SUBCLASS_LEVEL and class_data().get("subclasses", []).size() > 0


func choose_subclass(sc: String) -> void:
	subclass = sc
	var skill_id: String = DB.subclasses[sc]["skill"]
	if not skill_id in skills:
		skills.append(skill_id)
	if loadout.size() < 4:
		loadout.append(skill_id)


func learnable_skills() -> Array:
	var out: Array = []
	var c: Dictionary = class_data()
	for br in c["branches"]:
		for s in c["branches"][br]["skills"]:
			if not s in skills:
				out.append(s)
	return out


func learn(skill_id: String) -> void:
	if skill_id in skills:
		return
	skills.append(skill_id)
	if not DB.skill(skill_id).get("passive", false) and loadout.size() < 4:
		loadout.append(skill_id)


func active_skills() -> Array:
	var out: Array = []
	for s in skills:
		if not DB.skill(s).get("passive", false):
			out.append(s)
	return out


# ------------------------------------------------------------------ injuries
func injure(kind: String, rng: RandomNumberGenerator, nursery_speed: float, extra_weeks: int = 0) -> Dictionary:
	var weeks := 1
	if kind == "serious":
		weeks = rng.randi_range(2, 4)
	var m := mods()
	var f := (1.0 + float(m.get("heal_pct", 0.0))) * (1.0 - nursery_speed)
	weeks = maxi(1, roundi(weeks * f) + extra_weeks)
	injury = {"kind": kind, "weeks": weeks}
	var result := {"kind": kind, "weeks": weeks, "permanent": ""}
	if kind == "serious" and rng.randf() < 0.10:
		var perms := ["lost_eye", "limp", "broken_hand", "cracked_ribs", "shaken"]
		perms.shuffle()
		for p in perms:
			if not p in traits:
				traits.append(p)
				result["permanent"] = p
				break
	return result


func permanent_injuries() -> Array:
	var out: Array = []
	for t in traits:
		if DB.traits.get(t, {}).get("injury", false):
			out.append(t)
	return out


# ------------------------------------------------------------------ save
func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "race": race, "cls": cls, "subclass": subclass, "level": level, "xp": xp,
		"tier": tier, "base": base, "grown": grown, "potential": potential, "traits": traits,
		"skills": skills, "loadout": loadout, "skill_points": skill_points, "equipment": equipment,
		"injury": injury, "days_used": days_used, "history": history, "variant": variant, "palette": palette,
		"status": status, "death": death, "memorial": memorial, "reveal": reveal, "bio": bio, "hire_cost": hire_cost,
	}


static func from_dict(d: Dictionary) -> Member:
	var m := Member.new()
	for k in d:
		if k in m:
			m.set(k, d[k])
	m.id = int(d.get("id", 0))
	m.level = int(d.get("level", 1))
	m.xp = int(d.get("xp", 0))
	m.tier = int(d.get("tier", 1))
	m.skill_points = int(d.get("skill_points", 0))
	m.days_used = int(d.get("days_used", 0))
	m.reveal = int(d.get("reveal", 2))
	m.hire_cost = int(d.get("hire_cost", 0))
	for k in m.potential:
		m.potential[k] = int(m.potential[k])
	if not m.injury.is_empty():
		m.injury["weeks"] = int(m.injury.get("weeks", 1))
	if int(m.palette.get("v", 1)) < PALETTE_VERSION and DB.races.has(m.race) and DB.classes.has(m.cls):
		var rng := RandomNumberGenerator.new()
		rng.seed = m.id * 7919 + hash(m.name)
		m.paint(rng)
	return m
