# A Guilda

A turn-based tactics and guild management game in the spirit of XCOM and Battle Brothers, drawn in 3D pixel art.

You inherit an abandoned tavern in Carrow, an emblem no one can identify and a ledger full of blank pages. Recruit adventurers, send squads on missions, keep the four factions of Ambral alive and hold back **the Hush**, a grey silence that erases places and people from memory. Every week there are more missions than members. Whatever you leave on the board has a price.

The full design is in [`A Guilda — Game Design Document.md`](A%20Guilda%20—%20Game%20Design%20Document.md).

## Playing

Download a build, or open the project in **Godot 4.7.2** and press Play (main scene: `scenes/boot.tscn`).

| Where | Controls |
|-|-|
| Guild hub | Click a facility in the tavern or use the buttons on the left. Q/E rotate, wheel zooms, WASD pans. |
| Battle | Click a blue tile to move and click an enemy to attack. Keys 1–6 pick skills; right-click or Esc cancels. F defends, V sets overwatch, T waits, G stabilizes, C carries, X extracts, R interacts and Space ends the turn. While exploring, Tab (or a portrait) picks the next member and Space ends the squad turn. Q/E rotate, wheel zooms, WASD or middle-drag pans. |

**The loop.** Each week every member has 7 days to spend on missions. Pick missions on the Quest Board, where each one is pinned as the client's letter, and assemble a squad. Fight, then read the post-quest report for rewards, XP, injuries and deaths. **End Week** pays wages, heals the injured, refreshes recruits and the board, and lets the Hush advance.

**How you lose.** The game ends if:

- the Hush reaches 100;
- two factions collapse;
- the guild misses wages three weeks in a row;
- nobody is left and there is no gold to hire.

**How you win.** Finish the three acts and defeat the Unnamed in the Heart of the Hush. The ending depends on which allied faction is strongest.

**Exploration.** Hunt, clear, escort, rescue and retrieve missions take place on large maps under fog. You see the ground but not who stands on it, and the fog lifts around your members. Until a patrol spots you, the squad explores: move every member, end the squad turn, and the patrols walk their beat. Red tiles show where an unaware enemy would see you. When one enemy spots a member, its whole group joins and combat begins for that group only, on the usual timeline; other patrols keep walking until they see you too. Striking an unaware enemy counts as a flank. Hunt targets and caches wait in a far final area at the end of a marked trail. Defense and survive missions stay single fights, but the enemy comes out of the fog.

**Leveling.** Every quest gives 100 XP. Level 2 takes one quest, level 3 three more, level 4 five more, and so on up to level 7: 36 quests in all, or about 30 with kill and bonus XP, so a member who goes on two quests a week reaches it near the end of a campaign. Each class has two skill trees of six rows (levels 2 to 7). Each row offers one skill from each tree: learn one of the two, never both, and mix trees freely from row to row. With a Library you can retrain a row for gold. The level-7 skills are the strongest, and the tree of your level-7 skill gives the member its subclass title.

**Difficulty.** There are three levels: Forgiving, Standard and Merciless. **Ironman** keeps a single autosave, and leaving mid-battle abandons the mission.

## What's in the game

- **Combat**
  - Speed-based turn timeline, plus an exploration phase under fog of war with patrolling enemy groups.
  - Hit and crit chances always shown before you commit: half and full cover, high ground, flanking and range falloff.
  - Area spells (the Mystic's Evocation tree) always land but swing widely in damage, and they hit allies in the area too.
  - Zones of control and attacks of opportunity; overwatch; Defense that wears down.
  - Status effects resisted by Resolve.
  - Downed members bleed out and can be stabilized or carried.
  - Permanent death and injuries.
  - Retreat through extraction zones.
  - Objectives: clear, hunt, retrieve, rescue, escort, defense, survive and the final battle with its boss phases.
- **Guild**
  - 4 base classes plus 4 faction classes, each with two 6-row skill trees (pick one skill per row); the level-7 skill sets the subclass; ~120 skills.
  - Traits, quality tiers, hidden growth potential, 5 races.
  - Rare guild events bring named recruits with their own stories and fixed traits.
  - Equipment tiers and a forge.
  - 7 facilities with 3 levels each, and they change the tavern as they grow.
- **Strategy**
  - A weekly board of about 6 missions, each written as a first-person letter from its client: resource, strategic, rival pairs (taking one cancels the other), faction chains and story missions.
  - 4 factions with reputation and power; they can collapse.
  - Random and faction events.
  - The Hush meter, with 4 stages that change the game.
- **Story.** Three acts, six story missions, a final battle and five endings.
- **Presentation**
  - Low-resolution 3D rendered with a pixel-snapped orthographic camera at a 30° (2:1) angle and integer upscaling.
  - Every map sits in a skirt of countryside that dissolves into drifting, dithered mist, tinted per region.
  - Missions take place by day, at dusk or by night; at night lanterns and fires light the map under the moon.
  - Toon lighting with hue-shifted shadows, per-region palettes, depth outlines, and desaturation that follows the local Hush.
  - Billboard chibi sprites in 4 directions, drawn from the same 30° angle as the maps.
  - Anime-style chibi models: the Tidefolk, Mothkin, Barkborn and Khepri follow the concept sheets in `concept_art/`, and every class of every race has a masculine and a feminine model, each in its race's palette.
- **Audio**
  - Procedurally synthesized folk music in the guild.
  - Combat music with a danger layer that rises as the squad gets hurt.
  - 50 distinct sound effects.
  - Members call out short lines in combat, often in their people's idiom, with babbled voices pitched to their race.
  - A silent moment and a sting when a member dies.

## Project layout

```
data/            JSON game data: classes, skills, traits, races, statuses, enemies, items,
                 facilities, factions, regions, missions, story, events, names
scripts/core/    Headless rules: Rules, Member, Items, Campaign (weekly simulation), AutoPilot
scripts/combat/  Battle, BattleGrid, BattleAI, BattleFactory, MapGen, BattleScene, BattleHUD
scripts/view/    WorldView (pixel-perfect 3D), terrain/prop/unit views, overlays, FX
scripts/guild/   Guild hub (TavernView diorama) and its management screens
scripts/ui/      Theme, widgets, dialogs, title, story, report and ending screens
scripts/autoload DB, Settings, Game (campaign + saves), Audio, Scenes
shaders/         Toon, terrain, water, props, unit sprites, post-process outlines
assets/          Generated art and audio (see below) and OFL fonts
tests/           GUT unit tests (rules, members, battles, campaign, AutoPilot simulations)
tools/           Asset pipeline (Blender + Python), test/check/screenshot scripts
```

## Asset pipeline

Every asset is generated from code, and one command rebuilds them all:

```bash
powershell -ExecutionPolicy Bypass -File tools/build_assets.ps1
```

Pass `-Only units,props,textures,ui,audio` to rebuild a subset.

| Step | Tool | Output |
|-|-|-|
| units | Blender `tools/blender/units.py` (anime-style playable models in `characters.py`), then `tools/py/sprites_post.py` | Index-colour sprite sheets (4 directions × 30 frames), portraits and `units.json` |
| props | Blender `tools/blender/props.py` | 77 low-poly `.glb` props with palette-slot vertex colours |
| textures | `tools/py/textures.py` | Ground atlases, prop palettes per region, decoration sheet |
| ui | `tools/py/ui_art.py` | Panels, buttons, icons, emblems, world map |
| audio | `tools/py/audio.py` | Music loops and sound effects (numpy synthesis) |

Blender must be installed; the Python tools run in `.venv` (numpy and Pillow). Race and class colours live in `data/races.json` (`palette` and `looks`). Every class of every playable race has a masculine and a feminine model (`<race>_<look>_<m|f>`, humans add a hairstyle `_a`/`_b`), modelled after the sheets in `concept_art/`. `tools/py/race_sheet.py` builds a review sheet of the race models in those colours; for model work, `units.py --quick` plus `tools/py/model_sheet.py` renders a fast hi-res preview.

## Tests and checks

```bash
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

Runs the GUT suite. It covers:

- combat formulas, zones of control, attacks of opportunity, cover and bleed-out;
- AI battles in every region and objective;
- campaign rules and save round-trips;
- 30-week AutoPilot campaigns.

```bash
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

Loads every script and scene and reports parse errors.

```bash
powershell -ExecutionPolicy Bypass -File tools/shot.ps1 flow -Timeout 420
```

Drives the real scenes end to end: new guild, hub, board, squad, an auto-played battle, report, story page, hub and end of week. It saves a screenshot at each step to `tools/_cache/shots/`. Other captures:

- `screen_hub`, `screen_roster`, `screen_board`, `screen_board_letter`, `screen_board_map`, `screen_squad`, `screen_stash`, `screen_facilities`, `screen_realm`, `screen_ledger`, `screen_memorial`, `screen_recruit`
- `scene_title`, `scene_battle`, `scene_report`, `scene_story`, `scene_ending`
- `battle_<region>` and `battle_<region>_far` (zoomed out, to see the mist); `battle_<region>_<objective>` and `battle_<region>_<objective>_map` for the fog and patrols of an exploration map
- `lineup` (every race in every class) and `input` (real mouse events against battle and hub picking)

## Building

```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/AGuilda.exe
```

```bash
godot --headless --path . --export-release "Linux" build/linux/AGuilda.x86_64
```

Presets live in `export_presets.cfg`. The Godot 4.7.2 export templates must be installed.

## Credits

Design, code, art, music and sound effects were produced from the design document by an AI coding agent (Claude) using Godot, Blender and Python.

- **Engine:** [Godot Engine](https://godotengine.org) (MIT)
- **Tests:** [GUT](https://github.com/bitwes/Gut) (MIT)
- **Fonts** (SIL Open Font License 1.1; license files in `assets/fonts/`):
  - Alegreya Sans, by Juan Pablo del Peral / Huerta Tipográfica
  - Pixelify Sans, by Stefie Justprince
  - Jacquard 12 and Jersey 10, by Sarah Cadigan-Fried
