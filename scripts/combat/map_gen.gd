class_name MapGen
extends RefCounted
## Procedural battle maps per biome with handcrafted-feeling features.

# prop id -> [cover, solid, blocks LOS, flammable]
const PROPS := {
	"rock_s": [1, true, false, false], "rock_l": [2, true, true, false], "boulder": [2, true, true, false],
	"log": [1, true, false, true], "stump": [1, true, false, true], "crate": [1, true, false, true],
	"crates": [2, true, true, true], "barrel": [1, true, false, true], "fence": [1, true, false, true],
	"tree": [2, true, true, true], "tree_dead": [1, true, false, true], "palm": [1, true, false, true],
	"wall": [2, true, true, false], "wall_broken": [1, true, false, false], "pillar": [2, true, true, false],
	"column_broken": [1, true, false, false], "statue": [2, true, true, false], "shrine": [2, true, true, false],
	"lantern_post": [0, true, false, false], "post": [1, true, false, true], "boat": [2, true, true, true],
	"hut": [2, true, true, true], "hut_part": [2, true, true, true], "house": [2, true, true, false], "house_part": [2, true, true, false],
	"stall": [1, true, false, true], "cart": [1, true, false, true], "well": [1, true, false, false],
	"coral": [1, true, false, false], "tent": [2, true, true, true], "campfire": [0, true, false, true],
	"signpost": [0, true, false, true], "doorframe": [2, true, true, false], "bell": [2, true, true, false],
	"mushrooms": [0, true, false, false], "reeds": [0, false, false, true], "bush": [0, false, false, true],
	"cactus": [1, true, false, false], "pots": [1, true, false, false], "arch": [2, true, true, false], "arch_part": [2, true, true, false],
	"lectern": [1, true, false, true], "bell_tower": [2, true, true, false], "bell_tower_part": [2, true, true, false],
}

## Objectives played on big patrolled maps under fog of war.
const EXPLORE := ["clear", "hunt", "retrieve", "rescue", "escort"]
## A ground that stands out from the biome's own patches: the trail must read at a glance.
const TRAIL_GROUND := {"town": "dirt", "hush_town": "dirt", "coast": "stonepath", "jungle": "planks",
	"autumn": "stonepath", "desert": "cobble", "hush": "cobble"}
const CAMP := {
	"town": ["stall", "cart", "barrel", "crate", "crates"], "hush_town": ["lectern", "wall_broken", "barrel", "crate", "doorframe"],
	"coast": ["tent", "boat", "barrel", "crate", "crates"], "jungle": ["tent", "barrel", "crate", "crates", "log"],
	"autumn": ["tent", "log", "crate", "barrel", "stump"], "desert": ["tent", "pots", "crate", "crates", "cart"],
	"hush": ["lectern", "column_broken", "wall_broken", "crate", "signpost"],
}

const BIOME := {
	"town": {"ground": "cobble", "patch": "grass", "patch2": "dirt", "cliff": "stone"},
	"hush_town": {"ground": "cobble", "patch": "ash", "patch2": "dirt", "cliff": "stone"},
	"coast": {"ground": "sand", "patch": "grass", "patch2": "wetsand", "cliff": "rock"},
	"jungle": {"ground": "grass", "patch": "moss", "patch2": "dirt", "cliff": "earth"},
	"autumn": {"ground": "leaves", "patch": "grass", "patch2": "dirt", "cliff": "earth"},
	"desert": {"ground": "sand", "patch": "redsand", "patch2": "stonepath", "cliff": "sandstone"},
	"hush": {"ground": "ash", "patch": "stonepath", "patch2": "grass", "cliff": "stone"},
}

var g: BattleGrid
var rng: RandomNumberGenerator
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var biome := "town"
var reserved := {}
var explore := false
var trail: Array = []


static func is_explore(mission: Dictionary) -> bool:
	return mission.get("objective", "clear") in EXPLORE and not mission.get("small_map", false)


func generate(mission: Dictionary, p_rng: RandomNumberGenerator, squad_size: int) -> Dictionary:
	rng = p_rng
	var region: String = mission.get("region", "carrow")
	biome = mission.get("biome", DB.regions.get(region, {}).get("biome", "town"))
	var objective: String = mission.get("objective", "clear")
	explore = is_explore(mission)
	var w := 16
	var h := 16
	if explore:
		# long maps: the squad lands in the south, the objective waits in the north
		w = 22
		h = 36
		if objective == "escort":
			w = 18
			h = 40
	elif objective == "escort":
		w = 14
		h = 20
	elif objective == "final":
		w = 17
		h = 17
	elif objective in ["survive", "defense"]:
		w = 18
		h = 20
	g = BattleGrid.new(w, h)
	g.biome = biome
	g.region = region
	noise.seed = rng.randi()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	noise2.seed = rng.randi()
	noise2.frequency = 0.18
	reserved.clear()
	trail = []
	_heights()
	_ground()
	_biome_features()
	var out := _explore_layout(objective) if explore else _spawns(objective, squad_size)
	_objective_props(objective, mission, out)
	_scatter_props()
	if explore:
		_camp(out["objective_area"]["center"], int(out["objective_area"]["r"]))
	_decorate()
	_ensure_connected(out)
	out["explore"] = explore
	out["grid"] = g
	return out


# ---------------------------------------------------------------- terrain
func _heights() -> void:
	for p in g.all_cells():
		var n := noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		var hv := 0
		match biome:
			"town", "hush_town":
				hv = 1 if n > 0.68 else 0
			"coast":
				hv = int(clampf(n * 3.0 - 0.4, 0, 2))
			"jungle":
				hv = 1 + (1 if n > 0.66 else 0)
			"autumn":
				hv = int(clampf(n * 4.2 - 1.2, 0, 3))
			"desert":
				hv = int(clampf(n * 3.2 - 0.8, 0, 2))
				if n > 0.8:
					hv = 3
			"hush":
				hv = int(clampf(n * 3.4 - 1.0, 0, 2))
		g.t(p)["h"] = hv
	# soften so most steps are climbable; keep a few cliffs
	for it in 2:
		for p in g.all_cells():
			var hv := g.height(p)
			for nb in g.neighbors4(p):
				var hn := g.height(nb)
				if hv - hn >= 2 and rng.randf() < 0.7:
					g.t(p)["h"] = hn + 1
					hv = hn + 1


func _ground() -> void:
	var bd: Dictionary = BIOME[biome]
	for p in g.all_cells():
		var tl := g.t(p)
		var n2 := noise2.get_noise_2d(p.x * 1.3, p.y * 1.3) * 0.5 + 0.5
		tl["ground"] = bd["ground"]
		if n2 > 0.66:
			tl["ground"] = bd["patch"]
		elif n2 < 0.28:
			tl["ground"] = bd["patch2"]
		if biome == "autumn" and g.height(p) >= 2 and n2 > 0.5:
			tl["ground"] = "grass"
		if biome == "desert" and g.height(p) >= 3:
			tl["ground"] = "stonepath"


func _biome_features() -> void:
	match biome:
		"coast":
			_sea()
		"jungle":
			if explore:
				_canals(5, g.h / 2 - 3)
				_canals(g.h / 2 + 2, g.h - 9)
			else:
				_canals()
		"town", "hush_town":
			if explore:
				_streets(Rect2i(0, 0, g.w, g.h / 2))
				_streets(Rect2i(0, g.h / 2, g.w, g.h - g.h / 2))
			else:
				_streets()
		"autumn":
			if not explore:
				_path("dirt")
			if rng.randf() < 0.5:
				_stream()
		"desert":
			if not explore:
				_path("stonepath")
		"hush":
			_voids()
			if explore:
				_voids()
			else:
				_path("stonepath")


func _sea() -> void:
	# the sea eats the western edge with a ragged shore
	for y in g.h:
		var shore := 3 + int(noise.get_noise_1d(y * 7.0) * 2.5) + (1 if y < g.h / 3 else 0)
		for x in g.w:
			var p := Vector2i(x, y)
			var tl := g.t(p)
			if x < shore - 1:
				tl["h"] = 0
				tl["water"] = 2
				tl["ground"] = "wetsand"
			elif x < shore:
				tl["h"] = 0
				tl["water"] = 1
				tl["ground"] = "wetsand"
			elif x < shore + 2:
				tl["h"] = 0
				tl["ground"] = "wetsand"
			elif x < shore + 4:
				tl["h"] = mini(tl["h"], 1)
				tl["ground"] = "sand"
	# tide pools
	for i in rng.randi_range(1, 2) * (2 if explore else 1):
		var c := Vector2i(rng.randi_range(6, g.w - 3), rng.randi_range(3, g.h - 5))
		for p in g.cells_in_radius(c, 1):
			if rng.randf() < 0.7 and g.height(p) <= 1:
				g.t(p)["water"] = 1
				g.t(p)["h"] = 0
				g.t(p)["ground"] = "wetsand"


func _canals(y_lo := 5, y_hi := -1) -> void:
	# one horizontal and sometimes a vertical canal, with plank bridges
	if y_hi < 0:
		y_hi = g.h - 7
	var cy := rng.randi_range(y_lo, maxi(y_lo, y_hi))
	for x in g.w:
		var y := cy + int(noise.get_noise_1d(x * 9.0) * 1.5)
		for dy in 2:
			var p := Vector2i(x, y + dy)
			if g.inb(p):
				var tl := g.t(p)
				tl["h"] = 0
				tl["water"] = 2
				tl["ground"] = "mud"
	var bridges := [rng.randi_range(2, 5), rng.randi_range(g.w - 6, g.w - 3)]
	for bx in bridges:
		for y in range(cy - 2, cy + 4):
			for dx in 2:
				var p := Vector2i(bx + dx, y)
				if g.inb(p) and g.t(p)["water"] > 0:
					g.t(p)["water"] = 0
					g.t(p)["h"] = 1
					g.t(p)["ground"] = "planks"
	if rng.randf() < 0.5:
		var cx := rng.randi_range(4, g.w - 5)
		for y in range(maxi(0, y_lo - 5), cy):
			var p := Vector2i(cx, y)
			var tl := g.t(p)
			if tl["ground"] != "planks":
				tl["h"] = 0
				tl["water"] = 1
				tl["ground"] = "mud"


func _stream() -> void:
	var x0 := rng.randi_range(3, g.w - 4)
	for y in g.h:
		var x := x0 + int(noise.get_noise_1d(y * 6.0) * 3.0)
		var p := Vector2i(clampi(x, 0, g.w - 1), y)
		var tl := g.t(p)
		tl["water"] = 1
		tl["h"] = maxi(0, tl["h"] - 1)
		tl["ground"] = "mud"


func _streets(area := Rect2i()) -> void:
	if area.size == Vector2i.ZERO:
		area = Rect2i(0, 0, g.w, g.h)
	var ax := area.position.x
	var ay := area.position.y
	var sy := ay + rng.randi_range(5, maxi(5, area.size.y - 6))
	var sx := ax + rng.randi_range(4, maxi(4, area.size.x - 5))
	for p in g.all_cells():
		if not area.has_point(p):
			continue
		var tl := g.t(p)
		if absi(p.y - sy) <= 1 or absi(p.x - sx) <= 1:
			tl["ground"] = "cobble"
			tl["h"] = 0
		elif tl["ground"] == "cobble":
			tl["ground"] = "grass" if rng.randf() < 0.6 else "dirt"
	# houses in the quadrants
	var ex := area.end.x
	var ey := area.end.y
	var quads := [Rect2i(ax, ay, sx - ax - 1, sy - ay - 1), Rect2i(sx + 2, ay, ex - sx - 2, sy - ay - 1),
			Rect2i(ax, sy + 2, sx - ax - 1, ey - sy - 2), Rect2i(sx + 2, sy + 2, ex - sx - 2, ey - sy - 2)]
	for q in quads:
		if q.size.x >= 5 and q.size.y >= 4 and rng.randf() < 0.75:
			var hw := rng.randi_range(2, 3)
			var hh := 2
			var hx: int = q.position.x + rng.randi_range(1, q.size.x - hw - 1)
			var hy: int = q.position.y + rng.randi_range(0, maxi(0, q.size.y - hh - 1))
			_structure(Rect2i(hx, hy, hw, hh), "house")


func _path(ground: String) -> void:
	var x := rng.randi_range(4, g.w - 5)
	for y in g.h:
		x = clampi(x + rng.randi_range(-1, 1), 1, g.w - 2)
		for dx in 2:
			var p := Vector2i(x + dx, y)
			if g.inb(p) and g.t(p)["water"] == 0:
				g.t(p)["ground"] = ground


func _voids() -> void:
	for i in rng.randi_range(2, 4):
		var c := Vector2i(rng.randi_range(2, g.w - 3), rng.randi_range(4, g.h - 6))
		for p in g.cells_in_radius(c, rng.randi_range(1, 2)):
			if rng.randf() < 0.75:
				g.t(p)["water"] = 2
				g.t(p)["h"] = 0
				g.t(p)["ground"] = "void"


func _structure(r: Rect2i, kind: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if not g.inb(p):
				return
	var base_h := g.height(r.position)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var tl := g.t(p)
			tl["h"] = base_h
			tl["water"] = 0
			_set_prop(p, kind + "_part")
	var a := r.position
	g.t(a)["prop"] = kind
	g.t(a)["size"] = [r.size.x, r.size.y]


# ---------------------------------------------------------------- spawns
func _spawns(objective: String, squad_size: int) -> Dictionary:
	var out := {"player_spawns": [], "enemy_spawns": [], "edge_spawns": [], "player_facing": Vector2i(0, -1), "enemy_facing": Vector2i(0, 1)}
	# player: south edge, around the middle
	var cx := g.w / 2
	var zone: Array = []
	for y in range(g.h - 3, g.h):
		for x in range(cx - 3, cx + 4):
			zone.append(Vector2i(x, y))
	for p in zone:
		_clear(p)
		reserved[p] = true
		var tl := g.t(p)
		if tl["water"] > 0:
			tl["water"] = 0
			tl["h"] = maxi(tl["h"], 0)
			tl["ground"] = BIOME[biome]["patch2"]
	_flatten(zone)
	# extraction: the bottom row of the zone (or the far north for escort)
	var ext: Array = []
	if objective == "escort":
		for y in range(0, 2):
			for x in range(cx - 2, cx + 3):
				ext.append(Vector2i(x, y))
		_flatten(ext)
		for p in ext:
			_clear(p)
			reserved[p] = true
			if g.t(p)["water"] > 0:
				g.t(p)["water"] = 0
	else:
		for x in range(cx - 2, cx + 3):
			ext.append(Vector2i(x, g.h - 1))
	for p in ext:
		g.t(p)["extract"] = true
	var ps: Array = []
	for y in [g.h - 2, g.h - 3, g.h - 1]:
		for x in [cx, cx - 1, cx + 1, cx - 2, cx + 2, cx - 3, cx + 3]:
			var sp := Vector2i(x, y)
			if not g.standable(sp):
				continue
			if objective == "escort" and sp == Vector2i(cx, g.h - 2):
				continue  # the VIP stands here
			ps.append(sp)
	out["player_spawns"] = ps
	out["extract"] = ext
	# enemies: north half, spread out in small groups
	var cand: Array = []
	var ymax := g.h / 2 - (0 if objective != "escort" else -2)
	for y in range(0 if objective != "escort" else 3, ymax):
		for x in range(1, g.w - 1):
			var p := Vector2i(x, y)
			if g.standable(p) and g.t(p)["water"] == 0 and not reserved.has(p):
				cand.append(p)
	cand.shuffle()
	var groups: Array = []
	for i in 3:
		if cand.is_empty():
			break
		groups.append(cand[i % cand.size()])
	var es: Array = []
	for gc in groups:
		for p in g.cells_in_radius(gc, 2):
			if p in cand and not p in es:
				es.append(p)
	es.shuffle()
	# interleave groups so enemies spread out
	var sorted_es: Array = []
	for i in es.size():
		sorted_es.append(es[i])
	for p in cand:
		if not p in sorted_es:
			sorted_es.append(p)
	out["enemy_spawns"] = sorted_es.slice(0, 24)
	for p in sorted_es.slice(0, 24):
		_clear(p)
	# reinforcement edges: north and sides
	var edges: Array = []
	for x in range(g.w):
		edges.append(Vector2i(x, 0))
	for y in range(0, g.h / 2):
		edges.append(Vector2i(0, y))
		edges.append(Vector2i(g.w - 1, y))
	var good: Array = []
	for p in edges:
		if g.standable(p) and g.t(p)["water"] < 2:
			good.append(p)
	out["edge_spawns"] = good
	out["vip_spawn"] = Vector2i(cx, g.h - 2)
	out["object_spawn"] = Vector2i(cx, g.h - 5)
	return out


func _objective_props(objective: String, mission: Dictionary, out: Dictionary) -> void:
	if explore:
		_explore_objectives(objective, mission, out)
		return
	match objective:
		"retrieve":
			var n := int(mission.get("caches", 3))
			var spots := _far_spots(n, 3)
			for p in spots:
				_clear(p)
				g.t(p)["obj"] = {"kind": "cache"}
				reserved[p] = true
		"rescue":
			var spots := _far_spots(1, 2)
			if spots.size() > 0:
				var p: Vector2i = spots[0]
				_clear(p)
				g.t(p)["obj"] = {"kind": "captive", "name": "Captive"}
				reserved[p] = true
		"final":
			var spots := _far_spots(3, 4)
			for p in spots:
				_clear(p)
				g.t(p)["obj"] = {"kind": "page"}
				reserved[p] = true
		"defense":
			var op: Vector2i = out["object_spawn"]
			for p in g.cells_in_radius(op, 1):
				_clear(p)
				reserved[p] = true
			_flatten(g.cells_in_radius(op, 1))
		"escort":
			var vp: Vector2i = out["vip_spawn"]
			_clear(vp)
	# hidden chest (bonus objective)
	if rng.randf() < 0.6 and objective != "final":
		var spots := _far_spots(1, 2)
		if spots.size() > 0 and g.t(spots[0])["obj"].is_empty():
			_clear(spots[0])
			g.t(spots[0])["obj"] = {"kind": "chest"}
			reserved[spots[0]] = true
			out["has_chest"] = true


func _far_spots(n: int, min_gap: int) -> Array:
	var cand: Array = []
	for y in range(1, g.h - 5):
		for x in range(1, g.w - 1):
			var p := Vector2i(x, y)
			if g.standable(p) and g.t(p)["water"] == 0 and not reserved.has(p) and g.t(p)["prop"] == "":
				cand.append(p)
	cand.shuffle()
	var out: Array = []
	for p in cand:
		var ok := true
		for q in out:
			if Rules.distance(p, q) < min_gap + 2:
				ok = false
		if ok:
			out.append(p)
		if out.size() >= n:
			break
	return out


# ---------------------------------------------------------------- props
func _set_prop(p: Vector2i, id: String) -> void:
	var d: Array = PROPS[id]
	var tl := g.t(p)
	tl["prop"] = id
	tl["cover"] = d[0]
	tl["solid"] = d[1]
	tl["block"] = d[2]
	tl["flammable"] = d[3]


func _clear(p: Vector2i) -> void:
	if not g.inb(p):
		return
	var tl := g.t(p)
	if tl["prop"].ends_with("_part") or tl["prop"] in ["house", "hut", "arch", "bell_tower"]:
		return
	tl["prop"] = ""
	tl["cover"] = 0
	tl["solid"] = false
	tl["block"] = false
	tl["flammable"] = tl["ground"] in ["grass", "leaves", "moss"]


func _free(p: Vector2i) -> bool:
	return g.inb(p) and not reserved.has(p) and g.t(p)["prop"] == "" and g.t(p)["water"] == 0 and g.t(p)["obj"].is_empty() and not g.t(p)["extract"]


func _scatter_props() -> void:
	var table: Dictionary = {}
	match biome:
		"town":
			table = {"crate": 3, "crates": 2, "barrel": 3, "cart": 1, "stall": 2, "fence": 2, "well": 1, "lantern_post": 1, "tree": 2, "rock_s": 1, "wall_broken": 1}
		"hush_town":
			table = {"crate": 2, "barrel": 2, "wall_broken": 3, "wall": 2, "signpost": 1, "doorframe": 1, "tree_dead": 2, "lectern": 1, "rock_s": 2}
		"coast":
			table = {"rock_s": 4, "rock_l": 3, "log": 3, "post": 3, "crate": 2, "coral": 2, "boat": 1, "palm": 2, "barrel": 1}
		"jungle":
			table = {"tree": 5, "bush": 3, "crate": 2, "barrel": 1, "lantern_post": 2, "rock_s": 2, "log": 2, "reeds": 2, "stump": 1}
		"autumn":
			table = {"tree": 7, "stump": 2, "log": 3, "rock_s": 2, "rock_l": 2, "shrine": 1, "statue": 1, "mushrooms": 2, "bush": 3}
		"desert":
			table = {"wall": 3, "wall_broken": 3, "column_broken": 3, "pillar": 2, "rock_s": 2, "rock_l": 2, "tree_dead": 2, "pots": 2, "cactus": 1}
		"hush":
			table = {"wall_broken": 3, "doorframe": 2, "signpost": 2, "column_broken": 2, "tree_dead": 3, "rock_s": 2, "lectern": 1, "bell": 1, "crate": 1}
	# clustered placement for a hand-placed look
	var density: float = {"autumn": 0.2, "jungle": 0.17, "desert": 0.17, "coast": 0.14, "town": 0.13, "hush_town": 0.15, "hush": 0.15}[biome]
	var target := int(g.w * g.h * density)
	var placed := 0
	var tries := 0
	if biome == "jungle":
		for i in rng.randi_range(1, 2):
			var hp := Vector2i(rng.randi_range(1, g.w - 3), rng.randi_range(1, g.h / 2))
			var ok := true
			for p in [hp, hp + Vector2i(1, 0), hp + Vector2i(0, 1), hp + Vector2i(1, 1)]:
				if not _free(p) or g.t(p)["water"] > 0:
					ok = false
			if ok:
				_structure(Rect2i(hp, Vector2i(2, 2)), "hut")
	if biome == "desert" and rng.randf() < 0.7:
		var ap := Vector2i(rng.randi_range(2, g.w - 5), rng.randi_range(2, g.h / 2))
		if _free(ap) and _free(ap + Vector2i(2, 0)) and _free(ap + Vector2i(1, 0)):
			_set_prop(ap, "arch")
			_set_prop(ap + Vector2i(2, 0), "arch_part")
			g.t(ap)["size"] = [3, 1]
	if biome == "hush_town" or biome == "town":
		if rng.randf() < 0.3:
			var bp := Vector2i(rng.randi_range(2, g.w - 4), rng.randi_range(2, g.h / 2 - 2))
			if _free(bp):
				_set_prop(bp, "bell" if biome == "hush_town" else "well")
	while placed < target and tries < 900:
		tries += 1
		var seed_p := Vector2i(rng.randi_range(0, g.w - 1), rng.randi_range(0, g.h - 1))
		var cluster := rng.randi_range(1, 3)
		var id := _weighted(table)
		var p := seed_p
		for k in cluster:
			if _free(p) and _not_choking(p):
				_set_prop(p, id)
				placed += 1
			p += g.DIRS4[rng.randi() % 4]
			if rng.randf() < 0.4:
				id = _weighted(table)
	for p in g.all_cells():
		var tl := g.t(p)
		if tl["prop"] == "":
			tl["flammable"] = tl["ground"] in ["grass", "leaves", "moss"]


func _not_choking(p: Vector2i) -> bool:
	## avoid sealing corridors: at most 2 solid orthogonal neighbours
	var solid := 0
	for n in g.neighbors4(p):
		if g.t(n)["solid"] or g.t(n)["water"] >= 2:
			solid += 1
	return solid <= 1


func _weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += table[k]
	var r := rng.randf() * total
	for k in table:
		r -= table[k]
		if r <= 0:
			return k
	return table.keys()[0]


func _decorate() -> void:
	var decos: Dictionary = {
		"town": ["flowers", "tuft", "pebbles"], "hush_town": ["pebbles", "pages", "tuft"],
		"coast": ["shells", "tuft", "pebbles", "starfish"], "jungle": ["fern", "tuft", "flowers", "tuft"],
		"autumn": ["leaves", "tuft", "mushroom", "flowers"], "desert": ["bones", "pebbles", "skull", "tuft"],
		"hush": ["pages", "pebbles", "ash"],
	}
	var list: Array = decos[biome]
	for p in g.all_cells():
		var tl := g.t(p)
		if tl["prop"] != "" or tl["water"] > 0 or not tl["obj"].is_empty():
			continue
		if rng.randf() < 0.32:
			tl["deco"] = list[rng.randi() % list.size()]


func _flatten(cells: Array) -> void:
	if cells.is_empty():
		return
	var total := 0
	for p in cells:
		total += g.height(p)
	var avg := roundi(float(total) / cells.size())
	for p in cells:
		if g.inb(p):
			g.t(p)["h"] = avg


# ---------------------------------------------------------------- connectivity
func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var p: Vector2i = q.pop_back()
		for n in g.neighbors4(p):
			if seen.has(n):
				continue
			if g.step_cost(p, n) < 0 or g.step_cost(n, p) < 0:
				continue
			seen[n] = true
			q.append(n)
	return seen


func _ensure_connected(out: Dictionary) -> void:
	var start: Vector2i = out["player_spawns"][0]
	var important: Array = []
	important.append_array(out["enemy_spawns"].slice(0, 12 if not explore else 60))
	for p in g.all_cells():
		if not g.t(p)["obj"].is_empty():
			important.append(p)
	if out.has("extract"):
		important.append_array(out["extract"])
	for it in 6:
		var reach := _flood(start)
		var missing: Array = []
		for p in important:
			if not reach.has(p):
				missing.append(p)
		if missing.is_empty():
			break
		for p in missing:
			_carve(start, p)
	# drop enemy spawns that are still unreachable
	var reach2 := _flood(start)
	var es: Array = []
	for p in out["enemy_spawns"]:
		if reach2.has(p) and g.standable(p):
			es.append(p)
	out["enemy_spawns"] = es
	for pd in out.get("pods", []):
		pd["cells"] = pd["cells"].filter(func(c): return reach2.has(c) and g.standable(c))
		pd["route"] = pd["route"].filter(func(c): return reach2.has(c))
	var edges: Array = []
	for p in out["edge_spawns"]:
		if reach2.has(p):
			edges.append(p)
	out["edge_spawns"] = edges


func _carve(a: Vector2i, b: Vector2i, limit := 200) -> Array:
	var p := a
	var guard := 0
	var walked: Array = [a]
	while p != b and guard < limit:
		guard += 1
		var d := b - p
		var step := Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) or (absi(d.x) == absi(d.y) and rng.randf() < 0.5) else Vector2i(0, signi(d.y))
		var n := p + step
		var tn := g.t(n)
		if tn["prop"].ends_with("_part") or tn["prop"] in ["house", "hut", "arch", "bell_tower"]:
			# walk around structures
			step = Vector2i(step.y, step.x)
			n = p + step
			if not g.inb(n):
				n = p - step
			tn = g.t(n)
		if tn["solid"] and not (tn["prop"].ends_with("_part") or tn["prop"] in ["house", "hut", "arch"]):
			_clear(n)
		if tn["water"] >= 2:
			tn["water"] = 0
			tn["ground"] = "planks" if biome in ["jungle", "coast"] else BIOME[biome]["patch2"]
			tn["h"] = maxi(0, g.height(p) - 1)
		var dh := g.height(n) - g.height(p)
		if dh > 1:
			tn["h"] = g.height(p) + 1
		elif dh < -1:
			tn["h"] = g.height(p) - 1
		p = n
		walked.append(p)
	return walked


# ---------------------------------------------------------------- exploration maps
## Squad landing in the south, a clearing with the objective in the north and
## a winding trail between them, with patrolling pods along the way.
func _explore_layout(objective: String) -> Dictionary:
	var out := {"player_spawns": [], "enemy_spawns": [], "edge_spawns": [], "pods": [],
		"player_facing": Vector2i(0, -1), "enemy_facing": Vector2i(0, 1)}
	var cx := g.w / 2
	var zone: Array = []
	for y in range(g.h - 3, g.h):
		for x in range(cx - 3, cx + 4):
			zone.append(Vector2i(x, y))
	for p in zone:
		_clear(p)
		reserved[p] = true
		var tl := g.t(p)
		if tl["water"] > 0:
			tl["water"] = 0
			tl["ground"] = BIOME[biome]["patch2"]
	_flatten(zone)
	# the objective clearing
	var half := g.w / 2 - 6
	var oc := Vector2i(clampi(cx + rng.randi_range(-half, half), 6, g.w - 7), 3 if objective == "escort" else 5)
	var area_r := 4
	_clearing(oc, area_r)
	out["objective_area"] = {"center": oc, "r": area_r}
	# the trail
	var start := Vector2i(cx, g.h - 4)
	trail = _make_trail(start, oc + Vector2i(0, 1))
	out["route"] = trail
	# extraction: home in the south; escorts and rescues also leave from the north
	var ext: Array = []
	if objective in ["escort", "rescue"]:
		var north: Array = []
		for x in range(oc.x - 2, oc.x + 3):
			for y in range(0, 2):
				north.append(Vector2i(x, y))
		_flatten(north)
		for p in north:
			_clear(p)
			reserved[p] = true
			g.t(p)["water"] = 0
		ext.append_array(north)
	if objective != "escort":
		for x in range(cx - 2, cx + 3):
			ext.append(Vector2i(x, g.h - 1))
	for p in ext:
		g.t(p)["extract"] = true
	out["extract"] = ext
	var ps: Array = []
	for y in [g.h - 2, g.h - 3, g.h - 1]:
		for x in [cx, cx - 1, cx + 1, cx - 2, cx + 2, cx - 3, cx + 3]:
			var sp := Vector2i(x, y)
			if not g.standable(sp):
				continue
			if objective == "escort" and sp == Vector2i(cx, g.h - 2):
				continue
			ps.append(sp)
	out["player_spawns"] = ps
	out["vip_spawn"] = Vector2i(cx, g.h - 2)
	out["object_spawn"] = Vector2i(cx, g.h - 5)
	# pods: stations beside the trail, their beats crossing it; one guards the objective
	var pods: Array = []
	# trail pods spread over the stretch between the landing and the clearing
	var band: Array = []
	for i in trail.size():
		var c: Vector2i = trail[i]
		if Rules.chebyshev(c, start) >= 10 and Rules.chebyshev(c, oc) >= area_r + 3:
			band.append(i)
	var n_pods := clampi(band.size() / 6, 1, 3) if not band.is_empty() else 0
	for k in n_pods:
		var i: int = band[clampi(roundi((k + 0.5) * band.size() / float(n_pods)), 0, band.size() - 1)]
		var tp: Vector2i = trail[i]
		var side := -1 if rng.randf() < 0.5 else 1
		var station := _find_spot(tp + Vector2i(side * rng.randi_range(2, 4), rng.randi_range(-1, 1)), 3)
		if station == Vector2i(-1, -1):
			continue
		var beat: Array = []
		if rng.randf() < 0.75:
			var across := _find_spot(tp + Vector2i(-side * rng.randi_range(2, 4), rng.randi_range(-2, 2)), 3)
			var further := _find_spot(trail[mini(trail.size() - 1, i + 5)] + Vector2i(side * 2, 0), 3)
			for c in [station, across, further]:
				if c != Vector2i(-1, -1) and not c in beat:
					beat.append(c)
					reserved[c] = true   # keep the beat free of props
		pods.append({"cells": _pod_cells(station), "route": beat if beat.size() >= 2 else [], "objective": false})
	var guard := _find_spot(oc + Vector2i(0, -1), 2)
	pods.append({"cells": _pod_cells(guard if guard != Vector2i(-1, -1) else oc), "route": [], "objective": true})
	out["pods"] = pods
	var es: Array = []
	for pd in pods:
		es.append_array(pd["cells"])
	out["enemy_spawns"] = es
	return out


func _in_circle(p: Vector2i, c: Vector2i, r: int) -> bool:
	var d := p - c
	return d.x * d.x + d.y * d.y <= r * r + r


## A rough clearing: heights eased toward their average, water drained, the
## middle kept free of scattered props.
func _clearing(c: Vector2i, r: int) -> void:
	var cells: Array = []
	var total := 0
	for p in g.cells_in_radius(c, r):
		if _in_circle(p, c, r):
			cells.append(p)
			total += g.height(p)
	var avg := roundi(float(total) / maxf(cells.size(), 1))
	for p in cells:
		var tl := g.t(p)
		tl["h"] = avg if Rules.chebyshev(p, c) <= 2 else roundi((tl["h"] + avg) / 2.0)
		if tl["water"] > 0:
			tl["water"] = 0
			tl["ground"] = BIOME[biome]["patch2"]
		if Rules.chebyshev(p, c) <= 2:
			_clear(p)
			reserved[p] = true


## Carves a walkable, bridged, two-wide trail through the control points and
## lines it with signposts. Returns the trail cells from start to end.
func _make_trail(a: Vector2i, b: Vector2i) -> Array:
	var pts: Array = [a]
	var n := maxi(2, absi(b.y - a.y) / 6)
	var sway := -1 if rng.randf() < 0.5 else 1
	for i in range(1, n):
		# swing from side to side on the way north
		var f := float(i) / n
		var x := clampi(roundi(lerpf(a.x, b.x, f)) + sway * rng.randi_range(3, 6), 4, g.w - 5)
		sway = -sway
		pts.append(Vector2i(x, roundi(lerpf(a.y, b.y, f))))
	pts.append(b)
	var cells: Array = []
	for i in pts.size() - 1:
		for c in _carve(pts[i], pts[i + 1]):
			if cells.is_empty() or cells[-1] != c:
				cells.append(c)
	var ground: String = TRAIL_GROUND.get(biome, "dirt")
	for c in cells:
		for q in [c, c + Vector2i(1, 0)]:
			if not g.inb(q):
				continue
			var tl := g.t(q)
			if tl["prop"].ends_with("_part") or tl["prop"] in ["house", "hut", "arch", "bell_tower"]:
				continue
			_clear(q)
			if tl["water"] == 0 and tl["ground"] != "planks":
				tl["ground"] = ground
			reserved[q] = true
	# waymarks every few steps, just off the trail
	for i in range(6, cells.size() - 4, 8):
		var c: Vector2i = cells[i]
		for q in [c + Vector2i(-1, 0), c + Vector2i(2, 0), c + Vector2i(-1, 1)]:
			if g.inb(q) and _free(q) and g.standable(q) and _not_choking(q):
				_set_prop(q, "lantern_post" if biome in ["town", "hush_town", "jungle"] else "signpost")
				reserved[q] = true
				break
	return cells


## The free, dry, standable cell nearest `near` within `r` (not on the trail).
func _find_spot(near: Vector2i, r: int) -> Vector2i:
	near = Vector2i(clampi(near.x, 1, g.w - 2), clampi(near.y, 1, g.h - 2))
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for c in g.cells_in_radius(near, r):
		if not g.standable(c) or g.t(c)["water"] > 0 or reserved.has(c) or g.t(c)["prop"] != "" or g.t(c)["extract"]:
			continue
		var d := float(Rules.distance(c, near)) + rng.randf() * 0.5
		if d < bd:
			bd = d
			best = c
	return best


## A station and the free cells around it where a pod stands.
func _pod_cells(station: Vector2i) -> Array:
	var out: Array = [station]
	reserved[station] = true
	var around := g.cells_in_radius(station, 2)
	around.shuffle()
	for c in around:
		if out.size() >= 6:
			break
		if c == station or not g.standable(c) or g.t(c)["water"] > 0 or reserved.has(c) or g.t(c)["prop"] != "":
			continue
		out.append(c)
		reserved[c] = true
	return out


func _explore_objectives(objective: String, mission: Dictionary, out: Dictionary) -> void:
	var oc: Vector2i = out["objective_area"]["center"]
	var r := int(out["objective_area"]["r"])
	match objective:
		"retrieve":
			var n := int(mission.get("caches", 3))
			var cand: Array = []
			for p in g.cells_in_radius(oc, r - 1):
				if _in_circle(p, oc, r - 1) and g.standable(p) and g.t(p)["water"] == 0 and not p in trail and g.t(p)["prop"] == "" \
						and not g.t(p)["extract"] and p.y >= 1:
					cand.append(p)
			cand.shuffle()
			var placed: Array = []
			for p in cand:
				var ok := true
				for q in placed:
					if Rules.chebyshev(p, q) < 2:
						ok = false
				if ok:
					placed.append(p)
					_clear(p)
					g.t(p)["obj"] = {"kind": "cache"}
					reserved[p] = true
				if placed.size() >= n:
					break
		"rescue":
			var spot := _find_spot(oc, 2)
			if spot == Vector2i(-1, -1):
				spot = oc
			_clear(spot)
			g.t(spot)["obj"] = {"kind": "captive", "name": "Captive"}
			reserved[spot] = true
		"escort":
			_clear(out["vip_spawn"])
	if rng.randf() < 0.6:
		var spots := _far_spots(1, 2)
		if spots.size() > 0 and g.t(spots[0])["obj"].is_empty():
			_clear(spots[0])
			g.t(spots[0])["obj"] = {"kind": "chest"}
			reserved[spots[0]] = true
			out["has_chest"] = true


## Tents, crates and a fire around the objective clearing.
func _camp(c: Vector2i, r: int) -> void:
	var pool: Array = CAMP.get(biome, CAMP["town"])
	var ring: Array = []
	for p in g.cells_in_radius(c, r):
		var d := Rules.chebyshev(p, c)
		if d >= 3 and d <= r and _in_circle(p, c, r):
			ring.append(p)
	ring.shuffle()
	var placed := 0
	for p in ring:
		if placed >= 6:
			break
		if _free(p) and g.standable(p) and _not_choking(p) and not p in trail:
			_set_prop(p, pool[placed % pool.size()] if placed < pool.size() else pool[rng.randi() % pool.size()])
			placed += 1
	if not biome in ["hush", "hush_town"]:
		for p in [c + Vector2i(2, 2), c + Vector2i(-2, 2), c + Vector2i(2, -2)]:
			if g.inb(p) and g.t(p)["prop"] == "" and g.t(p)["obj"].is_empty() and g.standable(p) and not p in trail:
				_set_prop(p, "campfire")
				break
