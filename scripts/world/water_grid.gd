class_name WaterGrid
extends Node3D

const GRID_W        := 20
const GRID_H        := 20
const EVAP_RATE     := 0.0003
const TICKS_PER_SIM := 4      # Simulation alle 4 Physics-Frames

var source_rate:  float = 0.06
var _drought:     bool  = false

var _water:        Dictionary = {}  # Vector2i(x,z) -> float
var _meshes:       Dictionary = {}  # Vector2i(x,z) -> MeshInstance3D
var _sources:      Array[Vector2i] = []
var _terrain:      Terrain = null
var _tick:         int = 0
var _water_mat:    StandardMaterial3D

func _ready() -> void:
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.15, 0.45, 0.9, 0.65)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for x in range(GRID_W):
		for z in range(GRID_H):
			var key := Vector2i(x, z)
			_water[key] = 0.0
			_meshes[key] = _make_water_mesh(x, z)

	await get_tree().process_frame
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_load_sources_from_map()

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % TICKS_PER_SIM == 0:
		_simulate()
	_update_visuals()

# ── Simulation ──────────────────────────────────────────────

func _simulate() -> void:
	var next := _water.duplicate()

	# Quellen füllen (während Dürre kein Nachschub)
	if not _drought:
		for src in _sources:
			next[src] = minf(1.0, next.get(src, 0.0) + source_rate)

	# Fluss: von höherem Gesamtniveau zu niedrigerem
	for key in _water:
		var lvl: float = _water.get(key, 0.0)
		if lvl < 0.002:
			continue
		var my_total := _surface(key) + lvl
		for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nk: Vector2i = key + dir
			if nk.x < 0 or nk.y < 0 or nk.x >= GRID_W or nk.y >= GRID_H:
				continue
			var n_total: float = _surface(nk) + float(_water.get(nk, 0.0))
			if my_total > n_total + 0.05:
				var flow: float = minf((my_total - n_total) * 0.25, float(next.get(key, 0.0)))
				next[key]  = maxf(0.0, float(next.get(key, 0.0)) - flow)
				next[nk]   = minf(1.0, float(next.get(nk,  0.0)) + flow)

	# Verdunstung (während Dürre 5× schneller)
	var evap := EVAP_RATE * (5.0 if _drought else 1.0)
	for key in next:
		if not (key in _sources):
			next[key] = maxf(0.0, next.get(key, 0.0) - evap)

	_water = next

func _surface(key: Vector2i) -> float:
	if _terrain:
		return float(_terrain.get_height_at(key.x, key.y))
	return 1.0

# ── Visualisierung ──────────────────────────────────────────

func _update_visuals() -> void:
	for key in _meshes:
		var lvl: float = _water.get(key, 0.0)
		var mi: MeshInstance3D = _meshes[key]
		if lvl > 0.02:
			var surf := _surface(key)
			mi.position = Vector3(key.x, surf + lvl * 0.5 - 0.5, key.y)
			mi.scale.y  = lvl
			mi.visible  = true
		else:
			mi.visible = false

func _make_water_mesh(x: int, z: int) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 1.0, 0.92)
	mi.mesh              = mesh
	mi.material_override = _water_mat
	mi.position          = Vector3(x, 0.0, z)
	mi.visible           = false
	add_child(mi)
	return mi

# ── Quellen ─────────────────────────────────────────────────

func _load_sources_from_map() -> void:
	var map_name := SaveManager.get_current_map_name()
	if map_name.is_empty():
		return
	var data := SaveManager.load_map(map_name)
	for cell: Dictionary in data.get("cells", []):
		if cell.get("is_source", false):
			set_source(int(cell["x"]), int(cell["z"]), true)

func set_drought(active: bool) -> void:
	_drought = active

func set_source(x: int, z: int, enabled: bool) -> void:
	var key := Vector2i(x, z)
	if enabled:
		if not key in _sources:
			_sources.append(key)
	else:
		_sources.erase(key)

# ── Speichern/Laden-Helfer ──────────────────────────────────

func get_all_cells_with_water() -> Array:
	var result: Array = []
	for key in _water:
		if _water[key] > 0.01:
			result.append({"x": key.x, "z": key.y, "level": _water[key]})
	return result

func restore_water(cells: Array) -> void:
	for entry: Dictionary in cells:
		var key := Vector2i(int(entry["x"]), int(entry["z"]))
		_water[key] = float(entry.get("level", 0.0))
