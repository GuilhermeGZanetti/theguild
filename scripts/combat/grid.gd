class_name BattleGrid
extends RefCounted
## Tile map for a battle: heights, ground, props, cover, water, terrain effects.
## Heights are in levels (1 level = 0.5 world units).

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const LEVEL_H := 0.5

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


func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	if n == 0:
		out.append(a)
		return out
	var last := Vector2i(-999, -999)
	for i in n + 1:
		var f := float(i) / n
		var p := Vector2i(roundi(lerpf(a.x, b.x, f)), roundi(lerpf(a.y, b.y, f)))
		if p != last:
			out.append(p)
			last = p
	return out


## Line of sight between two tiles. Tiles next to either end are ignored
## (they are cover, not walls) so units can peek around corners.
func los(a: Vector2i, b: Vector2i) -> bool:
	var pts := line(a, b)
	var ha := height(a) + 2.0
	var hb := height(b) + 1.5
	var total := float(pts.size() - 1)
	for i in range(1, pts.size() - 1):
		var p := pts[i]
		if Rules.chebyshev(p, b) <= 1 or Rules.chebyshev(p, a) <= 1:
			continue
		var tl := t(p)
		if tl["block"]:
			return false
		var line_h := lerpf(ha, hb, i / total)
		if float(tl["h"]) > line_h:
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
