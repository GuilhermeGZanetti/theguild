extends GuildScreen
## The weekly quest board. Each mission is pinned as the client's letter on
## parchment (who asks and why, then the objective, reward and the cost of
## ignoring it), with the map of Ambral one tab away.

const CAT_COLORS := {"story": Color8(246, 204, 96), "breach": Color8(190, 150, 236), "crisis": Color8(232, 110, 90),
	"rivalry": Color8(236, 150, 80), "chain": Color8(130, 176, 240), "contract": Color8(238, 228, 206),
	"salvage": Color8(170, 200, 140), "training": Color8(140, 214, 120), "recruit": Color8(140, 214, 180)}

# ink on parchment
const INK_DIM := Color8(112, 86, 66)
const INK_TITLE := Color8(110, 50, 36)
const INK_GOLD := Color8(138, 88, 18)
const INK_GREEN := Color8(46, 106, 38)
const INK_RED := Color8(150, 40, 30)

var selected := -1
var view := "letter"   # right column: the client's letter or the map
var map_rect: TextureRect


func screen_title() -> String:
	return "Quest Board"


func subtitle() -> String:
	return "Week %d · %d of %d days left · %d members ready · max squad %d" % [campaign.week, campaign.days_left(), Campaign.WEEK_DAYS,
		campaign.available_members().size(), campaign.squad_cap()]


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
	# letter or map
	var right := UIKit.vbox(3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var tabs := UIKit.hbox(2)
	for pair in [["letter", "Letter"], ["map", "Map"]]:
		var id: String = pair[0]
		tabs.add_child(UIKit.button(pair[1], func():
			view = id
			rebuild(), "btn_blue" if view == id else "", 60))
	right.add_child(tabs)
	var mission := campaign.mission_by_id(selected)
	if view == "map":
		right.add_child(_map())
		if not mission.is_empty():
			right.add_child(_map_summary(mission))
	elif not mission.is_empty():
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


## The quest as a parchment: title, the client's letter in their own words,
## then what the guild is actually signing up for.
func _detail(m: Dictionary) -> Control:
	var v := UIKit.vbox(3)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var page := UIKit.panel("parchment", Vector4(14, 9, 10, 9))
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(page)
	var c := UIKit.vbox(4)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := scroll(c)
	page.add_child(sc)
	const W := 310.0
	# title and the facts at a glance
	var tl := UIKit.title(m["title"], 16, INK_TITLE)
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = W
	c.add_child(tl)
	var cat: String = m["category"]
	var cd: Dictionary = DB.missions["categories"][cat]
	var facts: Array = [cd["name"], DB.regions[m["region"]]["name"]]
	if m.get("faction", "") != "":
		facts.append("%s (%s)" % [DB.factions[m["faction"]]["short"], Rules.rep_name(int(campaign.factions[m["faction"]]["rep"]))])
	facts.append("%d day%s" % [int(m["days"]), "" if int(m["days"]) == 1 else "s"])
	var when: String = {"dusk": "at dusk", "night": "by night"}.get(m.get("time", "day"), "")
	if when != "":
		facts.append(when)
	var sub := UIKit.label(" · ".join(facts), 9, INK_DIM)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = W
	c.add_child(sub)
	var danger := CenterContainer.new()
	danger.tooltip_text = "Danger: %d skull%s" % [int(m["skulls"]), "" if int(m["skulls"]) == 1 else "s"]
	danger.add_child(UIKit.skulls(int(m["skulls"])))
	c.add_child(danger)
	c.add_child(_divider())
	# the client's letter, in their hand
	var l := MissionLore.letter(m, campaign.guild_name)
	var ink := hex(UITheme.INK)
	c.add_child(_ink("[color=#%s][i]%s[/i][/color]" % [ink, l["greeting"]], W, 10))
	c.add_child(_ink("[color=#%s][i]%s[/i][/color]" % [ink, l["body"]], W, 10))
	var sign := UIKit.hbox(4)
	sign.add_child(UIKit.spacer())
	sign.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sig_text := "[right][color=#%s]%s[i]%s[/i][/color][/right]" % [ink, "[i]%s[/i]\n" % l["signoff"] if l["signoff"] != "" else "", l["client"]]
	sign.add_child(_ink(sig_text, 220, 10))
	if m.get("faction", "") != "":
		var seal := UIKit.tex_rect(load("res://assets/sprites/ui/emblem_%s_32.png" % m["faction"]))
		seal.modulate = Color(1, 1, 1, 0.85)
		seal.tooltip_text = DB.factions[m["faction"]]["name"]
		sign.add_child(seal)
	c.add_child(sign)
	c.add_child(_divider())
	# the terms
	c.add_child(_ink(_terms(m), W, 9))
	# warnings and the way in
	var h := UIKit.hbox(4)
	if m.get("faction", "") != "" and int(campaign.factions[m["faction"]]["rep"]) <= -2:
		h.add_child(UIKit.label("Hostile: expect an ambush", 9, UITheme.RED))
	h.add_child(UIKit.spacer())
	h.get_child(h.get_child_count() - 1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_assemble_button(m))
	v.add_child(h)
	return v


## Objective, context, reward and the cost of ignoring it, in ink.
func _terms(m: Dictionary) -> String:
	var cat: String = m["category"]
	var cd: Dictionary = DB.missions["categories"][cat]
	var ink := hex(UITheme.INK)
	var dim := hex(INK_DIM)
	var lines: Array = []
	var od: Dictionary = DB.missions["objectives"].get(m["objective"], {})
	lines.append("[color=#%s][b]Objective (%s):[/b][/color] %s" % [hex(INK_GOLD), od.get("name", m["objective"].capitalize()), objective_text(m)])
	if MapGen.is_explore(m):
		lines.append("[color=#%s]Wide ground under fog. Patrols roam it; the objective waits at the end of the trail.[/color]" % dim)
	elif m["objective"] in ["survive", "defense"]:
		lines.append("[color=#%s]The enemy closes in from the fog.[/color]" % dim)
	if m.get("category", "") != "story" and String(m.get("desc", "")) != "":
		lines.append("[color=#%s]%s[/color]" % [dim, m["desc"]])
	lines.append("[color=#%s][b]Reward:[/b][/color] %s" % [hex(INK_GREEN), reward_text(m)])
	var ig := String(cd.get("ignored", "Nothing happens."))
	ig = ig.format({"hush": m.get("ignore", {}).get("hush", 0), "faction": DB.factions[m["faction"]]["short"] if m.get("faction", "") != "" else "?"})
	if m.has("conflict") and not campaign.mission_by_id(int(m["conflict"])).is_empty():
		ig = "Taking this cancels \"%s\" (%s: reputation -1)." % [campaign.mission_by_id(int(m["conflict"]))["title"], DB.factions[m.get("rival", m["faction"])]["short"]]
	lines.append("[color=#%s][b]If ignored:[/b][/color] %s" % [hex(INK_RED), ig])
	return "[color=#%s]%s[/color]" % [ink, "\n".join(lines)]


static func reward_text(m: Dictionary) -> String:
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
	return ", ".join(parts) if not parts.is_empty() else "none"


## On the map tab: the selected quest in one line, with its letter a click away.
func _map_summary(m: Dictionary) -> Control:
	var v := UIKit.vbox(2)
	var top := UIKit.hbox(4)
	var col: Color = CAT_COLORS.get(m["category"], UITheme.TEXT)
	top.add_child(UIKit.label(DB.missions["categories"][m["category"]]["name"].to_upper(), 8, col, UITheme.pixel_font))
	var tl := UIKit.label(m["title"], 10, UITheme.TEXT)
	tl.clip_text = true
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	top.add_child(UIKit.skulls(int(m["skulls"])))
	v.add_child(top)
	v.add_child(UIKit.rich("[color=#%s]%s:[/color] %s" % [hex(UITheme.GOLD), DB.missions["objectives"].get(m["objective"], {}).get("name", m["objective"].capitalize()),
		objective_text(m)], 320, 9))
	var h := UIKit.hbox(4)
	h.add_child(UIKit.button("Read Letter", func():
		view = "letter"
		Audio.sfx("page", 0.1, -8.0)
		rebuild(), "", 80))
	h.add_child(UIKit.spacer())
	h.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_assemble_button(m))
	v.add_child(h)
	return v


func _assemble_button(m: Dictionary) -> Button:
	var mid := int(m["id"])
	var b := UIKit.button("Assemble Squad", func(): hub.open_screen("squad", {"mission": mid}), "btn_green", 110)
	if not campaign.fits_week(m):
		b.disabled = true
		b.tooltip_text = "It takes %d days; the guild has %d left this week." % [int(m["days"]), campaign.days_left()]
	elif campaign.available_members().is_empty():
		b.disabled = true
		b.tooltip_text = "Nobody is fit to march."
	return b


static func _ink(bbcode: String, width: float, size: int) -> RichTextLabel:
	var r := UIKit.rich(bbcode, width, size)
	r.add_theme_color_override("default_color", UITheme.INK)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	r.add_theme_constant_override("line_separation", 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## A thin inked rule with a red diamond in the middle.
static func _divider() -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(0, 9)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func():
		var w := floorf(d.size.x)
		var mid := floorf(w / 2.0) + 0.5
		var col := Color(UITheme.INK, 0.4)
		d.draw_line(Vector2(floorf(w * 0.1), 4.5), Vector2(mid - 6, 4.5), col, 1.0)
		d.draw_line(Vector2(mid + 6, 4.5), Vector2(ceilf(w * 0.9), 4.5), col, 1.0)
		d.draw_colored_polygon(PackedVector2Array([Vector2(mid, 1), Vector2(mid + 3.5, 4.5), Vector2(mid, 8), Vector2(mid - 3.5, 4.5)]), INK_TITLE))
	return d
