class_name MissionLore
extends RefCounted
## The client's letter pinned to the quest board: who asks, why, and what
## they need done, in their own voice. Built from the mission's region,
## faction, category and objective, seeded by the mission so a letter reads
## the same every time it is opened. Story missions carry hand-written ones.

const CLIENTS := {
	"carrow": ["Aldous Fenn, Bell-warden of Carrow", "Widow Harrow of the Tanners' Row", "Reeve Tomas Quill, for the town of Carrow",
		"Brother Osk, Almshouse of the Cracked Bell", "Nell Barrowby, miller on the Mill Road"],
	"saltborn": ["Captain Maro Saltwhistle, Saltborn Compact", "Pilot Ysse of Gullrest", "Netmistress Oona Brack, Saltborn Compact",
		"Harbormaster Ket of the Brineworks"],
	"lantern": ["Archivist Pell Duskwing, Lantern Conclave", "Wickkeeper Sorrel of Mothlight Terrace", "Lamplighter Ivo Mothrane, Lantern Conclave",
		"Canal-warden Fenna of the Stilts"],
	"rootwardens": ["Elder Bramm of the Third Ring, Rootwardens", "Seedkeeper Alder of the Grave Orchard", "Warden Hazel Ashbough, Rootwardens",
		"Mourner Quince of Ashleaf Shrine"],
	"glass": ["Factor Khesset of the Glass Caravans", "Navigator Ammu of the glass-hull Sunstrider", "Scarab-broker Tethi, Glass Caravans",
		"Hullwright Sekh of Toadstone Well"],
	"unremembered": ["A voice without a name"],
}

const SIGNOFFS := {
	"carrow": ["May the Bell ring again,", "Yours, in haste,", "With what hope we have left,"],
	"saltborn": ["May the tide remember you,", "Salt and memory,", "Yours, from the pier,"],
	"lantern": ["By lantern-light,", "Keep a light burning,", "Yours, from the high archive,"],
	"rootwardens": ["Root and branch,", "Until the leaves return,", "Slowly, as we do all things,"],
	"glass": ["Fair winds on the glass,", "May the ledger favour you,", "Yours in trade,"],
	"unremembered": ["If anyone remembers,"],
}

const OPENERS := {
	"carrow": ["Carrow is not what it was, and the Bell has been silent too long.",
		"You know how quickly news travels between the market stalls. This news is bad.",
		"The watch will not help, and the old guilds are gone, so I am writing to you."],
	"coast": ["The tide at {place} has been wrong all week, and my jellyfish goes dark whenever I try to remember the old soundings.",
		"The bells under the water have started ringing again. On this coast that is never good news.",
		"The nets come up empty and the gulls have gone quiet along the shore."],
	"stilts": ["The lanterns along the canals are dimming, and every one that goes out is a memory lost.",
		"Fog has sat on the stilts for nine days. We can barely see from one bridge to the next.",
		"The archive keeps better records than any of us, and even the archive is afraid."],
	"ember": ["The leaves of the Ember Wood are falling faster than they should.",
		"My roots feel it before my eyes do: something is wrong in the wood.",
		"The shrines have gone cold, and the masks in the trees have started to watch us."],
	"dunes": ["The dunes have shifted and uncovered things that should have stayed buried.",
		"Trade across the sands has stalled, and stalled trade is a slow death for a caravan.",
		"The wind off the Glass Wastes has carried nothing but bad news this season."],
	"unremembered": ["I am writing this on a page that is already forgetting me."],
}

## Threat lines per objective. {place}, {target}, {foes}, {vip}, {object},
## {turns} and {n} are filled in from the mission.
const THREATS := {
	"hunt": ["{target_cap} has been prowling around {place}. Three of our people went hunting there and only one came back.",
		"There is a price on {target}, and we have been paying it in blood. The lair is at {place}, where the old trail ends.",
		"{target_cap} and a pack of {foes} have made {place} their hunting ground."],
	"clear": ["A band of {foes} has taken {place} for its own. Nobody goes near it after dark, and now not in daylight either.",
		"{foes_cap} have dug in at {place}. They patrol it like soldiers and waylay anyone foolish enough to pass.",
		"We lost {place} to {foes} a week ago, and they grow bolder by the day."],
	"escort": ["{vip_cap} must cross {place}, and the road is crawling with {foes}.",
		"{vip_cap} carries something we cannot afford to lose, and {foes} have been watching the road through {place}."],
	"rescue": ["{foes_cap} took one of ours near {place}. They hold the poor soul in a camp far past the old trail.",
		"A friend of mine was dragged off at {place} by {foes}. There has been no ransom note, and that frightens me most."],
	"retrieve": ["Our supplies went down at {place}, and {foes} are picking over the wreck. There are {n} caches worth saving.",
		"Somewhere past {place}, at the end of the old trail, lie {n} caches that were ours before the {foes} came."],
	"defense": ["{foes_cap} are gathering around {place}, and they have their eyes on our {object}.",
		"Everything we have left depends on the {object} at {place}, and {foes} mean to smash it."],
	"survive": ["Something is coming to {place} tonight. We have found the tracks of {foes} all around it.",
		"Our scouts at {place} are cut off, and {foes} keep coming out of the dark."],
}

const REQUESTS := {
	"hunt": ["Follow the trail to {target} and put an end to this.", "Find {target}, finish the job, and let us sleep again."],
	"clear": ["Drive every last one of them out.", "Clear them out, all of them, so we can take it back."],
	"escort": ["Walk beside {vip} to the far side and keep them breathing.", "See {vip} safely through. Nothing else matters."],
	"rescue": ["Cut the ropes and bring them home.", "Bring them back to us, please, while there is still someone to bring back."],
	"retrieve": ["Recover the caches before the scavengers finish, then get out.", "Bring back what you can carry. What you cannot, burn."],
	"defense": ["Hold them off for {turns} rounds, until our people can come.", "Keep it standing for {turns} rounds. That is all I ask."],
	"survive": ["Hold out for {turns} rounds, until the light comes back.", "Stay alive for {turns} rounds. The rest will take care of itself."],
}

## Rival contracts, by board title: each side tells its own story.
const RIVALRY := {
	"Escort the Salt Convoy": "Our salt convoy must cross the dunes road, and the Caravans would be happy to see it vanish in the sand.",
	"Raid the Salt Convoy": "A Saltborn salt convoy is crossing our dunes without paying a single toll. We would pay well to see it never arrive.",
	"Recover the Burnt Archive": "Fire took the lower archive, and our scorched records still lie in the ashes, waiting to be saved.",
	"Let the Archive Burn": "The fire-line by the old archive must hold. Let the Conclave's papers burn; the wood matters more than their records.",
}

const BREACH := ["The Hush has torn through at {place}. The air there has turned grey, and people forget their own names on the way home.",
	"There is a hole in the world at {place}. Hollows walk out of it, and the ground around it has forgotten what colour it was."]

const FLAVOR := {
	"contract": ["The purse is {gold} gold, fair pay for dangerous work.", "I can pay {gold} gold, and I am good for it."],
	"recruit": ["They are young and stubborn, and they talk of nothing but joining a guild. Bring them back and they are yours.",
		"If you save them, I think they will want to stay with you. They have nowhere else to go."],
	"salvage": ["Keep whatever gear you drag out of there. I only want the road clear again.",
		"Whatever you find is yours to keep. We only need it out of the wrong hands."],
	"training": ["It should be a gentle enough fight to blood your newer hands.", "Nothing your people cannot handle, I think. A good lesson for the green ones."],
	"breach": ["If it is left alone, the grey will spread.", "Every day it stays open, more of us forget."],
	"crisis": ["We cannot hold on much longer alone.", "The {faction} will not forget who answered when we called."],
	"rivalry": ["Whatever the {rival} offer you, we will remember this longer.", "Do not listen to the {rival}. They only want what is ours."],
	"chain": ["You have earned our trust. We would not give this task to anyone else.", "Few outsiders have been told what I am telling you now."],
}


## Returns {"greeting", "body", "signoff", "client"}.
static func letter(m: Dictionary, guild_name := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(m.get("seed", 0)) * 31 + int(m.get("id", 0)))
	var region: String = m.get("region", "carrow")
	var guild := guild_name if guild_name != "" else "the guild"
	if guild.begins_with("The "):
		guild = "the " + guild.substr(4)
	var greeting := _pick(rng, ["To the Guildmaster of %s," % guild, "Guildmaster,", "To whoever reads the board at %s," % guild])
	var sid: String = m.get("story_id", "")
	if sid != "":
		var s: Dictionary = DB.story["missions"].get(sid, {})
		if s.has("letter"):
			return {"greeting": "To the Guildmaster of %s," % guild, "body": s["letter"], "signoff": "", "client": s.get("client", "")}
	var who := _client_key(m)
	var vars := _vars(m, rng)
	var parts: Array = []
	parts.append(_pick(rng, OPENERS.get(region, OPENERS["carrow"])))
	var cat: String = m.get("category", "contract")
	var obj: String = m.get("objective", "clear")
	if cat == "breach":
		parts.append(_pick(rng, BREACH))
	elif cat == "rivalry" and RIVALRY.has(m.get("title", "")):
		parts.append(RIVALRY[m["title"]])
	else:
		parts.append(_pick(rng, THREATS.get(obj, THREATS["clear"])))
	parts.append(_pick(rng, REQUESTS.get(obj, REQUESTS["clear"])))
	if FLAVOR.has(cat):
		parts.append(_pick(rng, FLAVOR[cat]))
	var body := " ".join(parts)
	for k in vars:
		body = body.replace("{%s}" % k, str(vars[k]))
	return {"greeting": greeting, "body": body, "signoff": _pick(rng, SIGNOFFS.get(who, SIGNOFFS["carrow"])),
		"client": _pick(rng, CLIENTS.get(who, CLIENTS["carrow"]))}


## Who writes: the faction asking, or the region's own folk.
static func _client_key(m: Dictionary) -> String:
	var f: String = m.get("faction", "")
	if f != "" and CLIENTS.has(f):
		return f
	var region: String = m.get("region", "carrow")
	var rf: String = DB.regions.get(region, {}).get("faction", "")
	if rf != "" and CLIENTS.has(rf):
		return rf
	return region if CLIENTS.has(region) else "carrow"


static func _vars(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var region: String = m.get("region", "carrow")
	var pool: Dictionary = m.get("enemies", DB.regions.get(region, {}).get("enemies", {}))
	var foes := "brigands"
	if m.get("category", "") == "breach":
		foes = "hollows and quietlings"
	elif not pool.is_empty():
		var ids: Array = pool.keys()
		ids.sort()
		foes = plural(DB.enemies.get(ids[rng.randi() % ids.size()], {}).get("name", "brigand"))
	var target := "their leader"
	var eid: String = m.get("boss", m.get("elite", ""))
	if eid != "":
		target = the_name(DB.enemies.get(eid, {}).get("name", target))
	var vip: String = DB.missions["vips"].get(region, "the traveller")
	var fac: String = m.get("faction", "")
	var rival: String = m.get("rival", "")
	return {"place": m.get("place", DB.regions.get(region, {}).get("name", "the road")), "target": target, "target_cap": _cap(target),
		"foes": foes, "foes_cap": _cap(foes), "vip": vip, "vip_cap": _cap(vip),
		"object": DB.missions["objects"].get(region, "cart"), "turns": int(m.get("turns", 6)), "n": int(m.get("caches", 3)),
		"gold": int(m.get("reward", {}).get("gold", 0)),
		"faction": DB.factions[fac]["short"] if DB.factions.has(fac) else "town",
		"rival": DB.factions[rival]["short"] if DB.factions.has(rival) else "others"}


## "Stinger Queen" -> "the Stinger Queen", "The Rot Stag" -> "the Rot Stag",
## "Mott the Bell-Thief" stays a name.
static func the_name(n: String) -> String:
	if n.begins_with("The "):
		return "the " + n.substr(4)
	if " the " in n:
		return n
	return "the " + n


static func plural(n: String) -> String:
	var s := n.to_lower()
	if s.ends_with("deer"):
		return s
	if s.ends_with("thief"):
		return s.substr(0, s.length() - 5) + "thieves"
	return s + "s"


static func _cap(s: String) -> String:
	return s[0].to_upper() + s.substr(1) if s != "" else s


static func _pick(rng: RandomNumberGenerator, a: Array) -> String:
	return a[rng.randi() % a.size()]
