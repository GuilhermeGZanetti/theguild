class_name BattleAI
extends RefCounted
## Utility AI: scores every reachable tile x usable skill x target and
## picks the best plan. Profiles tweak the scoring (melee, ranged,
## skirmish, swarm, boss).

const STATUS_VALUE := {"stun": 12.0, "paralysis": 18.0, "fear": 12.0, "root": 6.0, "pinned": 8.0, "blind": 8.0,
	"marked": 5.0, "taunted": 6.0, "rallied": 5.0, "poison": 1.6, "bleed": 1.6, "burn": 1.6}

var b: Battle


func _init(battle: Battle) -> void:
	b = battle


func take_turn(u: BattleUnit) -> void:
	if not u.active():
		b.end_turn(u)
		return
	if u.team == BattleUnit.TEAM_PLAYER and _objective_step(u):
		if b.current == u:
			b.end_turn(u)
		return
	var plan := best_plan(u)
	if plan.is_empty():
		b.do_defend(u)
		return
	if plan["tile"] != u.pos:
		b.do_move(u, plan["tile"])
		if not u.active():
			if b.current == u:
				b.end_turn(u)
			return
	if plan.get("skill", "") != "" and u.active():
		var tgts := b.valid_targets(u, plan["skill"])
		if plan["target"] in tgts:
			b.use_skill(u, plan["skill"], plan["target"])
		else:
			var alt := _best_action_here(u)
			if not alt.is_empty():
				b.use_skill(u, alt["skill"], alt["target"])
	# skirmishers slip away after striking
	if u.ai == "skirmish" and u.active() and not u.moved and u.acted:
		var safe := _safest_tile(u)
		if safe != u.pos:
			b.do_move(u, safe)
	if u.active() and not u.acted and u.ai == "ranged" and plan.get("skill", "") == "":
		if b.current == u:
			b.do_overwatch(u)
			return
	if b.current == u:
		b.end_turn(u)


func best_plan(u: BattleUnit) -> Dictionary:
	var reach := b.reachable(u)
	var skills := []
	for s in u.usable_skills():
		if b.can_use(u, s):
			skills.append(s)
	var hostiles := b.hostiles_of(u)
	if hostiles.is_empty():
		return {}
	var best := {}
	var best_score := -1e9
	for tile in reach:
		if reach[tile].get("pass_only", false):
			continue
		var pos_score := position_score(u, tile, hostiles)
		if tile != u.pos:
			for o in b.aoo_attackers(u, b.path_to(u, tile, reach)):
				pos_score -= 8.0
		for s in skills:
			for tgt in b.valid_targets(u, s, tile):
				var v := eval_skill(u, s, tgt, tile)
				if v <= 0.5:
					continue
				var total := v + pos_score
				if total > best_score:
					best_score = total
					best = {"tile": tile, "skill": s, "target": tgt}
	if best.is_empty():
		# no action possible: advance toward the best target
		var goal := _goal_cell(u, hostiles)
		var field := b.distance_field([goal], u.swims, u.floats)
		var bt := u.pos
		var bd := 1e9
		for tile in reach:
			if reach[tile].get("pass_only", false):
				continue
			var fd := float(field.get(tile, 999))
			var d := fd - position_score(u, tile, hostiles) * 0.15
			if u.ai == "ranged":
				d = absf(fd - float(u.stat("range"))) - position_score(u, tile, hostiles) * 0.2
			if d < bd:
				bd = d
				bt = tile
		return {"tile": bt, "skill": "", "target": Vector2i.ZERO}
	return best


## Player-side autopilot: interact with objectives and walk VIPs out.
## Returns true when the whole turn was spent on the objective.
func _objective_step(u: BattleUnit) -> bool:
	if u.objective_role in ["vip", "captive"]:
		if b.can_extract(u):
			b.do_extract(u)
			return true
		var goal := _nearest_cell(u.pos, _extract_cells())
		_move_toward(u, goal)
		if b.can_extract(u):
			b.do_extract(u)
		return true
	if u.objective_role == "ally" or u.npc:
		return false
	for o in b.allies_of(u, false, false):
		if b.can_stabilize(u, o):
			b.do_stabilize(u, o)
			return false
	for c in b.interact_targets(u):
		b.do_interact(u, c)
		return false
	var objs := _objective_cells()
	if objs.is_empty():
		return false
	# go for objectives when nothing can be attacked this turn
	var attackable := false
	for s in u.usable_skills():
		if b.can_use(u, s) and not b.valid_targets(u, s).is_empty() and DB.skill(s).get("target", "") == "enemy":
			attackable = true
			break
	if attackable:
		return false
	_move_toward(u, _nearest_cell(u.pos, objs))
	for c in b.interact_targets(u):
		b.do_interact(u, c)
		break
	return true


func _objective_cells() -> Array:
	var out: Array = []
	for c in b.grid.all_cells():
		var o: Dictionary = b.grid.t(c)["obj"]
		if o.get("kind", "") in ["cache", "captive", "page"]:
			out.append(c)
	return out


func _extract_cells() -> Array:
	var out: Array = []
	for c in b.grid.all_cells():
		if b.grid.t(c)["extract"]:
			out.append(c)
	return out


func _nearest_cell(from: Vector2i, cells: Array) -> Vector2i:
	var best := from
	var bd := 1e9
	for c in cells:
		var d := float(Rules.distance(from, c))
		if d < bd:
			bd = d
			best = c
	return best


func _move_toward(u: BattleUnit, goal: Vector2i) -> void:
	var field := b.distance_field([goal], u.swims, u.floats)
	var reach := b.reachable(u)
	var bt := u.pos
	var bd := float(field.get(u.pos, 9999))
	for tile in reach:
		if reach[tile].get("pass_only", false):
			continue
		var d := float(field.get(tile, 9999))
		if d < bd:
			bd = d
			bt = tile
	if bt != u.pos:
		b.do_move(u, bt)


func _goal_cell(u: BattleUnit, hostiles: Array) -> Vector2i:
	var best: BattleUnit = null
	var bd := 1e9
	for o in hostiles:
		if o.hidden:
			continue
		var d := float(Rules.distance(u.pos, o.pos))
		if o.objective_role == "object":
			d *= 0.6
		if o.state == "downed":
			d += 6
		if d < bd:
			bd = d
			best = o
	return best.pos if best else u.pos


func _best_action_here(u: BattleUnit) -> Dictionary:
	var best := {}
	var bs := 0.5
	for s in u.usable_skills():
		if not b.can_use(u, s):
			continue
		for tgt in b.valid_targets(u, s):
			var v := eval_skill(u, s, tgt, u.pos)
			if v > bs:
				bs = v
				best = {"skill": s, "target": tgt}
	return best


func eval_skill(u: BattleUnit, skill_id: String, tgt: Vector2i, from: Vector2i) -> float:
	var s := DB.skill(skill_id)
	var pv := b.preview(u, skill_id, tgt, from)
	var total := 0.0
	var any := false
	for row in pv["targets"]:
		var o: BattleUnit = b.unit(row["uid"])
		if o == null:
			continue
		any = true
		var hostile := u.hostile_to(o)
		var sign_v := 1.0 if hostile else -1.0
		var prio := 1.0
		if o.objective_role == "object":
			prio = 1.35
		if o.objective_role in ["vip", "captive"]:
			prio = 1.3
		if o.state == "downed":
			prio = [0.0, 0.35, 0.9][clampi(b.difficulty, 0, 2)]
		if row.has("hit"):
			var hit: float = row["hit"] / 100.0
			var crit: float = row["crit"] / 100.0
			var avg := (float(row["dmg_min"]) + float(row["dmg_max"])) * 0.5 * float(row.get("hits", 1))
			var exp := hit * avg * (1.0 + crit)
			var kill := 0.0
			if avg * (1.0 + crit * 0.5) >= o.hp:
				kill = 22.0 * hit
			if o.state == "downed":
				kill = 30.0 * hit
			total += sign_v * (exp + kill) * prio
		if row.has("statuses"):
			for st in row["statuses"]:
				var sid: String = st[0]
				var ch: float = st[1] / 100.0
				var val: float = STATUS_VALUE.get(sid, 4.0)
				if sid in ["poison", "bleed", "burn"]:
					val *= 4.0
				var bad: bool = DB.statuses.get(sid, {}).get("bad", true)
				if bad and o.has_status(sid):
					val *= 0.3
				if not bad and o.has_status(sid):
					val *= 0.2
				total += (sign_v if bad else -sign_v) * val * ch * (1.0 if o.state != "downed" else 0.0)
		if row.has("heal"):
			var missing := o.max_hp() - o.hp
			total += minf(float(row["heal"]), missing) * (1.0 if not hostile else -1.0)
	for eff in s.get("effects", []):
		match eff["t"]:
			"erase_skill":
				total += 14.0
			"pull", "push":
				total += 3.0
			"terrain":
				total += 6.0
	if not any and s.get("target", "") in ["tile", "empty_tile"]:
		return 0.0
	# the basic attack is always a fine fallback, specials a little better
	if not s.get("basic", false):
		total *= 1.05
	return total


func position_score(u: BattleUnit, tile: Vector2i, hostiles: Array) -> float:
	var sc := 0.0
	var ranged := not u.melee
	var nearest := 1e9
	for o in hostiles:
		if o.hidden or o.state != "active":
			continue
		var d := Rules.distance(tile, o.pos)
		nearest = minf(nearest, d)
		if d <= int(o.stat("move")) + int(o.stat("range")) + 1:
			var c := b.grid.cover_from(tile, o.pos)
			sc += c * 2.5
			if c == 0 and not o.melee:
				sc -= 2.0
	if ranged:
		if nearest <= 1:
			sc -= 7.0
		elif nearest <= 2:
			sc -= 2.5
	if u.ai == "skirmish" and nearest <= 1:
		sc -= 2.0
	if b.grid.height(tile) > 0:
		sc += 0.6 * b.grid.height(tile)
	var fx: Dictionary = b.grid.t(tile)["fx"]
	if not fx.is_empty() and int(fx.get("team", -1)) != u.team and fx["kind"] in ["fire", "flood", "thorns", "trap"]:
		sc -= 8.0
	return sc


func _safest_tile(u: BattleUnit) -> Vector2i:
	var reach := b.reachable(u)
	var hostiles := b.hostiles_of(u)
	var best := u.pos
	var bs := -1e9
	for tile in reach:
		if reach[tile].get("pass_only", false) or reach[tile]["zoc"]:
			continue
		var s := position_score(u, tile, hostiles)
		for o in hostiles:
			s += minf(Rules.distance(tile, o.pos), 6) * 0.8
		if s > bs:
			bs = s
			best = tile
	return best
