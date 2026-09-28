class_name TileOverlay
extends Node3D
## Coloured tile highlights: movement range, target range, AoE, path,
## zones of control, extraction zone and the hover cursor.

const LAYERS := ["extract", "move", "zoc", "range", "aoe", "path", "cursor", "fx"]
const EDGE := 1.0 / 24.0

var map_view: BattleMapView
var layers := {}
var mat_cache := {}


func setup(mv: BattleMapView) -> void:
	map_view = mv
	for n in LAYERS:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _mat(LAYERS.find(n))
		add_child(mi)
		layers[n] = mi


func _mat(priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = priority - 20
	return m


func _y(p: Vector2i) -> float:
	var g := map_view.grid
	if int(g.t(p)["water"]) > 0:
		return TerrainBuilder.water_y(g, p) + 0.02
	return TerrainBuilder.top_y(g, p) + 0.02


func clear(layer: String) -> void:
	layers[layer].mesh = null


## Fill + border on the outline of the region.
func show_cells(layer: String, cells: Array, fill: Color, border: Color, inset := 0.0) -> void:
	if cells.is_empty():
		clear(layer)
		return
	var set := {}
	for c in cells:
		set[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cells:
		var y := _y(c)
		var x0: float = c.x + inset
		var z0: float = c.y + inset
		var x1: float = c.x + 1 - inset
		var z1: float = c.y + 1 - inset
		_rect(st, x0, z0, x1, z1, y, fill)
		if border.a > 0:
			var e := EDGE * 1.0
			if not set.has(c + Vector2i(0, -1)):
				_rect(st, x0, z0, x1, z0 + e, y + 0.002, border)
			if not set.has(c + Vector2i(0, 1)):
				_rect(st, x0, z1 - e, x1, z1, y + 0.002, border)
			if not set.has(c + Vector2i(-1, 0)):
				_rect(st, x0, z0, x0 + e, z1, y + 0.002, border)
			if not set.has(c + Vector2i(1, 0)):
				_rect(st, x1 - e, z0, x1, z1, y + 0.002, border)
	layers[layer].mesh = st.commit()


func _rect(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, c: Color) -> void:
	for v in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.set_color(c)
		st.add_vertex(v)


## Path: small squares at each step and a larger one at the destination.
func show_path(path: Array, color: Color, danger_cells := []) -> void:
	if path.is_empty():
		clear("path")
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in path.size():
		var c: Vector2i = path[i]
		var y := _y(c) + 0.01
		var r := 0.09 if i < path.size() - 1 else 0.3
		var col := color
		if c in danger_cells:
			col = Color(1.0, 0.35, 0.25, 0.95)
		if i == path.size() - 1:
			# destination: hollow square
			var e := 0.06
			_rect(st, c.x + 0.5 - r, c.y + 0.5 - r, c.x + 0.5 + r, c.y + 0.5 - r + e, y, col)
			_rect(st, c.x + 0.5 - r, c.y + 0.5 + r - e, c.x + 0.5 + r, c.y + 0.5 + r, y, col)
			_rect(st, c.x + 0.5 - r, c.y + 0.5 - r, c.x + 0.5 - r + e, c.y + 0.5 + r, y, col)
			_rect(st, c.x + 0.5 + r - e, c.y + 0.5 - r, c.x + 0.5 + r, c.y + 0.5 + r, y, col)
		else:
			_rect(st, c.x + 0.5 - r, c.y + 0.5 - r, c.x + 0.5 + r, c.y + 0.5 + r, y, col)
	layers["path"].mesh = st.commit()


func show_cursor(c: Vector2i, color: Color) -> void:
	if c == Vector2i(-1, -1):
		clear("cursor")
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := _y(c) + 0.015
	var e := 2.0 / 24.0
	var l := 0.28
	# corner brackets
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var x0: float = c.x + corner.x
		var z0: float = c.y + corner.y
		var sx := 1.0 if corner.x == 0 else -1.0
		var sz := 1.0 if corner.y == 0 else -1.0
		_rect(st, minf(x0, x0 + sx * l), minf(z0, z0 + sz * e), maxf(x0, x0 + sx * l), maxf(z0, z0 + sz * e), y, color)
		_rect(st, minf(x0, x0 + sx * e), minf(z0, z0 + sz * l), maxf(x0, x0 + sx * e), maxf(z0, z0 + sz * l), y, color)
	layers["cursor"].mesh = st.commit()
