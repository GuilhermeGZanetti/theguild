class_name TerrainBuilder
extends RefCounted
## Builds the terrain mesh (tops + cliff sides, diorama base), the water
## surface, and the splat/shore textures from a BattleGrid.

const BASE := -1.1
const WATER_DROP := 0.14

static var ground_meta := {}


static func meta() -> Dictionary:
	if ground_meta.is_empty():
		ground_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/ground.json"))
	return ground_meta


static func ground_index(name: String) -> int:
	var arr: Array = meta()["grounds"]
	var i := arr.find(name)
	return i if i >= 0 else 0


static func top_y(g: BattleGrid, p: Vector2i) -> float:
	var tl := g.t(p)
	var y := float(tl["h"]) * BattleGrid.LEVEL_H
	if int(tl["water"]) == 1:
		y -= 0.32
	elif int(tl["water"]) >= 2:
		y -= 0.7
	return y


static func water_y(g: BattleGrid, p: Vector2i) -> float:
	return float(g.t(p)["h"]) * BattleGrid.LEVEL_H - WATER_DROP


static func build_terrain(g: BattleGrid, edge_walls := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in g.all_cells():
		var y := top_y(g, p)
		var x0 := float(p.x)
		var z0 := float(p.y)
		# top
		_quad(st, Vector3(x0, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + 1), Vector3(x0, y, z0 + 1), Vector3.UP, y)
		# sides
		for d in BattleGrid.DIRS4:
			var n: Vector2i = p + d
			var ny := BASE
			if g.inb(n):
				ny = top_y(g, n)
			elif not edge_walls:
				continue
			if ny >= y - 0.001:
				continue
			var nrm := Vector3(d.x, 0, d.y)
			var a: Vector3
			var b: Vector3
			match d:
				Vector2i(1, 0):
					a = Vector3(x0 + 1, 0, z0 + 1)
					b = Vector3(x0 + 1, 0, z0)
				Vector2i(-1, 0):
					a = Vector3(x0, 0, z0)
					b = Vector3(x0, 0, z0 + 1)
				Vector2i(0, 1):
					a = Vector3(x0, 0, z0 + 1)
					b = Vector3(x0 + 1, 0, z0 + 1)
				_:
					a = Vector3(x0 + 1, 0, z0)
					b = Vector3(x0, 0, z0)
			_quad(st, a + Vector3(0, y, 0), b + Vector3(0, y, 0), b + Vector3(0, ny, 0), a + Vector3(0, ny, 0), nrm, y)
	st.index()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, top: float) -> void:
	# a-b-c-d counter-clockwise when seen from the normal side
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_uv2(Vector2(top, 0))
		st.add_vertex(v)


static func build_water(g: BattleGrid, edge_walls := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for p in g.all_cells():
		if int(g.t(p)["water"]) == 0:
			continue
		any = true
		var y := water_y(g, p)
		var x0 := float(p.x)
		var z0 := float(p.y)
		_quad(st, Vector3(x0, y, z0), Vector3(x0 + 1, y, z0), Vector3(x0 + 1, y, z0 + 1), Vector3(x0, y, z0 + 1), Vector3.UP, y)
		for d in BattleGrid.DIRS4:
			var n: Vector2i = p + d
			if g.inb(n) or not edge_walls:
				continue
			var a: Vector3
			var b: Vector3
			match d:
				Vector2i(1, 0):
					a = Vector3(x0 + 1, 0, z0 + 1)
					b = Vector3(x0 + 1, 0, z0)
				Vector2i(-1, 0):
					a = Vector3(x0, 0, z0)
					b = Vector3(x0, 0, z0 + 1)
				Vector2i(0, 1):
					a = Vector3(x0, 0, z0 + 1)
					b = Vector3(x0 + 1, 0, z0 + 1)
				_:
					a = Vector3(x0 + 1, 0, z0)
					b = Vector3(x0, 0, z0)
			_quad(st, a + Vector3(0, y, 0), b + Vector3(0, y, 0), b + Vector3(0, BASE + 0.02, 0), a + Vector3(0, BASE + 0.02, 0), Vector3(d.x, 0, d.y), y)
	if not any:
		return null
	return st.commit()


## A render-only copy of the grid with `pad` tiles of land around it that
## continue the map's edges (heights, grounds, rivers and shores), so the
## board blends into the countryside instead of ending in a cliff.
static func padded(g: BattleGrid, pad: int, seed_: int) -> BattleGrid:
	var out := BattleGrid.new(g.w + pad * 2, g.h + pad * 2)
	out.biome = g.biome
	out.region = g.region
	var bd: Dictionary = MapGen.BIOME.get(g.biome, MapGen.BIOME["town"])
	var hn := FastNoiseLite.new()
	hn.seed = seed_
	hn.frequency = 0.11
	var gn := FastNoiseLite.new()
	gn.seed = seed_ + 17
	gn.frequency = 0.16
	for q in out.all_cells():
		var p := q - Vector2i(pad, pad)
		var tl: Dictionary = out.t(q)
		if g.inb(p):
			var src := g.t(p)
			tl["h"] = src["h"]
			tl["ground"] = src["ground"]
			tl["water"] = src["water"]
			continue
		var e := Vector2i(clampi(p.x, 0, g.w - 1), clampi(p.y, 0, g.h - 1))
		var src := g.t(e)
		var d := maxi(absi(p.x - e.x), absi(p.y - e.y))
		var eh := int(src["h"])
		var ground: String = src["ground"]
		if ground in ["planks", "void"]:
			ground = bd["ground"]
		# rolling land: flat next to the board so nothing hides the edge rows
		var roll := hn.get_noise_2d(p.x, p.y) * 1.7 * smoothstep(1.5, 5.0, float(d))
		var hgt := clampi(eh + roundi(roll), -1, eh + 2)
		var water := int(src["water"])
		if water > 0:
			hgt = eh
			if water == 1 and d >= 2 and hn.get_noise_2d(p.x, p.y) > 0.35:
				water = 0
				ground = "wetsand" if g.biome == "coast" else "mud"
		tl["h"] = hgt
		tl["water"] = water
		var gv := gn.get_noise_2d(p.x, p.y)
		if water == 0 and d >= 2:
			if gv > 0.3:
				ground = bd["patch"]
			elif gv < -0.45:
				ground = bd["patch2"]
			elif d >= 4 and ground in ["cobble", "stonepath"] and gv > -0.1:
				ground = bd["patch"]
		tl["ground"] = ground
	return out


static func splat_texture(g: BattleGrid) -> ImageTexture:
	var img := Image.create(g.w, g.h, false, Image.FORMAT_R8)
	for p in g.all_cells():
		var tl := g.t(p)
		var name: String = tl["ground"]
		img.set_pixel(p.x, p.y, Color(ground_index(name) / 255.0, 0, 0))
	return ImageTexture.create_from_image(img)


static func shore_texture(g: BattleGrid) -> ImageTexture:
	var img := Image.create(g.w, g.h, false, Image.FORMAT_R8)
	for p in g.all_cells():
		var v := 0.0
		if int(g.t(p)["water"]) == 0:
			v = 1.0
		else:
			var best := 9
			for q in g.cells_in_radius(p, 2):
				if int(g.t(q)["water"]) == 0:
					best = mini(best, Rules.chebyshev(p, q))
			if best == 1:
				v = 0.5
			elif best == 2:
				v = 0.25
		img.set_pixel(p.x, p.y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
