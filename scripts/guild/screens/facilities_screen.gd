extends GuildScreen
## The seven facilities, three levels each. Building one changes the tavern.

const ORDER := ["barracks", "recruiter", "nursery", "training", "forge", "library", "memorial"]
const ICONS := {"barracks": "bulwark", "recruiter": "knight", "nursery": "mend", "training": "steady", "forge": "sunder",
	"library": "quill", "memorial": "memory"}


func screen_title() -> String:
	return "Facilities"


func subtitle() -> String:
	return "Renown %d (%s)" % [campaign.renown, Rules.rank_name(campaign.rank())]


func build() -> void:
	var focus: String = params.get("focus", "")
	var h := UIKit.hbox(6)
	body.add_child(h)
	var list := UIKit.vbox(3)
	for fid in ORDER:
		list.add_child(_row(fid, fid == focus))
	var sc := scroll(list)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sc)
	if focus != "":
		var side := _context(focus)
		if side:
			h.add_child(side)


func _row(fid: String, focused: bool) -> Control:
	var fd: Dictionary = DB.facilities[fid]
	var lvl := int(campaign.facilities[fid])
	var p := UIKit.panel("panel_light" if focused else "panel_inset", Vector4(5, 3, 5, 3))
	var ink := UITheme.INK if focused else UITheme.TEXT
	var dim := UITheme.INK.lightened(0.3) if focused else UITheme.TEXT_DIM
	var h := UIKit.hbox(5)
	p.add_child(h)
	var ic := UIKit.tex_rect(UIKit.icon_tex(ICONS[fid]))
	ic.custom_minimum_size = Vector2(20, 20)
	h.add_child(ic)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := UIKit.hbox(4)
	top.add_child(UIKit.label(fd["name"], 10, ink, UITheme.pixel_font))
	for i in 3:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 6)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = UITheme.GOLD if i < lvl else Color(0.2, 0.15, 0.2)
		top.add_child(pip)
	v.add_child(top)
	var now := "Not built." if lvl == 0 else String(fd["levels"][lvl - 1])
	if fid == "barracks":
		now = "Roster %d, squad of %d" % [campaign.roster_cap(), campaign.squad_cap()]
	v.add_child(UIKit.rich("[color=#%s]%s[/color] [color=#%s]Now: %s[/color]" % [hex(dim), fd["desc"], hex(ink), now], 360, 8))
	if lvl < 3:
		v.add_child(UIKit.rich("[color=#%s]Next: %s[/color]" % [hex(UITheme.GREEN if not focused else Color8(40, 100, 40)), fd["levels"][lvl]], 360, 8))
		var cost := campaign.facility_upgrade_cost(fid)
		var req := campaign.facility_renown_req(fid)
		var b := UIKit.button("%s · %d gold" % ["Build" if lvl == 0 else "Upgrade", cost], func():
			var name: String = fd["name"]
			if act(campaign.upgrade_facility(fid), "%s level %d!" % [name, lvl + 1], true):
				Audio.sfx("objective", 0.0, -2.0), "btn_green", 120)
		var err := ""
		if campaign.renown < req:
			err = "Requires %d Renown." % req
		elif campaign.gold < cost:
			err = "Not enough gold."
		b.disabled = err != ""
		b.tooltip_text = err
		var bv := UIKit.vbox(0)
		bv.add_child(b)
		if req > 0:
			bv.add_child(UIKit.label("Renown %d" % req, 8, UITheme.RED if campaign.renown < req else dim))
		h.add_child(bv)
	else:
		h.add_child(UIKit.label("Complete", 9, UITheme.GOLD if not focused else UITheme.INK))
	return p


func _context(fid: String) -> Control:
	var v := UIKit.vbox(3)
	v.custom_minimum_size.x = 170
	match fid:
		"nursery":
			v.add_child(UIKit.header("Resting", 10))
			var any := false
			for m in campaign.roster:
				if not m.injury.is_empty() or not m.permanent_injuries().is_empty():
					any = true
					v.add_child(MemberCard.row(m, 168))
					for p in m.permanent_injuries():
						v.add_child(UIKit.rich("[color=#%s]%s[/color]: %s" % [hex(Color8(220, 140, 110)), DB.traits[p]["name"], DB.traits[p]["desc"]], 168, 8))
			if not any:
				v.add_child(UIKit.label("Everyone is healthy.", 9, UITheme.TEXT_DIM))
			if int(campaign.facilities["nursery"]) >= 3:
				v.add_child(UIKit.rich("Treat permanent injuries from each member's page in the Roster.", 168, 8))
		"training":
			var xp := int(DB.facilities["training"]["xp"][int(campaign.facilities["training"])])
			v.add_child(UIKit.header("Sparring", 10))
			v.add_child(UIKit.rich("Members who spend no days on missions earn [color=#%s]%d XP[/color] when the week ends." % [hex(UITheme.GOLD), xp], 168, 9))
			for m in campaign.roster:
				if m.days_used == 0 and m.injury.is_empty():
					v.add_child(MemberCard.row(m, 168))
		"barracks":
			v.add_child(UIKit.header("Bunks", 10))
			v.add_child(UIKit.rich("Members: %d of %d\nSquad size: %d\nWages: %d gold per week" % [campaign.active_members().size(), campaign.roster_cap(),
				campaign.squad_cap(), campaign.weekly_wages()], 168, 9))
		_:
			return null
	return v
