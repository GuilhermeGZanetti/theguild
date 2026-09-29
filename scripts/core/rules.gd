class_name Rules
extends RefCounted
## Combat and progression formulas from the GDD. Pure functions, unit tested.

const HIT_MIN := 5
const HIT_MAX := 95
const HALF_COVER := 20
const FULL_COVER := 40
const HIGH_GROUND_HIT := 10
const FLANK_HIT := 15
const FLANK_CRIT := 10
const RANGE_FALLOFF := 10
const MAX_RANGE_EXTRA := 3
const OVERWATCH_PENALTY := 10
const ARMOR_WEAR := 0.15          # share of raw damage that wears Defense down
const DAMAGE_VARIANCE := 0.10
const DEFEND_DODGE := 20
const DEFEND_CRIT_DEF := 25
const ROUND_TICKS := 12.0
const BLEEDOUT_TURNS := 3


static func turn_delay(speed: float) -> float:
	return 1000.0 / (maxf(speed, -40.0) + 50.0)


static func cover_penalty(cover: int) -> int:
	match cover:
		1: return HALF_COVER
		2: return FULL_COVER
	return 0


## Hit = Accuracy - Dodge + Cover + Elevation + Flank (+ other), clamped 5..95.
static func hit_chance(accuracy: float, dodge: float, cover: int, high_ground: bool, flanking: bool, tiles_beyond_optimal: int = 0, extra: float = 0.0) -> int:
	var h := accuracy - dodge - cover_penalty(cover)
	if high_ground:
		h += HIGH_GROUND_HIT
	if flanking:
		h += FLANK_HIT
	h -= RANGE_FALLOFF * maxi(tiles_beyond_optimal, 0)
	h += extra
	return clampi(roundi(h), HIT_MIN, HIT_MAX)


static func crit_chance(crit: float, flanking: bool, extra: float = 0.0) -> int:
	var c := crit + (FLANK_CRIT if flanking else 0) + extra
	return clampi(roundi(c), 0, 100)


## Chance = Base + 5 x (Level_att - Level_target) - Resolve_target / 4
static func status_chance(base: float, level_att: int, level_target: int, resolve_target: float) -> int:
	if base >= 100.0:
		return 100
	var c := base + 5.0 * (level_att - level_target) - resolve_target / 4.0
	return clampi(roundi(c), HIT_MIN, HIT_MAX)


## Raw damage = Attack x multiplier, with +-10% variance. roll in [-1, 1].
static func raw_damage(attack: float, mult: float, roll: float) -> float:
	return maxf(0.0, attack * mult * (1.0 + DAMAGE_VARIANCE * roll))


## Returns {damage, wear}: current Defense is subtracted from the raw damage;
## the hit also wears the Defense down by a share of the raw damage.
static func apply_defense(raw: float, current_def: float, pierce: float = 0.0) -> Dictionary:
	var eff_def := current_def * (1.0 - clampf(pierce, 0.0, 1.0))
	var dmg := maxi(1, roundi(raw - eff_def)) if raw > 0.0 else 0
	var wear := minf(current_def, raw * ARMOR_WEAR)
	return {"damage": dmg, "wear": wear}


## Each member's share of a quest's XP: about one ordinary quest's worth
## (DB.QUEST_XP), a little more for harder ones. The fallen's shares go to the
## survivors.
static func xp_share(skulls: int, squad: int, survivors: int, bonus_mult: float = 1.0) -> int:
	if survivors <= 0:
		return 0
	var pool := (100.0 + 8.0 * (skulls - 1)) * maxf(squad, 1) * bonus_mult
	return roundi(pool / survivors)


## Extra XP for a member's kills and rescues in one quest.
static func deed_xp(kills: int, stabilizes: int, skulls: int) -> int:
	return kills * (2 + skulls) + stabilizes * 12


static func grade(objectives_done: bool, bonus_done: int, bonus_total: int, rounds: int, par_rounds: int, deaths: int, downed: int) -> String:
	if not objectives_done:
		return "D"
	var score := 3.0
	score += float(bonus_done) / maxf(bonus_total, 1)
	if rounds <= par_rounds:
		score += 0.5
	elif rounds > par_rounds * 1.6:
		score -= 0.5
	score -= deaths * 1.2
	score -= downed * 0.3
	if score >= 4.2:
		return "S"
	if score >= 3.4:
		return "A"
	if score >= 2.6:
		return "B"
	if score >= 1.6:
		return "C"
	return "D"


static func grade_mult(g: String) -> float:
	return {"S": 1.5, "A": 1.25, "B": 1.0, "C": 0.8, "D": 0.6}.get(g, 1.0)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	if dx <= 1 and dy <= 1:
		return maxi(dx, dy)
	return roundi(sqrt(float(dx * dx + dy * dy)))


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func renown_rank(renown: int) -> int:
	var thresholds := [0, 40, 120, 250, 400, 600]
	var r := 0
	for i in thresholds.size():
		if renown >= thresholds[i]:
			r = i
	return r


static func rank_name(rank: int) -> String:
	return ["Unknown", "Local", "Respected", "Renowned", "Famed", "Legendary"][clampi(rank, 0, 5)]


static func max_skulls(rank: int) -> int:
	return clampi(2 + rank, 2, 5)


## Time of day of a mission, fixed by its seed: 55% day, 25% dusk, 20% night.
static func time_of_day(seed_value: int) -> String:
	var k := posmod(seed_value, 20)
	return "day" if k < 11 else ("dusk" if k < 16 else "night")


static func hush_stage(hush: int) -> int:
	if hush >= 100:
		return 4
	if hush >= 75:
		return 3
	if hush >= 50:
		return 2
	if hush >= 25:
		return 1
	return 0


static func hush_stage_name(stage: int) -> String:
	return ["Calm", "Fading", "Forgetting", "Unremembered", "Silence"][clampi(stage, 0, 4)]


static func rep_name(rep: int) -> String:
	if rep <= -2:
		return "Hostile"
	if rep == -1:
		return "Wary"
	if rep == 0:
		return "Neutral"
	if rep == 1:
		return "Friendly"
	if rep == 2:
		return "Trusted"
	return "Allied"
