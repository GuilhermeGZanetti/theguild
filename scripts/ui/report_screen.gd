extends Control
## Post-quest screen: result and grade, rewards, bonus objectives and what
## happened to each member (XP, level ups, injuries, new traits, deaths).

var rep := {}
var campaign: Campaign


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	campaign = Game.campaign
	rep = Game.last_report
	if rep.is_empty() or campaign == null:
		Scenes.go("res://scenes/title.tscn")
		return
	var bg := ColorRect.new()
	bg.color = Color8(22, 16, 26)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()
	var victory: bool = rep["result"] == "victory"
	Audio.play_music("guild" if victory else "menu")


func _build() -> void:
	var vs := get_viewport_rect().size
	var root := UIKit.vbox(4)
	root.position = Vector2(12, 8)
	root.size = vs - Vector2(24, 16)
	add_child(root)
	var result: String = rep["result"]
	var mission: Dictionary = rep["mission"]
	var head := UIKit.hbox(10)
	root.add_child(head)
	var titles := {"victory": ["Victory", UITheme.GOLD], "retreat": ["Retreat", UITheme.TEXT], "failed": ["Mission Failed", UITheme.RED], "defeat": ["Defeat", UITheme.RED]}
	var t: Array = titles.get(result, ["Defeat", UITheme.RED])
	var tv := UIKit.vbox(0)
	tv.add_child(UIKit.title(t[0], 30, t[1]))
	tv.add_child(UIKit.label(mission.get("title", ""), 10, UITheme.TEXT_DIM, UITheme.pixel_font))
	head.add_child(tv)
	head.add_child(UIKit.spacer())
	# grade
	var gp := UIKit.panel("frame_gold", Vector4(8, 2, 8, 2))
	var gv := UIKit.vbox(0)
	gv.add_child(UIKit.label("Grade", 8, UITheme.TEXT_DIM, UITheme.pixel_font))
	var gl := UIKit.title(rep["grade"], 30, {"S": UITheme.GOLD, "A": UITheme.GREEN, "B": UITheme.TEXT, "C": UITheme.TEXT_DIM, "D": UITheme.RED}.get(rep["grade"], UITheme.TEXT))
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(gl)
	gp.add_child(gv)
	head.add_child(gp)
	gp.pivot_offset = Vector2(20, 20)
	gp.scale = Vector2(2.5, 2.5)
	gp.modulate.a = 0.0
	var tw := gp.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func(): Audio.sfx("crit" if rep["grade"] in ["S", "A"] else "hit", 0.0, -2.0))
	tw.parallel().tween_property(gp, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gp, "modulate:a", 1.0, 0.2)
	var body := UIKit.hbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_rewards())
	body.add_child(_squad())
	var foot := UIKit.hbox(6)
	foot.add_child(UIKit.label("Week %d · %s" % [campaign.week, campaign.guild_name], 9, UITheme.TEXT_DIM))
	foot.add_child(UIKit.spacer())
	foot.add_child(UIKit.button("Return to the Guild", _continue, "btn_green", 140))
	root.add_child(foot)


func _rewards() -> Control:
	var p := UIKit.panel("panel", Vector4(6, 5, 6, 5))
	p.custom_minimum_size.x = 220
	var v := UIKit.vbox(2)
	p.add_child(v)
	v.add_child(UIKit.header("Spoils", 11))
	var g := UITheme.GOLD.to_html(false)
	if int(rep["gold"]) != 0:
		v.add_child(_count_row("gold", int(rep["gold"]), "gold", UITheme.GOLD))
	v.add_child(_count_row("renown", int(rep["renown"]), "renown", UITheme.GREEN if int(rep["renown"]) >= 0 else UITheme.RED))
	if int(rep["materials"]) > 0:
		v.add_child(_count_row("materials", int(rep["materials"]), "materials", UITheme.TEXT))
	if int(rep["hush"]) != 0:
		v.add_child(UIKit.stat_row("hush", "Hush %+d" % int(rep["hush"]), UITheme.PURPLE))
	for it in rep["items"]:
		var h := UIKit.hbox(3)
		h.add_child(UIKit.tex_rect(MemberCard.item_icon(it)))
		h.add_child(MemberCard.item_line(it))
		v.add_child(h)
	if rep["recruit"] != "":
		v.add_child(UIKit.rich("[color=#%s]%s joins the guild.[/color]" % [UITheme.GREEN.to_html(false), rep["recruit"]], 206, 9))
	for f in rep["faction"]:
		v.add_child(UIKit.rich("[color=#%s]%s[/color]" % [UITheme.BLUE.to_html(false), f], 206, 9))
	for n in rep["lost_items"]:
		v.add_child(UIKit.rich("[color=#%s]%s's gear was left on the field.[/color]" % [UITheme.RED.to_html(false), n], 206, 9))
	if not rep["bonus"].is_empty():
		v.add_child(HSeparator.new())
		v.add_child(UIKit.header("Bonus objectives", 10))
		for b in rep["bonus"]:
			var done: bool = b.get("done", false)
			v.add_child(UIKit.rich("[color=#%s]%s %s[/color]" % [(UITheme.GREEN if done else UITheme.TEXT_DIM).to_html(false), "+" if done else "-", b.get("desc", "")], 206, 9))
	if rep["result"] == "victory":
		v.add_child(UIKit.rich("[color=#%s]Grade %s: rewards x%.2f[/color]" % [g, rep["grade"], Rules.grade_mult(rep["grade"])], 206, 8))
	return GuildScreen.scroll(p)


func _count_row(icon: String, amount: int, word: String, col: Color) -> Control:
	var h := UIKit.hbox(3)
	h.add_child(UIKit.tex_rect(UIKit.small_tex(icon)))
	var l := UIKit.label("", 11, col, UITheme.number_font)
	h.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(0.3)
	tw.tween_method(func(x: float): l.text = "%+d %s" % [roundi(x), word], 0.0, float(amount), 0.8)
	return h


func _squad() -> Control:
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.header("The Squad", 11))
	var delay := 0.4
	for id in Game.squad_ids:
		var m := campaign.member(int(id))
		if m:
			v.add_child(_member_row(m, delay))
		delay += 0.25
	for n in rep["deaths"]:
		var d := {}
		for dd in campaign.dead:
			if dd.get("name", "") == n:
				d = dd
		var p := UIKit.panel("panel_inset", Vector4(5, 3, 5, 3))
		var h := UIKit.hbox(5)
		p.add_child(h)
		h.add_child(MemberCard.portrait_dict(d, 24, 0.9))
		var iv := UIKit.vbox(0)
		iv.add_child(UIKit.label(n, 10, UITheme.RED, UITheme.pixel_font))
		iv.add_child(UIKit.rich("[color=#%s]%s. %s[/color]" % [UITheme.TEXT_DIM.to_html(false), d.get("death", {}).get("cause", "Fell"),
			"Carve their name in the Memorial, or the Hush will feed on it." if not d.get("memorial", false) else ""], 330, 8))
		h.add_child(iv)
		v.add_child(p)
	var sc := GuildScreen.scroll(v)
	return sc


func _member_row(m: Member, delay: float) -> Control:
	var p := UIKit.panel("panel_inset", Vector4(5, 3, 5, 3))
	var h := UIKit.hbox(5)
	p.add_child(h)
	h.add_child(MemberCard.portrait(m, 24))
	var iv := UIKit.vbox(1)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(iv)
	var top := UIKit.hbox(4)
	top.add_child(UIKit.label(m.name, 10, UITheme.TEXT, UITheme.pixel_font))
	top.add_child(UIKit.label("Lv %d %s" % [m.level, m.class_name_full()], 9, UITheme.TEXT_DIM))
	iv.add_child(top)
	var xp := int(rep["xp"].get(m.id, rep["xp"].get(str(m.id), 0)))
	var line := UIKit.hbox(4)
	line.add_child(UIKit.tex_rect(UIKit.small_tex("xp")))
	var bar := UIKit.bar(0, 1, UITheme.BLUE, 80, 5)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(bar)
	line.add_child(UIKit.label("+%d XP" % xp, 9, UITheme.BLUE))
	iv.add_child(line)
	# animate the bar to the member's current progress
	var fill: ColorRect = bar.get_child(1)
	var hl: ColorRect = bar.get_child(2)
	var target_w := 78.0 * clampf(float(m.xp) / maxf(m.xp_needed(), 1), 0, 1)
	fill.size.x = 0
	hl.size.x = 0
	var tw := bar.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(x: float):
		fill.size.x = x
		hl.size.x = x, 0.0, target_w, 0.6)
	var notes: Array = []
	var ups: Array = rep["levels"].get(m.id, rep["levels"].get(str(m.id), []))
	for u in ups:
		var gains: Array = []
		for k in u.get("gains", {}):
			gains.append("%s +%d" % [DB.STAT_NAMES.get(k, k), int(u["gains"][k])])
		notes.append("[color=#%s]Level %d![/color] %s" % [UITheme.GOLD.to_html(false), int(u["level"]), ", ".join(gains)])
	if not ups.is_empty():
		notes.append("[color=#%s]%s new skill%s to choose in the Roster.[/color]" % [UITheme.GREEN.to_html(false),
			"A" if ups.size() == 1 else str(ups.size()), "" if ups.size() == 1 else "s"])
	var inj: Dictionary = rep["injuries"].get(m.id, rep["injuries"].get(str(m.id), {}))
	if not inj.is_empty():
		var s := "[color=#%s]%s injury: out for %d week%s.[/color]" % [UITheme.RED.to_html(false), inj.get("kind", "light").capitalize(), int(inj["weeks"]), "" if int(inj["weeks"]) == 1 else "s"]
		if inj.get("cause", "") == "wounds":
			s = "[color=#%s]Took a beating (%d HP lost in all). Light injury: out for %d week%s.[/color]" % [UITheme.RED.to_html(false),
				int(inj.get("lost", 0)), int(inj["weeks"]), "" if int(inj["weeks"]) == 1 else "s"]
		if inj.get("permanent", "") != "":
			s += " [color=#%s]Permanent: %s.[/color]" % [UITheme.RED.to_html(false), DB.traits[inj["permanent"]]["name"]]
		notes.append(s)
	var tr: String = rep["traits"].get(m.id, rep["traits"].get(str(m.id), ""))
	if tr != "":
		notes.append("[color=#%s]New trait: %s[/color] (%s)" % [UITheme.PURPLE.to_html(false), DB.traits[tr]["name"], DB.traits[tr]["desc"]])
	if not notes.is_empty():
		iv.add_child(UIKit.rich("\n".join(notes), 330, 8))
	if not ups.is_empty():
		var tw2 := p.create_tween()
		tw2.tween_interval(delay + 0.6)
		tw2.tween_callback(func(): Audio.sfx("buff", 0.05, -4.0))
		tw2.tween_property(p, "modulate", Color(1.4, 1.3, 0.9), 0.12)
		tw2.tween_property(p, "modulate", Color(1, 1, 1), 0.3)
	return p


func _continue() -> void:
	var pages: Array = []
	var story: String = rep.get("story", "")
	if story != "":
		pages.append({"title": rep["mission"].get("title", ""), "text": story})
	if rep.has("act"):
		var a: Dictionary = DB.story["acts"][str(int(rep["act"]))]
		pages.append({"title": a["name"], "text": a["desc"], "big": true})
	var next := "res://scenes/guild.tscn"
	if campaign.game_over != "":
		next = "res://scenes/ending.tscn"
	if pages.is_empty():
		Scenes.go(next)
	else:
		Scenes.go("res://scenes/story.tscn", {"pages": pages, "next": next})
