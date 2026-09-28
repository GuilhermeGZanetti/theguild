class_name PropLib
extends RefCounted
## Loads prop meshes exported from Blender and gives them region palettes.

const SHADER := preload("res://shaders/prop.gdshader")
const VARIANTS := {
	"rock_s": ["rock_s", "rock_s_1"], "rock_l": ["rock_l", "rock_l_1"], "boulder": ["boulder", "boulder_1"],
	"wall": ["wall", "wall_1"], "wall_broken": ["wall_broken", "wall_broken_1"], "column_broken": ["column_broken", "column_broken_1"],
	"bush": ["bush", "bush_1"], "tree_dead": ["tree_dead", "tree_dead_1"],
}
const TREES := {
	"town": ["tree_oak", "tree_oak_1"], "hush_town": ["tree_dead", "tree_oak"], "coast": ["palm", "tree_oak"],
	"jungle": ["tree_jungle", "tree_jungle_1"], "autumn": ["tree_autumn", "tree_autumn_1", "tree_autumn_2"],
	"desert": ["tree_dead", "tree_dead_1"], "hush": ["tree_dead", "tree_dead_1"],
}

static var _meshes := {}
static var _mats := {}
static var noise: Texture2D


static func biome_of_region(region: String) -> String:
	return DB.regions.get(region, {}).get("biome", "town")


static func mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var path := "res://assets/models/props/%s.glb" % id
	var m: Mesh = null
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var inst := scene.instantiate()
		var mi := _find_mesh(inst)
		if mi:
			m = mi.mesh
		inst.free()
	_meshes[id] = m
	return m


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


static func material(biome: String) -> ShaderMaterial:
	if _mats.has(biome):
		return _mats[biome]
	if noise == null:
		noise = load("res://assets/textures/noise.png")
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var p := "res://assets/textures/props_%s.png" % biome
	if not ResourceLoader.exists(p):
		p = "res://assets/textures/props_town.png"
	m.set_shader_parameter("palette", load(p))
	m.set_shader_parameter("noise_tex", noise)
	_mats[biome] = m
	return m


static func resolve(id: String, biome: String, rng: RandomNumberGenerator = null) -> String:
	var pick := func(arr: Array) -> String:
		return arr[(rng.randi() if rng else randi()) % arr.size()]
	if id == "tree":
		return pick.call(TREES.get(biome, TREES["town"]))
	if id == "palm":
		return "palm"
	if VARIANTS.has(id):
		return pick.call(VARIANTS[id])
	return id


static func instance(id: String, biome: String, rng: RandomNumberGenerator = null, own_material := false) -> MeshInstance3D:
	var real := resolve(id, biome, rng)
	var m := mesh(real)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if own_material:
		mi.material_override = material(biome).duplicate()
	else:
		mi.material_override = material(biome)
	mi.set_meta("prop_id", real)
	return mi
