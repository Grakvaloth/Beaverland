class_name Terrain
extends Node3D

const GRID_SIZE_X := 20
const GRID_SIZE_Z := 20
const MAX_HEIGHT   := 20
const CELL_GAP     := 0.0

var _cells:       Dictionary = {}
var _terrain_mat: ShaderMaterial = null

const _TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float max_height = 20.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float h = clamp(world_y / max_height, 0.0, 1.0);

	vec3 grass = vec3(0.20, 0.50, 0.14);
	vec3 dirt  = vec3(0.56, 0.42, 0.20);
	vec3 rock  = vec3(0.48, 0.46, 0.42);
	vec3 snow  = vec3(0.92, 0.94, 0.96);

	vec3 col;
	if (h < 0.25) {
		col = mix(grass, dirt, h / 0.25);
	} else if (h < 0.55) {
		col = mix(dirt, rock, (h - 0.25) / 0.30);
	} else {
		col = mix(rock, snow, (h - 0.55) / 0.45);
	}

	// Leichte Rasterung für Tiefenwirkung
	float grid = mod(floor(world_y + 0.5), 2.0) * 0.04;
	ALBEDO = col - vec3(grid);
	ROUGHNESS = 0.92;
	METALLIC  = 0.0;
}
"""

func _ready() -> void:
	add_to_group("terrain")
	var shader := Shader.new()
	shader.code = _TERRAIN_SHADER
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = shader
	_terrain_mat.set_shader_parameter("max_height", float(MAX_HEIGHT))
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
	mi.mesh              = mesh
	mi.material_override = _terrain_mat
	body.add_child(mi)

	var col   := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape  = shape
	body.add_child(col)

	_cells[Vector3i(x, y, z)] = body
	return body

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
		mi.material_override = _terrain_mat
