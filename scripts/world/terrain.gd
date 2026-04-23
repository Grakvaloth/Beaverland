class_name Terrain
extends Node3D

const GRID_SIZE_X := 20
const GRID_SIZE_Z := 20
const MAX_HEIGHT   := 20
const CELL_GAP     := 0.05

var _cells: Dictionary = {}

func _ready() -> void:
	add_to_group("terrain")
	_generate_grid()

func _generate_grid() -> void:
	for x in range(GRID_SIZE_X):
		for z in range(GRID_SIZE_Z):
			_create_cell(x, 0, z)

func _create_cell(x: int, y: int, z: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(x, y, z)
	body.set_meta("grid_x", x)
	body.set_meta("grid_y", y)
	body.set_meta("grid_z", z)
	add_child(body)

	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var s    := 1.0 - CELL_GAP
	mesh.size = Vector3(s, 1.0, s)
	mi.mesh   = mesh
	mi.material_override = _make_height_mat(y)
	body.add_child(mi)

	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape  = shape
	body.add_child(col)

	_cells[Vector3i(x, y, z)] = body
	return body

func _make_height_mat(y: int) -> StandardMaterial3D:
	var t   := float(y) / float(MAX_HEIGHT - 1)
	var col := Color(0.22, 0.48, 0.18).lerp(Color(0.85, 0.82, 0.80), t)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	return mat

func get_cell_at(x: int, y: int, z: int) -> Node3D:
	return _cells.get(Vector3i(x, y, z), null)

func get_height_at(x: int, z: int) -> int:
	for y in range(MAX_HEIGHT, -1, -1):
		if _cells.has(Vector3i(x, y, z)):
			return y + 1
	return 0

func set_cell_height(x: int, z: int, height: int) -> void:
	height = clampi(height, 0, MAX_HEIGHT)
	for y in range(MAX_HEIGHT + 1):
		var key := Vector3i(x, y, z)
		if _cells.has(key):
			_cells[key].queue_free()
			_cells.erase(key)
	for y in range(height):
		_create_cell(x, y, z)

func set_cell_color_override(x: int, z: int, color: Color) -> void:
	var h := get_height_at(x, z)
	if h == 0:
		return
	var body := _cells.get(Vector3i(x, h - 1, z)) as StaticBody3D
	if not body:
		return
	var mi := body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mi.material_override = mat

func clear_cell_color_override(x: int, z: int) -> void:
	var h := get_height_at(x, z)
	if h == 0:
		return
	var body := _cells.get(Vector3i(x, h - 1, z)) as StaticBody3D
	if not body:
		return
	var mi := body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		mi.material_override = _make_height_mat(h - 1)
