class_name BattleUnit
extends RefCounted
## A combatant inside one battle.

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1
const TEAM_NPC := 2

var uid := 0
var team := TEAM_ENEMY
var name := ""
var member: Member = null
var member_id := -1
var enemy_id := ""
var pos := Vector2i.ZERO
var facing := Vector2i(0, 1)
var st := {}
var hp := 1
var def_cur := 0.0
var level := 1
var skills: Array = []
var basic := "strike"
var mods := {}
var cds := {}
var statuses: Array = []
var next_time := 0.0
var state := "active"
var bleed := 0
var stabilized := false
var moved := false
var acted := false
var run_left := 0           # after a walk, how far a run could still carry the unit this turn
var lucky_used := false
var rampage_used := false
var alerted := true         # enemies in an unaware pod patrol until they spot the squad
var pod := -1
var exposed_round := -1     # attacked from the fog: visible to the squad this round
var explore_done := false   # exploring: this member already had its squad turn
var carapace_used := false
var erased: Array = []
var carrying := -1
var carried_by := -1
var elite := false
var boss := false
var npc := false
var hush := false
var floats := false
var swims := false
var melee := true
var ai := "melee"
var sprite := ""
var palette := {}
var hidden := false
var kills := 0
var stabilizes := 0
var was_downed := false
var hp_lost := 0             # every point of HP lost this battle, healed or not (light injuries)
var echo := false
var xp_value := 10
var skulls := 1
var phase := 0
var def_regen := 0
var crits_taken := 0
var overwatch_left := 0
var target_uid := -1
var objective_role := ""


func alive() -> bool:
	return state == "active" or state == "downed"


func active() -> bool:
	return state == "active"


func on_map() -> bool:
	return (state == "active" or state == "downed" or state == "dead") and carried_by < 0


func is_player() -> bool:
	return team == TEAM_PLAYER


func hostile_to(o: BattleUnit) -> bool:
	if team == TEAM_ENEMY:
		return o.team != TEAM_ENEMY
	return o.team == TEAM_ENEMY


func has_status(id: String) -> bool:
	for s in statuses:
		if s["id"] == id:
			return true
	return false


func status_power(id: String) -> float:
	var p := 0.0
	for s in statuses:
		if s["id"] == id:
			p += float(s.get("power", 0)) * int(s.get("stacks", 1))
	return p


func get_status(id: String) -> Dictionary:
	for s in statuses:
		if s["id"] == id:
			return s
	return {}


func remove_status(id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i]["id"] == id:
			statuses.remove_at(i)


func stat(k: String) -> float:
	var v: float = float(st.get(k, 0))
	match k:
		"dodge":
			v += status_power("dodge_up")
			if has_status("defending"):
				v += Rules.DEFEND_DODGE
		"accuracy":
			v -= status_power("blind")
			v -= status_power("pinned")
			v += status_power("rallied")
			v += status_power("inspired")
		"resolve":
			v += status_power("rallied") * 1.5
		"move":
			if carrying >= 0:
				v -= 2
	return v


func max_def() -> float:
	return float(st.get("defense", 0))


func max_hp() -> int:
	return int(st.get("hp", 1))


func defense_now() -> float:
	return def_cur + status_power("warded")


func mod(k: String, default = 0):
	return mods.get(k, default)


func usable_skills() -> Array:
	var out: Array = []
	for s in skills:
		if s in erased:
			continue
		out.append(s)
	return out


func cooldown(s: String) -> int:
	return int(cds.get(s, 0))


func xp_worth() -> int:
	return xp_value
