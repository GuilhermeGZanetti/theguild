extends GuildScreen
## The guild ledger: story progress, totals and the chronicle of every week.


func screen_title() -> String:
	return "The Ledger"


func subtitle() -> String:
	return "Written names resist the Hush"


func build() -> void:
	var h := UIKit.hbox(8)
	body.add_child(h)
	var left := UIKit.vbox(3)
	left.custom_minimum_size.x = 200
	h.add_child(left)
	var act: Dictionary = DB.story["acts"][str(campaign.act)]
	left.add_child(UIKit.header(act["name"], 11))
	left.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.TEXT_DIM), act["desc"]], 196, 9))
	var hint := campaign.story_hint()
	if hint != "":
		left.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.GOLD), hint], 196, 9))
	var done: Array = []
	for sid in ["s1", "s2", "s3", "s4", "s5", "s6", "final"]:
		if campaign.story_done.get(sid, false):
			done.append("• " + DB.story["missions"][sid]["title"])
	if not done.is_empty():
		left.add_child(UIKit.rich("\n".join(done), 196, 9))
	left.add_child(HSeparator.new())
	left.add_child(UIKit.header("Totals", 10))
	var s: Dictionary = campaign.stats
	left.add_child(UIKit.rich("Missions: %d (%d won)\nEnemies slain: %d\nMembers lost: %d\nRecruited: %d\nRenown: %d · %s\nDifficulty: %s%s" % [
		int(s["missions"]), int(s["victories"]), int(s["kills"]), int(s["deaths"]), int(s["recruited"]), campaign.renown,
		Rules.rank_name(campaign.rank()), ["Forgiving", "Standard", "Merciless"][campaign.difficulty], " · Ironman" if campaign.ironman else ""], 196, 9))
	# chronicle
	var right := UIKit.vbox(1)
	var page := GuildScreen.inset(right, "parchment")
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entries: Array = campaign.chronicle.duplicate()
	entries.reverse()
	var last_week := -1
	for e in entries:
		var w := int(e.get("week", 1))
		if w != last_week:
			last_week = w
			right.add_child(UIKit.label("Week %d" % w, 10, Color8(120, 60, 40), UITheme.pixel_font))
		right.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.INK), e.get("text", "")], 360, 9))
	var sc := scroll(page)
	h.add_child(sc)
