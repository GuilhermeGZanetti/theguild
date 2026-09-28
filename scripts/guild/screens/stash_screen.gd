extends GuildScreen
## Forge and stash: equip, upgrade and sell items; buy from the weekly market.

var sel_kind := ""   # "stash" | "worn"
var sel_index := -1
var sel_member: Member = null
var sel_slot := ""


func screen_title() -> String:
	return "Forge & Stash"


func subtitle() -> String:
	var lvl := int(campaign.facilities["forge"])
	return "Forge %s · materials %d" % ["not built" if lvl == 0 else "level %d" % lvl, campaign.materials]


func build() -> void:
	var h := UIKit.hbox(6)
	body.add_child(h)
	# left: stash + worn gear
	var left := UIKit.vbox(2)
	left.add_child(UIKit.header("Stash (%d)" % campaign.inventory.size(), 10))
	if campaign.inventory.is_empty():
		left.add_child(UIKit.label("Empty. Loot comes from missions.", 9, UITheme.TEXT_DIM))
	for i in campaign.inventory.size():
		left.add_child(_item_button(campaign.inventory[i], "stash", i, null, ""))
	left.add_child(UIKit.header("Worn by members", 10))
	for m in campaign.roster:
		for slot in ["weapon", "armor"]:
			var it: Dictionary = m.equipment.get(slot, {})
			if not it.is_empty():
				left.add_child(_item_button(it, "worn", -1, m, slot))
	var sc := scroll(left)
	sc.custom_minimum_size.x = 210
	sc.size_flags_horizontal = Control.SIZE_FILL
	h.add_child(sc)
	# middle: selection detail
	var mid := UIKit.vbox(3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	_detail(mid)
	# right: market
	var right := UIKit.vbox(2)
	right.custom_minimum_size.x = 170
	right.add_child(UIKit.header("Market", 10))
	right.add_child(UIKit.label("Stock changes every week.", 8, UITheme.TEXT_DIM))
	for i in campaign.shop.size():
		right.add_child(_shop_entry(i))
	if campaign.shop.is_empty():
		right.add_child(UIKit.label("Sold out.", 9, UITheme.TEXT_DIM))
	h.add_child(scroll(right))


func _item_button(it: Dictionary, kind: String, idx: int, m: Member, slot: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(204, 20)
	b.button_pressed = (kind == "stash" and sel_kind == "stash" and sel_index == idx) or (kind == "worn" and sel_kind == "worn" and sel_member == m and sel_slot == slot)
	UIKit.list_row(b, b.button_pressed)
	var hb := UIKit.hbox(3)
	hb.position = Vector2(3, 2)
	var ic := UIKit.tex_rect(MemberCard.item_icon(it))
	ic.custom_minimum_size = Vector2(16, 16)
	hb.add_child(ic)
	var l := UIKit.label(Items.name_of(it), 9, MemberCard.item_color(it))
	l.custom_minimum_size.x = 104
	l.clip_text = true
	hb.add_child(l)
	if m:
		var who := UIKit.label(m.name.split(" ")[0], 8, UITheme.TEXT_DIM)
		who.custom_minimum_size.x = 70
		who.clip_text = true
		hb.add_child(who)
	for c in hb.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	b.tooltip_text = Items.desc_of(it)
	b.pressed.connect(func():
		sel_kind = kind
		sel_index = idx
		sel_member = m
		sel_slot = slot
		Audio.sfx("cloth", 0.1, -8.0)
		rebuild())
	return b


func _selected_item() -> Dictionary:
	if sel_kind == "stash" and sel_index >= 0 and sel_index < campaign.inventory.size():
		return campaign.inventory[sel_index]
	if sel_kind == "worn" and sel_member and sel_member in campaign.roster:
		return sel_member.equipment.get(sel_slot, {})
	return {}


func _detail(v: VBoxContainer) -> void:
	var it := _selected_item()
	if it.is_empty():
		v.add_child(UIKit.rich("Select an item to equip, upgrade or sell.\n\nThe [color=#%s]Forge[/color] improves weapons and armor: Worn → Steel → Masterwork → Relic. Each step costs gold and materials." % hex(UITheme.GOLD), 200, 9))
		return
	var top := UIKit.hbox(4)
	var ic := UIKit.tex_rect(MemberCard.item_icon(it), 2.0)
	top.add_child(ic)
	var tv := UIKit.vbox(0)
	tv.add_child(UIKit.label(Items.name_of(it), 11, MemberCard.item_color(it), UITheme.pixel_font))
	var kind: String = it.get("kind", "")
	var sub := kind.capitalize()
	if kind in ["weapon", "armor"]:
		sub = "%s %s" % [DB.items["tiers"][int(it["tier"]) - 1], DB.items[kind + "s"][it["base"]]["name"]]
	tv.add_child(UIKit.label(sub, 9, UITheme.TEXT_DIM))
	top.add_child(tv)
	v.add_child(top)
	v.add_child(UIKit.rich(Items.desc_of(it), 200, 9))
	var users: Array = []
	for c in DB.base_classes() + ["tidecaller", "lanternbearer", "graftwarden", "sandreaver"]:
		if Items.fits(it, c):
			users.append(DB.classes[c]["name"])
	v.add_child(UIKit.rich("[color=#%s]Usable by: %s[/color]" % [hex(UITheme.TEXT_DIM), ", ".join(users)], 200, 8))
	if Items.can_upgrade(it):
		var c := campaign.forge_cost(it)
		var err := campaign.can_forge(it)
		var nxt := it.duplicate()
		nxt["tier"] = int(it["tier"]) + 1
		v.add_child(UIKit.rich("[color=#%s]Next: %s — %s[/color]" % [hex(UITheme.GREEN), Items.name_of(nxt), Items.desc_of(nxt)], 200, 8))
		var owner := sel_member if sel_kind == "worn" else null
		var b := UIKit.button("Upgrade · %d gold, %d materials" % [c[0], c[1]], func():
			if act(campaign.forge_upgrade(it, owner), "Forged: %s" % Items.name_of(it)):
				Audio.sfx("armor_break", 0.1, -3.0), "btn_green")
		b.disabled = err != ""
		b.tooltip_text = err
		v.add_child(b)
		if err != "":
			v.add_child(UIKit.label(err, 8, UITheme.RED))
	if sel_kind == "stash":
		v.add_child(HSeparator.new())
		v.add_child(UIKit.label("Equip on:", 9, UITheme.TEXT_DIM))
		var flow := HFlowContainer.new()
		flow.custom_minimum_size.x = 200
		for m in campaign.roster:
			if Items.fits(it, m.cls):
				var mm: Member = m
				var b := UIKit.button(m.name.split(" ")[0], func():
					var name := Items.name_of(it)
					sel_index = -1
					if act(campaign.equip(mm, it), "%s equips %s." % [mm.name.split(" ")[0], name]):
						Audio.sfx("cloth", 0.1, -4.0))
				b.tooltip_text = "Now: %s" % Items.name_of(m.equipment.get(Items.slot(it), {}))
				flow.add_child(b)
		v.add_child(flow)
		v.add_child(UIKit.button("Sell for %d gold" % Items.sell_price(it), func():
			var price := Items.sell_price(it)
			campaign.sell(it)
			sel_index = -1
			act("", "Sold for %d gold." % price), "btn_red"))


func _shop_entry(i: int) -> Control:
	var e: Dictionary = campaign.shop[i]
	var it: Dictionary = e["item"]
	var p := UIKit.panel("panel_inset", Vector4(4, 3, 4, 3))
	var v := UIKit.vbox(1)
	p.add_child(v)
	var top := UIKit.hbox(3)
	top.add_child(UIKit.tex_rect(MemberCard.item_icon(it)))
	var nl := UIKit.label(Items.name_of(it), 9, MemberCard.item_color(it))
	nl.custom_minimum_size.x = 120
	nl.clip_text = true
	top.add_child(nl)
	v.add_child(top)
	if e.has("faction"):
		v.add_child(UIKit.label("Offered by the %s" % DB.factions[e["faction"]]["short"], 8, UITheme.PURPLE))
	v.add_child(UIKit.rich("[color=#%s]%s[/color]" % [hex(UITheme.TEXT_DIM), Items.desc_of(it)], 158, 8))
	var price := campaign.price(int(e["price"]))
	var b := UIKit.button("Buy · %d gold" % price, func(): act(campaign.buy_shop(i), "Bought %s." % Items.name_of(it)), "btn_green")
	b.disabled = campaign.gold < price
	v.add_child(b)
	return p
