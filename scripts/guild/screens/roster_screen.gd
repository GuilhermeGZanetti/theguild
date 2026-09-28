extends GuildScreen
## Roster: every member with stats, potential, traits, history, skills,
## loadout, subclass and equipment.

var selected: Member = null
var tab := "overview"


func screen_title() -> String:
	return "Roster"


func subtitle() -> String:
	return "%d / %d members · wages %d gold per week" % [campaign.active_members().size(), campaign.roster_cap(), campaign.weekly_wages()]


func build() -> void:
	if params.has("member"):
		selected = campaign.member(int(params["member"]))
		params.erase("member")
	if params.has("tab"):
		tab = params["tab"]
		params.erase("tab")
	if selected == null or not selected in campaign.roster:
		selected = campaign.roster[0] if not campaign.roster.is_empty() else null
	var h := UIKit.hbox(6)
	body.add_child(h)
	# list
	var list := UIKit.vbox(2)
	for m in campaign.roster:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(164, 30)
		b.toggle_mode = true
		b.button_pressed = m == selected
		UIKit.list_row(b, m == selected)
		var r := MemberCard.row(m, 160)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in r.find_children("*", "Control", true, false):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = Vector2(3, 2)
		b.add_child(r)
		if m.skill_points > 0 or m.can_pick_subclass():
			var badge := UIKit.label("+", 10, UITheme.GOLD, UITheme.pixel_font)
			badge.position = Vector2(154, 1)
			b.add_child(badge)
		var mm: Member = m
		b.pressed.connect(func():
			selected = mm
			Audio.sfx("ui_click", 0.05, -6.0)
			rebuild())
		list.add_child(b)
	var sc := scroll(list)
	sc.custom_minimum_size.x = 172
	sc.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(sc)
	# detail
	var detail := UIKit.vbox(3)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(detail)
	if selected == null:
		detail.add_child(UIKit.label("No members. Hire recruits at the bar.", 10, UITheme.TEXT_DIM))
		return
	var tabs := UIKit.hbox(2)
	for t in [["overview", "Overview"], ["skills", "Skills%s" % (" (%d)" % selected.skill_points if selected.skill_points > 0 else "")], ["gear", "Gear"]]:
		var id: String = t[0]
		var b := UIKit.button(t[1], func():
			tab = id
			rebuild(), "btn_blue" if tab == id else "", 70)
		tabs.add_child(b)
	detail.add_child(tabs)
	var content := UIKit.vbox(3)
	match tab:
		"skills":
			_skills(content)
		"gear":
			_gear(content)
		_:
			_overview(content)
	detail.add_child(scroll(content))


# ---------------------------------------------------------------- overview
func _overview(v: VBoxContainer) -> void:
	var m := selected
	var top := UIKit.hbox(6)
	v.add_child(top)
	top.add_child(MemberCard.portrait(m, 64))
	var info := UIKit.vbox(1)
	top.add_child(info)
	info.add_child(UIKit.header(m.name, 12))
	info.add_child(UIKit.rich("Lv %d [color=#%s]%s[/color] · %s · [color=#%s]%s[/color]" % [m.level, hex(UITheme.GOLD), m.class_name_full(),
		DB.races[m.race]["name"], hex(MemberCard.tier_color(m)), MemberCard.tier_text(m)], 300, 10))
	var xp := UIKit.hbox(3)
	xp.add_child(UIKit.tex_rect(UIKit.small_tex("xp")))
	if m.level >= DB.LEVEL_CAP:
		xp.add_child(UIKit.label("Max level", 9, UITheme.GOLD))
	else:
		var bar := UIKit.bar(m.xp, m.xp_needed(), UITheme.BLUE, 90, 5)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		xp.add_child(bar)
		xp.add_child(UIKit.label("%d / %d XP" % [m.xp, m.xp_needed()], 9, UITheme.TEXT_DIM))
	info.add_child(xp)
	info.add_child(UIKit.rich("%s · Wage [color=#%s]%d[/color] gold/week" % [MemberCard.status_text(m), hex(UITheme.GOLD), m.wage()], 300, 9))
	var mid := UIKit.hbox(12)
	v.add_child(mid)
	var sv := UIKit.vbox(2)
	sv.add_child(UIKit.header("Stats", 10))
	sv.add_child(MemberCard.stats_grid(m, m.reveal >= 2))
	mid.add_child(sv)
	var tv := UIKit.vbox(2)
	tv.add_child(UIKit.header("Traits", 10))
	tv.add_child(MemberCard.traits_flow(m.traits, 170))
	tv.add_child(UIKit.header("History", 10))
	var hist: Dictionary = m.history
	tv.add_child(UIKit.rich("Joined in week %d\nQuests: %d · Kills: %d\nNear deaths: %d" % [int(hist.get("joined", 1)), int(hist.get("quests", 0)),
		int(hist.get("kills", 0)), int(hist.get("near_deaths", 0))], 170, 9))
	if m.bio != "":
		tv.add_child(UIKit.rich("[i]%s[/i]" % m.bio, 170, 9))
	mid.add_child(tv)
	var gear := UIKit.hbox(4)
	gear.add_child(UIKit.header("Gear", 10))
	for slot in ["weapon", "armor", "trinket"]:
		var it: Dictionary = m.equipment.get(slot, {})
		if it.is_empty():
			continue
		var gi := UIKit.tex_rect(MemberCard.item_icon(it))
		gi.tooltip_text = "%s
%s" % [Items.name_of(it), Items.desc_of(it)]
		gear.add_child(gi)
		gear.add_child(MemberCard.item_line(it))
	v.add_child(gear)
	var sk := UIKit.hbox(3)
	sk.add_child(UIKit.header("Loadout", 10))
	var basic: String = m.class_data().get("basic", "")
	if basic != "":
		sk.add_child(MemberCard.skill_icon(basic, 18))
	for s in m.loadout:
		sk.add_child(MemberCard.skill_icon(s, 18))
	for s in m.all_passives():
		sk.add_child(MemberCard.skill_icon(s, 14))
	v.add_child(sk)
	var actions := UIKit.hbox(4)
	v.add_child(actions)
	var perm := m.permanent_injuries()
	if not perm.is_empty() and int(campaign.facilities["nursery"]) >= 3:
		for p in perm:
			var pid: String = p
			actions.add_child(UIKit.button("Treat %s (%d)" % [DB.traits[pid]["name"], campaign.price(200)], func():
				act(campaign.treat_permanent(m, pid), "%s is healed." % m.name), "btn_green"))
	actions.add_child(UIKit.spacer())
	if campaign.roster.size() > 1:
		actions.add_child(UIKit.button("Dismiss", func():
			Dialogs.confirm(hub, "Dismiss %s?" % m.name, "They leave the guild for good. Unique items and upgraded gear go back to the stash.", func():
				campaign.dismiss(m)
				selected = null
				hub.changed()
				rebuild(), "Dismiss"), "btn_red"))


# ---------------------------------------------------------------- skills
func _skills(v: VBoxContainer) -> void:
	var m := selected
	var lib := int(campaign.facilities["library"])
	var info := "Skill points: [color=#%s]%d[/color]" % [hex(UITheme.GOLD), m.skill_points]
	if lib > 0:
		info += " · Library %d: buy skills up to level %d%s" % [lib, int(DB.facilities["library"]["max_level"][lib]),
			(" (%d%% off)" % roundi(float(DB.facilities["library"]["discount"][lib]) * 100)) if float(DB.facilities["library"]["discount"][lib]) > 0 else ""]
	else:
		info += " · [color=#%s]Build the Library to buy skills with gold.[/color]" % hex(UITheme.TEXT_DIM)
	v.add_child(UIKit.rich(info, 400, 9))
	# subclass
	if m.can_pick_subclass():
		var sp := GuildScreen.inset(UIKit.vbox(2), "panel_light")
		var sv: VBoxContainer = sp.get_child(0)
		sv.add_child(UIKit.header("Choose a subclass (level %d)" % DB.SUBCLASS_LEVEL, 10, UITheme.INK))
		for sc in m.class_data()["subclasses"]:
			var scd: Dictionary = DB.subclasses[sc]
			var row := UIKit.hbox(4)
			var sid: String = sc
			row.add_child(UIKit.button(scd["name"], func():
				Dialogs.confirm(hub, "Become a %s?" % scd["name"], "%s\n\nThis choice is permanent." % scd["desc"], func():
					m.choose_subclass(sid)
					hub.changed()
					rebuild()), "btn_blue", 80))
			var d := UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.INK), scd["desc"]], 300, 9)
			row.add_child(d)
			sv.add_child(row)
		v.add_child(sp)
	elif m.subclass != "":
		v.add_child(UIKit.rich("Subclass: [color=#%s]%s[/color] · %s" % [hex(UITheme.GOLD), DB.subclasses[m.subclass]["name"], DB.subclasses[m.subclass]["desc"]], 400, 9))
	# loadout
	v.add_child(UIKit.header("Loadout (%d/4) · click to swap in or out" % m.loadout.size(), 10))
	var lo := UIKit.hbox(3)
	var basic: String = m.class_data().get("basic", "")
	if basic != "":
		var bi := MemberCard.skill_icon(basic, 20)
		bi.tooltip_text = "Basic attack (always available)\n" + MemberCard.skill_tip(basic)
		lo.add_child(bi)
		lo.add_child(UIKit.spacer(4, 1))
	for s in m.active_skills():
		var sid: String = s
		var inl: bool = s in m.loadout
		var b := UIKit.icon_button(UIKit.skill_icon(s), func():
			if sid in m.loadout:
				m.loadout.erase(sid)
			elif m.loadout.size() < 4:
				m.loadout.append(sid)
			else:
				hub.toast("The loadout is full (4 skills).", UITheme.RED)
				return
			hub.changed()
			rebuild(), MemberCard.skill_tip(s) + ("\n[In loadout]" if inl else "\n[Not in loadout]"), 22)
		b.modulate = Color(1, 1, 1) if inl else Color(0.45, 0.45, 0.5)
		if inl:
			b.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0), UITheme.GOLD, 1, 0))
		lo.add_child(b)
	v.add_child(lo)
	var pas := m.all_passives()
	if not pas.is_empty():
		var ph := UIKit.hbox(3)
		ph.add_child(UIKit.label("Passives:", 9, UITheme.TEXT_DIM))
		for p in pas:
			ph.add_child(MemberCard.skill_icon(p, 16))
		v.add_child(ph)
	# branches
	var cd := m.class_data()
	var bh := UIKit.hbox(8)
	v.add_child(bh)
	for br in cd["branches"]:
		var col := UIKit.vbox(2)
		col.custom_minimum_size.x = 196
		col.add_child(UIKit.header(cd["branches"][br]["name"], 10))
		for s in cd["branches"][br]["skills"]:
			col.add_child(_skill_row(m, s))
		bh.add_child(col)


func _skill_row(m: Member, s: String) -> Control:
	var sd := DB.skill(s)
	var h := UIKit.hbox(3)
	var known: bool = s in m.skills
	h.add_child(MemberCard.skill_icon(s, 18, not known and m.level < int(sd.get("level", 1))))
	var v := UIKit.vbox(0)
	var nl := UIKit.label(sd.get("name", s), 9, UITheme.TEXT if known else UITheme.TEXT_DIM)
	nl.custom_minimum_size.x = 80
	nl.clip_text = true
	v.add_child(nl)
	v.add_child(UIKit.label("Lv %d%s" % [int(sd.get("level", 1)), " · passive" if sd.get("passive", false) else ""], 8, UITheme.TEXT_DIM))
	h.add_child(v)
	h.tooltip_text = MemberCard.skill_tip(s)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	if known:
		h.add_child(UIKit.label("Learned", 9, UITheme.GREEN))
		return h
	var sp_err := campaign.can_learn(m, s, false)
	var b1 := UIKit.button("1 SP", func(): act(campaign.learn_skill(m, s, false), "%s learned %s." % [m.name.split(" ")[0], sd.get("name", s)]), "btn_green", 0)
	b1.disabled = sp_err != ""
	b1.tooltip_text = sp_err if sp_err != "" else "Spend a skill point."
	h.add_child(b1)
	if int(campaign.facilities["library"]) > 0:
		var g_err := campaign.can_learn(m, s, true)
		var b2 := UIKit.button("%dg" % campaign.skill_gold_cost(s), func(): act(campaign.learn_skill(m, s, true), "%s learned %s." % [m.name.split(" ")[0], sd.get("name", s)]), "", 0)
		b2.disabled = g_err != ""
		b2.tooltip_text = g_err if g_err != "" else "Buy with gold at the Library."
		h.add_child(b2)
	return h


# ---------------------------------------------------------------- gear
func _gear(v: VBoxContainer) -> void:
	var m := selected
	v.add_child(UIKit.rich("Materials: [color=#%s]%d[/color] · Forge level %d (upgrades up to %s)" % [hex(UITheme.GOLD), campaign.materials,
		int(campaign.facilities["forge"]), DB.items["tiers"][int(DB.facilities["forge"]["max_tier"][int(campaign.facilities["forge"])]) - 1]], 400, 9))
	for slot in ["weapon", "armor", "trinket"]:
		var it: Dictionary = m.equipment.get(slot, {})
		var row := UIKit.hbox(4)
		var icon := UIKit.tex_rect(MemberCard.item_icon(it) if not it.is_empty() else UIKit.icon_tex("interact"))
		icon.custom_minimum_size = Vector2(18, 18)
		row.add_child(icon)
		var col := UIKit.vbox(0)
		col.custom_minimum_size.x = 250
		col.add_child(UIKit.label(slot.capitalize(), 8, UITheme.TEXT_DIM))
		col.add_child(MemberCard.item_line(it, "Empty"))
		if not it.is_empty():
			col.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.TEXT_DIM), Items.desc_of(it)], 250, 8))
		row.add_child(col)
		if Items.can_upgrade(it):
			var c := campaign.forge_cost(it)
			var err := campaign.can_forge(it)
			var itd: Dictionary = it
			var b := UIKit.button("Upgrade %dg %dm" % [c[0], c[1]], func():
				if act(campaign.forge_upgrade(itd, m), "%s is now %s." % [slot.capitalize(), Items.name_of(itd)]):
					Audio.sfx("armor_break", 0.1, -4.0), "btn_green")
			b.disabled = err != ""
			b.tooltip_text = err if err != "" else "Improve to %s." % DB.items["tiers"][int(it["tier"])]
			row.add_child(b)
		if slot == "trinket" and not it.is_empty():
			row.add_child(UIKit.button("Unequip", func():
				campaign.unequip(m, "trinket")
				hub.changed()
				rebuild()))
		v.add_child(row)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.header("From the stash", 10))
	var any := false
	for it in campaign.inventory:
		if not Items.fits(it, m.cls):
			continue
		any = true
		var row := UIKit.hbox(4)
		var icon := UIKit.tex_rect(MemberCard.item_icon(it))
		icon.custom_minimum_size = Vector2(16, 16)
		row.add_child(icon)
		var line := MemberCard.item_line(it)
		line.custom_minimum_size.x = 120
		row.add_child(line)
		var d := UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.TEXT_DIM), Items.desc_of(it)], 190, 8)
		row.add_child(d)
		var itd: Dictionary = it
		row.add_child(UIKit.button("Equip", func():
			if act(campaign.equip(m, itd), "%s equipped." % Items.name_of(itd)):
				Audio.sfx("cloth", 0.1, -4.0)))
		v.add_child(row)
	if not any:
		v.add_child(UIKit.label("Nothing in the stash fits a %s." % m.class_name_full(), 9, UITheme.TEXT_DIM))
