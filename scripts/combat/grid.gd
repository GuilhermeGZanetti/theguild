class_name BattleGrid
extends RefCounted
## Tile map for a battle: heights, ground, props, cover, water, terrain effects.
## Heights are in levels (1 level = 0.5 world units).

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const LEVEL_H := 0.5
## Eye height above the ground at both ends of a sight line, in levels.
const EYE_H := 1.75
## How far (in tiles) a sight line may lean sideways to get past an obstacle
## it only grazes: units are not points.
const LOS_LEAN := 0.35
## Full-cover props taller than a person: how many levels above their base a
## viewer must stand to see over them. Any other full cover takes one.
const TALL_PROPS := {"house": 4, "house_part": 4, "hut": 3, "hut_part": 3, "bell_tower": 6, "bell_tower_part": 6}

var w := 0
var h := 0
var tiles: Array = []
var biome := "town"
var region := "carrow"
var hush := 0
var water_level := -1
var time := "day"          # day, dusk or night: lighting only


func _init(width: int = 0, height: int = 0) -> void:
	if width > 0:
		resize(width, height)


func resize(width: int, height: int) -> void:
	w = width
	h = height
	tiles.clear()
	for i in w * h:
		tiles.append(new_tile())


static func new_tile() -> Dictionary:
	return {"h": 0, "ground": "grass", "water": 0, "prop": "", "cover": 0, "solid": false,
			"block": false, "flammable": false, "extract": false, "fx": {}, "obj": {}, "deco": ""}


func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func t(p: Vector2i) -> Dictionary:
	return tiles[p.y * w + p.x]


func height(p: Vector2i) -> int:
	return int(tiles[p.y * w + p.x]["h"])


func world_y(p: Vector2i) -> float:
	var tl := t(p)
	if tl["water"] > 0:
		return (float(tl["h"]) - 0.4) * LEVEL_H
	return float(tl["h"]) * LEVEL_H


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in h:
		for x in w:
			out.append(Vector2i(x, y))
	return out


## Can a unit stand on this tile (ignoring other units)?
func standable(p: Vector2i, swims := false, floats := false) -> bool:
	if not inb(p):
		return false
	var tl := t(p)
	if tl["solid"]:
		return false
	var fx: Dictionary = tl["fx"]
	if fx.get("kind", "") == "flood" and not (swims or floats):
		return true
	if int(tl["water"]) >= 2 and not (swims or floats):
		return false
	return true


## Movement cost of a single orthogonal step, -1 when impossible.
func step_cost(a: Vector2i, b: Vector2i, swims := false, floats := false) -> int:
	if not standable(b, swims, floats):
		return -1
	var dh := height(b) - height(a)
	if dh > 1 and not floats:
		return -1
	if dh < -2 and not floats:
		return -1
	var c := 1
	if dh == 1:
		c += 1
	var tb := t(b)
	if int(tb["water"]) == 1 and not (swims or floats):
		c += 1
	if tb["fx"].get("kind", "") == "flood" and not (swims or floats):
		c += 1
	return c


## Low obstacles (half-cover props) can be vaulted.
func vaultable(p: Vector2i) -> bool:
	if not inb(p):
		return false
	var tl := t(p)
	return tl["solid"] and int(tl["cover"]) == 1


## Cost of vaulting from `a` over the half cover at `a + dir` onto `a + 2 dir`:
## the obstacle's tile plus the landing step, -1 when there is nothing to vault
## or no footing on the far side.
func vault_cost(a: Vector2i, dir: Vector2i, swims := false, floats := false) -> int:
	var mid := a + dir
	if not vaultable(mid) or height(mid) > height(a):
		return -1
	var sc := step_cost(a, a + dir * 2, swims, floats)
	return -1 if sc < 0 else sc + 1


## Cover (0 none, 1 half, 2 full) a unit at `target` gets against `from`.
func cover_from(target: Vector2i, from: Vector2i) -> int:
	var d := Vector2(from - target)
	if d.length() < 1.5:
		return 0
	d = d.normalized()
	var best := 0
	for n in DIRS4:
		var np := target + n
		if not inb(np):
			continue
		if Vector2(n).dot(d) < 0.5:
			continue
		best = maxi(best, cover_of_tile(np, target))
	return best


## Cover a neighbour tile provides to a unit standing on `owner_tile`.
func cover_of_tile(np: Vector2i, owner_tile: Vector2i) -> int:
	var tl := t(np)
	var c := int(tl["cover"])
	var dh := height(np) - height(owner_tile)
	if dh >= 2:
		c = maxi(c, 2)
	elif dh == 1:
		c = maxi(c, 1)
	if tl["fx"].get("kind", "") == "thorns":
		c = maxi(c, 1)
	return c


func cover_dirs(p: Vector2i) -> Array:
	## [dir, cover] pairs for UI shields
	var out: Array = []
	for n in DIRS4:
		var np := p + n
		if inb(np):
			var c := cover_of_tile(np, p)
			if c > 0:
				out.append([n, c])
	return out


## Line of sight between two tiles, the same both ways. Tiles next to either
## end are ignored (they are cover, not walls) so units can peek around
## corners, and a line that only grazes an obstacle gets past by leaning a
## little to one side. Full cover walls off only what stands no higher than
## it: from a level above its base you see over a rock, a wall or a tree
## (buildings need more, see TALL_PROPS).
func los(a: Vector2i, b: Vector2i) -> bool:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		# always traced from the same end, so rounding can never make it one-way
		var s := a
		a = b
		b = s
	if _sight_ray(a, b, 0.0):
		return true
	return _sight_ray(a, b, LOS_LEAN) or _sight_ray(a, b, -LOS_LEAN)


## One sight line from `a` to `b`, shifted sideways by `lean` tiles.
func _sight_ray(a: Vector2i, b: Vector2i, lean: float) -> bool:
	var d := Vector2(b - a)
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 3
	if n == 0:
		return true
	var start := Vector2(a) + Vector2(-d.y, d.x).normalized() * lean
	var ha := height(a) + EYE_H
	var hb := height(b) + EYE_H
	var top := maxi(height(a), height(b))
	var last := a
	for i in range(1, n):
		var f := float(i) / n
		var q := start + d * f
		var p := Vector2i(roundi(q.x), roundi(q.y))
		if p == last:
			continue
		last = p
		if not inb(p) or Rules.chebyshev(p, a) <= 1 or Rules.chebyshev(p, b) <= 1:
			continue
		var tl := t(p)
		var th := int(tl["h"])
		if float(th) > lerpf(ha, hb, f):
			return false
		if tl["block"] and th + int(TALL_PROPS.get(tl["prop"], 1)) > top:
			return false
	return true


func neighbors4(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS4:
		if inb(p + d):
			out.append(p + d)
	return out


func neighbors8(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS8:
		if inb(p + d):
			out.append(p + d)
	return out


func cells_in_radius(c: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var p := Vector2i(x, y)
			if inb(p) and Rules.chebyshev(p, c) <= r:
				out.append(p)
	return out


func to_dict() -> Dictionary:
	return {"w": w, "h": h, "tiles": tiles, "biome": biome, "region": region, "hush": hush, "time": time}


static func from_dict(d: Dictionary) -> BattleGrid:
	var g := BattleGrid.new()
	g.w = int(d["w"])
	g.h = int(d["h"])
	g.tiles = d["tiles"]
	g.biome = d.get("biome", "town")
	g.region = d.get("region", "carrow")
	g.hush = int(d.get("hush", 0))
	g.time = d.get("time", "day")
	for tl in g.tiles:
		tl["h"] = int(tl["h"])
		tl["water"] = int(tl["water"])
		tl["cover"] = int(tl["cover"])
	return g
