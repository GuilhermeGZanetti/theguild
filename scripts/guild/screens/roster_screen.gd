extends GuildScreen
## Roster: every member with stats, potential, traits, history, the skill
## tree, loadout and equipment.

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
		if m.pending_picks() > 0:
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
	for t in [["overview", "Overview"], ["skills", "Skills%s" % (" (%d)" % selected.pending_picks() if selected.pending_picks() > 0 else "")], ["gear", "Gear"]]:
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
## XCOM-style tree: one row per level from 2 to 10, one skill from each branch
## per row. A member takes one skill of a row, never both; the Library can
## retrain a row for gold.
func _skills(v: VBoxContainer) -> void:
	var m := selected
	var lib := int(campaign.facilities["library"])
	var picks := m.pending_picks()
	var info := ""
	if picks > 0:
		info = "[color=#%s]%d skill%s to choose.[/color] " % [hex(UITheme.GREEN), picks, "" if picks == 1 else "s"]
	elif m.level < DB.LEVEL_CAP:
		info = "Next skill at level %d. " % (m.level + 1)
	if lib > 0:
		info += "Library: retrain skills up to level %d%s." % [int(DB.facilities["library"]["max_level"][lib]),
			(" (%d%% off)" % roundi(float(DB.facilities["library"]["discount"][lib]) * 100)) if float(DB.facilities["library"]["discount"][lib]) > 0 else ""]
	else:
		info += "[color=#%s]Build the Library to retrain skills.[/color]" % hex(UITheme.TEXT_DIM)
	v.add_child(UIKit.rich(info, 440, 9))
	# loadout
	v.add_child(UIKit.header("Loadout (%d/%d) · click to swap in or out" % [m.loadout.size(), Member.LOADOUT], 10))
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
			elif m.loadout.size() < Member.LOADOUT:
				m.loadout.append(sid)
			else:
				hub.toast("The loadout is full (%d skills)." % Member.LOADOUT, UITheme.RED)
				return
			hub.changed()
			rebuild(), MemberCard.skill_tip(s) + ("\n[In loadout]" if inl else "\n[Not in loadout]"), 22)
		b.modulate = Color(1, 1, 1) if inl else Color(0.45, 0.45, 0.5)
		if inl:
			b.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0), UITheme.GOLD, 1, 0))
		lo.add_child(b)
	var pas := m.all_passives()
	if not pas.is_empty():
		lo.add_child(UIKit.spacer(6, 1))
		lo.add_child(UIKit.label("Passives:", 9, UITheme.TEXT_DIM))
		for p in pas:
			lo.add_child(MemberCard.skill_icon(p, 16))
	v.add_child(lo)
	# tree
	var cd := m.class_data()
	var brs: Array = cd["branches"].keys()
	var head := UIKit.hbox(3)
	head.add_child(UIKit.spacer(26, 1))
	for br in brs:
		var bd: Dictionary = cd["branches"][br]
		var title: String = DB.subclasses.get(bd.get("title", ""), {}).get("name", "")
		var hl := UIKit.rich("[color=#%s]%s[/color]  [color=#%s]→ %s[/color]" % [hex(UITheme.GOLD), bd["name"], hex(UITheme.TEXT_DIM), title], 206, 10)
		hl.custom_minimum_size.x = 206
		hl.tooltip_text = "Taking the level 10 %s skill makes %s a %s.\n%s" % [bd["name"], m.name.split(" ")[0], title,
			DB.subclasses.get(bd.get("title", ""), {}).get("desc", "")]
		head.add_child(hl)
	v.add_child(head)
	for row in range(2, DB.LEVEL_CAP + 1):
		var pair := m.row_skills(row)
		if pair.is_empty():
			continue
		var h := UIKit.hbox(3)
		var ll := UIKit.label("Lv%d" % row, 9, UITheme.GOLD if row <= m.level else UITheme.TEXT_DIM, UITheme.pixel_font)
		ll.custom_minimum_size = Vector2(26, 24)
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(ll)
		for br in brs:
			var sid := ""
			for s in pair:
				if DB.branch_of(s) == br:
					sid = s
			h.add_child(_tree_cell(m, row, sid) if sid != "" else UIKit.spacer(206, 24))
		v.add_child(h)


func _tree_cell(m: Member, row: int, s: String) -> Control:
	var sd := DB.skill(s)
	var taken := s in m.skills
	var other := m.row_pick(row)
	var open := row <= m.level and other == ""
	var b := Button.new()
	b.custom_minimum_size = Vector2(206, 24)
	UIKit.list_row(b, taken)
	var h := UIKit.hbox(4)
	h.position = Vector2(3, 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon := MemberCard.skill_icon(s, 18, not taken and not open)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var col := UIKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_col := UITheme.GOLD if taken else (UITheme.TEXT if open else UITheme.TEXT_DIM)
	var nl := UIKit.label(sd.get("name", s), 9, name_col)
	nl.custom_minimum_size.x = 118
	nl.clip_text = true
	col.add_child(nl)
	col.add_child(UIKit.label("Passive" if sd.get("passive", false) else "Active", 8, UITheme.TEXT_DIM))
	h.add_child(col)
	for c in col.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := ""
	var tag_col := UITheme.TEXT_DIM
	var first := m.name.split(" ")[0]
	var cb := Callable()
	if taken:
		tag = "Learned"
		tag_col = UITheme.GREEN
	elif open:
		tag = "Learn"
		tag_col = UITheme.GREEN
		var others: Array = m.row_skills(row).filter(func(x): return x != s)
		var lost: String = DB.skill(others[0]).get("name", others[0]) if not others.is_empty() else ""
		cb = func():
			Dialogs.confirm(hub, "Learn %s?" % sd.get("name", s), "%s\n\n%s will not be able to learn %s (level %d) unless retrained at the Library." % [
				sd.get("desc", ""), first, lost, row], func():
					act(campaign.learn_skill(m, s), "%s learned %s." % [first, sd.get("name", s)]), "Learn")
	elif row > m.level:
		tag = "Lv %d" % row
	else:
		var err := campaign.can_retrain(m, row)
		tag = "Retrain %dg" % campaign.retrain_cost(row)
		tag_col = UITheme.GOLD if err == "" else UITheme.TEXT_DIM
		b.tooltip_text = "\n\n" + (err if err != "" else "Swap %s for this skill." % DB.skill(other).get("name", other))
		if err == "":
			cb = func():
				Dialogs.confirm(hub, "Retrain %s?" % first, "Forget %s and learn %s for %d gold." % [DB.skill(other).get("name", other), sd.get("name", s), campaign.retrain_cost(row)], func():
					act(campaign.retrain(m, row), "%s retrained: %s." % [first, sd.get("name", s)]), "Retrain")
	var tl := UIKit.label(tag, 8, tag_col)
	tl.custom_minimum_size.x = 52
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tl)
	b.tooltip_text = MemberCard.skill_tip(s) + b.tooltip_text
	if cb.is_valid():
		b.pressed.connect(func():
			Audio.sfx("ui_click", 0.05, -4.0)
			cb.call())
	else:
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if not taken and not open:
		b.modulate = Color(0.8, 0.8, 0.85)
	return b


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
