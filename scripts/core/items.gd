class_name Items
extends RefCounted
## Equipment helpers. Items are plain dictionaries so they serialize directly:
##   {"kind": "weapon", "base": "sword", "tier": 1}
##   {"kind": "armor", "base": "heavy", "tier": 2}
##   {"kind": "trinket", "id": "lucky_coin"}
##   {"kind": "unique", "id": "coral_armor", "crits": 0, "bonus": 0}


static func weapon(base: String, tier: int = 1) -> Dictionary:
	return {"kind": "weapon", "base": base, "tier": tier}


static func armor(base: String, tier: int = 1) -> Dictionary:
	return {"kind": "armor", "base": base, "tier": tier}


static func trinket(id: String) -> Dictionary:
	return {"kind": "trinket", "id": id}


static func unique(id: String) -> Dictionary:
	return {"kind": "unique", "id": id, "crits": 0, "bonus": 0}


static func slot(item: Dictionary) -> String:
	match item.get("kind", ""):
		"weapon": return "weapon"
		"armor": return "armor"
		"trinket": return "trinket"
		"unique": return DB.items["uniques"].get(item.get("id", ""), {}).get("slot", "trinket")
	return ""


static func name_of(item: Dictionary) -> String:
	if item.is_empty():
		return "-"
	match item.get("kind", ""):
		"weapon":
			return DB.items["weapons"][item["base"]]["names"][int(item["tier"]) - 1]
		"armor":
			return DB.items["armors"][item["base"]]["names"][int(item["tier"]) - 1]
		"trinket":
			return DB.items["trinkets"][item["id"]]["name"]
		"unique":
			return DB.items["uniques"][item["id"]]["name"]
	return "?"


static func desc_of(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	match item.get("kind", ""):
		"trinket":
			return DB.items["trinkets"][item["id"]]["desc"]
		"unique":
			var d: String = DB.items["uniques"][item["id"]]["desc"]
			if item["id"] == "barkskin":
				d += " (currently +%d)" % int(item.get("bonus", 0))
			if item["id"] == "glass_blades":
				d += " (%d crits left)" % (5 - int(item.get("crits", 0)))
			return d
	var s := stats_of(item)
	var parts: Array[String] = []
	for k in s:
		parts.append("%+d %s" % [int(s[k]), DB.STAT_NAMES.get(k, k)])
	return ", ".join(parts) if parts.size() > 0 else "No bonuses."


static func stats_of(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	match item.get("kind", ""):
		"weapon":
			return DB.items["weapons"][item["base"]]["stats"][int(item["tier"]) - 1].duplicate()
		"armor":
			return DB.items["armors"][item["base"]]["stats"][int(item["tier"]) - 1].duplicate()
		"trinket":
			return DB.items["trinkets"][item["id"]].get("stats", {}).duplicate()
		"unique":
			var s: Dictionary = DB.items["uniques"][item["id"]].get("stats", {}).duplicate()
			if item["id"] == "barkskin":
				s["defense"] = s.get("defense", 0) + int(item.get("bonus", 0))
			return s
	return {}


static func mods_of(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	match item.get("kind", ""):
		"trinket":
			return DB.items["trinkets"][item["id"]].get("mods", {})
		"unique":
			return DB.items["uniques"][item["id"]].get("mods", {})
	return {}


static func tier_of(item: Dictionary) -> int:
	if item.get("kind", "") in ["weapon", "armor"]:
		return int(item.get("tier", 1))
	if item.get("kind", "") == "unique":
		return 3
	return 1


static func can_upgrade(item: Dictionary) -> bool:
	return item.get("kind", "") in ["weapon", "armor"] and int(item.get("tier", 1)) < 4


static func upgrade_cost(item: Dictionary) -> Array:
	var t := int(item.get("tier", 1))
	if t >= 4:
		return [0, 0]
	return DB.items["upgrade_cost"][t - 1]


static func sell_price(item: Dictionary) -> int:
	match item.get("kind", ""):
		"weapon", "armor":
			return [15, 60, 140, 280][int(item["tier"]) - 1]
		"trinket":
			return int(DB.items["trinkets"][item["id"]].get("price", 80) * 0.4)
		"unique":
			return int(DB.items["uniques"][item["id"]].get("price", 300) * 0.4)
	return 0


static func fits(item: Dictionary, cls: String) -> bool:
	var c: Dictionary = DB.classes.get(cls, {})
	match item.get("kind", ""):
		"weapon":
			return item["base"] == c.get("weapon_family", "")
		"armor":
			return item["base"] == c.get("armor_family", "") or (c.get("armor_family", "") == "heavy" and item["base"] == "medium")
		"trinket":
			return true
		"unique":
			var u: Dictionary = DB.items["uniques"][item["id"]]
			if u.get("any_melee", false):
				return c.get("melee", false)
			return true
	return false


static func random_loot(rng: RandomNumberGenerator, skulls: int) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.45:
		var keys: Array = DB.items["trinkets"].keys()
		keys.erase("bell_shard")
		return trinket(keys[rng.randi() % keys.size()])
	var tier := 1
	var t := rng.randf() + skulls * 0.09
	if t > 1.05:
		tier = 3
	elif t > 0.6:
		tier = 2
	if skulls >= 6 and rng.randf() < 0.15:
		tier = 4
	if roll < 0.75:
		var wk: Array = DB.items["weapons"].keys()
		return weapon(wk[rng.randi() % wk.size()], tier)
	var ak: Array = DB.items["armors"].keys()
	return armor(ak[rng.randi() % ak.size()], tier)
