# A Guilda — Game Design Document

Sep 25, 2026 · @Guilherme Goes

## I. Executive Summary

### Game Overview

A Guilda is a turn-based tactical strategy game with guild management, set in a medieval fantasy world. The player rebuilds an abandoned tavern into an adventurers' guild, recruits members, sends them on quests and fights tactical battles on a 3D grid. Main references: XCOM (tactical combat, permanent loss) and Battle Brothers (roster management, flawed recruits, economic pressure).

### Core Pillars

1. **Every member matters.** Members are unique, grow over time and can be injured or die permanently. Losing a veteran must hurt.
2. **Calculated risk.** Every combat action shows its probability. The player wins by stacking odds, not by guaranteed outcomes.
3. **Two layers, one loop.** Decisions in the guild (who to train, heal, equip) decide battles; battle results (gold, injuries, deaths) decide the guild.
4. **Handcrafted look.** 3D scenes rendered with a pixel art look, readable and warm.

### Game Objectives

* Short term: complete quests, bring members home alive.
* Mid term: raise guild renown, unlock better recruits, facilities and quest tiers.
* Long term: become the most renowned guild in the realm and face the campaign's final threat (see Story).
* Failure: the Hush reaches 100, two factions collapse, the roster is empty with no gold, or wages go unpaid for 3 weeks (see Loss Conditions).

### Target Audience

* PC players aged 18–40 who enjoy tactical and management games (XCOM, Battle Brothers, Darkest Dungeon, Wartales).
* Players who accept high difficulty and permanent loss.
* Session length: 30–90 minutes; campaign length: 20–40 hours.

## II. Game Mechanics — Combat

### Main Gameplay

Combat is turn-based on a 3D tile grid with elevation and cover. The player brings 4–6 members per quest. Every attack, skill and status effect shows its success chance before confirming. A quest ends when all objectives are complete, all members are down, or the squad retreats through an extraction zone.

### Character Attributes

Characters have three attribute groups that define combat performance: Stats, Traits and Skills. Each member also has a **class** and a **level**.

Base classes (proposal):

|Class|Role|Stat focus|
|-|-|-|
|Warrior|Frontline, holds ZOC, protects allies|HP, Defense|
|Rogue|Flanker, burst damage, debuffs|Dodge, Crit, Movement|
|Ranger|Ranged damage, overwatch|Accuracy, Range|
|Mystic|Area spells that always land and hit allies too, or healing and support, by specialization|Attack, Range|

### Stats

Stats are numbers that directly affect combat. All stats except Cooldown Reduction range from 0 to 100; higher is better.

|Stat|Effect|
|-|-|
|HP|Damage the character can take before going down.|
|Defense|A bar with max and current value. Its current value is subtracted from each hit's raw damage. Can be reduced by enemy skills. Shown in combat next to HP.|
|Dodge|Reduces the enemy's chance to hit.|
|Speed|How soon the character acts again after a turn. Higher speed = earlier and more turns.|
|Movement|Tiles the character can move per turn.|
|Crit Chance|Chance that an attack or a defense is critical. Critical attack = one and a half times the damage. Critical defense = half damage taken.|
|Attack|Damage for all attack types: physical, ranged and magical.|
|Accuracy|Chance to hit with any attack type.|
|Range|How far the character can target attacks or skills. Also applies to melee skills.|
|Resolve (proposal)|Resistance to debuffs and fear. Drops when allies die nearby.|

Cooldown Reduction (0–3 turns) moves to Traits and equipment only, as noted in the original draft. It is too strong as a base stat.

### Traits

Traits are fixed modifiers rolled at recruitment. Each member has 1–3 traits, mixing positive and negative. They make members unique and give the player reasons to keep a flawed recruit.

|Trait|Effect|
|-|-|
|Quick Hands|−1 cooldown on all active skills|
|Iron Skin|+10% max Defense|
|Eagle Eye|+10 Accuracy on ranged attacks|
|Brave|Immune to fear|
|Coward|−15 Resolve; may flee when an ally dies nearby|
|Clumsy|−5 Dodge, −5 Accuracy|
|Slow Healer|Injuries take 50% longer to heal|
|Lucky|Once per quest, survives a lethal hit with 1 HP|

Members can gain new traits from events: surviving a near-death hit, killing a boss, or suffering a permanent injury.

### Character Skills

* Each class has a skill tree with 2 branches of 6 skills, one per level from 2 to 7 (e.g. Mystic: Evocation or Support).
* Members start with 1 active skill and gain a skill point per level.
* Skills can also be learned in the guild with gold, with level requirements (see Guild Resources).
* Active skills have cooldowns in turns. Passive skills are always on.
* A member equips up to 4 active skills per quest.

### Combat System

**Turn order.** A timeline shows upcoming turns. After acting, a character's next turn is delayed by a value inversely proportional to Speed. A fast Rogue may act twice before a slow Warrior.

```latex
\\text{delay} = \\frac{1000}{\\text{Speed} + 50}
```

**Actions per turn.** One Move and one Action, in any order. Alternatives: Defend (+20 Dodge and +1 crit defense chance until next turn), Overwatch (attack the first enemy that moves in range), or Wait (act later in the timeline). Running moves up to twice the Movement but spends the Action; a member can walk first and then run on, as far as one run from the start of the turn would have reached. Half cover (crates, barrels, low walls) can be vaulted onto a free tile beyond, at the cost of both tiles.

**Hit chance.** Every attack shows its final chance, clamped between 5% and 95%, so nothing is ever certain.

```latex
\\text{Hit} = \\text{Accuracy} - \\text{Dodge}\_{target} + \\text{Cover} + \\text{Elevation} + \\text{Flank}
```

|Modifier|Value|
|-|-|
|Half cover|−20 hit|
|Full cover|−40 hit|
|Attacker on higher ground|+10 hit; +1 Range (optimal and max) per level above the target, for every ranged skill except charges and teleports|
|Flanking (target has no cover from attacker)|+15 hit, +10 Crit|
|Each tile beyond optimal range|−10 hit|

**Damage.** Raw damage = Attack × skill multiplier, with ±10% variance. The target's current Defense is subtracted from it. Each hit also lowers the target's current Defense by a small amount (proposal: 10% of raw damage), so sustained attacks break armor even without dedicated skills. Armor-break skills reduce Defense directly.

**Status effects.** Chance to apply depends on the skill's base chance, the level difference and the target's Resolve:

```latex
\\text{Chance} = \\text{Base} + 5 \\times (\\text{Level}\_{att} - \\text{Level}\_{target}) - \\frac{\\text{Resolve}\_{target}}{4}
```

|Effect|Result|
|-|-|
|Poison|Damage over time, ignores Defense|
|Bleed|Damage over time, stacks|
|Paralysis|Skips next turn|
|Stun|Loses Action but can still move|
|Armor Break|Current Defense reduced|
|Fear|Cannot attack; moves away from the source|
|Burn|Damage over time, spreads to adjacent flammable tiles|

**Zone of Control (ZOC).** Melee characters control the tiles directly around them. An enemy inside a ZOC tile can only move 1 tile if it moves to another tile in the same ZOC. Leaving a ZOC triggers an attack of opportunity (a normal attack).

**Durability.** Survival depends on HP, Defense and Dodge. Dodge is compared to the attacker's Accuracy. Defense makes heavily armored characters hard to damage until it is broken.

### Injuries and Death

This is the core of the XCOM-like tension.

* At 0 HP a member is **Downed**, not dead. They bleed out in 3 turns unless stabilized by an ally (Action, adjacent) or a healing skill.
* Hits on a Downed member, or overkill damage above 50% of max HP, kill instantly.
* Members who were Downed receive an injury after the quest (serious 40% / 55% / 70% of the time by difficulty, light otherwise).
* Members who lost half their max HP or more over the battle, even if healed back up, may get a light injury: 20% at half, 50% at a full bar, up to 80%.

|Injury|Recovery|Effect|
|-|-|-|
|Light|1 week|Cannot go on quests|
|Serious|2–5 weeks|Cannot go on quests|
|Permanent (10% chance on serious)|Never|Stat penalty or negative trait, e.g. lost eye (−15 Accuracy)|

* Dead members are gone. Their equipment is lost unless an ally carries the body to extraction.
* The Nursery facility reduces recovery time.
* Ironman mode: single autosave, no reloads.

### Retreat

Every quest map has an extraction zone. The squad can retreat at any time; the quest fails, but members who reach the zone survive. Downed members left behind are lost.

### Reward System

Quest results give:

* **Gold:** base reward plus bonus objectives.
* **XP:** split among survivors; bonus for kills and for stabilizing allies.
* **Loot:** equipment and materials from enemies and chests.
* **Renown:** raises guild rank; lost on failed quests and member deaths.

A grade (S to D) based on objectives, turns and casualties multiplies gold and renown.

## III. Game Mechanics — Guild Management

### Core Loop

Time passes in weeks. Each week: recruit, manage members (heal, train, equip), upgrade facilities, pick quests, play quests, collect rewards. Weekly wages create constant economic pressure.

### Guild Creation

* The player founds the guild in an old tavern and names it. The guild icon is fixed.
* Starting roster: four members, one per base class. One of them is Skilled; the rest are Normal or Mediocre.
* The player can also recruit one or two random members at the start.

### Member Management

Each member has a class, level, stats, growth rates, traits, quality tier, equipment, injuries and a weekly wage. The roster screen shows all of this plus quest history (quests, kills, near deaths).

**Quality tier** sets starting stats, stat gain per level and wage:

|Tier|Stat budget|Gain per level|Rarity|
|-|-|-|-|
|Mediocre|Low|Low|Common|
|Normal|Medium|Medium|Common|
|Skilled|High|High|Uncommon|
|Genius|Very high|Very high|Rare|

**Growth rates and specialties.** Each stat has a potential (1–3 stars) defined by class plus a random factor. Higher potential = larger gains on level up. Example: a Warrior with 3-star Defense grows Defense faster than other stats.

Tier and potential are partially hidden at recruitment. The Recruiter facility reveals more.

### Member Progression

* XP comes from quests. Level cap: 20 (proposal).
* On level up: stats grow by tier and potential, plus 1 skill point.
* At level 7 (the cap), members pick a subclass (e.g. Warrior → Knight or Berserker).
* Veterans demand higher wages as they level.

### Member Recruitment

* Each week a new pool of candidates appears at the tavern.
* Pool size and quality depend on guild renown and the Recruiter level.
* Each candidate shows class, visible traits, estimated tier and hiring cost.
* Rare events bring unique named recruits with fixed traits.

### Guild Resources

|Resource|Source|Use|
|-|-|-|
|Gold|Quests, selling loot|Wages, recruits, skills, equipment, facilities|
|Renown|Quest success, grade|Unlocks recruit quality, quest tiers, facility levels|
|Materials|Loot|Crafting and equipment upgrades|

Gold is spent on:

* Recruiting new members.
* Learning new skills (level requirements apply).
* Improving equipment.
* Weekly wages. Unpaid members lose morale and may leave.
* Upgrading facilities.

### Facilities

Each facility has 3 levels.

|Facility|Effect|
|-|-|
|Recruiter|More and better candidates; reveals hidden tier and potential|
|Nursery|Faster injury recovery; at level 3, can treat permanent injuries|
|Training Grounds|Passive XP for members not on quests|
|Forge|Equipment upgrades and crafting|
|Library|New skills to learn; cheaper skill costs|
|Barracks|Larger roster cap|
|Memorial|Records dead members' names so they do not feed the Hush; small Resolve bonus for the roster|

### Mission Choice and Consequences

Each week the board offers more missions than the guild can take. Taking one closes others, and every ignored strategic mission has a cost. Resource missions make the guild strong; strategic missions keep the world alive. The player can never do both fully.

**Weekly board**

* 4–6 missions per week, each tied to a region and usually to a faction.
* Missions last 1–4 days, and the guild has 7 days a week however many members it has: two to four missions, three on average. A bigger roster does not take more missions; it covers for the injured.
* Some missions are **conflicting pairs**: escort a Saltborn convoy or raid it for the Glass Caravans. Taking one cancels the other.
* Unchosen missions expire at the end of the week and trigger their "if ignored" effect.
* Each mission shows region, faction, difficulty (1–7 skulls), duration, reward and its consequence if ignored.
* **Skulls are member levels.** A skull-N quest is a hard fight for four level-N members: more enemies, and enemies whose blows, hide and pace keep step with a level-N member and that level's gear. The board follows the calendar, not the guild's fortunes: most quests match the level a member on two quests a week has reached by then (level 4 around week 5, level 7 around week 16), about a third are one or two skulls easier and one in five is a skull harder.

**Mission categories**

|Category|Mission|Reward|If ignored|
|-|-|-|-|
|Resource|Contract|Gold|Nothing|
|Resource|Recruit|A promising recruit (Skilled or Genius)|Nothing|
|Resource|Salvage|Equipment and materials|Nothing|
|Resource|Training|Bonus XP|Nothing|
|Strategic|Hush Breach|Lowers the Hush|Hush +3 to +8|
|Strategic|Faction Crisis|Faction Power +1, Reputation +1|Faction Power −1|
|Strategic|Story|Advances the act, unlocks regions|Story event with a negative outcome|
|Faction chain|Special mission|Unique class, equipment, ending influence|Chain delayed; may fail after 3 weeks|

Mission objectives (Hunt, Escort, Rescue, Clear, Retrieve, Defense, Survive N turns) apply to any category.

### Factions

Four factions compete for the realm (lore in Story and Game World). Each has two values:

|Value|Range|Meaning|Affects|
|-|-|-|-|
|Reputation|−3 to +3|How the faction sees the guild|Access to missions, recruits, shop, special chain|
|Power|0 to 10|How strong the faction is in the world|Number of its missions on the board, region stability|

Helping a faction often costs its rival Power:

* **Saltborn Compact vs Glass Caravans:** control of trade routes.
* **Lantern Conclave vs Rootwardens:** remember everything vs let things fade.

|Reputation|Unlocks|
|-|-|
|Hostile (−2 to −3)|Faction ambushes guild squads; its missions are harder|
|Neutral (0)|Basic contracts|
|Friendly (+1)|Faction recruits appear in the tavern|
|Trusted (+2)|Faction shop with unique equipment; special chain part 1|
|Allied (+3)|Unique class; chain finale; faction sends reinforcements to the final battle|

|Faction|Unique class|Unique equipment|
|-|-|-|
|Saltborn Compact|Tidecaller: pulls and pushes units, drowns tiles|Coral armor: regenerates 5 Defense per turn|
|Lantern Conclave|Lanternbearer: reveals hidden units, cleanses Hush effects|Memory lantern: allies in 2 tiles are immune to fear|
|Rootwardens|Graftwarden: roots enemies, extends ZOC to 2 tiles|Barkskin: +2 max Defense per quest survived|
|Glass Caravans|Sandreaver: burrows and resurfaces anywhere in range|Glass blades: +20 Crit, shatter after 5 crits|

**Collapse.** At Power 0 a faction collapses. Its region is swallowed by the Hush, its missions disappear, and the Hush rises +15 permanently. A one-time refugee event offers some of its members as recruits.

**Faction events (examples)**

|Trigger|Event|
|-|-|
|Saltborn Power ≥ 8|Tide Fleet: coastal missions pay +25%, sea routes open|
|Glass Caravans Power ≤ 3|Trade routes cut: all prices +20%|
|Rootwardens Power ≥ 8|Healing sap: Nursery recovery −1 week|
|Lantern Conclave collapses|Memorial no longer protects names (see The Hush)|
|Two rivals both at Power ≥ 7|Open war: the guild must pick a side; the other becomes Hostile|

### The Hush

The Hush is the campaign's doom meter, like XCOM's panic bar. It is a grey silence that erases places and people from memory (see Story). Global Hush goes from 0 to 100; each region also shows a local level from 0 to 5 that sets fog density and enemy strength on its maps.

|Change|Value|
|-|-|
|Every week|+2|
|Ignored Hush Breach mission|+3 to +8|
|Member dies without a Memorial record|+1|
|Faction collapses|+15|
|Hush Breach mission completed|−5 to −10|
|Story mission completed|−10|
|Lantern Conclave Allied|−1 per week|

|Hush|Stage|Effects|
|-|-|-|
|0–24|Calm|None|
|25–49|Fading|1 fewer mission per week; Hush creatures join regular missions|
|50–74|Forgetting|Recruits may have the Hollow trait (−25% XP); prices +20%; a random region gains +1 local Hush per week|
|75–99|Unremembered|Each week, 10% chance a benched member forgets the guild and leaves; the weakest faction loses 1 Power per week|
|100|Silence|Game over: the realm is forgotten|

**Memorial.** Recording a dead member's name at the Memorial costs gold. Recorded members do not feed the Hush and do not return as Echoes in the final mission.

### Loss Conditions

* The Hush reaches 100.
* Two factions collapse.
* The guild has no active members and no gold to recruit.
* Wages go unpaid for 3 consecutive weeks.

## IV. Story and Game World

The realm of Ambral is being erased by the Hush, a silent grey fog that makes the world forget. Written names resist it, which makes a guild's ledger one of the last things holding the realm together.

### Premise

For centuries the Great Bell of Carrow rang once a day, and its sound kept the Hush beyond the edges of the map. Twenty years ago the Bell cracked. The great guilds marched into the Hush to reforge it and never returned. No one remembers their names.

The player inherits an abandoned tavern in Carrow, an old guild emblem nobody can identify (the fixed guild icon) and a ledger full of blank pages where names used to be.

What the Hush does:

* Swallowed villages vanish from maps and from memory. Neighbors forget they ever existed.
* People touched by it lose memories, then their names, then themselves.
* Sound dies inside it. Hush maps get quieter as the fog thickens.
* Written names resist it. Ledgers, oaths and the Memorial matter mechanically.

### Factions and Peoples

|Faction|People|Home|Answer to the Hush|
|-|-|-|-|
|Saltborn Compact|Tidefolk: amphibious sailors who keep their memories inside symbiotic jellyfish|Coast of the Drowned Bells|Flee by sea; the ocean remembers|
|Lantern Conclave|Mothkin: moth-winged archivists who store memories as light in lanterns|Lampwick Stilts, a stilt city over misty jungle canals|Record everything; nothing may be forgotten|
|Rootwardens|Barkborn: wooden people grown from seeds planted on graves, carrying fragments of the dead|The Ember Wood, a forest in endless autumn|Forgetting is natural; the Hush is a season that must pass|
|Glass Caravans|Khepri: beetle-folk merchants sailing the dunes in glass-hulled ships|The Sunken Dunes, full of ruins of forgotten cities|Sell what the Hush leaves behind|

Humans live everywhere, belong to no faction and are the most common recruits.

|Playable race|Modifier|Racial trait|
|-|-|-|
|Human|Balanced|+10% XP|
|Tidefolk|+HP, −Speed|Tide-lungs: +10 Dodge on water tiles, immune to drowning|
|Mothkin|+Accuracy, +Movement, −HP|Lightbound: sees hidden units within 3 tiles|
|Barkborn|+Defense, −Speed|Graft: on death, leaves a seed; a Barkborn recruit with one of its traits appears next week|
|Khepri|+Crit, −Resolve|Carapace: the first hit each quest deals half damage|

### Regions

|Region|Faction|Biome|Typical enemies|
|-|-|-|-|
|Carrow|None (hub)|Town around the cracked Bell|—|
|Coast of the Drowned Bells|Saltborn Compact|Beaches, shipwrecks, sunken towers|Stingers (giant jellyfish), reef raiders|
|Lampwick Stilts|Lantern Conclave|Jungle canals, stilt villages|Canal serpents, lantern thieves|
|The Ember Wood|Rootwardens|Autumn forest, shrines|Masked spirits, rot-deer|
|The Sunken Dunes|Glass Caravans|Desert, ruins|Glass scorpions, toadfolk bandits|
|The Unremembered|—|Inside the Hush|Hush creatures, Echoes|

|Hush creature|Behavior|
|-|-|
|Hollow|Faceless person emptied by the Hush; weak alone, attacks in groups|
|Quietling|Small and fast; erases buffs from the target|
|Unwritten|Elite; erases one active skill of the target for the rest of the fight|
|Echo|A dead guild member returned by the Hush (final mission)|

### Campaign Arc

1. **Act 1 — The Blank Pages:** local missions around Carrow. The guild learns the Hush eats names and that the blank pages belonged to the old guild.
2. **Act 2 — The Four Answers:** each faction offers its own way to stop the Hush. Mission choices decide which factions rise and fall. Clues point to the old guild's founder.
3. **Act 3 — The Unremembered:** the guild enters the Hush to reach its heart.

Most play time stays emergent, driven by members' stories and faction events.

### Final Enemy: The Unnamed

The Unnamed is the founder of the old guild, the one whose emblem hangs over the tavern door. Twenty years ago she learned the Hush cannot be destroyed, only fed. She let it take her name and became its heart, holding it back with her own memories. Those memories are gone now. What remains is grief that wants the whole realm as silent as she is.

Final mission:

* Set in the Unremembered: a world built from forgotten things — vanished villages, the old guild, and the player's own dead members.
* Dead members without a Memorial record return as Echoes, with their names, stats and skills.
* Allied factions send reinforcements.
* The Unnamed erases one squad skill per phase. Recovering pages of the old ledger during the fight restores her name and weakens her.

### Endings

The ending depends on the strongest Allied faction when the final mission starts.

|Dominant faction|Ending|
|-|-|
|Lantern Conclave|The Bell is reforged and the Hush sealed forever. The price: the realm forgets the guild's name.|
|Rootwardens|The Unnamed is allowed to rest. The Hush becomes a tide that comes and goes, and the realm learns to live with forgetting.|
|Saltborn Compact|The Hush is carried out to sea. The coast is lost; the rest is saved.|
|Glass Caravans|The Hush is bottled in glass. The realm is saved, and the Caravans now own a weapon.|
|None Allied|The guild fights alone. Hardest version; the epilogue depends on how many names are in the Memorial.|

## V. Art and Design

### Graphics and Animation

The game uses 3D scenes rendered with a pixel art look ("3D pixel art"): low-poly models with pixel textures, rendered at low resolution and upscaled with nearest-neighbor filtering.

* **Camera:** isometric-style orthographic camera, rotatable in 90° steps, with zoom. Pixel-snapped to avoid shimmering.
* **Rendering:** low internal resolution (e.g. 640×360) upscaled to screen; limited palette per region; pixel-perfect outlines on characters.
* **Lighting:** real-time dynamic lights (torches, spells, day/night) — the main advantage of 3D over flat pixel art.
* **Characters:** 2D pixel sprites (billboards) with 8 directions, as the references suggest (see Art Direction). Low-poly 3D characters lose the hand-drawn detail at this size.
* **Equipment:** visible on characters (helmet, armor, weapon) so each member looks unique.
* **Wounds:** visible bandages and scars on injured members reinforce loss.
* **Animations:** idle, walk, attack per weapon type, hit, dodge, downed, death, cast.

### Art Direction from References

\[image: Reference 1: beach, jungle village, autumn forest and desert ruins]

The target look is dense, warm, hand-placed pixel art seen from a high 3/4 top-down angle, with small chibi characters in detailed environments.

**Tone.** The contrast between warm art and harsh mechanics is intentional and varies by environment. Faction regions stay warm and saturated. Maps lose saturation as their local Hush rises. The Unremembered is almost monochrome, with pixels dithering into grey at the fog's edge.

|Aspect|Reference|Application in 3D|
|-|-|-|
|Camera|High 3/4 top-down, around 50–60° pitch|Orthographic camera at a fixed pitch; rotation in 90° steps is optional and must not break framing|
|Characters|Chibi, about 2.5 heads tall, big heads, clear silhouettes, dark outlines|2D billboard sprites, 4 or 8 directions, around 32 px tall|
|Shadows|Soft elliptical drop shadow under each character|Blob shadow decal under every unit and prop|
|Environment|Many handcrafted props: logs, rocks, crates, ruins, shrines, banners|Modular low-poly tiles and props with pixel textures at one fixed texel density|
|Foliage|Trees and branches overlap the scene edges and frame it|Foreground foliage as sprites that fade when they cover units|
|Palette|Saturated and warm; shading shifts hue (shadows to blue and purple, lights to yellow)|Toon lighting ramp plus a palette lookup per region; no pure black shadows|
|Light|Soft sun from the upper left|One main directional light per map, plus dynamic lights for torches and spells|
|Creatures|Stylized, readable, slightly whimsical (jellyfish, scorpion, frog bandit, forest spirits)|Each enemy type readable by silhouette alone at combat zoom|

Region palettes, based on the reference biomes:

|Region|Reference biome|Dominant colors|
|-|-|-|
|Coast of the Drowned Bells|Coast|Sand, teal water, white foam|
|Lampwick Stilts|Jungle village|Lime green, turquoise, thatch brown, lantern gold|
|The Ember Wood|Autumn forest|Olive, ochre, orange leaves|
|The Sunken Dunes|Desert ruins|Terracotta, pink sand, gray stone|
|The Unremembered|—|Grays with a single accent color per map|

### User Interface

|Screen|Content|
|-|-|
|Guild hub|Tavern interior; each facility is a clickable area|
|Roster|Member list, stats, traits, injuries, equipment|
|Quest board|Available quests with risk and reward|
|Squad selection|Pick members and loadouts before a quest|
|Combat HUD|Turn timeline, HP and Defense bars, skill bar, hit % on hover|
|Post-quest|Rewards, XP, injuries, deaths|

Rules:

* Every probability is visible before confirming an action.
* Hovering a tile previews movement, ZOC, attacks of opportunity and cover.
* Pixel fonts for titles; a readable font for numbers and descriptions.

### Music and Sound Effects

* **Music:** medieval folk (lute, fiddle, flute) in the guild; a battle theme for horns and strings over war drums in combat; adaptive layers that rise with danger.
* **Sound effects:** distinct sounds for hit, miss, critical, block and armor break, so outcomes read by ear.
* **Death:** a short, silent moment and a unique sting when a member dies.
* **Voices:** short barks per member in combat (no full voice acting).

## VI. Development and Technology

### Platform

* Primary: PC (Windows, Linux)



### Technologies Used

Development is done mainly by an AI coding agent (Claude Code). The stack is chosen so the agent can write, run, test and check everything from the command line.

|Area|Choice|Reason|
|-|-|-|
|OS|Windows||
|Engine|Godot 4|Scenes, resources and scripts are plain text; headless run, test and export from CLI; no license login. .exe in "C:\\Users\\ferna\\Desktop\\Godot"|
|Language|GDScript|Text-based, fast iteration, native to Godot|
|Tests|GUT or GdUnit4|Agent validates combat formulas, progression and campaign rules without a human|
|Art|Blender, driven by Python (`bpy`), or any better alternative|Agent models, textures, renders and exports by script, headless|
|Image processing|Python + Pillow|Palette quantization, outlines, sprite sheets|
|Data|JSON or `.tres` resources|Classes, skills, traits, missions and factions as data, easy to balance|
|Visual checks|`xvfb` + screenshots|Agent runs the game with rendering and inspects screenshots|
|Version control|Git + LFS|Binary assets|

### Art Pipeline

All art is produced by the agent through Blender scripts. One build command regenerates every asset, so changes to palette, camera angle or resolution apply everywhere.

1. **Modeling:** low-poly props, tiles and chibi characters built from primitives and modifiers in Python.
2. **Textures:** pixel textures generated by code (Pillow or procedural nodes) at low resolution, with a fixed palette per region.
3. **Character sprites:** 3D models rendered with an orthographic camera at the game angle, 8 directions, low resolution, no anti-aliasing, toon shading. The render is reduced to the region palette and gets a 1 px outline.
4. **Animation:** simple rigs with keyframes set by script (idle, walk, attack, hit, downed, death, cast), rendered frame by frame into sprite sheets.
5. **Environments:** exported as `.glb` to Godot with pixel textures and nearest filtering.
6. **Review:** the agent renders preview sheets and inspects them before exporting.

Render engine: Cycles on CPU or Workbench when no GPU is available; both are fast at sprite resolution.

### 

### Scope and Milestones

1. **Combat prototype:** one map, 4 classes, hit chance, ZOC, injuries and death, plus an art pipeline test (one character, one enemy, one tile per region).
2. **Vertical slice:** guild hub, recruitment, 3 facilities, 5 quest types, one region with final art.
3. **Alpha:** all systems, 3 regions, Act 1.
4. **Beta:** full campaign, balancing, Ironman mode.
5. **Release.**
* ### Open Questions
* Squad size: fixed or upgradeable via facility?

  * Upgradable up to 6
* Is permanent death always on, or optional by difficulty?

  * Always on. The difficulty changes the chance of death.

