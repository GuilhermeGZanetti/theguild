extends GuildScreen
## The Memorial: the fallen. Recorded names do not feed the Hush and never
## return as Echoes in the final battle.


func screen_title() -> String:
	return "Memorial"


func subtitle() -> String:
	var lvl := int(campaign.facilities["memorial"])
	if lvl == 0:
		return "Not built · the unrecorded dead feed the Hush"
	var c := campaign.memorial_cost()
	return "Level %d · recording a name costs %s" % [lvl, "nothing" if c == 0 else "%d gold" % c]


func build() -> void:
	var v := UIKit.vbox(3)
	body.add_child(scroll(v))
	if campaign.dead.is_empty():
		v.add_child(UIKit.rich("[color=#%s]No one has fallen yet. Keep it that way.[/color]" % hex(UITheme.TEXT_DIM), 400, 10))
		return
	var lvl := int(campaign.facilities["memorial"])
	for i in range(campaign.dead.size() - 1, -1, -1):
		var d: Dictionary = campaign.dead[i]
		var p := UIKit.panel("panel_inset", Vector4(5, 3, 5, 3))
		var h := UIKit.hbox(5)
		p.add_child(h)
		h.add_child(MemberCard.portrait_dict(d, 24, 0.85))
		var info := UIKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var death: Dictionary = d.get("death", {})
		var cls: String = DB.classes.get(d.get("cls", "warrior"), {}).get("name", "?")
		if DB.subclasses.has(d.get("subclass", "")):
			cls = DB.subclasses[d["subclass"]]["name"]
		info.add_child(UIKit.label(d.get("name", "?"), 10, UITheme.TEXT if d.get("memorial", false) else UITheme.TEXT_DIM, UITheme.pixel_font))
		info.add_child(UIKit.rich("[color=#%s]Lv %d %s · %s at %s, week %d · %d quests, %d kills[/color]" % [hex(UITheme.TEXT_DIM), int(d.get("level", 1)), cls,
			death.get("cause", "Fell"), death.get("mission", "?"), int(death.get("week", 1)), int(d.get("history", {}).get("quests", 0)),
			int(d.get("history", {}).get("kills", 0))], 420, 8))
		h.add_child(info)
		if d.get("memorial", false):
			h.add_child(UIKit.label("Remembered", 9, UITheme.GOLD))
		elif lvl == 0:
			h.add_child(UIKit.label("Build the Memorial", 8, UITheme.TEXT_DIM))
		else:
			var idx := i
			var c := campaign.memorial_cost()
			var b := UIKit.button("Carve the name%s" % ("" if c == 0 else " · %dg" % c), func():
				if act(campaign.record_memorial(idx), "%s will be remembered." % d.get("name", "?")):
					Audio.sfx("bell_far", 0.0, -2.0), "btn_green")
			b.disabled = campaign.gold < c
			h.add_child(b)
		v.add_child(p)
