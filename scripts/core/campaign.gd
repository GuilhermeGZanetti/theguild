class_name Campaign
extends RefCounted
## The whole guild-management state and weekly simulation. Headless.

const FACTIONS := ["saltborn", "lantern", "rootwardens", "glass"]
const START_GOLD := [420, 320, 240]

var guild_name := "The Guild"
var week := 1
var gold := 320
var renown := 0
var materials := 4
var hush := 10
var difficulty := 1
var ironman := false
var act := 1
var story_done := {}
var final_unlocked := false
var roster: Array = []
var dead: Array = []
var recruits: Array = []
var next_member_id := 1
var facilities := {}
var factions := {}
var regions := {}
var board: Array = []
var inventory: Array = []
var unpaid_weeks := 0
var flags := {}
var chronicle: Array = []
var pending_events: Array = []
var stats := {"missions": 0, "victories": 0, "deaths": 0, "kills": 0, "recruited": 0}
var seeds: Array = []
var game_over := ""
var ending := ""
var rng := RandomNumberGenerator.new()
var next_mission_id := 1
var shop: Array = []
var week_deaths: Array = []
var last_report := {}
var tutorial_seen := {}


# ====================================================================== setup
func new_game(p_name: String, p_difficulty: int, p_ironman: bool, seed_value: int = 0) -> void:
	guild_name = p_name
	difficulty = clampi(p_difficulty, 0, 2)
	ironman = p_ironman
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	gold = START_GOLD[difficulty]
	renown = 0
	hush = 10
	week = 1
	for fid in DB.facilities:
		facilities[fid] = int(DB.facilities[fid].get("start", 0))
	for fid in FACTIONS:
		factions[fid] = {"rep": 0, "power": 5, "collapsed": false, "chain": 0, "chain_wait": 0, "hostile_ambush": false}
	for rid in DB.regions:
		regions[rid] = {"hush": 0, "lost": false}
	regions["unremembered"]["hush"] = 5
	# starting roster: one per base class, one of them Skilled
	var classes := DB.base_classes().duplicate()
	var skilled_idx := rng.randi() % 4
	for i in 4:
		var t := 2 if i == skilled_idx else (1 if rng.randf() < 0.6 else 0)
		var race: String = "human" if rng.randf() < 0.7 else ["tidefolk", "mothkin", "barkborn", "khepri"][rng.randi() % 4]
		var m := Member.create(rng, classes[i], race, t, 1, 1)
		add_member(m)
	for i in 2:
		inventory.append(Items.trinket(["lucky_coin", "hawk_feather", "iron_charm", "feather_token"][rng.randi() % 4]))
	roll_recruits()
	generate_board()
	chronicle.append({"week": 1, "text": "%s is founded in an abandoned tavern in Carrow." % guild_name})


func add_member(m: Member) -> void:
	m.id = next_member_id
	next_member_id += 1
	m.reveal = 2
	roster.append(m)


func member(id: int) -> Member:
	for m in roster:
		if m.id == id:
			return m
	return null


# ====================================================================== derived
func rank() -> int:
	return Rules.renown_rank(renown)


func hush_stage() -> int:
	return Rules.hush_stage(hush)


func roster_cap() -> int:
	return int(DB.facilities["barracks"]["roster"][facilities["barracks"]])


func squad_cap() -> int:
	return int(DB.facilities["barracks"]["squad"][facilities["barracks"]])


func active_members() -> Array:
	var out: Array = []
	for m in roster:
		if m.status == "active":
			out.append(m)
	return out


func available_members(days := 1) -> Array:
	var out: Array = []
	for m in roster:
		if m.is_available() and m.days_left() >= days:
			out.append(m)
	return out


func price_mult() -> float:
	var p := 1.0
	if flags.get("trade_cut", false):
		p += 0.2
	if hush_stage() >= 2:
		p += 0.2
	return p


func price(base: int) -> int:
	return roundi(base * price_mult())


func weekly_wages() -> int:
	var total := 0
	for m in roster:
		if m.status == "active":
			total += m.wage()
	return total


func memorial_resolve() -> int:
	return int(DB.facilities["memorial"]["resolve"][facilities["memorial"]])


func nursery_speed() -> float:
	return float(DB.facilities["nursery"]["speed"][facilities["nursery"]])


func allied_factions() -> Array:
	var out: Array = []
	for f in FACTIONS:
		if int(factions[f]["rep"]) >= 3 and not factions[f]["collapsed"]:
			out.append(f)
	return out


func collapsed_count() -> int:
	var n := 0
	for f in FACTIONS:
		if factions[f]["collapsed"]:
			n += 1
	return n


func change_rep(fid: String, amount: int) -> void:
	if fid == "" or not factions.has(fid):
		return
	factions[fid]["rep"] = clampi(int(factions[fid]["rep"]) + amount, -3, 3)


func change_power(fid: String, amount: int) -> void:
	if fid == "" or not factions.has(fid) or factions[fid]["collapsed"]:
		return
	factions[fid]["power"] = clampi(int(factions[fid]["power"]) + amount, 0, 10)


func change_hush(amount: int, reason := "") -> void:
	hush = clampi(hush + amount, 0, 100)


# ====================================================================== recruitment
func roll_recruits() -> void:
	recruits.clear()
	var lvl := int(facilities["recruiter"])
	var n := int(DB.facilities["recruiter"]["pool"][lvl])
	if hush_stage() >= 3:
		n = maxi(2, n - 1)
	for i in n:
		recruits.append(random_recruit())
	for s in seeds:
		recruits.append(s)
	seeds.clear()
	# faction recruits when Friendly
	for f in FACTIONS:
		if int(factions[f]["rep"]) >= 1 and not factions[f]["collapsed"] and rng.randf() < 0.5:
			var cls: String = DB.base_classes()[rng.randi() % 4]
			var m := Member.create(rng, cls, DB.factions[f]["race"], _roll_tier(1), _recruit_level(), week)
			m.bio = "Sent by the %s." % DB.factions[f]["name"]
			_finalize_recruit(m)
			recruits.append(m)


## Levels are slow to earn, so hired hands arrive seasoned but never veteran.
func _recruit_level() -> int:
	return clampi(1 + (rank() + rng.randi_range(-1, 1)) / 2, 1, 4)


func _roll_tier(bonus := 0) -> int:
	var q := int(DB.facilities["recruiter"]["quality"][facilities["recruiter"]]) + bonus
	var r := rng.randf() + 0.06 * rank() + 0.08 * q
	if r > 1.06:
		return 3
	if r > 0.82:
		return 2
	if r > 0.4:
		return 1
	return 0


func random_recruit() -> Member:
	var race := "human"
	var weights := {"human": 60.0}
	for f in FACTIONS:
		var rc: String = DB.factions[f]["race"]
		var w := 10.0
		if factions[f]["collapsed"]:
			w = 3.0
		if int(factions[f]["rep"]) >= 1:
			w *= 2.0
		if int(factions[f]["rep"]) <= -2:
			w *= 0.3
		weights[rc] = w
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := rng.randf() * total
	for k in weights:
		roll -= weights[k]
		if roll <= 0:
			race = k
			break
	var cls: String = DB.base_classes()[rng.randi() % 4]
	var m := Member.create(rng, cls, race, _roll_tier(), _recruit_level(), week)
	_finalize_recruit(m)
	return m


func _finalize_recruit(m: Member) -> void:
	m.reveal = int(DB.facilities["recruiter"]["reveal"][facilities["recruiter"]])
	if hush_stage() >= 2 and rng.randf() < 0.3:
		m.add_trait("hollow")
	m.hire_cost = price(m.compute_hire_cost())


func hire(m: Member) -> String:
	if not m in recruits:
		return "Not available."
	if active_members().size() >= roster_cap():
		return "The barracks are full."
	if gold < m.hire_cost:
		return "Not enough gold."
	gold -= m.hire_cost
	recruits.erase(m)
	add_member(m)
	stats["recruited"] += 1
	return ""


func dismiss(m: Member) -> void:
	if m in roster:
		for s in ["weapon", "armor", "trinket"]:
			var it: Dictionary = m.equipment.get(s, {})
			if not it.is_empty() and (it.get("kind", "") in ["trinket", "unique"] or Items.tier_of(it) > 1):
				inventory.append(it)
		roster.erase(m)
		chronicle.append({"week": week, "text": "%s left the guild." % m.name})


# ====================================================================== facilities
func facility_upgrade_cost(fid: String) -> int:
	var lvl := int(facilities[fid])
	if lvl >= 3:
		return -1
	return price(int(DB.facilities[fid]["costs"][lvl]))


func facility_renown_req(fid: String) -> int:
	var lvl := int(facilities[fid])
	if lvl >= 3:
		return 0
	return int(DB.facilities[fid]["renown"][lvl])


func upgrade_facility(fid: String) -> String:
	var cost := facility_upgrade_cost(fid)
	if cost < 0:
		return "Already at the highest level."
	if renown < facility_renown_req(fid):
		return "Requires %d Renown." % facility_renown_req(fid)
	if gold < cost:
		return "Not enough gold."
	gold -= cost
	facilities[fid] = int(facilities[fid]) + 1
	chronicle.append({"week": week, "text": "Built %s level %d." % [DB.facilities[fid]["name"], facilities[fid]]})
	if fid == "recruiter":
		for r in recruits:
			r.reveal = maxi(r.reveal, int(DB.facilities["recruiter"]["reveal"][facilities[fid]]))
	return ""


# ====================================================================== equipment & skills
## Taking the skill of an unlocked row is free; changing it later costs a
## retraining at the Library.
func learn_skill(m: Member, skill_id: String) -> String:
	return m.pick(skill_id)


func retrain_cost(row: int) -> int:
	var disc := float(DB.facilities["library"]["discount"][facilities["library"]])
	return price(roundi((30 + 20 * row) * (1.0 - disc)))


func can_retrain(m: Member, row: int) -> String:
	if m.row_pick(row) == "":
		return "Nothing learned at level %d." % row
	if int(facilities["library"]) == 0:
		return "Build the Library to retrain."
	if row > int(DB.facilities["library"]["max_level"][facilities["library"]]):
		return "The Library needs an upgrade to retrain level %d skills." % row
	if gold < retrain_cost(row):
		return "Not enough gold."
	return ""


func retrain(m: Member, row: int) -> String:
	var err := can_retrain(m, row)
	if err != "":
		return err
	gold -= retrain_cost(row)
	return m.swap_pick(row)


func forge_cost(item: Dictionary) -> Array:
	var c: Array = Items.upgrade_cost(item)
	return [price(int(c[0])), int(c[1])]


func can_forge(item: Dictionary) -> String:
	if not Items.can_upgrade(item):
		return "Cannot be improved further."
	var max_tier := int(DB.facilities["forge"]["max_tier"][facilities["forge"]])
	if int(item.get("tier", 1)) >= max_tier:
		return "The Forge needs an upgrade." if int(facilities["forge"]) > 0 else "Build the Forge first."
	var c := forge_cost(item)
	if gold < int(c[0]):
		return "Not enough gold."
	if materials < int(c[1]):
		return "Not enough materials."
	return ""


func forge_upgrade(item: Dictionary, owner: Member = null) -> String:
	var err := can_forge(item)
	if err != "":
		return err
	var c := forge_cost(item)
	gold -= int(c[0])
	materials -= int(c[1])
	item["tier"] = int(item["tier"]) + 1
	if owner:
		owner.refresh_gear_colors()
	return ""


func equip(m: Member, item: Dictionary) -> String:
	if not item in inventory:
		return "Not in the stash."
	if not Items.fits(item, m.cls):
		return "%s cannot use that." % m.class_name_full()
	var slot := Items.slot(item)
	var old: Dictionary = m.equipment.get(slot, {})
	inventory.erase(item)
	if not old.is_empty():
		inventory.append(old)
	m.equipment[slot] = item
	m.refresh_gear_colors()
	return ""


func unequip(m: Member, slot: String) -> void:
	var old: Dictionary = m.equipment.get(slot, {})
	if old.is_empty() or slot != "trinket":
		return
	inventory.append(old)
	m.equipment[slot] = {}


func sell(item: Dictionary) -> void:
	if item in inventory:
		inventory.erase(item)
		gold += Items.sell_price(item)


func buy_shop(idx: int) -> String:
	if idx < 0 or idx >= shop.size():
		return "Sold out."
	var entry: Dictionary = shop[idx]
	var cost := price(int(entry["price"]))
	if gold < cost:
		return "Not enough gold."
	gold -= cost
	inventory.append(entry["item"])
	shop.remove_at(idx)
	return ""


func refresh_shop() -> void:
	shop.clear()
	var keys: Array = DB.items["trinkets"].keys()
	keys.erase("bell_shard")
	keys.shuffle()
	for k in keys.slice(0, 3):
		shop.append({"item": Items.trinket(k), "price": int(DB.items["trinkets"][k]["price"])})
	for f in FACTIONS:
		if int(factions[f]["rep"]) >= 2 and not factions[f]["collapsed"]:
			var uid: String = DB.factions[f]["unique_item"]
			var owned := false
			for it in inventory:
				if it.get("id", "") == uid:
					owned = true
			if not owned:
				shop.append({"item": Items.unique(uid), "price": int(DB.items["uniques"][uid]["price"]), "faction": f})
	if int(facilities["forge"]) >= 1:
		var fam: Array = DB.items["weapons"].keys()
		var t := mini(3, int(DB.facilities["forge"]["max_tier"][facilities["forge"]]))
		shop.append({"item": Items.weapon(fam[rng.randi() % fam.size()], t), "price": [0, 120, 240, 420][t - 1] if t > 1 else 60})


func record_memorial(idx: int) -> String:
	if idx < 0 or idx >= dead.size():
		return "?"
	var lvl := int(facilities["memorial"])
	if lvl == 0:
		return "Build the Memorial first."
	var d: Dictionary = dead[idx]
	if d.get("memorial", false):
		return "Already recorded."
	var cost := price(int(DB.facilities["memorial"]["record_cost"][lvl]))
	if gold < cost:
		return "Not enough gold."
	gold -= cost
	d["memorial"] = true
	chronicle.append({"week": week, "text": "The name of %s was carved into the Memorial." % d["name"]})
	return ""


func memorial_cost() -> int:
	var lvl := int(facilities["memorial"])
	if lvl == 0:
		return -1
	return price(int(DB.facilities["memorial"]["record_cost"][lvl]))


func treat_permanent(m: Member, trait_id: String) -> String:
	if int(facilities["nursery"]) < 3:
		return "Requires the Nursery at level 3."
	var cost := price(200)
	if gold < cost:
		return "Not enough gold."
	if not trait_id in m.traits:
		return "?"
	gold -= cost
	m.traits.erase(trait_id)
	return ""


# ====================================================================== missions
func generate_board() -> void:
	board.clear()
	var stage := hush_stage()
	var n := 4 + rng.randi_range(0, 2) - (1 if stage >= 1 else 0)
	n = maxi(3, n)
	var open_regions: Array = []
	for rid in DB.regions:
		if rid != "unremembered" and not regions[rid]["lost"]:
			open_regions.append(rid)
	# strategic first
	if hush >= 14 or rng.randf() < 0.6:
		board.append(_make_mission("breach", _hushiest_region(open_regions)))
	var crisis_count := 1 + (1 if rng.randf() < 0.45 else 0)
	for i in crisis_count:
		var f := _weak_faction()
		if f != "":
			board.append(_make_mission("crisis", DB.factions[f]["region"], f))
	if rng.randf() < 0.4:
		var pair: Dictionary = DB.missions["rivalries"][rng.randi() % DB.missions["rivalries"].size()]
		if not factions[pair["a"]]["collapsed"] and not factions[pair["b"]]["collapsed"]:
			var ma := _make_mission("rivalry", DB.factions[pair["a"]]["region"], pair["a"])
			var mb := _make_mission("rivalry", DB.factions[pair["b"]]["region"], pair["b"])
			ma["title"] = pair["a_title"]
			mb["title"] = pair["b_title"]
			ma["desc"] = pair["a_desc"]
			mb["desc"] = pair["b_desc"]
			ma["rival"] = pair["b"]
			mb["rival"] = pair["a"]
			ma["conflict"] = mb["id"]
			mb["conflict"] = ma["id"]
			board.append(ma)
			board.append(mb)
	while board.size() < n:
		var r := rng.randf()
		var cat := "contract"
		if r > 0.45:
			cat = "salvage"
		if r > 0.66:
			cat = "training"
		if r > 0.84:
			cat = "recruit"
		board.append(_make_mission(cat, _region_by_power(open_regions)))
	# chain missions
	for f in FACTIONS:
		var fd: Dictionary = factions[f]
		if fd["collapsed"]:
			continue
		var step := int(fd["chain"])
		if step == 0 and int(fd["rep"]) >= 2 or step == 1 and int(fd["rep"]) >= 3:
			var cm := _make_mission("chain", DB.factions[f]["region"], f)
			cm["chain_step"] = step
			cm["title"] = DB.factions[f]["chain"][step]
			cm["skulls"] = clampi(3 + step, 1, 5)
			board.append(cm)
	# story
	var sid := next_story()
	if sid != "":
		board.append(_story_mission(sid))
	if final_unlocked and not story_done.get("final", false):
		board.append(_story_mission("final"))
	refresh_shop()


func next_story() -> String:
	for sid in ["s1", "s2", "s3", "s4", "s5", "s6"]:
		if story_done.get(sid, false):
			continue
		var s: Dictionary = DB.story["missions"][sid]
		if int(s["act"]) > act:
			return ""
		if week >= int(s["min_week"]) and renown >= int(s["min_renown"]):
			return sid
		return ""
	return ""


func story_hint() -> String:
	for sid in ["s1", "s2", "s3", "s4", "s5", "s6"]:
		if story_done.get(sid, false):
			continue
		var s: Dictionary = DB.story["missions"][sid]
		var parts: Array = []
		if week < int(s["min_week"]):
			parts.append("week %d" % int(s["min_week"]))
		if renown < int(s["min_renown"]):
			parts.append("%d Renown" % int(s["min_renown"]))
		if parts.is_empty():
			return "The next story mission is on the board."
		return "Next story mission: \"%s\" (needs %s)." % [s["title"], " and ".join(parts)]
	if final_unlocked and not story_done.get("final", false):
		return "The Heart of the Hush awaits."
	return ""


func _story_mission(sid: String) -> Dictionary:
	var s: Dictionary = DB.story["missions"][sid]
	var m := {
		"id": next_mission_id, "title": s["title"], "category": "story", "objective": s["objective"],
		"region": s["region"], "faction": "", "skulls": int(s["skulls"]), "days": int(s["days"]),
		"story_id": sid, "desc": s["brief"], "seed": rng.randi(), "turns": int(s.get("turns", 6)),
		"caches": int(s.get("caches", 3)), "hush_map": int(s.get("hush_map", regions[s["region"]]["hush"])),
		"reward": s["reward"].duplicate(), "par_rounds": 9,
	}
	m["time"] = s.get("time", Rules.time_of_day(int(m["seed"])))
	next_mission_id += 1
	if s.has("boss"):
		m["boss"] = s["boss"]
	if s.has("enemies"):
		m["enemies"] = s["enemies"]
	if s.has("biome"):
		m["biome"] = s["biome"]
	if s.has("elite_count"):
		m["elite_count"] = s["elite_count"]
	m["ignore"] = {"story": true}
	return m


func _hushiest_region(open_regions: Array) -> String:
	var best: String = open_regions[rng.randi() % open_regions.size()]
	var bh := -1.0
	for r in open_regions:
		var v := float(regions[r]["hush"]) + rng.randf() * 1.5
		if v > bh:
			bh = v
			best = r
	return best


func _weak_faction() -> String:
	var total := 0.0
	var w := {}
	for f in FACTIONS:
		if factions[f]["collapsed"]:
			continue
		w[f] = 11.0 - float(factions[f]["power"])
		total += w[f]
	if total <= 0:
		return ""
	var r := rng.randf() * total
	for f in w:
		r -= w[f]
		if r <= 0:
			return f
	return w.keys()[0]


func _region_by_power(open_regions: Array) -> String:
	var total := 0.0
	var w := {}
	for r in open_regions:
		var f: String = DB.regions[r]["faction"]
		w[r] = 4.0 if f == "" else 1.0 + float(factions[f]["power"])
		total += w[r]
	var roll := rng.randf() * total
	for r in w:
		roll -= w[r]
		if roll <= 0:
			return r
	return open_regions[0]


func _make_mission(cat: String, region: String, faction := "") -> Dictionary:
	var cd: Dictionary = DB.missions["categories"][cat]
	var objs: Array = cd["objectives"]
	var obj: String = objs[rng.randi() % objs.size()]
	if faction == "":
		faction = DB.regions[region]["faction"]
	var max_sk := Rules.max_skulls(rank())
	var sk := clampi(1 + rank() + rng.randi_range(-1, 1), 1, max_sk)
	if cat in ["breach", "crisis", "rivalry"]:
		sk = clampi(sk + (1 if rng.randf() < 0.4 else 0), 1, max_sk)
	if cat == "training":
		sk = maxi(1, sk - 1)
	if faction != "" and int(factions.get(faction, {}).get("rep", 0)) <= -2:
		sk = mini(5, sk + 1)
	var days := rng.randi_range(int(cd["days"][0]), int(cd["days"][1]))
	var place: Array = DB.regions[region]["places"]
	var place_name: String = place[rng.randi() % place.size()]
	var od: Dictionary = DB.missions["objectives"][obj]
	var titles: Array = od["titles"]
	var elite_names: Array = DB.regions[region]["elite"]
	var elite_id: String = elite_names[rng.randi() % elite_names.size()]
	var elite_name: String = DB.enemies[elite_id]["name"]
	var tpl: String = titles[rng.randi() % titles.size()]
	if " the " in elite_name:   # a proper name: "Hunt Mott the Bell-Thief"
		tpl = tpl.replace("the {elite}", "{elite}").replace("The {elite}", "{elite}")
	var title: String = tpl.format({"place": place_name, "elite": elite_name}).replace("the The", "the")
	title = title[0].to_upper() + title.substr(1)
	var gold_base: Array = {"contract": [70, 55], "recruit": [25, 15], "salvage": [25, 12], "training": [25, 15], "breach": [35, 25],
		"crisis": [45, 32], "rivalry": [60, 45], "chain": [100, 60]}[cat]
	var g := roundi((gold_base[0] + gold_base[1] * sk) * rng.randf_range(0.9, 1.2))
	if flags.get("tide_fleet", false) and region == "coast":
		g = roundi(g * 1.25)
	if flags.get("undercut", false):
		g = roundi(g * 0.9)
	var m := {
		"id": next_mission_id, "title": title, "category": cat, "objective": obj, "region": region,
		"faction": faction, "skulls": sk, "days": days, "seed": rng.randi(), "place": place_name, "elite": elite_id,
		"turns": 5 + sk, "caches": 3, "hush_map": int(regions[region]["hush"]), "par_rounds": 6 + sk,
		"reward": {"gold": g, "renown": 3 + 3 * sk},
		"desc": cd["desc"],
	}
	m["time"] = Rules.time_of_day(int(m["seed"]))
	next_mission_id += 1
	match cat:
		"recruit":
			var t := 2 if rng.randf() < 0.75 else 3
			var cls: String = DB.base_classes()[rng.randi() % 4]
			var race := "human"
			if faction != "":
				race = DB.factions[faction]["race"] if rng.randf() < 0.6 else "human"
			var rm := Member.create(rng, cls, race, t, _recruit_level(), week)
			rm.bio = "Rescued at %s." % place_name
			m["reward"]["recruit"] = rm.to_dict()
		"salvage":
			m["reward"]["items"] = [Items.random_loot(rng, sk), Items.random_loot(rng, sk)]
			m["reward"]["materials"] = 3 + 2 * sk
		"training":
			m["reward"]["xp_mult"] = 1.7
		"breach":
			m["reward"]["hush"] = -(5 + rng.randi_range(0, 5))
			m["ignore"] = {"hush": 3 + rng.randi_range(0, 5)}
			m["hush_map"] = mini(5, int(regions[region]["hush"]) + 2)
			m["enemies"] = {"hollow": 5, "quietling": 2}
			m["enemies"].merge(DB.regions[region]["enemies"])
			m["desc"] = "The Hush is pushing through at %s. Drive it back." % place_name
		"crisis":
			m["reward"]["power"] = 1
			m["reward"]["rep"] = 1
			m["ignore"] = {"power": -1}
			m["desc"] = "The %s needs help at %s." % [DB.factions[faction]["name"], place_name]
		"rivalry":
			m["reward"]["power"] = 1
			m["reward"]["rep"] = 1
		"chain":
			m["reward"]["rep"] = 1
			m["ignore"] = {"chain": true}
			m["desc"] = "A special mission for the %s." % DB.factions[faction]["name"]
	var od_desc: String = od["desc"]
	m["objective_desc"] = od_desc.format({"target": MissionLore.the_name(elite_name), "vip": DB.missions["vips"].get(region, "the traveller"),
		"n": 3, "object": DB.missions["objects"].get(region, "cart"), "turns": m["turns"]})
	return m


func mission_by_id(mid: int) -> Dictionary:
	for m in board:
		if int(m["id"]) == mid:
			return m
	return {}


func can_launch(mission: Dictionary, squad: Array) -> String:
	if squad.is_empty():
		return "Choose at least one member."
	if squad.size() > squad_cap():
		return "Your barracks allow a squad of %d." % squad_cap()
	for m in squad:
		if not m.is_available():
			return "%s cannot go." % m.name
		if m.days_left() < int(mission["days"]):
			return "%s does not have %d days left this week." % [m.name, int(mission["days"])]
	return ""


func battle_context(mission: Dictionary) -> Dictionary:
	var echoes: Array = []
	if mission.get("objective", "") == "final":
		for d in dead:
			if not d.get("memorial", false) or flags.get("conclave_falls", false):
				echoes.append(d)
	var f: String = mission.get("faction", "")
	return {
		"difficulty": difficulty, "resolve_bonus": memorial_resolve(), "region_hush": int(regions[mission["region"]]["hush"]),
		"hush_stage": hush_stage(), "echoes": echoes, "allied_factions": allied_factions(),
		"ambush": f != "" and int(factions.get(f, {}).get("rep", 0)) <= -2,
	}


## Apply the outcome of a battle. Returns a report for the post-quest screen.
func finish_mission(mission: Dictionary, battle: Battle) -> Dictionary:
	var rep := {"mission": mission, "result": battle.result, "grade": "D", "gold": 0, "renown": 0, "xp": {}, "levels": {},
		"injuries": {}, "deaths": [], "items": [], "materials": 0, "hush": 0, "faction": [], "story": "", "recruit": "",
		"lost_items": [], "traits": {}, "bonus": battle.bonus}
	stats["missions"] += 1
	var victory := battle.result == "victory"
	var squad_units: Array = []
	for u in battle.units:
		if u.team == BattleUnit.TEAM_PLAYER and u.member != null:
			squad_units.append(u)
	var survivors := 0
	for u in squad_units:
		if u.state != "dead" and u.state != "recovered" and not (u.state == "downed" and not victory and u.carried_by < 0):
			survivors += 1
	# --- deaths (including downed left behind on a failed mission)
	for u in squad_units:
		var m: Member = u.member
		m.days_used += int(mission["days"])
		m.history["quests"] += 1
		m.history["kills"] += u.kills
		stats["kills"] += u.kills
		var left_behind: bool = not victory and u.state == "downed"
		# "recovered" = a dead body carried out: still dead, but the gear comes home
		if u.state == "dead" or u.state == "recovered" or left_behind:
			var recovered: bool = u.state == "recovered" or (victory and u.state == "dead")
			_member_died(m, mission, "Left behind" if left_behind else "Slain", recovered)
			rep["deaths"].append(m.name)
			if not recovered:
				rep["lost_items"].append(m.name)
	# --- rewards
	var bonus_done := 0
	for b in battle.bonus:
		if b.get("done", false):
			bonus_done += 1
	var g := Rules.grade(victory, bonus_done, battle.bonus.size(), battle.round_num, battle.par_rounds, rep["deaths"].size(), battle.downs)
	rep["grade"] = g
	var gm := Rules.grade_mult(g)
	var reward: Dictionary = mission.get("reward", {})
	if victory:
		stats["victories"] += 1
		rep["gold"] = roundi(int(reward.get("gold", 0)) * gm)
		rep["renown"] = roundi(int(reward.get("renown", 5)) * gm)
		rep["materials"] = int(reward.get("materials", 0)) + battle.rng.randi_range(0, int(mission["skulls"]))
		for it in reward.get("items", []):
			rep["items"].append(it)
		if battle.chests_opened > 0:
			rep["items"].append(Items.random_loot(rng, int(mission["skulls"]) + 1))
			rep["gold"] += 30 * int(mission["skulls"])
		if reward.has("item"):
			var rid: String = reward["item"]
			rep["items"].append(Items.trinket(rid) if DB.items["trinkets"].has(rid) else Items.unique(rid))
		if rng.randf() < 0.35 + 0.05 * int(mission["skulls"]):
			rep["items"].append(Items.random_loot(rng, int(mission["skulls"])))
		if reward.has("recruit"):
			var rm := Member.from_dict(reward["recruit"])
			if active_members().size() < roster_cap():
				add_member(rm)
				rep["recruit"] = rm.name
			else:
				rm.hire_cost = 0
				recruits.append(rm)
				rep["recruit"] = rm.name + " (waiting in the tavern: barracks full)"
		if reward.has("hush"):
			rep["hush"] = int(reward["hush"])
			regions[mission["region"]]["hush"] = maxi(0, int(regions[mission["region"]]["hush"]) - 1)
		_faction_success(mission, rep)
		if mission.get("category", "") == "story":
			_story_success(mission, rep)
	else:
		rep["renown"] = -10 if battle.result != "retreat" else -6
		_faction_failure(mission, rep)
		if mission.get("category", "") == "story" and mission.get("story_id", "") == "final":
			game_over = "final"
	rep["renown"] -= 5 * rep["deaths"].size()
	gold += rep["gold"]
	renown = maxi(0, renown + rep["renown"])
	materials += rep["materials"]
	inventory.append_array(rep["items"])
	change_hush(rep["hush"])
	# --- xp, injuries, traits
	var xp_mult := float(reward.get("xp_mult", 1.0)) if victory else 0.5
	var share := Rules.xp_share(int(mission["skulls"]), squad_units.size(), maxi(1, survivors), xp_mult)
	for u in squad_units:
		var m: Member = u.member
		if m.status != "active":
			continue
		var xp: int = share + Rules.deed_xp(u.kills, u.stabilizes, int(mission["skulls"]))
		rep["xp"][m.id] = xp
		var ups := m.add_xp(xp, rng)
		if not ups.is_empty():
			rep["levels"][m.id] = ups
		if u.was_downed:
			m.history["near_deaths"] += 1
			m.history["downed"] += 1
			var serious_ch: float = [0.25, 0.4, 0.55][difficulty]
			var kind := "serious" if rng.randf() < serious_ch else "light"
			var extra := -1 if flags.get("healing_sap", false) and kind == "serious" else 0
			var inj := m.injure(kind, rng, nursery_speed(), extra)
			rep["injuries"][m.id] = inj
			if rng.randf() < 0.25 and m.add_trait("survivor"):
				rep["traits"][m.id] = "survivor"
		if u.kills > 0:
			for o in battle.units:
				pass
		for o in battle.units:
			if o.boss and o.state == "dead" and u.kills > 0 and rng.randf() < 0.5:
				if m.add_trait("bossbane"):
					rep["traits"][m.id] = "bossbane"
				break
		if not rep["deaths"].is_empty() and rng.randf() < 0.2:
			var tr := "vengeful" if rng.randf() < 0.5 else "haunted"
			if m.add_trait(tr):
				rep["traits"][m.id] = tr
		# barkskin grows
		var arm: Dictionary = m.equipment.get("armor", {})
		if arm.get("id", "") == "barkskin":
			arm["bonus"] = mini(20, int(arm.get("bonus", 0)) + 2)
	# conflicting mission and this one leave the board
	var conflict := int(mission.get("conflict", -1))
	board = board.filter(func(x): return int(x["id"]) != int(mission["id"]) and int(x["id"]) != conflict)
	if mission.get("story_id", "") != "" and not victory and mission["story_id"] != "final":
		pass
	chronicle.append({"week": week, "text": "%s: %s (grade %s)." % [mission["title"], "Victory" if victory else ("Retreat" if battle.result == "retreat" else "Defeat"), g]})
	last_report = rep
	_check_loss()
	return rep


func _member_died(m: Member, mission: Dictionary, cause: String, recovered: bool) -> void:
	m.status = "dead"
	var d := m.to_dict()
	d["death"] = {"week": week, "mission": mission.get("title", ""), "cause": cause}
	d["memorial"] = false
	if not recovered:
		d["equipment"] = {"weapon": {}, "armor": {}, "trinket": {}}
	else:
		for s in ["trinket"]:
			var it: Dictionary = m.equipment.get(s, {})
			if not it.is_empty():
				inventory.append(it)
		var arm: Dictionary = m.equipment.get("armor", {})
		if arm.get("kind", "") == "unique" or Items.tier_of(arm) > 1:
			inventory.append(arm)
		var wpn: Dictionary = m.equipment.get("weapon", {})
		if wpn.get("kind", "") == "unique" or Items.tier_of(wpn) > 1:
			inventory.append(wpn)
	dead.append(d)
	week_deaths.append(d)
	roster.erase(m)
	stats["deaths"] += 1
	chronicle.append({"week": week, "text": "%s fell at %s." % [m.name, mission.get("title", "?")]})
	if m.race == "barkborn":
		var seedling := Member.create(rng, DB.base_classes()[rng.randi() % 4], "barkborn", m.tier, 1, week + 1)
		var good: Array = []
		for t in m.traits:
			if DB.traits.get(t, {}).get("good", false) and not DB.traits[t].get("special", false):
				good.append(t)
		if not good.is_empty():
			seedling.add_trait(good[rng.randi() % good.size()])
		seedling.bio = "Grown from the seed of %s." % m.name
		seedling.hire_cost = 0
		seeds.append(seedling)


func _faction_success(mission: Dictionary, rep: Dictionary) -> void:
	var f: String = mission.get("faction", "")
	var reward: Dictionary = mission.get("reward", {})
	match mission.get("category", ""):
		"crisis":
			change_power(f, 1)
			change_rep(f, 1)
			rep["faction"].append("%s: Power +1, Reputation +1" % DB.factions[f]["short"])
		"rivalry":
			var rival: String = mission.get("rival", "")
			change_power(f, 1)
			change_rep(f, 1)
			change_power(rival, -1)
			change_rep(rival, -1)
			rep["faction"].append("%s: Power +1, Reputation +1" % DB.factions[f]["short"])
			rep["faction"].append("%s: Power -1, Reputation -1" % DB.factions[rival]["short"])
		"chain":
			var step := int(mission.get("chain_step", 0))
			factions[f]["chain"] = step + 1
			factions[f]["chain_wait"] = 0
			change_rep(f, 1)
			if step == 0:
				var uid: String = DB.factions[f]["unique_item"]
				rep["items"].append(Items.unique(uid))
				rep["faction"].append("%s: Reputation +1. They gift you their %s." % [DB.factions[f]["short"], DB.items["uniques"][uid]["name"]])
			else:
				var cls: String = DB.factions[f]["unique_class"]
				var champion := Member.create(rng, cls, DB.factions[f]["race"], 2, maxi(3, _recruit_level() + 1), week)
				champion.bio = "A %s sworn to the guild by the %s." % [DB.classes[cls]["name"], DB.factions[f]["name"]]
				if active_members().size() < roster_cap():
					add_member(champion)
				else:
					champion.hire_cost = 0
					recruits.append(champion)
				rep["recruit"] = champion.name + " the " + DB.classes[cls]["name"]
				rep["faction"].append("The %s is now Allied. They will send reinforcements to the final battle." % DB.factions[f]["name"])
		_:
			pass


func _faction_failure(mission: Dictionary, rep: Dictionary) -> void:
	var f: String = mission.get("faction", "")
	if f == "" or not factions.has(f):
		return
	if mission.get("category", "") in ["crisis", "rivalry", "chain"]:
		change_rep(f, -1)
		rep["faction"].append("%s: Reputation -1" % DB.factions[f]["short"])
		if mission.get("category", "") == "crisis":
			change_power(f, -1)
			rep["faction"].append("%s: Power -1" % DB.factions[f]["short"])


func _story_success(mission: Dictionary, rep: Dictionary) -> void:
	var sid: String = mission.get("story_id", "")
	story_done[sid] = true
	var s: Dictionary = DB.story["missions"][sid]
	rep["story"] = s.get("outro", "")
	if s.has("next_act"):
		act = int(s["next_act"])
		rep["act"] = act
		chronicle.append({"week": week, "text": DB.story["acts"][str(act)]["name"] + " begins."})
	if s.get("unlock_final", false):
		final_unlocked = true
	if sid == "final":
		ending = ending_key()
		game_over = "victory"


func ending_key() -> String:
	var best := "none"
	var bp := -1
	for f in allied_factions():
		if int(factions[f]["power"]) > bp:
			bp = int(factions[f]["power"])
			best = f
	return best


# ====================================================================== week
func end_week() -> Dictionary:
	var rep := {"week": week, "ignored": [], "wages": 0, "paid": true, "left": [], "healed": [], "training": 0,
		"hush_before": hush, "events": [], "collapsed": [], "stage_before": hush_stage()}
	# ignored missions
	for m in board:
		var ig: Dictionary = m.get("ignore", {})
		if ig.has("hush"):
			change_hush(int(ig["hush"]))
			regions[m["region"]]["hush"] = mini(5, int(regions[m["region"]]["hush"]) + 1)
			rep["ignored"].append("%s: the Hush rises by %d." % [m["title"], int(ig["hush"])])
		if ig.has("power"):
			change_power(m["faction"], int(ig["power"]))
			rep["ignored"].append("%s: %s loses 1 Power." % [m["title"], DB.factions[m["faction"]]["short"]])
		if ig.get("story", false):
			change_hush(3)
			renown = maxi(0, renown - 3)
			rep["ignored"].append("%s: %s" % [m["title"], "the story moves on without you. Hush +3, Renown -3."])
		if ig.get("chain", false):
			var f: String = m["faction"]
			factions[f]["chain_wait"] = int(factions[f]["chain_wait"]) + 1
			if int(factions[f]["chain_wait"]) >= 3 and rng.randf() < 0.5:
				change_rep(f, -1)
				factions[f]["chain_wait"] = 0
				rep["ignored"].append("%s: the %s lose patience. Reputation -1." % [m["title"], DB.factions[f]["short"]])
	# deaths without a memorial record feed the Hush
	for d in week_deaths:
		if not d.get("memorial", false) or flags.get("conclave_falls", false):
			change_hush(1)
	week_deaths.clear()
	# wages
	var wages := weekly_wages()
	rep["wages"] = wages
	if gold >= wages:
		gold -= wages
		unpaid_weeks = 0
	else:
		gold = 0
		unpaid_weeks += 1
		rep["paid"] = false
		for m in active_members().duplicate():
			if rng.randf() < 0.2 * unpaid_weeks:
				rep["left"].append(m.name + " (unpaid)")
				dismiss(m)
	# injuries and training
	var train_xp := int(DB.facilities["training"]["xp"][facilities["training"]])
	for m in roster:
		if not m.injury.is_empty():
			m.injury["weeks"] = int(m.injury["weeks"]) - 1
			if int(m.injury["weeks"]) <= 0:
				m.injury = {}
				rep["healed"].append(m.name)
		elif m.days_used == 0 and train_xp > 0:
			m.add_xp(train_xp, rng)
			rep["training"] += 1
		m.days_used = 0
	# the Hush advances
	change_hush(2)
	if "lantern" in allied_factions():
		change_hush(-1)
	var stage := hush_stage()
	for rid in regions:
		if rid == "unremembered":
			continue
		regions[rid]["hush"] = maxi(int(regions[rid]["hush"]), mini(5, stage))
	if stage >= 2:
		var open: Array = []
		for rid in regions:
			if rid != "unremembered" and not regions[rid]["lost"]:
				open.append(rid)
		if not open.is_empty():
			var r: String = open[rng.randi() % open.size()]
			regions[r]["hush"] = mini(5, int(regions[r]["hush"]) + 1)
	if stage >= 3:
		for m in active_members().duplicate():
			if m.days_used == 0 and rng.randf() < 0.1 and roster.size() > 1:
				rep["left"].append(m.name + " (forgot the guild)")
				dismiss(m)
		var weakest := ""
		var wp := 99
		for f in FACTIONS:
			if not factions[f]["collapsed"] and int(factions[f]["power"]) < wp:
				wp = int(factions[f]["power"])
				weakest = f
		if weakest != "":
			change_power(weakest, -1)
	# faction events
	_faction_events(rep)
	flags.erase("undercut")
	rep["hush_after"] = hush
	rep["stage_after"] = hush_stage()
	week += 1
	for m in roster:
		m.days_used = 0
	roll_recruits()
	generate_board()
	# random guild event; now and then a named stranger with a story walks in
	if rng.randf() < 0.55:
		var evs: Dictionary = DB.events["random"]
		var normal: Array = evs.keys().filter(func(k): return not evs[k].has("named"))
		var named: Array = evs.keys().filter(func(k): return evs[k].has("named") and not flags.has("met_" + k))
		var k: String = normal[rng.randi() % normal.size()]
		if week >= 3 and not named.is_empty() and rng.randf() < 0.2:
			k = named[rng.randi() % named.size()]
			flags["met_" + k] = true
		if int(evs[k].get("needs", 0)) <= active_members().size():
			pending_events.append({"kind": "random", "id": k})
	_check_loss()
	last_report = rep
	return rep


func _faction_events(rep: Dictionary) -> void:
	for f in FACTIONS:
		var fd: Dictionary = factions[f]
		if fd["collapsed"]:
			continue
		if int(fd["power"]) <= 0:
			fd["collapsed"] = true
			var region: String = DB.factions[f]["region"]
			regions[region]["lost"] = true
			regions[region]["hush"] = 5
			change_hush(15)
			rep["collapsed"].append(f)
			var ev: Dictionary = DB.events["faction"]["collapse"]
			pending_events.append({"kind": "faction", "title": ev["title"].format({"faction": DB.factions[f]["name"]}),
				"text": ev["text"].format({"faction": DB.factions[f]["name"], "region": DB.regions[region]["name"]})})
			for i in 2:
				var refugee := Member.create(rng, DB.base_classes()[rng.randi() % 4], DB.factions[f]["race"], _roll_tier(), _recruit_level(), week + 1)
				refugee.hire_cost = 0
				refugee.bio = "A refugee of the fallen %s." % DB.factions[f]["name"]
				seeds.append(refugee)
			chronicle.append({"week": week, "text": "The %s collapsed. The Hush swallowed %s." % [DB.factions[f]["name"], DB.regions[region]["name"]]})
			if f == "lantern":
				flags["conclave_falls"] = true
				pending_events.append({"kind": "faction", "title": DB.events["faction"]["conclave_falls"]["title"], "text": DB.events["faction"]["conclave_falls"]["text"]})
	_threshold_flag("tide_fleet", int(factions["saltborn"]["power"]) >= 8 and not factions["saltborn"]["collapsed"])
	_threshold_flag("trade_cut", int(factions["glass"]["power"]) <= 3 or factions["glass"]["collapsed"])
	_threshold_flag("healing_sap", int(factions["rootwardens"]["power"]) >= 8 and not factions["rootwardens"]["collapsed"])
	for pair in [["saltborn", "glass"], ["lantern", "rootwardens"]]:
		var key: String = "war_" + pair[0]
		if flags.get(key, false):
			continue
		if int(factions[pair[0]]["power"]) >= 7 and int(factions[pair[1]]["power"]) >= 7:
			flags[key] = true
			var ev: Dictionary = DB.events["faction"]["open_war"]
			pending_events.append({"kind": "war", "a": pair[0], "b": pair[1], "title": ev["title"],
				"text": ev["text"].format({"a": DB.factions[pair[0]]["name"], "b": DB.factions[pair[1]]["name"]})})


func _threshold_flag(key: String, on: bool) -> void:
	var was: bool = flags.get(key, false)
	flags[key] = on
	if on and not was:
		var ev: Dictionary = DB.events["faction"][key]
		pending_events.append({"kind": "faction", "title": ev["title"], "text": ev["text"]})


func resolve_war(winner: String, loser: String) -> void:
	change_rep(winner, 1)
	factions[loser]["rep"] = mini(int(factions[loser]["rep"]), -2)
	change_power(loser, -1)
	chronicle.append({"week": week, "text": "The guild sided with the %s in their war against the %s." % [DB.factions[winner]["name"], DB.factions[loser]["name"]]})


## Apply a choice of a random guild event. Returns the result text.
func resolve_event(ev_id: String, choice: int) -> String:
	var ev: Dictionary = DB.events["random"][ev_id]
	var ch: Dictionary = ev["choices"][choice]
	var cost: Dictionary = ch.get("cost", {})
	if int(cost.get("gold", 0)) > gold:
		return "You cannot afford that."
	gold -= int(cost.get("gold", 0))
	var e: Dictionary = ch.get("effects", {})
	gold += int(e.get("gold", 0))
	renown = maxi(0, renown + int(e.get("renown", 0)))
	change_hush(int(e.get("hush", 0)))
	materials += int(e.get("materials", 0))
	if e.has("flag"):
		flags[e["flag"]] = true
	var members := active_members()
	if not members.is_empty():
		if e.has("member_xp"):
			for m in members.slice(0, 2):
				m.add_xp(int(e["member_xp"]), rng)
		if e.has("member_xp_all"):
			for m in members:
				m.add_xp(int(e["member_xp_all"]), rng)
		if e.has("member_injure"):
			var healthy: Array = members.filter(func(x): return x.injury.is_empty())
			if not healthy.is_empty():
				healthy[rng.randi() % healthy.size()].injure("light", rng, 0.0)
		if e.has("member_resolve"):
			pass
	if e.has("named_recruit"):
		named_recruit(e["named_recruit"])
	return ch.get("result", "")


## A unique recruit from a guild event: fixed name, class, race, traits and story.
## Joins at once, or waits in the tavern for free when the barracks are full.
func named_recruit(id: String) -> Member:
	var d: Dictionary = DB.events["named"][id]
	var m := Member.create(rng, d["cls"], d["race"], int(d["tier"]), int(d.get("level", 1)), week)
	m.name = d["name"]
	if d.has("gender"):
		m.gender = d["gender"]
		m.pick_look(rng)
	m.traits.clear()
	for t in d["traits"]:
		m.add_trait(t)
	m.bio = d["bio"]
	m.hire_cost = 0
	if active_members().size() < roster_cap():
		add_member(m)
	else:
		recruits.append(m)
	return m


func can_continue() -> bool:
	return game_over == ""


func _check_loss() -> void:
	if game_over != "":
		return
	if hush >= 100:
		game_over = "hush"
	elif collapsed_count() >= 2:
		game_over = "factions"
	elif unpaid_weeks >= 3:
		game_over = "wages"
	elif active_members().is_empty():
		var cheapest := 99999
		for r in recruits:
			cheapest = mini(cheapest, r.hire_cost)
		if gold < cheapest:
			game_over = "roster"


# ====================================================================== save
func to_dict() -> Dictionary:
	var ros: Array = []
	for m in roster:
		ros.append(m.to_dict())
	var rec: Array = []
	for m in recruits:
		rec.append(m.to_dict())
	var sd: Array = []
	for m in seeds:
		sd.append(m.to_dict())
	return {
		"version": 1, "guild_name": guild_name, "week": week, "gold": gold, "renown": renown, "materials": materials,
		"hush": hush, "difficulty": difficulty, "ironman": ironman, "act": act, "story_done": story_done,
		"final_unlocked": final_unlocked, "roster": ros, "dead": dead, "recruits": rec, "next_member_id": next_member_id,
		"facilities": facilities, "factions": factions, "regions": regions, "board": board, "inventory": inventory,
		"unpaid_weeks": unpaid_weeks, "flags": flags, "chronicle": chronicle, "pending_events": pending_events,
		"stats": stats, "seeds": sd, "game_over": game_over, "ending": ending, "rng_state": str(rng.state), "rng_seed": str(rng.seed),
		"next_mission_id": next_mission_id, "shop": shop, "week_deaths": week_deaths, "tutorial_seen": tutorial_seen,
	}


static func from_dict(d: Dictionary) -> Campaign:
	var c := Campaign.new()
	c.guild_name = d["guild_name"]
	c.week = int(d["week"])
	c.gold = int(d["gold"])
	c.renown = int(d["renown"])
	c.materials = int(d["materials"])
	c.hush = int(d["hush"])
	c.difficulty = int(d["difficulty"])
	c.ironman = d["ironman"]
	c.act = int(d["act"])
	c.story_done = d["story_done"]
	c.final_unlocked = d["final_unlocked"]
	for md in d["roster"]:
		c.roster.append(Member.from_dict(md))
	c.dead = d["dead"]
	for md in d["recruits"]:
		c.recruits.append(Member.from_dict(md))
	for md in d.get("seeds", []):
		c.seeds.append(Member.from_dict(md))
	c.next_member_id = int(d["next_member_id"])
	c.facilities = d["facilities"]
	for k in c.facilities:
		c.facilities[k] = int(c.facilities[k])
	c.factions = d["factions"]
	for f in c.factions:
		for k in ["rep", "power", "chain", "chain_wait"]:
			c.factions[f][k] = int(c.factions[f][k])
	c.regions = d["regions"]
	for r in c.regions:
		c.regions[r]["hush"] = int(c.regions[r]["hush"])
	c.board = d["board"]
	for m in c.board:
		for k in ["id", "skulls", "days", "seed", "turns", "caches", "hush_map", "par_rounds", "conflict", "chain_step"]:
			if m.has(k):
				m[k] = int(m[k])
	c.inventory = d["inventory"]
	c.unpaid_weeks = int(d["unpaid_weeks"])
	c.flags = d["flags"]
	c.chronicle = d["chronicle"]
	c.pending_events = d["pending_events"]
	c.stats = d["stats"]
	c.game_over = d["game_over"]
	c.ending = d["ending"]
	c.rng.seed = int(d.get("rng_seed", "1"))
	c.rng.state = int(d.get("rng_state", "1"))
	c.next_mission_id = int(d["next_mission_id"])
	c.shop = d.get("shop", [])
	c.week_deaths = d.get("week_deaths", [])
	c.tutorial_seen = d.get("tutorial_seen", {})
	return c
