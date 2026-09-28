class_name Battle
extends RefCounted
## Turn-based combat rules. Headless: every state change is appended to
## `events` so the 3D view can animate it and tests/AI can run without it.

var grid: BattleGrid
var units: Array = []
var rng := RandomNumberGenerator.new()
var time := 0.0
var round_num := 1
var current: BattleUnit = null
var events: Array = []
var mission := {}
var objective := {}
var bonus: Array = []
var result := ""
var over := false
var skulls := 1
var difficulty := 1
var waves: Array = []
var next_uid := 1
var turn_count := 0
var downs := 0
var deaths := 0
var pages_found := 0
var chests_opened := 0
var ai: BattleAI = null
var log_lines: Array = []


func _init() -> void:
	ai = BattleAI.new(self)


# ====================================================================== query
func add_unit(u: BattleUnit) -> BattleUnit:
	u.uid = next_uid
	next_uid += 1
	units.append(u)
	return u


func unit(uid: int) -> BattleUnit:
	for u in units:
		if u.uid == uid:
			return u
	return null


func unit_at(p: Vector2i, include_dead := false) -> BattleUnit:
	for u in units:
		if u.pos == p and u.carried_by < 0:
			if u.state == "active" or u.state == "downed":
				return u
			if include_dead and u.state == "dead":
				return u
	return null


func blocked_by_unit(p: Vector2i) -> bool:
	return unit_at(p) != null


func team_units(team: int, only_active := true) -> Array:
	var out: Array = []
	for u in units:
		if u.team == team and (u.active() if only_active else u.alive()):
			out.append(u)
	return out


func hostiles_of(u: BattleUnit, only_active := true) -> Array:
	var out: Array = []
	for o in units:
		if o != u and u.hostile_to(o) and (o.active() if only_active else o.alive()) and o.carried_by < 0:
			out.append(o)
	return out


func allies_of(u: BattleUnit, include_self := true, only_active := true) -> Array:
	var out: Array = []
	for o in units:
		if (o != u or include_self) and not u.hostile_to(o) and (o.active() if only_active else o.alive()) and o.carried_by < 0:
			out.append(o)
	return out


func visible_to_player(u: BattleUnit) -> bool:
	return not u.hidden


func is_ranged_skill(s: Dictionary) -> bool:
	var k: String = s.get("range", {}).get("kind", "melee")
	return k == "weapon" or (k == "fixed" and int(s["range"].get("max", 1)) > 1) or k == "charge"


# ====================================================================== timeline
func start() -> void:
	for u in units:
		var d := Rules.turn_delay(u.stat("speed"))
		u.next_time = d * rng.randf_range(0.15, 0.95) * (0.75 if u.team == BattleUnit.TEAM_PLAYER else 1.0)
		u.def_cur = u.max_def()
	_update_hidden()
	emit({"t": "start"})


func timeline_preview(count := 12) -> Array:
	## Upcoming turns as [uid, time] without changing state.
	var sim: Array = []
	for u in units:
		if not u.alive() or u.carried_by >= 0 or u.hidden or u.objective_role == "object":
			continue
		if u.state == "downed" and u.stabilized:
			continue
		sim.append([u.uid, u.next_time, Rules.turn_delay(u.stat("speed"))])
	var out: Array = []
	if sim.is_empty():
		return out
	for i in count:
		var best := 0
		for j in sim.size():
			if sim[j][1] < sim[best][1]:
				best = j
		out.append([sim[best][0], sim[best][1]])
		sim[best][1] += sim[best][2]
	return out


func next_turn() -> BattleUnit:
	if over:
		return null
	var best: BattleUnit = null
	for u in units:
		if not u.alive() or u.carried_by >= 0:
			continue
		if u.objective_role == "object":
			continue
		if best == null or u.next_time < best.next_time:
			best = u
	if best == null:
		_check_end()
		return null
	time = best.next_time
	var r := int(floor(time / Rules.ROUND_TICKS)) + 1
	while r > round_num and not over:
		round_num += 1
		_on_new_round()
	if over:
		return null
	current = best
	turn_count += 1
	_begin_turn(best)
	return best


func _begin_turn(u: BattleUnit) -> void:
	u.moved = false
	u.acted = false
	emit({"t": "turn", "uid": u.uid})
	if u.state == "downed":
		if not u.stabilized:
			u.bleed -= 1
			emit({"t": "bleed", "uid": u.uid, "left": u.bleed})
			if u.bleed <= 0:
				_kill(u, null, "bled out")
		end_turn(u)
		return
	# start-of-turn statuses
	for sid in ["defending", "overwatch", "dodge_up", "warded", "shielded", "last_stand"]:
		_tick_status(u, sid)
	if u.def_regen > 0 and u.def_cur < u.max_def():
		u.def_cur = minf(u.max_def(), u.def_cur + u.def_regen)
	var tile := grid.t(u.pos)
	var fx: Dictionary = tile["fx"]
	if fx.get("kind", "") == "sanctuary" and int(fx.get("team", -1)) == u.team:
		_heal(u, 6, null)
	if fx.get("kind", "") == "flood" and not u.swims and not u.floats and u.team != int(fx.get("team", -1)):
		_damage_raw(u, 4, null, "drown")
	if fx.get("kind", "") == "fire":
		_apply_status(null, u, "burn", 100, 2, 3)
	for s in u.statuses.duplicate():
		match s["id"]:
			"poison", "burn":
				_damage_raw(u, int(s.get("power", 3)), null, s["id"])
			"bleed":
				_damage_raw(u, int(s.get("power", 3)) * int(s.get("stacks", 1)), null, "bleed")
			"regen":
				_heal(u, int(s.get("power", 4)), null)
		if not u.active():
			end_turn(u)
			return
	for sid in ["poison", "burn", "bleed", "regen"]:
		_tick_status(u, sid)
	if u.has_status("paralysis"):
		emit({"t": "float", "uid": u.uid, "text": "Paralyzed", "kind": "bad"})
		u.moved = true
		u.acted = true
		end_turn(u)
		return
	if u.has_status("stun"):
		emit({"t": "float", "uid": u.uid, "text": "Stunned", "kind": "bad"})
		u.acted = true
	if u.has_status("root") or u.has_status("pinned"):
		u.moved = true
	if u.has_status("fear"):
		_flee(u)
		u.acted = true
		u.moved = true
		end_turn(u)
		return


func _tick_status(u: BattleUnit, sid: String) -> void:
	for i in range(u.statuses.size() - 1, -1, -1):
		var s: Dictionary = u.statuses[i]
		if s["id"] == sid:
			s["dur"] = int(s["dur"]) - 1
			if s["dur"] <= 0:
				u.statuses.remove_at(i)
				emit({"t": "status_end", "uid": u.uid, "id": sid})


func end_turn(u: BattleUnit, delay_mult := 1.0) -> void:
	if u == null:
		return
	for k in u.cds.keys():
		if int(u.cds[k]) > 0:
			u.cds[k] = int(u.cds[k]) - 1
	for sid in ["root", "pinned", "blind", "fear", "taunted", "stun", "paralysis", "marked", "rallied", "inspired"]:
		_tick_status(u, sid)
	u.next_time += Rules.turn_delay(u.stat("speed")) * delay_mult
	if current == u:
		current = null
	emit({"t": "end_turn", "uid": u.uid})
	_check_end()


func do_wait(u: BattleUnit) -> void:
	if u.moved or u.acted:
		return
	u.next_time += Rules.turn_delay(u.stat("speed")) * 0.5
	emit({"t": "float", "uid": u.uid, "text": "Wait", "kind": "info"})
	current = null
	emit({"t": "end_turn", "uid": u.uid})


func do_defend(u: BattleUnit) -> void:
	_add_status(u, "defending", 1, 0, u)
	emit({"t": "float", "uid": u.uid, "text": "Defend", "kind": "info"})
	emit({"t": "anim", "uid": u.uid, "anim": "cast"})
	u.acted = true
	end_turn(u)


func do_overwatch(u: BattleUnit) -> void:
	_add_status(u, "overwatch", 1, 0, u)
	u.overwatch_left = maxi(1, int(u.mod("overwatch_shots", 1)))
	emit({"t": "float", "uid": u.uid, "text": "Overwatch", "kind": "info"})
	u.acted = true
	end_turn(u)


func _on_new_round() -> void:
	emit({"t": "round", "n": round_num})
	# terrain durations
	for p in grid.all_cells():
		var tl := grid.t(p)
		var fx: Dictionary = tl["fx"]
		if fx.is_empty():
			continue
		fx["dur"] = int(fx.get("dur", 1)) - 1
		if fx["kind"] == "fire" and rng.randf() < 0.35:
			for n in grid.neighbors4(p):
				var nt := grid.t(n)
				if nt["flammable"] and nt["fx"].is_empty():
					nt["fx"] = {"kind": "fire", "dur": 2, "team": -1}
					emit({"t": "terrain", "cells": [n], "kind": "fire"})
		if fx["dur"] <= 0:
			tl["fx"] = {}
			emit({"t": "terrain_end", "cells": [p], "kind": fx["kind"]})
	for w in waves:
		if int(w["round"]) == round_num and not w.get("done", false):
			w["done"] = true
			_spawn_wave(w)
	_check_objective_rounds()


# ====================================================================== movement
func zoc_radius(u: BattleUnit) -> int:
	return int(u.mod("zoc_radius", 1))


func exerts_zoc(u: BattleUnit) -> bool:
	return u.active() and u.melee and not u.hidden and not u.npc and not u.has_status("fear") and not u.has_status("paralysis") and u.carrying < 0


func zoc_holders(p: Vector2i, mover: BattleUnit) -> Array:
	var out: Array = []
	for o in units:
		if o == mover or not mover.hostile_to(o) or not exerts_zoc(o) or o.carried_by >= 0:
			continue
		if Rules.chebyshev(o.pos, p) <= zoc_radius(o) and absi(grid.height(o.pos) - grid.height(p)) <= 2:
			out.append(o)
	return out


func move_budget(u: BattleUnit) -> int:
	if u.moved or u.has_status("root") or u.has_status("pinned") or u.objective_role == "object":
		return 0
	var b := int(u.stat("move"))
	if int(u.mod("water_move", 0)) > 0 and grid.t(u.pos)["water"] > 0:
		b += int(u.mod("water_move", 0))
	return maxi(b, 1)


## Running doubles the move but spends the action too, so it needs one left.
func run_budget(u: BattleUnit) -> int:
	if u.acted or u.carrying >= 0:
		return 0
	return move_budget(u) * 2


## Movement reach including the run band; cells costing more than
## move_budget() are run-only.
func reachable_with_run(u: BattleUnit) -> Dictionary:
	return reachable(u, maxi(move_budget(u), run_budget(u)))


func is_run(u: BattleUnit, reach: Dictionary, dest: Vector2i) -> bool:
	return reach.has(dest) and int(reach[dest]["cost"]) > move_budget(u)


## Dijkstra over the grid honouring height, water, units and zones of control.
## Returns cell -> {"cost", "prev", "zoc"}.
func reachable(u: BattleUnit, budget := -1) -> Dictionary:
	if budget < 0:
		budget = move_budget(u)
	var out := {u.pos: {"cost": 0, "prev": u.pos, "zoc": false}}
	if budget <= 0:
		return out
	var frontier: Array = [[0, u.pos]]
	while not frontier.is_empty():
		var bi := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[bi][0]:
				bi = i
		var cur: Array = frontier[bi]
		frontier.remove_at(bi)
		var cost: int = cur[0]
		var p: Vector2i = cur[1]
		if cost > int(out[p]["cost"]):
			continue
		if p != u.pos and out[p]["zoc"]:
			continue
		for n in grid.neighbors4(p):
			var sc := grid.step_cost(p, n, u.swims, u.floats)
			if sc < 0:
				continue
			var nc := cost + sc
			if nc > budget:
				continue
			var occ := unit_at(n)
			if occ != null and u.hostile_to(occ):
				continue
			if out.has(n) and int(out[n]["cost"]) <= nc:
				continue
			var z := not zoc_holders(n, u).is_empty()
			out[n] = {"cost": nc, "prev": p, "zoc": z}
			frontier.append([nc, n])
	# cannot stop on occupied tiles
	for c in out.keys():
		if c != u.pos and unit_at(c) != null:
			out[c]["pass_only"] = true
	return out


## Walking distance from every cell to the nearest goal cell (ignores units).
func distance_field(goals: Array, swims := false, floats := false) -> Dictionary:
	var dist := {}
	var frontier: Array = []
	for gcell in goals:
		dist[gcell] = 0
		frontier.append(gcell)
	var head := 0
	while head < frontier.size():
		var p: Vector2i = frontier[head]
		head += 1
		for n in grid.neighbors4(p):
			# walking from n to p
			var sc := grid.step_cost(n, p, swims, floats)
			if sc < 0 and not goals.has(p):
				continue
			if sc < 0:
				sc = 1
			if not grid.standable(n, swims, floats):
				continue
			var nd: int = dist[p] + sc
			if not dist.has(n) or nd < int(dist[n]):
				dist[n] = nd
				frontier.append(n)
	return dist


func path_to(u: BattleUnit, dest: Vector2i, reach := {}) -> Array:
	if reach.is_empty():
		reach = reachable(u)
	if not reach.has(dest) or reach[dest].get("pass_only", false):
		return []
	var path: Array = []
	var p := dest
	while p != u.pos:
		path.push_front(p)
		p = reach[p]["prev"]
	return path


func aoo_attackers(u: BattleUnit, path: Array) -> Array:
	if path.is_empty():
		return []
	var before := zoc_holders(u.pos, u)
	var after := zoc_holders(path[0], u)
	var out: Array = []
	for o in before:
		if not o in after:
			out.append(o)
	return out


func do_move(u: BattleUnit, dest: Vector2i) -> bool:
	var reach := reachable_with_run(u)
	var path := path_to(u, dest, reach)
	if path.is_empty():
		return false
	if is_run(u, reach, dest):
		u.acted = true
		emit({"t": "float", "uid": u.uid, "text": "Run!", "kind": "warn"})
	u.moved = true
	for o in aoo_attackers(u, path):
		if not u.active():
			break
		emit({"t": "float", "uid": o.uid, "text": "Attack of Opportunity", "kind": "warn"})
		_face(o, u.pos)
		_attack_basic(o, u, {"aoo": true})
	if not u.active():
		return true
	var walked: Array = []
	for step in path:
		if not u.active():
			break
		var prev := u.pos
		u.pos = step
		_face(u, step + (step - prev))
		walked.append(step)
		var stop := false
		var tile := grid.t(step)
		var fx: Dictionary = tile["fx"]
		if fx.get("kind", "") == "trap" and int(fx.get("team", -1)) != u.team:
			emit({"t": "move", "uid": u.uid, "path": walked.duplicate()})
			walked.clear()
			_trigger_trap(u, step, fx)
			stop = true
		elif fx.get("kind", "") == "thorns" and int(fx.get("team", -1)) != u.team:
			emit({"t": "move", "uid": u.uid, "path": walked.duplicate()})
			walked.clear()
			_apply_status(null, u, "bleed", 100, 2, 3)
		elif fx.get("kind", "") == "fire":
			emit({"t": "move", "uid": u.uid, "path": walked.duplicate()})
			walked.clear()
			_apply_status(null, u, "burn", 70, 2, 3)
		# overwatch
		for o in hostiles_of(u):
			if not u.active():
				break
			if o.has_status("overwatch") and o.overwatch_left > 0:
				var s := DB.skill(o.basic)
				if _in_skill_range(o, s, o.pos, u.pos) and _los_ok(o, s, o.pos, u.pos):
					if not walked.is_empty():
						emit({"t": "move", "uid": u.uid, "path": walked.duplicate()})
						walked.clear()
					o.overwatch_left -= 1
					if o.overwatch_left <= 0:
						o.remove_status("overwatch")
					emit({"t": "float", "uid": o.uid, "text": "Overwatch!", "kind": "warn"})
					_face(o, u.pos)
					_attack_basic(o, u, {"overwatch": true})
		_update_hidden()
		if stop or not u.active() or u.has_status("root"):
			break
	if not walked.is_empty():
		emit({"t": "move", "uid": u.uid, "path": walked})
	if u.carrying >= 0:
		var body := unit(u.carrying)
		if body:
			body.pos = u.pos
	_check_end()
	return true


func _trigger_trap(u: BattleUnit, p: Vector2i, fx: Dictionary) -> void:
	grid.t(p)["fx"] = {}
	emit({"t": "terrain_end", "cells": [p], "kind": "trap"})
	emit({"t": "float", "uid": u.uid, "text": "Snare!", "kind": "bad"})
	_damage_raw(u, int(fx.get("power", 12)), unit(int(fx.get("owner", -1))), "trap")
	if u.active():
		_add_status(u, "root", 2, 0, null)


func _flee(u: BattleUnit) -> void:
	var src: BattleUnit = unit(int(u.get_status("fear").get("source", -1)))
	var threats: Array = [src] if src and src.alive() else hostiles_of(u)
	if threats.is_empty():
		return
	var reach := reachable(u, int(u.stat("move")))
	var best := u.pos
	var best_score := -9999.0
	for c in reach:
		if reach[c].get("pass_only", false) or reach[c]["zoc"]:
			continue
		var d := 0.0
		for tth in threats:
			d += Rules.distance(c, tth.pos)
		if d > best_score:
			best_score = d
			best = c
	emit({"t": "float", "uid": u.uid, "text": "Afraid!", "kind": "bad"})
	if best != u.pos:
		do_move(u, best)


func _update_hidden() -> void:
	for e in units:
		if not e.hidden or not e.active():
			continue
		for p in units:
			if p.team == e.team or not p.active():
				continue
			var sight := 2 + int(p.mod("sight", 0))
			if Rules.chebyshev(p.pos, e.pos) <= sight:
				_reveal(e)
				break


func _reveal(e: BattleUnit) -> void:
	if e.hidden:
		e.hidden = false
		emit({"t": "reveal", "uid": e.uid})


func _face(u: BattleUnit, target: Vector2i) -> void:
	var d := target - u.pos
	if d == Vector2i.ZERO:
		return
	if absi(d.x) >= absi(d.y):
		u.facing = Vector2i(signi(d.x), 0)
	else:
		u.facing = Vector2i(0, signi(d.y))
	emit({"t": "face", "uid": u.uid, "dir": u.facing})


# ====================================================================== targeting
func skill_range(u: BattleUnit, s: Dictionary, from: Vector2i) -> Array:
	## [min, optimal, max]
	var r: Dictionary = s.get("range", {"kind": "melee"})
	match r.get("kind", "melee"):
		"self":
			return [0, 0, 0]
		"melee":
			return [1, 1, 1]
		"weapon":
			var opt := int(u.stat("range")) + int(r.get("bonus", 0))
			return [1, opt, opt + Rules.MAX_RANGE_EXTRA]
		"fixed", "charge":
			return [int(r.get("min", 1)), int(r.get("max", 1)), int(r.get("max", 1))]
	return [1, 1, 1]


func _high_ground(u_pos: Vector2i, t_pos: Vector2i) -> bool:
	return grid.height(u_pos) - grid.height(t_pos) >= 1


func _in_skill_range(u: BattleUnit, s: Dictionary, from: Vector2i, target: Vector2i) -> bool:
	var rr := skill_range(u, s, from)
	var kind: String = s.get("range", {}).get("kind", "melee")
	if kind == "self":
		return target == from
	if kind == "melee":
		return Rules.chebyshev(from, target) == 1 and absi(grid.height(from) - grid.height(target)) <= 2
	var d := Rules.distance(from, target)
	var mx: int = rr[2]
	if kind == "weapon" and _high_ground(from, target):
		mx += 1
	return d >= rr[0] and d <= mx


func _los_ok(u: BattleUnit, s: Dictionary, from: Vector2i, target: Vector2i) -> bool:
	var kind: String = s.get("range", {}).get("kind", "melee")
	if kind == "melee" or kind == "self":
		return true
	var need: bool = s.get("los", true)
	if not need:
		return true
	return grid.los(from, target)


func valid_targets(u: BattleUnit, skill_id: String, from := Vector2i(-99, -99)) -> Array:
	if from == Vector2i(-99, -99):
		from = u.pos
	var s := DB.skill(skill_id)
	var out: Array = []
	var tgt: String = s.get("target", "enemy")
	var taunter := -1
	if u.has_status("taunted"):
		taunter = int(u.get_status("taunted").get("source", -1))
	match tgt:
		"self":
			out.append(from)
		"enemy":
			for o in hostiles_of(u):
				if o.hidden:
					continue
				if taunter >= 0 and unit(taunter) and unit(taunter).active() and o.uid != taunter:
					continue
				if _in_skill_range(u, s, from, o.pos) and _los_ok(u, s, from, o.pos):
					if s.get("range", {}).get("kind", "") == "charge" and _charge_path(u, from, o.pos).is_empty():
						continue
					out.append(o.pos)
		"ally", "ally_or_self":
			for o in units:
				if o.carried_by >= 0 or not o.alive() or u.hostile_to(o):
					continue
				if tgt == "ally" and o == u:
					continue
				if o.objective_role == "object":
					continue
				var op: Vector2i = o.pos if o != u else from
				if _in_skill_range(u, s, from, op) or (op == from and tgt == "ally_or_self"):
					out.append(op)
		"tile", "empty_tile":
			var rr := skill_range(u, s, from)
			for c in grid.cells_in_radius(from, rr[2] + 1):
				if tgt == "empty_tile" and (not grid.standable(c, u.swims, u.floats) or unit_at(c, true) != null):
					continue
				if Rules.distance(from, c) < rr[0] or Rules.distance(from, c) > rr[2]:
					continue
				if not _los_ok(u, s, from, c):
					continue
				out.append(c)
	return out


func can_use(u: BattleUnit, skill_id: String) -> bool:
	if not u.active() or skill_id in u.erased:
		return false
	var s := DB.skill(skill_id)
	if s.is_empty() or s.get("passive", false):
		return false
	if u.cooldown(skill_id) > 0:
		return false
	var uses: String = s.get("uses", "move" if s.get("keeps_action", false) else "action")
	if uses == "move":
		if u.moved:
			return false
	elif u.acted:
		return false
	if u.has_status("fear") and s.get("target", "enemy") == "enemy":
		return false
	return true


func affected(u: BattleUnit, skill_id: String, target: Vector2i, from := Vector2i(-99, -99)) -> Array:
	## Units hit by a skill aimed at `target`.
	if from == Vector2i(-99, -99):
		from = u.pos
	var s := DB.skill(skill_id)
	var aoe: Dictionary = s.get("aoe", {"shape": "single"})
	var who: String = aoe.get("who", "")
	if who == "":
		who = "enemy" if s.get("target", "enemy") == "enemy" else ("ally" if s.get("target", "") in ["ally", "ally_or_self"] else "any")
	var cells: Array = []
	match aoe.get("shape", "single"):
		"single":
			cells = [target]
		"radius":
			var center := target if s.get("target", "") != "self" else from
			cells = grid.cells_in_radius(center, int(aoe.get("r", 1)))
		"arc":
			cells = [target]
			for n in grid.neighbors8(target):
				if Rules.chebyshev(n, from) == 1:
					cells.append(n)
		"line":
			var dir := Vector2(target - from).normalized()
			var seen := {}
			for i in range(1, int(aoe.get("len", 6)) + 1):
				var c := from + Vector2i(roundi(dir.x * i), roundi(dir.y * i))
				if not grid.inb(c) or seen.has(c):
					continue
				seen[c] = true
				if grid.t(c)["block"]:
					break
				cells.append(c)
		"cone":
			cells = cone_cells(from, target, int(aoe.get("len", 3)))
		"chain":
			var first := unit_at(target)
			var chain: Array = []
			if first:
				chain.append(first)
				var last: BattleUnit = first
				for j in int(aoe.get("jumps", 2)):
					var nxt: BattleUnit = null
					var nd := 999
					for o in hostiles_of(u):
						if o in chain or o.hidden:
							continue
						var d := Rules.distance(last.pos, o.pos)
						if d <= int(aoe.get("r", 2)) and d < nd:
							nd = d
							nxt = o
					if nxt == null:
						break
					chain.append(nxt)
					last = nxt
			return chain
		"wall":
			cells = wall_cells(from, target, int(aoe.get("len", 3)))
	var out: Array = []
	for c in cells:
		var o := unit_at(c)
		if o == null or o.hidden:
			continue
		if who == "enemy" and not u.hostile_to(o):
			continue
		if who == "ally" and u.hostile_to(o):
			continue
		if o.objective_role == "object" and who != "enemy":
			continue
		out.append(o)
	return out


func cone_cells(from: Vector2i, target: Vector2i, length: int) -> Array:
	var d := target - from
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 0)
	var side := Vector2i(dir.y, dir.x)
	var cells: Array = []
	for i in range(1, length + 1):
		for j in range(-(i - 1), i):
			var c := from + dir * i + side * j
			if grid.inb(c):
				cells.append(c)
	return cells


func wall_cells(from: Vector2i, target: Vector2i, length: int) -> Array:
	var d := target - from
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	var side := Vector2i(dir.y, dir.x)
	if side == Vector2i.ZERO:
		side = Vector2i(1, 0)
	var cells: Array = []
	var half := length / 2
	for j in range(-half, length - half):
		var c := target + side * j
		if grid.inb(c) and grid.standable(c):
			cells.append(c)
	return cells


func aoe_cells(u: BattleUnit, skill_id: String, target: Vector2i) -> Array:
	## Cells highlighted when previewing an area skill.
	var s := DB.skill(skill_id)
	var aoe: Dictionary = s.get("aoe", {"shape": "single"})
	match aoe.get("shape", "single"):
		"radius":
			var center := target if s.get("target", "") != "self" else u.pos
			return grid.cells_in_radius(center, int(aoe.get("r", 1)))
		"cone":
			return cone_cells(u.pos, target, int(aoe.get("len", 3)))
		"wall":
			return wall_cells(u.pos, target, int(aoe.get("len", 3)))
		"line":
			var out: Array = []
			var dir := Vector2(target - u.pos).normalized()
			for i in range(1, int(aoe.get("len", 6)) + 1):
				var c := u.pos + Vector2i(roundi(dir.x * i), roundi(dir.y * i))
				if grid.inb(c) and not c in out:
					if grid.t(c)["block"]:
						break
					out.append(c)
			return out
		"arc":
			var cells: Array = [target]
			for n in grid.neighbors8(target):
				if Rules.chebyshev(n, u.pos) == 1:
					cells.append(n)
			return cells
	return [target]


# ====================================================================== attack math
func attack_context(att: BattleUnit, target: BattleUnit, s: Dictionary, eff: Dictionary, from := Vector2i(-99, -99), extra := {}) -> Dictionary:
	if from == Vector2i(-99, -99):
		from = att.pos
	var ranged := is_ranged_skill(s) and Rules.chebyshev(from, target.pos) > 1
	var cover := 0
	var flank := false
	if ranged:
		cover = grid.cover_from(target.pos, from)
		if target.has_status("shielded"):
			cover = maxi(cover, 1)
		flank = cover == 0
	else:
		var to_att := from - target.pos
		var dotv := to_att.x * target.facing.x + to_att.y * target.facing.y
		flank = dotv <= 0
	var high := _high_ground(from, target.pos)
	var beyond := 0
	if s.get("range", {}).get("kind", "") == "weapon":
		var opt := int(att.stat("range")) + int(s["range"].get("bonus", 0)) + (1 if high else 0)
		beyond = maxi(0, Rules.distance(from, target.pos) - opt)
	var acc := att.stat("accuracy") + float(eff.get("acc", 0))
	if ranged:
		acc += float(att.mod("ranged_acc", 0))
		if not att.moved and int(att.mod("steady_hands", 0)) > 0 and from == att.pos:
			acc += float(att.mod("steady_hands", 0))
	var dodge := target.stat("dodge")
	var ttile := grid.t(target.pos)
	if ranged and ttile["fx"].get("kind", "") == "smoke":
		dodge += 30
	if ttile["water"] > 0 and int(target.mod("water_dodge", 0)) > 0:
		dodge += float(target.mod("water_dodge", 0))
	if ttile["fx"].get("kind", "") == "flood" and not target.swims and not target.floats:
		dodge -= 20
	if target.state == "downed":
		dodge = -100
	var extra_hit := target.status_power("marked")
	if extra.get("aoo", false):
		extra_hit += float(att.mod("aoo_hit", 0))
	if extra.get("overwatch", false):
		extra_hit -= Rules.OVERWATCH_PENALTY
	for a in allies_of(target, false):
		if int(a.mod("aura_dodge", 0)) > 0 and Rules.chebyshev(a.pos, target.pos) == 1:
			dodge += float(a.mod("aura_dodge", 0))
	var hit := Rules.hit_chance(acc, dodge, cover, high, flank and ranged, beyond, extra_hit + (Rules.FLANK_HIT if flank and not ranged else 0))
	if target.state == "downed":
		hit = 100
	var crit_extra := float(eff.get("crit", 0))
	if ranged:
		crit_extra += float(att.mod("ranged_crit", 0))
	if flank:
		crit_extra += float(eff.get("flank_crit", 0))
	var crit := Rules.crit_chance(att.stat("crit"), flank, crit_extra)
	return {"hit": hit, "crit": crit, "cover": cover, "flank": flank, "high": high, "beyond": beyond, "ranged": ranged}


func damage_mult(att: BattleUnit, target: BattleUnit, eff: Dictionary) -> float:
	var m := 1.0 + float(att.mod("dmg_pct", 0.0))
	if float(att.mod("executioner", 0.0)) > 0 and target.hp < target.max_hp() * 0.35:
		m += float(att.mod("executioner", 0.0))
	if float(att.mod("bloodlust", 0.0)) > 0:
		var missing := 1.0 - float(att.hp) / att.max_hp()
		m += float(att.mod("bloodlust", 0.0)) * floor(missing * 10.0)
	if (target.elite or target.boss) and float(att.mod("elite_dmg", 0.0)) > 0:
		m += float(att.mod("elite_dmg", 0.0))
	if int(eff.get("swarm", 0)) > 0:
		for o in allies_of(att, false):
			if o.enemy_id == att.enemy_id and Rules.chebyshev(o.pos, target.pos) == 1:
				m += int(eff["swarm"]) / 100.0
	if att.boss:
		m *= 1.0 - 0.15 * pages_found
	return m


func preview(att: BattleUnit, skill_id: String, target_cell: Vector2i, from := Vector2i(-99, -99)) -> Dictionary:
	## Everything the HUD shows before confirming an action.
	if from == Vector2i(-99, -99):
		from = att.pos
	var s := DB.skill(skill_id)
	var out := {"targets": [], "skill": skill_id}
	for o in affected(att, skill_id, target_cell, from):
		var row := {"uid": o.uid, "name": o.name}
		for eff in s.get("effects", []):
			match eff["t"]:
				"damage":
					if not row.has("hit"):
						var ctx := attack_context(att, o, s, eff, from)
						row.merge(ctx)
						var raw_lo := Rules.raw_damage(att.stat("attack"), float(eff.get("mult", 1.0)), -1.0) * damage_mult(att, o, eff)
						var raw_hi := Rules.raw_damage(att.stat("attack"), float(eff.get("mult", 1.0)), 1.0) * damage_mult(att, o, eff)
						var d: float = o.defense_now()
						for e2 in s.get("effects", []):
							if e2["t"] == "armor_break":
								d *= 1.0 - float(e2.get("pct", 0.5))
						row["dmg_min"] = Rules.apply_defense(raw_lo, d, float(eff.get("pierce", 0)))["damage"]
						row["dmg_max"] = Rules.apply_defense(raw_hi, d, float(eff.get("pierce", 0)))["damage"]
						row["hits"] = 1
					else:
						row["hits"] = int(row.get("hits", 1)) + 1
				"status":
					var ch := _status_chance_for(att, o, eff)
					if not row.has("statuses"):
						row["statuses"] = []
					row["statuses"].append([eff["id"], ch])
				"heal":
					row["heal"] = _heal_amount(att, eff)
		out["targets"].append(row)
	return out


func _status_chance_for(att: BattleUnit, o: BattleUnit, eff: Dictionary) -> int:
	var sid: String = eff["id"]
	var bad: bool = DB.statuses.get(sid, {}).get("bad", true)
	if not bad or not att.hostile_to(o):
		return 100
	if _immune(o, sid):
		return 0
	var base := float(eff.get("chance", 50))
	if sid == "burn":
		base += float(att.mod("burn_chance", 0))
	var c := Rules.status_chance(base, att.level, o.level, o.stat("resolve"))
	if o.boss and sid in ["paralysis", "stun", "fear", "root"]:
		c = c / 2
	return c


func _immune(o: BattleUnit, sid: String) -> bool:
	if sid == "fear":
		if int(o.mod("fearless", 0)) > 0:
			return true
		for a in allies_of(o, true):
			if int(a.mod("aura_fearless", 0)) > 0 and Rules.chebyshev(a.pos, o.pos) <= int(a.mod("aura_fearless", 0)):
				return true
		var fx: Dictionary = grid.t(o.pos)["fx"]
		if fx.get("kind", "") == "sanctuary" and int(fx.get("team", -1)) == o.team:
			return true
	return false


func _heal_amount(att: BattleUnit, eff: Dictionary) -> int:
	var amt := float(eff.get("base", 0)) + float(eff.get("mult", 0)) * att.stat("attack")
	amt *= 1.0 + float(att.mod("heal_bonus", 0.0))
	return roundi(amt)


# ====================================================================== actions
func use_skill(u: BattleUnit, skill_id: String, target: Vector2i) -> bool:
	if not can_use(u, skill_id):
		return false
	if not target in valid_targets(u, skill_id):
		return false
	var s := DB.skill(skill_id)
	var cd := int(s.get("cd", 0))
	if cd > 0:
		cd = maxi(1, cd + int(u.mod("cooldown", 0)))
		u.cds[skill_id] = cd + 1
	var uses: String = s.get("uses", "move" if s.get("keeps_action", false) else "action")
	if uses == "move":
		u.moved = true
	else:
		u.acted = true
	if u.hidden:
		_reveal(u)
	if target != u.pos:
		_face(u, target)
	emit({"t": "skill", "uid": u.uid, "skill": skill_id, "target": target, "anim": s.get("anim", "attack"), "fx": s.get("fx", "slash"), "name": s.get("name", "")})
	# charge: move next to target first
	if s.get("range", {}).get("kind", "") == "charge":
		var path := _charge_path(u, u.pos, target)
		if path.size() > 0:
			u.pos = path[-1]
			emit({"t": "move", "uid": u.uid, "path": path, "fast": true})
	var targets := affected(u, skill_id, target)
	var hit_map := {}
	for eff in s.get("effects", []):
		var et: String = eff["t"]
		if et == "restore_def" and eff.get("self", false):
			u.def_cur = minf(u.max_def(), u.def_cur + u.max_def() * float(eff.get("pct", 1.0)))
			emit({"t": "def", "uid": u.uid, "value": u.def_cur, "gain": 1})
			continue
		match et:
			"teleport":
				var from := u.pos
				u.pos = target
				if u.carrying >= 0 and unit(u.carrying):
					unit(u.carrying).pos = target
				emit({"t": "teleport", "uid": u.uid, "from": from, "to": target, "fx": s.get("fx", "shadow")})
				_update_hidden()
			"splash":
				for o in hostiles_of(u):
					if Rules.chebyshev(o.pos, u.pos) <= int(eff.get("r", 1)) and not o.hidden:
						_resolve_damage(u, o, s, {"t": "damage", "mult": eff.get("mult", 0.8)})
			"terrain":
				var cells: Array = aoe_cells(u, skill_id, target)
				_place_terrain(u, cells, eff)
			"self_status":
				_add_status(u, eff["id"], int(eff.get("dur", 1)), float(eff.get("power", 0)), u)
			"charge":
				pass
			_:
				for o in targets:
					if not o.alive() and et != "stabilize":
						continue
					if et == "damage":
						var did_hit := _resolve_damage(u, o, s, eff)
						hit_map[o.uid] = hit_map.get(o.uid, false) or did_hit
						continue
					if et in ["status", "push", "pull", "erase_skill", "remove_buffs"] and hit_map.has(o.uid) and not hit_map[o.uid]:
						continue
					_apply_effect(u, o, s, eff)
	_check_end()
	return true


func _apply_effect(u: BattleUnit, o: BattleUnit, s: Dictionary, eff: Dictionary) -> void:
	match eff["t"]:
		"damage":
			if o.active() or o.state == "downed":
				_resolve_damage(u, o, s, eff)
		"status":
			if o.active():
				var ch := _status_chance_for(u, o, eff)
				var power := float(eff.get("power", 0))
				if eff["id"] == "burn":
					power *= 1.0 + float(u.mod("burn_power", 0.0))
				if rng.randi_range(1, 100) <= ch:
					_add_status(o, eff["id"], int(eff.get("dur", 1)), power, u)
				else:
					emit({"t": "float", "uid": o.uid, "text": "Resisted", "kind": "info"})
		"heal":
			_heal(o, _heal_amount(u, eff), u)
		"stabilize":
			if o.state == "downed" and not o.stabilized:
				o.stabilized = true
				u.stabilizes += 1
				emit({"t": "float", "uid": o.uid, "text": "Stabilized", "kind": "good"})
		"cleanse":
			var only: Array = eff.get("only", [])
			for st in o.statuses.duplicate():
				if DB.statuses.get(st["id"], {}).get("bad", false) and (only.is_empty() or st["id"] in only):
					o.remove_status(st["id"])
			emit({"t": "float", "uid": o.uid, "text": "Cleansed", "kind": "good"})
			emit({"t": "statuses", "uid": o.uid})
		"restore_def":
			var before := o.def_cur
			o.def_cur = minf(o.max_def(), o.def_cur + o.max_def() * float(eff.get("pct", 0.5)))
			emit({"t": "def", "uid": o.uid, "value": o.def_cur, "gain": o.def_cur - before})
		"armor_break":
			if o.active():
				var loss := o.def_cur * float(eff.get("pct", 0.5))
				o.def_cur -= loss
				emit({"t": "armor_break", "uid": o.uid, "value": o.def_cur, "loss": loss})
		"push":
			if o.active():
				_push(u, o, int(eff.get("dist", 1)), eff.get("stun", false), 1)
		"pull":
			if o.active():
				_push(u, o, int(eff.get("dist", 1)), false, -1)
		"reveal":
			_reveal(o)
		"remove_buffs":
			var removed := false
			for st in o.statuses.duplicate():
				if not DB.statuses.get(st["id"], {}).get("bad", true):
					o.remove_status(st["id"])
					removed = true
			if removed:
				emit({"t": "float", "uid": o.uid, "text": "Buffs erased", "kind": "bad"})
				emit({"t": "statuses", "uid": o.uid})
		"erase_skill":
			erase_skill(o)
		"restore_skills":
			if not o.erased.is_empty():
				o.erased.clear()
				o.remove_status("silenced")
				emit({"t": "float", "uid": o.uid, "text": "Memory restored", "kind": "good"})
		"hasten":
			o.next_time -= float(eff.get("amount", 5))
			emit({"t": "float", "uid": o.uid, "text": "Hastened", "kind": "good"})


func erase_skill(o: BattleUnit) -> void:
	var pool: Array = []
	for sk in o.skills:
		if sk != o.basic and not sk in o.erased:
			pool.append(sk)
	if pool.is_empty():
		return
	var sk: String = pool[rng.randi() % pool.size()]
	o.erased.append(sk)
	_add_status(o, "silenced", 99, 0, null)
	emit({"t": "float", "uid": o.uid, "text": "Forgot %s" % DB.skill(sk).get("name", sk), "kind": "bad"})


func _attack_basic(att: BattleUnit, target: BattleUnit, extra := {}) -> void:
	var s := DB.skill(att.basic)
	emit({"t": "skill", "uid": att.uid, "skill": att.basic, "target": target.pos, "anim": s.get("anim", "attack"), "fx": s.get("fx", "slash"), "name": ""})
	var did_hit := false
	for eff in s.get("effects", []):
		if eff["t"] == "damage":
			did_hit = _resolve_damage(att, target, s, eff, extra) or did_hit
		elif eff["t"] == "status" and target.active() and did_hit:
			_apply_effect(att, target, s, eff)


func _resolve_damage(att: BattleUnit, o: BattleUnit, s: Dictionary, eff: Dictionary, extra := {}) -> bool:
	var ctx := attack_context(att, o, s, eff, att.pos, extra)
	var roll := rng.randi_range(1, 100)
	if roll > int(ctx["hit"]):
		emit({"t": "miss", "uid": o.uid, "src": att.uid, "fx": s.get("fx", "slash")})
		if int(o.mod("riposte", 0)) > 0 and o.active() and Rules.chebyshev(o.pos, att.pos) == 1 and not extra.get("riposte", false):
			emit({"t": "float", "uid": o.uid, "text": "Riposte!", "kind": "info"})
			_face(o, att.pos)
			var bs := DB.skill(o.basic)
			for e2 in bs.get("effects", []):
				if e2["t"] == "damage":
					_resolve_damage(o, att, bs, e2, {"riposte": true})
		return false
	var crit := rng.randi_range(1, 100) <= int(ctx["crit"])
	var raw := Rules.raw_damage(att.stat("attack"), float(eff.get("mult", 1.0)), rng.randf_range(-1.0, 1.0))
	raw *= damage_mult(att, o, eff)
	if crit:
		raw *= 2.0
	var crit_def := false
	var cd_chance := o.stat("crit") * 0.5 + (Rules.DEFEND_CRIT_DEF if o.has_status("defending") else 0)
	if o.state == "active" and rng.randi_range(1, 100) <= int(cd_chance):
		crit_def = true
		raw *= 0.5
	if int(o.mod("carapace", 0)) > 0 and not o.carapace_used:
		o.carapace_used = true
		raw *= 0.5
		emit({"t": "float", "uid": o.uid, "text": "Carapace", "kind": "info"})
	var res := Rules.apply_defense(raw, o.defense_now(), float(eff.get("pierce", 0.0)))
	var dmg: int = res["damage"]
	o.def_cur = maxf(0.0, o.def_cur - float(res["wear"]))
	emit({"t": "hit", "uid": o.uid, "src": att.uid, "dmg": dmg, "crit": crit, "crit_def": crit_def, "def": o.def_cur, "fx": s.get("fx", "slash"), "absorbed": roundi(raw) - dmg})
	if crit and int(att.mod("crit_bleed", 0)) > 0 and o.active():
		_add_status(o, "bleed", 3, float(att.mod("crit_bleed", 0)), att)
	if crit and int(att.mod("shatter", 0)) > 0 and att.member:
		_glass_crit(att)
	_apply_damage(o, dmg, att)
	return true


func _glass_crit(att: BattleUnit) -> void:
	var w: Dictionary = att.member.equipment.get("weapon", {})
	if w.get("id", "") == "glass_blades":
		w["crits"] = int(w.get("crits", 0)) + 1
		if int(w["crits"]) >= 5:
			emit({"t": "float", "uid": att.uid, "text": "The glass blades shatter!", "kind": "bad"})
			att.member.equipment["weapon"] = Items.weapon(att.member.class_data()["weapon_family"], 1) if att.member.class_data()["weapon_family"] != "glassblades" else Items.weapon("glassblades", 1)
			att.mods["shatter"] = 0
			att.mods["crit"] = 0
			att.st["crit"] = maxi(0, int(att.st["crit"]) - 20)
			att.st["attack"] = maxi(0, int(att.st["attack"]) - 4)


func _damage_raw(o: BattleUnit, dmg: int, src: BattleUnit, kind: String) -> void:
	emit({"t": "hit", "uid": o.uid, "src": src.uid if src else -1, "dmg": dmg, "crit": false, "dot": kind, "def": o.def_cur, "fx": kind})
	_apply_damage(o, dmg, src)


func _apply_damage(o: BattleUnit, dmg: int, src: BattleUnit) -> void:
	if o.state == "downed":
		_kill(o, src, "executed")
		return
	var before := o.hp
	o.hp -= dmg
	if o.hp <= 0 and o.has_status("last_stand"):
		o.hp = 1
		emit({"t": "float", "uid": o.uid, "text": "Last Stand!", "kind": "good"})
	if o.hp <= 0 and int(o.mod("lucky", 0)) > 0 and not o.lucky_used:
		o.lucky_used = true
		o.hp = 1
		emit({"t": "float", "uid": o.uid, "text": "Lucky!", "kind": "good"})
	_check_boss_phase(o, before)
	if o.hp > 0:
		return
	var overkill := -o.hp
	o.hp = 0
	var threshold: float = [0.75, 0.5, 0.35][clampi(difficulty, 0, 2)]
	if o.team == BattleUnit.TEAM_PLAYER and not o.npc and not o.echo and overkill <= o.max_hp() * threshold:
		o.state = "downed"
		o.was_downed = true
		o.bleed = [4, 3, 2][clampi(difficulty, 0, 2)]
		o.stabilized = false
		o.statuses.clear()
		downs += 1
		if o.carrying >= 0:
			_drop_body(o)
		emit({"t": "downed", "uid": o.uid, "src": src.uid if src else -1})
		_morale_shock(o, src)
	else:
		_kill(o, src, "slain")


func _kill(o: BattleUnit, src: BattleUnit, cause: String) -> void:
	o.state = "dead"
	o.hp = 0
	o.statuses.clear()
	if o.carrying >= 0:
		_drop_body(o)
	if src and src != o:
		src.kills += 1
	if o.team == BattleUnit.TEAM_PLAYER and not o.npc:
		deaths += 1
	emit({"t": "death", "uid": o.uid, "src": src.uid if src else -1, "cause": cause})
	if o.team == BattleUnit.TEAM_PLAYER and not o.npc and o.member != null:
		_morale_shock(o, src)
	_check_end()


func _morale_shock(victim: BattleUnit, src: BattleUnit) -> void:
	for a in allies_of(victim, false):
		if a.npc or a.objective_role == "object" or Rules.chebyshev(a.pos, victim.pos) > 3:
			continue
		if _immune(a, "fear"):
			continue
		var base := 20.0
		if int(a.mod("coward", 0)) > 0:
			base = 60.0
		var ch := Rules.status_chance(base, maxi(1, victim.level), a.level, a.stat("resolve"))
		if rng.randi_range(1, 100) <= ch:
			_add_status(a, "fear", 1 if int(a.mod("coward", 0)) == 0 else 2, 0, src if src else victim)


func _heal(o: BattleUnit, amount: int, src: BattleUnit) -> void:
	if o.state == "dead":
		return
	if o.state == "downed":
		o.state = "active"
		o.hp = maxi(1, amount)
		o.bleed = 0
		o.stabilized = false
		emit({"t": "revive", "uid": o.uid, "hp": o.hp})
		return
	var before := o.hp
	o.hp = mini(o.max_hp(), o.hp + amount)
	if o.hp > before:
		emit({"t": "heal", "uid": o.uid, "amount": o.hp - before})


func _add_status(o: BattleUnit, sid: String, dur: int, power: float, src: BattleUnit) -> void:
	if not o.alive():
		return
	var existing := o.get_status(sid)
	var def: Dictionary = DB.statuses.get(sid, {})
	if not existing.is_empty():
		existing["dur"] = maxi(int(existing["dur"]), dur)
		existing["power"] = maxf(float(existing.get("power", 0)), power)
		if def.has("stacks"):
			existing["stacks"] = mini(int(def["stacks"]), int(existing.get("stacks", 1)) + 1)
	else:
		o.statuses.append({"id": sid, "dur": dur, "power": power, "stacks": 1, "source": src.uid if src else -1})
	emit({"t": "status", "uid": o.uid, "id": sid, "dur": dur})
	if sid == "fear" and o.has_status("overwatch"):
		o.remove_status("overwatch")


func _apply_status(src: BattleUnit, o: BattleUnit, sid: String, chance: int, dur: int, power: float) -> void:
	if rng.randi_range(1, 100) <= chance:
		_add_status(o, sid, dur, power, src)


func _push(src: BattleUnit, o: BattleUnit, dist: int, stun_on_hit: bool, sign_dir: int) -> void:
	if o.boss:
		emit({"t": "float", "uid": o.uid, "text": "Immovable", "kind": "info"})
		return
	var d := o.pos - src.pos
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	dir *= sign_dir
	var path: Array = []
	var p := o.pos
	var collided := false
	for i in dist:
		var n := p + dir
		if not grid.inb(n) or not grid.standable(n, o.swims, o.floats) or unit_at(n) != null or n == src.pos or grid.height(n) - grid.height(p) > 1:
			collided = true
			break
		p = n
		path.append(p)
	if not path.is_empty():
		o.pos = p
		emit({"t": "move", "uid": o.uid, "path": path, "fast": true, "knock": true})
		var fx: Dictionary = grid.t(p)["fx"]
		if fx.get("kind", "") == "trap" and int(fx.get("team", -1)) != o.team:
			_trigger_trap(o, p, fx)
	if collided and stun_on_hit and o.active():
		emit({"t": "float", "uid": o.uid, "text": "Slammed!", "kind": "bad"})
		_damage_raw(o, 4, src, "impact")
		if o.active():
			_add_status(o, "stun", 1, 0, src)


func _charge_path(u: BattleUnit, from: Vector2i, target: Vector2i) -> Array:
	var d := target - from
	if d.x != 0 and d.y != 0:
		return []
	var dir := Vector2i(signi(d.x), signi(d.y))
	var path: Array = []
	var p := from
	while p + dir != target:
		var n := p + dir
		if grid.step_cost(p, n, u.swims, u.floats) < 0 or unit_at(n) != null:
			return []
		path.append(n)
		p = n
		if path.size() > 6:
			return []
	return path if path.size() >= 1 else []


func _place_terrain(u: BattleUnit, cells: Array, eff: Dictionary) -> void:
	var kind: String = eff["kind"]
	var placed: Array = []
	for c in cells:
		if not grid.inb(c):
			continue
		var tl := grid.t(c)
		if kind in ["thorns", "trap"] and (tl["solid"] or unit_at(c) != null and kind == "trap"):
			continue
		tl["fx"] = {"kind": kind, "dur": int(eff.get("dur", 2)), "team": u.team, "owner": u.uid, "power": roundi(u.stat("attack") * 1.0)}
		placed.append(c)
	emit({"t": "terrain", "cells": placed, "kind": kind, "team": u.team})


func _drop_body(carrier: BattleUnit) -> void:
	var body := unit(carrier.carrying)
	carrier.carrying = -1
	if body == null:
		return
	body.carried_by = -1
	var spot := carrier.pos
	for n in grid.neighbors8(carrier.pos):
		if grid.standable(n) and unit_at(n, true) == null:
			spot = n
			break
	body.pos = spot
	emit({"t": "drop", "uid": body.uid, "pos": spot})


# ---------------------------------------------------------------- other actions
func can_stabilize(u: BattleUnit, o: BattleUnit) -> bool:
	return u.active() and not u.acted and o.state == "downed" and not o.stabilized and not u.hostile_to(o) and Rules.chebyshev(u.pos, o.pos) == 1 and o.carried_by < 0


func do_stabilize(u: BattleUnit, o: BattleUnit) -> bool:
	if not can_stabilize(u, o):
		return false
	o.stabilized = true
	u.acted = true
	u.stabilizes += 1
	_face(u, o.pos)
	emit({"t": "anim", "uid": u.uid, "anim": "cast"})
	emit({"t": "float", "uid": o.uid, "text": "Stabilized", "kind": "good"})
	return true


func can_carry(u: BattleUnit, o: BattleUnit) -> bool:
	return u.active() and not u.acted and u.carrying < 0 and u.team == BattleUnit.TEAM_PLAYER and o.team == BattleUnit.TEAM_PLAYER and not o.npc \
		and (o.state == "downed" or o.state == "dead") and o.carried_by < 0 and Rules.chebyshev(u.pos, o.pos) <= 1 and o != u


func do_carry(u: BattleUnit, o: BattleUnit) -> bool:
	if not can_carry(u, o):
		return false
	u.carrying = o.uid
	o.carried_by = u.uid
	o.pos = u.pos
	u.acted = true
	emit({"t": "carry", "uid": u.uid, "body": o.uid})
	return true


func can_extract(u: BattleUnit) -> bool:
	return u.active() and not u.acted and grid.t(u.pos)["extract"] and u.objective_role != "object"


func do_extract(u: BattleUnit) -> bool:
	if not can_extract(u):
		return false
	u.state = "extracted"
	u.acted = true
	emit({"t": "extract", "uid": u.uid})
	if u.carrying >= 0:
		var body := unit(u.carrying)
		if body:
			body.state = "extracted" if body.state == "downed" else "recovered"
			emit({"t": "extract", "uid": body.uid})
	if u.objective_role in ["vip", "captive"]:
		objective["done"] = true
		emit({"t": "objective", "text": "%s reached safety!" % u.name})
	current = null
	emit({"t": "end_turn", "uid": u.uid})
	_check_end()
	return true


func interact_targets(u: BattleUnit) -> Array:
	var out: Array = []
	if not u.active() or u.acted or u.team != BattleUnit.TEAM_PLAYER:
		return out
	for c in grid.cells_in_radius(u.pos, 1):
		if not grid.t(c)["obj"].is_empty():
			out.append(c)
	return out


func do_interact(u: BattleUnit, c: Vector2i) -> bool:
	if not c in interact_targets(u):
		return false
	var obj: Dictionary = grid.t(c)["obj"]
	grid.t(c)["obj"] = {}
	u.acted = true
	_face(u, c)
	emit({"t": "anim", "uid": u.uid, "anim": "cast"})
	match obj.get("kind", ""):
		"cache":
			objective["found"] = int(objective.get("found", 0)) + 1
			emit({"t": "interact", "cell": c, "kind": "cache", "uid": u.uid})
			emit({"t": "objective", "text": "Cache recovered (%d/%d)" % [objective["found"], objective.get("n", 3)]})
			if int(objective["found"]) >= int(objective.get("n", 3)):
				objective["done"] = true
		"chest":
			chests_opened += 1
			emit({"t": "interact", "cell": c, "kind": "chest", "uid": u.uid})
			emit({"t": "float", "uid": u.uid, "text": "Chest opened", "kind": "good"})
			mark_bonus("chest")
		"page":
			pages_found += 1
			emit({"t": "interact", "cell": c, "kind": "page", "uid": u.uid})
			var lines: Array = DB.story.get("unnamed_lines", [])
			emit({"t": "objective", "text": "Ledger page recovered (%d/3)" % pages_found})
			var boss := _boss()
			if boss:
				if pages_found < lines.size():
					emit({"t": "bark", "uid": boss.uid, "text": lines[mini(pages_found, lines.size() - 1)]})
				boss.st["defense"] = maxi(0, int(boss.st["defense"]) - 5)
				boss.def_cur = minf(boss.def_cur, boss.max_def())
				if pages_found >= 3:
					boss.st["dodge"] = maxi(0, int(boss.st["dodge"]) - 20)
					boss.st["defense"] = 0
					boss.def_cur = 0
					boss.name = DB.story.get("unnamed_name", "Maren")
					emit({"t": "bark", "uid": boss.uid, "text": "Maren... yes. That was my name."})
					emit({"t": "rename", "uid": boss.uid, "name": boss.name})
		"captive":
			var cap := spawn_npc("villager", c, "captive", obj.get("name", "Captive"))
			cap.team = BattleUnit.TEAM_PLAYER
			emit({"t": "interact", "cell": c, "kind": "captive", "uid": u.uid})
			emit({"t": "objective", "text": "Captive freed! Bring them to the extraction zone."})
	_check_end()
	return true


func _boss() -> BattleUnit:
	for o in units:
		if o.boss and o.alive():
			return o
	return null


func _check_boss_phase(o: BattleUnit, before: int) -> void:
	if not o.boss or o.hp <= 0:
		return
	var frac_before := float(before) / o.max_hp()
	var frac_now := float(o.hp) / o.max_hp()
	for th in [0.66, 0.33]:
		if frac_before > th and frac_now <= th:
			o.phase += 1
			var lines: Array = DB.story.get("unnamed_lines", [])
			emit({"t": "bark", "uid": o.uid, "text": ["The page turns...", "You will forget me too."][mini(o.phase - 1, 1)]})
			# erase one squad skill
			var pool: Array = []
			for p in team_units(BattleUnit.TEAM_PLAYER):
				if not p.npc:
					pool.append(p)
			if not pool.is_empty():
				erase_skill(pool[rng.randi() % pool.size()])
			for i in 2:
				var spot := _free_near(o.pos, 3)
				if spot != Vector2i(-1, -1):
					spawn_enemy("hollow" if i == 0 else "quietling", spot)


# ====================================================================== spawning
func spawn_enemy(eid: String, p: Vector2i) -> BattleUnit:
	var u := BattleFactory.enemy_unit(eid, skulls, grid.hush, rng)
	u.pos = p
	add_unit(u)
	u.next_time = time + Rules.turn_delay(u.stat("speed")) * rng.randf_range(0.3, 0.8)
	u.def_cur = u.max_def()
	emit({"t": "spawn", "uid": u.uid})
	return u


func spawn_npc(eid: String, p: Vector2i, role: String, nm: String) -> BattleUnit:
	var u := BattleFactory.enemy_unit(eid, 1, 0, rng)
	u.team = BattleUnit.TEAM_NPC
	u.npc = true
	u.objective_role = role
	u.name = nm
	u.pos = p
	add_unit(u)
	u.next_time = time + 1.0
	u.def_cur = u.max_def()
	emit({"t": "spawn", "uid": u.uid})
	return u


func _free_near(c: Vector2i, r: int) -> Vector2i:
	var cells := grid.cells_in_radius(c, r)
	cells.shuffle()
	for p in cells:
		if grid.standable(p) and unit_at(p, true) == null and p != c:
			return p
	return Vector2i(-1, -1)


func _spawn_wave(w: Dictionary) -> void:
	emit({"t": "objective", "text": "Enemy reinforcements!"})
	var spots: Array = w.get("spots", [])
	var i := 0
	for eid in w["enemies"]:
		var p := Vector2i(-1, -1)
		while i < spots.size():
			var cand: Vector2i = spots[i]
			i += 1
			if grid.standable(cand) and unit_at(cand, true) == null:
				p = cand
				break
		if p == Vector2i(-1, -1):
			continue
		spawn_enemy(eid, p)


# ====================================================================== objectives
func mark_bonus(id: String) -> void:
	for b in bonus:
		if b["id"] == id and not b.get("failed", false):
			b["done"] = true


func _check_objective_rounds() -> void:
	var typ: String = objective.get("type", "clear")
	if typ in ["survive", "defense"] and round_num > int(objective.get("turns", 6)):
		objective["done"] = true
		emit({"t": "objective", "text": "You held out!"})
		_check_end()


func objective_text() -> String:
	var typ: String = objective.get("type", "clear")
	match typ:
		"clear": return "Defeat every enemy"
		"hunt": return "Slay %s" % objective.get("target_name", "the target")
		"escort": return "Escort %s to the extraction zone" % objective.get("vip_name", "the VIP")
		"rescue": return "Free the captive and bring them to the extraction zone"
		"retrieve": return "Recover caches (%d/%d)" % [int(objective.get("found", 0)), int(objective.get("n", 3))]
		"defense": return "Protect the %s until round %d" % [objective.get("object_name", "object"), int(objective.get("turns", 6)) + 1]
		"survive": return "Survive until round %d" % (int(objective.get("turns", 6)) + 1)
		"final": return "Defeat the Unnamed. Ledger pages: %d/3" % pages_found
	return ""


func _check_end() -> void:
	if over:
		return
	var typ: String = objective.get("type", "clear")
	var hostile_left := 0
	for u in units:
		if u.team == BattleUnit.TEAM_ENEMY and u.alive() and not u.npc:
			hostile_left += 1
	var pending_waves := false
	for w in waves:
		if not w.get("done", false):
			pending_waves = true
	match typ:
		"clear":
			if hostile_left == 0 and not pending_waves:
				objective["done"] = true
		"hunt", "final":
			var tgt := unit(int(objective.get("target_uid", -1)))
			if tgt == null or tgt.state == "dead":
				objective["done"] = true
		"retrieve":
			if hostile_left == 0 and not pending_waves and int(objective.get("found", 0)) >= int(objective.get("n", 3)):
				objective["done"] = true
	# failure conditions
	for u in units:
		if u.objective_role in ["vip", "captive", "object"] and u.state == "dead":
			objective["failed"] = true
	if objective.get("done", false):
		_finish("victory")
		return
	if objective.get("failed", false):
		_finish("failed")
		return
	var active_players := 0
	var extracted := 0
	for u in units:
		if u.team == BattleUnit.TEAM_PLAYER and not u.npc:
			if u.active() and u.carried_by < 0:
				active_players += 1
			if u.state == "extracted":
				extracted += 1
	if active_players == 0:
		_finish("retreat" if extracted > 0 else "defeat")


func _finish(res: String) -> void:
	if over:
		return
	over = true
	result = res
	if res == "victory":
		if downs == 0 and deaths == 0:
			mark_bonus("no_downs")
		if round_num <= int(mission.get("par_rounds", 8)):
			mark_bonus("fast")
		for u in units:
			if u.elite and u.team == BattleUnit.TEAM_ENEMY and u.state == "dead":
				mark_bonus("elite")
	emit({"t": "end", "result": res})


func abandon() -> void:
	## Player sounds the full retreat from the pause menu.
	for u in units:
		if u.team == BattleUnit.TEAM_PLAYER and u.active() and grid.t(u.pos)["extract"]:
			u.state = "extracted"
	_finish("retreat")


func emit(e: Dictionary) -> void:
	events.append(e)


func pop_events() -> Array:
	var e := events
	events = []
	return e
