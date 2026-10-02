extends Node
## Holds the running campaign, the battle being played, and save/load.

const SAVE_DIR := "user://saves"
const SLOTS := 3

var campaign: Campaign = null
var slot := 0
var mission := {}
var squad_ids: Array = []
var battle: Battle = null
var last_report := {}
var autoplay := false   # developer smoke test: the AI plays the squad


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func new_campaign(guild: String, difficulty: int, ironman: bool, p_slot: int) -> void:
	campaign = Campaign.new()
	campaign.new_game(guild, difficulty, ironman)
	slot = p_slot
	save()


func slot_path(s: int) -> String:
	return "%s/slot%d.json" % [SAVE_DIR, s]


func save() -> void:
	if campaign == null:
		return
	var d := campaign.to_dict()
	d["saved_at"] = Time.get_datetime_string_from_system(false, true)
	d["in_battle"] = battle != null and not battle.over
	d["battle_mission"] = mission if battle != null and not battle.over else {}
	d["battle_squad"] = squad_ids if battle != null and not battle.over else []
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func slot_info(s: int) -> Dictionary:
	var p := slot_path(s)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d == null or not d is Dictionary:
		return {"corrupt": true}
	return {"guild": d.get("guild_name", "?"), "week": int(d.get("week", 1)), "renown": int(d.get("renown", 0)),
		"ironman": d.get("ironman", false), "saved_at": d.get("saved_at", ""), "over": d.get("game_over", ""),
		"difficulty": int(d.get("difficulty", 1)), "members": d.get("roster", []).size(), "hush": int(d.get("hush", 0))}


func load_slot(s: int) -> bool:
	var p := slot_path(s)
	if not FileAccess.file_exists(p):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d == null or not d is Dictionary:
		return false
	campaign = Campaign.from_dict(d)
	slot = s
	battle = null
	# Ironman: quitting mid-battle counts as abandoning the mission.
	if d.get("in_battle", false) and campaign.ironman:
		var m: Dictionary = d.get("battle_mission", {})
		if not m.is_empty():
			campaign.renown = maxi(0, campaign.renown - 10)
			for id in d.get("battle_squad", []):
				var mem := campaign.member(int(id))
				if mem:
					mem.days_used += int(m.get("days", 1))
			campaign.days_used += int(m.get("days", 1))
			campaign.board = campaign.board.filter(func(x): return int(x["id"]) != int(m.get("id", -1)))
			campaign.pending_events.append({"kind": "faction", "title": "Abandoned Mission",
				"text": "The squad sent to \"%s\" came back empty-handed after the guild lost contact. Renown -10." % m.get("title", "?")})
		save()
	return true


func delete_slot(s: int) -> void:
	var p := slot_path(s)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func start_battle(p_mission: Dictionary, squad: Array) -> void:
	mission = p_mission
	squad_ids = []
	for m in squad:
		squad_ids.append(m.id)
	battle = BattleFactory.build(p_mission, squad, campaign.battle_context(p_mission))
	if campaign.ironman:
		save()


func finish_battle() -> Dictionary:
	last_report = campaign.finish_mission(mission, battle)
	battle = null
	save()
	return last_report
