class_name AutoPilot
extends RefCounted
## A bot that plays the campaign like a careful player. Used by tests to
## balance the economy and to smoke-test every system end to end.

const PRIORITY := {"story": 0, "breach": 1, "crisis": 2, "chain": 2, "rivalry": 3, "recruit": 3, "contract": 4, "salvage": 5, "training": 6}
const BUILD_ORDER := ["nursery", "recruiter", "barracks", "memorial", "training", "forge", "library"]

var c: Campaign
var log: Array = []
var battles := 0
var wins := 0


func _init(campaign: Campaign) -> void:
	c = campaign


func play_week(max_missions := 3, allow_final := true) -> void:
	_handle_events()
	_manage()
	var missions := c.board.duplicate()
	missions.sort_custom(func(a, b): return PRIORITY.get(a["category"], 9) < PRIORITY.get(b["category"], 9))
	var played := 0
	for m in missions:
		if played >= max_missions or c.game_over != "":
			break
		if not c.mission_by_id(int(m["id"])).size():
			continue
		if m.get("story_id", "") == "final" and (not allow_final or c.roster.size() < 4 or _avg_level() < 4):
			continue
		var squad := _pick_squad(m)
		if squad.size() < mini(3, c.squad_cap()) or c.can_launch(m, squad) != "":
			continue
		# skulls are member levels: nothing past the squad's, and the story at most one past
		var reach := 1 if m["category"] in ["story", "breach"] else 0
		if int(m["skulls"]) > roundi(_level_of(squad)) + reach:
			continue
		var b := BattleFactory.build(m, squad, c.battle_context(m))
		run_battle(b)
		battles += 1
		if b.result == "victory":
			wins += 1
		c.finish_mission(m, b)
		played += 1
	_handle_events()
	if c.game_over == "":
		c.end_week()


static func run_battle(b: Battle, max_turns := 900) -> void:
	var guard := 0
	while not b.over and guard < max_turns:
		guard += 1
		b.auto_step()
		b.pop_events()
	if not b.over:
		b._finish("retreat")


func _avg_level() -> float:
	var s := 0.0
	var n := 0
	for m in c.active_members():
		s += m.level
		n += 1
	return s / maxf(n, 1)


func _level_of(squad: Array) -> float:
	var s := 0.0
	for m in squad:
		s += m.level
	return s / maxf(squad.size(), 1)


func _pick_squad(m: Dictionary) -> Array:
	var avail := c.available_members()
	avail.sort_custom(func(a, b): return a.level > b.level)
	var squad: Array = []
	var classes := {}
	for mem in avail:
		if squad.size() >= c.squad_cap():
			break
		if classes.get(mem.cls, 0) >= 2:
			continue
		squad.append(mem)
		classes[mem.cls] = classes.get(mem.cls, 0) + 1
	for mem in avail:
		if squad.size() >= c.squad_cap():
			break
		if not mem in squad:
			squad.append(mem)
	return squad


func _handle_events() -> void:
	for ev in c.pending_events:
		match ev.get("kind", ""):
			"random":
				var d: Dictionary = DB.events["random"][ev["id"]]
				var choice := 1 if d["choices"].size() > 1 else 0
				if int(d["choices"][0].get("cost", {}).get("gold", 0)) < c.gold / 5:
					choice = 0
				c.resolve_event(ev["id"], choice)
			"war":
				var a: String = ev["a"]
				var b: String = ev["b"]
				if int(c.factions[a]["rep"]) >= int(c.factions[b]["rep"]):
					c.resolve_war(a, b)
				else:
					c.resolve_war(b, a)
	c.pending_events.clear()


func _manage() -> void:
	var reserve := c.weekly_wages() * 2 + 60
	# memorial first: names protect against the Hush
	for i in c.dead.size():
		if not c.dead[i].get("memorial", false) and c.memorial_cost() >= 0 and c.gold > c.memorial_cost() + reserve:
			c.record_memorial(i)
	for fid in BUILD_ORDER:
		var cost := c.facility_upgrade_cost(fid)
		if cost > 0 and c.gold > cost + reserve and c.renown >= c.facility_renown_req(fid):
			if c.upgrade_facility(fid) == "":
				log.append("week %d built %s" % [c.week, fid])
				break
	# skill trees: each member leans on one branch
	for m in c.active_members():
		if m.pending_picks() > 0:
			var brs: Array = m.class_data()["branches"].keys()
			m.auto_pick(c.rng, brs[m.id % brs.size()])
		if m.loadout.size() < Member.LOADOUT:
			for s in m.active_skills():
				if not s in m.loadout and m.loadout.size() < Member.LOADOUT:
					m.loadout.append(s)
	# gear
	for item in c.inventory.duplicate():
		for m in c.active_members():
			var slot := Items.slot(item)
			if slot == "" or not Items.fits(item, m.cls):
				continue
			var cur: Dictionary = m.equipment.get(slot, {})
			if cur.is_empty() or Items.tier_of(item) > Items.tier_of(cur):
				c.equip(m, item)
				break
	for m in c.active_members():
		for s in ["armor", "weapon"]:
			var it: Dictionary = m.equipment.get(s, {})
			if c.can_forge(it) == "" and c.gold > c.forge_cost(it)[0] + reserve:
				c.forge_upgrade(it, m)
	# hire
	var want := c.squad_cap() + 3
	while c.active_members().size() < mini(want, c.roster_cap()) and not c.recruits.is_empty():
		var best: Member = null
		for r in c.recruits:
			if best == null or r.tier * 10 + r.level > best.tier * 10 + best.level:
				best = r
		if best == null or c.gold < best.hire_cost + reserve / 2:
			break
		if c.hire(best) != "":
			break
