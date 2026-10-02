class_name MemberCard
extends RefCounted
## UI building blocks for showing a member: portrait rows, stat grids with
## growth potential, traits, equipment and skill tooltips.

const STAT_ICONS := {"hp": "hp", "defense": "defense", "dodge": "dodge", "speed": "speed", "move": "move", "crit": "crit",
	"attack": "attack", "accuracy": "accuracy", "range": "range", "resolve": "resolve"}
const STAT_TIPS := {
	"hp": "Health. At 0 the member is Downed and starts bleeding out.",
	"defense": "Armor. Subtracted from damage; wears down by 15% of each hit.",
	"dodge": "Lowers enemy hit chance.",
	"speed": "Acts sooner and more often on the timeline.",
	"move": "Tiles per turn.",
	"crit": "Chance of a critical hit (x1.5 damage).",
	"attack": "Damage of weapon attacks and skills.",
	"accuracy": "Raises hit chance.",
	"range": "Optimal range of ranged attacks. -10 hit per tile beyond.",
	"resolve": "Resists fear, stuns and other status effects; steadies morale when allies fall.",
}


static func portrait(m: Member, size := 24, grey := 0.0) -> Control:
	var p := UIKit.portrait(m.variant, m.palette, not m.injury.is_empty(), grey)
	p.custom_minimum_size = Vector2(size, size)
	if size <= 26:
		var at := AtlasTexture.new()
		at.atlas = p.texture
		at.region = Rect2(4, 2, 24, 24)
		p.texture = at
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color8(24, 16, 26), Color8(90, 70, 70), 1, 1))
	frame.add_child(p)
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	return frame


static func portrait_dict(d: Dictionary, size := 24, grey := 0.9) -> Control:
	var p := UIKit.portrait(d.get("variant", "human_warrior_m_a"), d.get("palette", {}), false, grey)
	p.custom_minimum_size = Vector2(size, size)
	var at := AtlasTexture.new()
	at.atlas = p.texture
	at.region = Rect2(4, 2, 24, 24)
	p.texture = at
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color8(24, 16, 26), Color8(70, 64, 70), 1, 1))
	frame.add_child(p)
	return frame


static func tier_text(m: Member) -> String:
	if m.reveal >= 1:
		return DB.TIERS[m.tier]
	# the untrained eye guesses, and may be wrong by one step
	var guess := clampi(m.tier + (absi(hash(m.name)) % 3) - 1, 0, 3)
	return "Looks %s?" % DB.TIERS[guess]


static func tier_color(m: Member) -> Color:
	if m.reveal < 1:
		return UITheme.TEXT_DIM
	return [Color8(170, 150, 140), UITheme.TEXT, UITheme.BLUE, UITheme.GOLD][m.tier]


static func status_text(m: Member) -> String:
	if not m.injury.is_empty():
		var w := int(m.injury["weeks"])
		return "[color=#%s]%s injury · %d week%s[/color]" % [UITheme.RED.to_html(false), m.injury.get("kind", "light").capitalize(), w, "" if w == 1 else "s"]
	return "[color=#%s]Ready[/color]" % UITheme.GREEN.to_html(false)


## Compact row: portrait, name, class and level, status.
static func row(m: Member, width := 150) -> HBoxContainer:
	var h := UIKit.hbox(4)
	h.add_child(portrait(m))
	var v := UIKit.vbox(0)
	var nl := UIKit.label(m.name, 10, UITheme.TEXT)
	nl.clip_text = true
	nl.custom_minimum_size.x = width - 30
	v.add_child(nl)
	v.add_child(UIKit.rich("[color=#%s]Lv %d %s[/color]  %s" % [UITheme.TEXT_DIM.to_html(false), m.level, m.class_name_full(), status_text(m)], width - 30, 8))
	h.add_child(v)
	return h


static func stats_grid(m: Member, show_potential: bool) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 0)
	var s := m.stats()
	for k in DB.STATS:
		var h := UIKit.hbox(2)
		h.add_child(UIKit.tex_rect(UIKit.small_tex(STAT_ICONS[k])))
		var name := UIKit.label(DB.STAT_NAMES[k], 9, UITheme.TEXT_DIM)
		name.custom_minimum_size.x = 44
		h.add_child(name)
		var val := UIKit.label(str(int(s[k])), 10, UITheme.TEXT, UITheme.number_font)
		val.custom_minimum_size.x = 20
		h.add_child(val)
		if show_potential and m.potential.has(k):
			h.add_child(pips(int(m.potential[k])))
		h.tooltip_text = STAT_TIPS[k] + ("\nGrowth potential: %s" % ["", "low", "medium", "high"][int(m.potential[k])] if show_potential and m.potential.has(k) else "")
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(h)
	return g


## Growth potential as 1-3 small pips.
static func pips(n: int) -> HBoxContainer:
	var h := UIKit.hbox(1)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col: Color = [UITheme.TEXT_DIM, UITheme.TEXT_DIM, UITheme.TEXT, UITheme.GOLD][clampi(n, 0, 3)]
	for i in 3:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(3, 3)
		r.color = col if i < n else Color(0.22, 0.17, 0.22)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h


static func traits_flow(traits: Array, width := 200) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 3)
	f.add_theme_constant_override("v_separation", 2)
	f.custom_minimum_size.x = width
	for t in traits:
		var d: Dictionary = DB.traits.get(t, {"name": t, "desc": "", "good": true})
		var col := UITheme.GREEN if d.get("good", false) else UITheme.RED
		if d.get("special", false):
			col = UITheme.PURPLE
		if d.get("injury", false):
			col = Color8(220, 140, 110)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UITheme.flat(Color8(30, 22, 32), col.darkened(0.45), 1, 2))
		p.add_child(UIKit.label(d.get("name", t), 9, col))
		p.tooltip_text = d.get("desc", "")
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		f.add_child(p)
	if traits.is_empty():
		f.add_child(UIKit.label("No traits", 9, UITheme.TEXT_DIM))
	return f


static func skill_tip(skill_id: String) -> String:
	var s := DB.skill(skill_id)
	var parts: Array = [s.get("name", skill_id)]
	var meta: Array = []
	if s.get("passive", false):
		meta.append("Passive")
	else:
		if int(s.get("cd", 0)) > 0:
			meta.append("Cooldown %d" % int(s["cd"]))
		var r: Dictionary = s.get("range", {})
		match r.get("kind", ""):
			"melee": meta.append("Melee")
			"weapon": meta.append("Weapon range")
			"fixed": meta.append("Range %d" % int(r.get("max", r.get("r", 3))))
			"self": meta.append("Self")
			"charge": meta.append("Charge")
	if int(s.get("level", 0)) > 1:
		meta.append("Level %d" % int(s["level"]))
	for eff in s.get("effects", []):
		if eff.get("sure", false):
			meta.append("Always hits")
			break
	if s.get("aoe", {}).get("who", "") == "all":
		meta.append("Hits allies too")
	if not meta.is_empty():
		parts.append(" · ".join(meta))
	parts.append(s.get("desc", ""))
	return "\n".join(parts)


static func skill_icon(skill_id: String, size := 18, dim := false) -> TextureRect:
	var r := UIKit.tex_rect(UIKit.skill_icon(skill_id))
	r.custom_minimum_size = Vector2(size, size)
	r.tooltip_text = skill_tip(skill_id)
	if dim:
		r.modulate = Color(0.5, 0.5, 0.55)
	return r


static func item_line(item: Dictionary, empty_label := "-") -> RichTextLabel:
	if item.is_empty():
		return UIKit.rich("[color=#%s]%s[/color]" % [UITheme.TEXT_DIM.to_html(false), empty_label], 0, 9)
	var col := item_color(item)
	var r := UIKit.rich("[color=#%s]%s[/color]" % [col.to_html(false), Items.name_of(item)], 0, 9)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.tooltip_text = "%s\n%s" % [Items.name_of(item), Items.desc_of(item)]
	return r


static func item_color(item: Dictionary) -> Color:
	match item.get("kind", ""):
		"unique":
			return UITheme.PURPLE
		"trinket":
			return UITheme.BLUE
	return [UITheme.TEXT_DIM, UITheme.TEXT, UITheme.GREEN, UITheme.GOLD][clampi(int(item.get("tier", 1)) - 1, 0, 3)]


static func item_icon(item: Dictionary) -> Texture2D:
	match item.get("kind", ""):
		"weapon":
			return UIKit.icon_tex({"sword": "sword", "daggers": "dagger", "bow": "bow", "staff": "orb", "trident": "trident",
				"lantern": "lantern", "graftstaff": "staff", "glassblades": "glass"}.get(item.get("base", ""), "sword"))
		"armor":
			return UIKit.icon_tex("shield")
		"trinket":
			return UIKit.icon_tex("memory")
		"unique":
			return UIKit.icon_tex("beacon")
	return UIKit.icon_tex("sword")
