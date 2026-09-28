extends GuildScreen
## Recruits waiting at the bar: class, visible traits, estimated tier and
## hiring cost. The Recruiter facility reveals tier and growth potential.


func screen_title() -> String:
	return "Recruits"


func subtitle() -> String:
	var lvl := int(campaign.facilities["recruiter"])
	return "Recruiter level %d · %s · roster %d/%d" % [lvl, ["tier and potential hidden", "tier revealed", "tier and potential revealed", "tier and potential revealed"][lvl],
		campaign.active_members().size(), campaign.roster_cap()]


func build() -> void:
	if campaign.recruits.is_empty():
		body.add_child(UIKit.label("Nobody is looking for work this week. New faces arrive when the week ends.", 10, UITheme.TEXT_DIM))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var focus := int(params.get("index", -1))
	for i in campaign.recruits.size():
		grid.add_child(_card(campaign.recruits[i], i == focus))
	body.add_child(scroll(grid))


func _card(m: Member, focused: bool) -> Control:
	var p := UIKit.panel("panel_light" if focused else "panel", Vector4(5, 4, 5, 4))
	p.custom_minimum_size.x = 196
	var v := UIKit.vbox(2)
	p.add_child(v)
	var ink := UITheme.INK if focused else UITheme.TEXT
	var dim := UITheme.INK.lightened(0.25) if focused else UITheme.TEXT_DIM
	var top := UIKit.hbox(4)
	top.add_child(MemberCard.portrait(m, 32))
	var info := UIKit.vbox(0)
	var nl := UIKit.label(m.name, 10, ink)
	nl.custom_minimum_size.x = 150
	nl.clip_text = true
	info.add_child(nl)
	info.add_child(UIKit.label("Lv %d %s · %s" % [m.level, m.class_name_full(), DB.races[m.race]["name"]], 9, dim))
	info.add_child(UIKit.label(MemberCard.tier_text(m), 9, MemberCard.tier_color(m) if not focused else UITheme.INK))
	top.add_child(info)
	v.add_child(top)
	v.add_child(MemberCard.traits_flow(m.traits, 184))
	var s := m.stats()
	var sl := UIKit.hbox(4)
	for k in ["hp", "attack", "defense", "accuracy", "dodge", "speed"]:
		var h := UIKit.hbox(1)
		h.add_child(UIKit.tex_rect(UIKit.small_tex(k)))
		h.add_child(UIKit.label(str(int(s[k])), 9, ink, UITheme.number_font))
		if m.reveal >= 2 and m.potential.has(k):
			h.add_child(MemberCard.pips(int(m.potential[k])))
		h.tooltip_text = DB.STAT_NAMES[k] + (" (pips: growth potential)" if m.reveal >= 2 else "")
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		sl.add_child(h)
	v.add_child(sl)
	if m.bio != "":
		v.add_child(UIKit.rich("[i][color=#%s]%s[/color][/i]" % [hex(dim), m.bio], 184, 8))
	var cost := UIKit.hbox(4)
	cost.add_child(UIKit.stat_row("gold", "Hire %d" % m.hire_cost if m.hire_cost > 0 else "Free", UITheme.GOLD if not focused else UITheme.INK))
	cost.add_child(UIKit.stat_row("wage", "%d/wk" % m.wage(), dim))
	cost.add_child(UIKit.spacer())
	var mm := m
	var b := UIKit.button("Hire", func():
		if act(campaign.hire(mm), "%s joins the guild!" % mm.name):
			Audio.sfx("objective", 0.0, -4.0), "btn_green", 44)
	if campaign.active_members().size() >= campaign.roster_cap():
		b.disabled = true
		b.tooltip_text = "The barracks are full."
	elif campaign.gold < m.hire_cost:
		b.disabled = true
		b.tooltip_text = "Not enough gold."
	cost.add_child(b)
	v.add_child(cost)
	return p
