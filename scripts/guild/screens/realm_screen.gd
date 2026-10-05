extends GuildScreen
## The state of Ambral: the four factions, their power and trust in the
## guild, the regions and the Hush.

const FLAG_TEXT := {
	"tide_fleet": ["The Tide Fleet sails", "Coast missions pay 25% more."],
	"trade_cut": ["Trade routes cut", "Market prices +20%."],
	"healing_sap": ["Healing sap flows", "Serious injuries heal a week faster."],
	"conclave_falls": ["The Conclave has fallen", "The Memorial no longer protects the dead from the Hush."],
}


func screen_title() -> String:
	return "The Realm"


func subtitle() -> String:
	return "Factions still Allied when the final battle comes fight beside you"


func build() -> void:
	var v := UIKit.vbox(4)
	body.add_child(scroll(v))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for f in Campaign.FACTIONS:
		grid.add_child(_faction(f))
	v.add_child(grid)
	v.add_child(_hush())


func _faction(f: String) -> Control:
	var fd: Dictionary = DB.factions[f]
	var st: Dictionary = campaign.factions[f]
	var p := UIKit.panel("panel_inset", Vector4(5, 4, 5, 4))
	p.custom_minimum_size.x = 292
	var h := UIKit.hbox(5)
	p.add_child(h)
	var em := UIKit.tex_rect(load("res://assets/sprites/ui/emblem_%s_32.png" % f))
	if st["collapsed"]:
		em.modulate = Color(0.45, 0.45, 0.5)
	h.add_child(em)
	var v := UIKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var fc := DB.color_of(fd["color"])
	v.add_child(UIKit.label(fd["name"], 10, fc if not st["collapsed"] else UITheme.TEXT_DIM, UITheme.pixel_font))
	if st["collapsed"]:
		v.add_child(UIKit.rich("[color=#%s]Collapsed. %s is lost to the Hush.[/color]" % [hex(UITheme.RED), DB.regions[fd["region"]]["name"]], 250, 9))
		return p
	v.add_child(UIKit.rich("[color=#%s]%s · %s[/color]" % [hex(UITheme.TEXT_DIM), fd["people"], DB.regions[fd["region"]]["name"]], 250, 8))
	var rep := int(st["rep"])
	var rh := UIKit.hbox(3)
	var rl := UIKit.label("Trust", 8, UITheme.TEXT_DIM)
	rl.custom_minimum_size.x = 30
	rh.add_child(rl)
	for i in range(-3, 4):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8, 5)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var on := (i < 0 and rep <= i) or (i > 0 and rep >= i) or i == 0
		pip.color = (UITheme.RED if i < 0 else (UITheme.GREEN if i > 0 else UITheme.TEXT_DIM)) if on else Color(0.18, 0.13, 0.18)
		rh.add_child(pip)
	rh.add_child(UIKit.label(Rules.rep_name(rep), 9, UITheme.GREEN if rep > 0 else (UITheme.RED if rep < 0 else UITheme.TEXT)))
	v.add_child(rh)
	var ph := UIKit.hbox(3)
	var pl := UIKit.label("Power", 8, UITheme.TEXT_DIM)
	pl.custom_minimum_size.x = 30
	ph.add_child(pl)
	var pw := int(st["power"])
	var bar := UIKit.bar(pw, 10, fc, 76, 5)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(bar)
	ph.add_child(UIKit.label("%d/10%s" % [pw, "  weak!" if pw <= 3 else ""], 9, UITheme.RED if pw <= 3 else UITheme.TEXT))
	v.add_child(ph)
	var chain := int(st["chain"])
	var ctext := ""
	if chain >= 2:
		ctext = "Chain complete. "
	elif rep >= 2 + chain:
		ctext = "Chain mission available: \"%s\"." % fd["chain"][chain]
	else:
		ctext = "Reach %s to unlock \"%s\"." % [Rules.rep_name(2 + chain), fd["chain"][chain]]
	if rep >= 3:
		ctext += ("\n" if chain < 2 else "") + "Allied: while they stay Allied, they will fight beside you in the final battle and now and then send a %s to your tavern." % DB.classes[fd["unique_class"]]["name"]
	elif chain >= 2:
		ctext += "No longer Allied: win back their trust or they will not come to the final battle."
	v.add_child(UIKit.rich("[color=#%s]Their answer:[/color] %s\n[color=#%s]%s[/color]" % [hex(UITheme.GOLD), fd["answer"], hex(UITheme.TEXT_DIM), ctext], 250, 8))
	p.tooltip_text = fd["desc"]
	return p


func _hush() -> Control:
	var p := UIKit.panel("panel_inset", Vector4(5, 4, 5, 4))
	var v := UIKit.vbox(2)
	p.add_child(v)
	var stage := campaign.hush_stage()
	var h := UIKit.hbox(6)
	h.add_child(UIKit.tex_rect(UIKit.small_tex("hush"), 2.0))
	h.add_child(UIKit.label("The Hush: %d / 100" % campaign.hush, 11, UITheme.PURPLE, UITheme.pixel_font))
	var bar := UIKit.bar(campaign.hush, 100, UITheme.PURPLE.lerp(UITheme.RED, stage / 4.0), 200, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(UIKit.label("Stage: %s" % Rules.hush_stage_name(stage), 10, UITheme.TEXT))
	v.add_child(h)
	var ev: String = DB.events["hush_stages"].get(Rules.hush_stage_name(stage).to_lower(), "")
	if ev != "":
		v.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.TEXT_DIM), ev], 580, 8))
	v.add_child(UIKit.rich("It grows by 2 each week, and when breaches and the story are ignored. Victories against the Hush and names carved into the Memorial hold it back. At 100 the realm is forgotten.", 580, 8))
	var flags: Array = []
	for k in FLAG_TEXT:
		if campaign.flags.get(k, false):
			flags.append("[color=#%s]%s:[/color] %s" % [hex(UITheme.GOLD), FLAG_TEXT[k][0], FLAG_TEXT[k][1]])
	if not flags.is_empty():
		v.add_child(UIKit.rich("\n".join(flags), 580, 8))
	return p
