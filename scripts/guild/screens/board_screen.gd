extends GuildScreen
## The weekly quest board over the map of Ambral. Each mission shows its
## region, faction, skulls, days, reward and the cost of ignoring it.

const CAT_COLORS := {"story": Color8(246, 204, 96), "breach": Color8(190, 150, 236), "crisis": Color8(232, 110, 90),
	"rivalry": Color8(236, 150, 80), "chain": Color8(130, 176, 240), "contract": Color8(238, 228, 206),
	"salvage": Color8(170, 200, 140), "training": Color8(140, 214, 120), "recruit": Color8(140, 214, 180)}

var selected := -1
var map_rect: TextureRect


func screen_title() -> String:
	return "Quest Board"


func subtitle() -> String:
	return "Week %d · %d members ready · max squad %d" % [campaign.week, campaign.available_members(1).size(), campaign.squad_cap()]


func build() -> void:
	if selected < 0 or campaign.mission_by_id(selected).is_empty():
		selected = int(campaign.board[0]["id"]) if not campaign.board.is_empty() else -1
		for m in campaign.board:
			if m["category"] == "story":
				selected = int(m["id"])
	var h := UIKit.hbox(6)
	body.add_child(h)
	# list
	var list := UIKit.vbox(2)
	for m in campaign.board:
		list.add_child(_card(m))
	if campaign.board.is_empty():
		list.add_child(UIKit.label("The board is empty until next week.", 10, UITheme.TEXT_DIM))
	var sc := scroll(list)
	sc.custom_minimum_size.x = 250
	sc.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(sc)
	# map and detail
	var right := UIKit.vbox(3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(_map())
	var mission := campaign.mission_by_id(selected)
	if not mission.is_empty():
		right.add_child(_detail(mission))


func _card(m: Dictionary) -> Control:
	var cat: String = m["category"]
	var col: Color = CAT_COLORS.get(cat, UITheme.TEXT)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = int(m["id"]) == selected
	UIKit.list_row(b, int(m["id"]) == selected)
	b.custom_minimum_size = Vector2(244, 34)
	var v := UIKit.vbox(0)
	v.position = Vector2(5, 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var top := UIKit.hbox(3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := UIKit.label(DB.missions["categories"][cat]["name"].to_upper(), 8, col, UITheme.pixel_font)
	top.add_child(cl)
	if m.get("faction", "") != "":
		top.add_child(UIKit.tex_rect(load("res://assets/sprites/ui/emblem_%s_16.png" % m["faction"]), 0.625))
	top.add_child(UIKit.spacer())
	var sk := UIKit.skulls(int(m["skulls"]))
	top.add_child(sk)
	top.add_child(UIKit.label(" %dd" % int(m["days"]), 9, UITheme.TEXT_DIM, UITheme.number_font))
	top.custom_minimum_size.x = 234
	v.add_child(top)
	var tl := UIKit.label(m["title"], 10, UITheme.TEXT)
	tl.custom_minimum_size.x = 234
	tl.clip_text = true
	v.add_child(tl)
	for c in v.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if m.has("conflict") and not campaign.mission_by_id(int(m["conflict"])).is_empty():
		b.tooltip_text = "Conflicts with \"%s\": taking one cancels the other." % campaign.mission_by_id(int(m["conflict"]))["title"]
	var id := int(m["id"])
	b.pressed.connect(func():
		selected = id
		Audio.sfx("page", 0.1, -8.0)
		rebuild())
	return b


func _map() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(320, 190)
	var map := TextureRect.new()
	map.texture = load("res://assets/sprites/ui/world_map.png")
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.size = Vector2(320, 190)
	holder.add_child(map)
	var frame := Panel.new()
	var fsb := UITheme.tex_box("res://assets/sprites/ui/frame_gold.png", 4)
	fsb.draw_center = false
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size = Vector2(320, 190)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	# region names and local Hush
	for rid in DB.regions:
		var rd: Dictionary = DB.regions[rid]
		var p := Vector2(float(rd["map_pos"][0]) * 320.0, float(rd["map_pos"][1]) * 190.0)
		var rs: Dictionary = campaign.regions[rid]
		var name := UIKit.label(rd["name"].replace("The ", "").replace("Coast of the ", ""), 8, UITheme.TEXT if not rs["lost"] else UITheme.TEXT_DIM, UITheme.pixel_font)
		name.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.08, 0.9))
		name.position = p + Vector2(-30, 10)
		name.size = Vector2(60, 10)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		name.tooltip_text = "%s\n%s\nLocal Hush: %d/5%s" % [rd["name"], rd["desc"], int(rs["hush"]), "\nLost to the Hush." if rs["lost"] else ""]
		holder.add_child(name)
		var hush := int(rs["hush"])
		for i in 5:
			var pip := ColorRect.new()
			pip.size = Vector2(3, 2)
			pip.position = p + Vector2(-9 + i * 4, 21)
			pip.color = UITheme.PURPLE if i < hush else Color(0.15, 0.1, 0.16, 0.8)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(pip)
		if rs["lost"]:
			var fog := ColorRect.new()
			fog.color = Color(0.5, 0.5, 0.54, 0.35)
			fog.size = Vector2(44, 30)
			fog.position = p - Vector2(22, 15)
			fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(fog)
	# pins
	var per_region := {}
	for m in campaign.board:
		var rid: String = m["region"]
		var k := int(per_region.get(rid, 0))
		per_region[rid] = k + 1
		var rd: Dictionary = DB.regions[rid]
		var p := Vector2(float(rd["map_pos"][0]) * 320.0, float(rd["map_pos"][1]) * 190.0) + Vector2(-14 + k * 11 - (0 if k < 4 else 44), -8 - (0 if k < 4 else 11))
		var pin := Button.new()
		pin.focus_mode = Control.FOCUS_NONE
		pin.size = Vector2(10, 10)
		pin.position = p
		var col: Color = CAT_COLORS.get(m["category"], UITheme.TEXT)
		var sel := int(m["id"]) == selected
		pin.add_theme_stylebox_override("normal", UITheme.flat(col.darkened(0.2), UITheme.INK if not sel else Color(1, 1, 1), 1, 0))
		pin.add_theme_stylebox_override("hover", UITheme.flat(col.lightened(0.2), Color(1, 1, 1), 1, 0))
		pin.add_theme_stylebox_override("pressed", UITheme.flat(col, Color(1, 1, 1), 1, 0))
		pin.tooltip_text = "%s\n%s · %d skull%s" % [m["title"], DB.regions[rid]["name"], int(m["skulls"]), "" if int(m["skulls"]) == 1 else "s"]
		var id := int(m["id"])
		pin.pressed.connect(func():
			selected = id
			Audio.sfx("page", 0.1, -8.0)
			rebuild())
		holder.add_child(pin)
		if sel:
			var tw := pin.create_tween().set_loops()
			tw.tween_property(pin, "position:y", p.y - 2, 0.35)
			tw.tween_property(pin, "position:y", p.y, 0.35)
	return holder


static func objective_text(m: Dictionary) -> String:
	if m.has("objective_desc"):
		return m["objective_desc"]
	if m["objective"] == "final":
		return "Defeat the Unnamed. Recover the lost pages of the ledger."
	var od: Dictionary = DB.missions["objectives"].get(m["objective"], {})
	var target := "their leader"
	if m.has("boss"):
		target = DB.enemies.get(m["boss"], {}).get("name", target)
	return String(od.get("desc", "")).format({"target": target, "vip": DB.missions["vips"].get(m["region"], "the traveller"), "n": int(m.get("caches", 3)),
		"object": DB.missions["objects"].get(m["region"], "cart"), "turns": int(m.get("turns", 6))})


func _detail(m: Dictionary) -> Control:
	var v := UIKit.vbox(1)
	var cat: String = m["category"]
	var cd: Dictionary = DB.missions["categories"][cat]
	var g := hex(UITheme.GOLD)
	var d := hex(UITheme.TEXT_DIM)
	var lines: Array = []
	var fac := ""
	if m.get("faction", "") != "":
		fac = " · %s (%s)" % [DB.factions[m["faction"]]["short"], Rules.rep_name(int(campaign.factions[m["faction"]]["rep"]))]
	var when: String = {"dusk": " · at dusk", "night": " · by night"}.get(m.get("time", "day"), "")
	lines.append("[color=#%s]%s[/color] · %s%s · %d days%s" % [hex(CAT_COLORS.get(cat, UITheme.TEXT)), cd["name"], DB.regions[m["region"]]["name"], fac, int(m["days"]), when])
	var od: Dictionary = DB.missions["objectives"].get(m["objective"], {})
	var obj_line := objective_text(m)
	lines.append("[color=#%s]%s:[/color] %s" % [g, od.get("name", m["objective"].capitalize()), obj_line])
	lines.append("[color=#%s]%s[/color]" % [d, m.get("desc", "")])
	var rw: Dictionary = m.get("reward", {})
	var parts: Array = []
	if int(rw.get("gold", 0)) > 0:
		parts.append("%d gold" % int(rw["gold"]))
	if int(rw.get("renown", 0)) > 0:
		parts.append("%d renown" % int(rw["renown"]))
	if rw.has("materials"):
		parts.append("%d materials" % int(rw["materials"]))
	if rw.has("items"):
		parts.append("%d items" % rw["items"].size())
	if rw.has("item"):
		parts.append("a special item")
	if rw.has("recruit"):
		var rd: Dictionary = rw["recruit"]
		parts.append("recruit: %s (%s)" % [rd.get("name", "?"), DB.classes[rd.get("cls", "warrior")]["name"]])
	if rw.has("hush"):
		parts.append("Hush %d" % int(rw["hush"]))
	if rw.has("rep"):
		parts.append("reputation +%d" % int(rw["rep"]))
	if rw.has("power"):
		parts.append("power +%d" % int(rw["power"]))
	if rw.has("xp_mult"):
		parts.append("bonus XP")
	lines.append("[color=#%s]Reward:[/color] %s" % [hex(UITheme.GREEN), ", ".join(parts)])
	var ig := String(cd.get("ignored", "Nothing happens."))
	ig = ig.format({"hush": m.get("ignore", {}).get("hush", 0), "faction": DB.factions[m["faction"]]["short"] if m.get("faction", "") != "" else "?"})
	if m.has("conflict") and not campaign.mission_by_id(int(m["conflict"])).is_empty():
		ig = "Taking this cancels \"%s\" (%s: reputation -1)." % [campaign.mission_by_id(int(m["conflict"]))["title"], DB.factions[m.get("rival", m["faction"])]["short"]]
	lines.append("[color=#%s]If ignored:[/color] %s" % [hex(UITheme.RED), ig])
	var r := UIKit.rich("[b]%s[/b]\n%s" % [m["title"], "\n".join(lines)], 322, 9)
	var sc := scroll(r)
	v.add_child(sc)
	var h := UIKit.hbox(4)
	h.add_child(UIKit.skulls(int(m["skulls"])))
	if m.get("faction", "") != "" and int(campaign.factions[m["faction"]]["rep"]) <= -2:
		h.add_child(UIKit.label("Hostile: expect an ambush", 9, UITheme.RED))
	h.add_child(UIKit.spacer())
	var mid := int(m["id"])
	var ready := campaign.available_members(int(m["days"])).size()
	var b := UIKit.button("Assemble Squad", func(): hub.open_screen("squad", {"mission": mid}), "btn_green", 110)
	if ready == 0:
		b.disabled = true
		b.tooltip_text = "Nobody has %d free days this week." % int(m["days"])
	h.add_child(b)
	v.add_child(h)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return v
