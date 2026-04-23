extends Node

enum Type { LUMBERJACK, STORAGE, HOUSE, WATERWHEEL }

const TYPE_NAMES: Dictionary = {
	Type.LUMBERJACK: "Holzfäller",
	Type.STORAGE:    "Lager",
	Type.HOUSE:      "Haus",
	Type.WATERWHEEL: "Wasserrad",
}
const TYPE_COLORS: Dictionary = {
	Type.LUMBERJACK: Color(0.55, 0.35, 0.15),
	Type.STORAGE:    Color(0.60, 0.60, 0.60),
	Type.HOUSE:      Color(0.90, 0.80, 0.20),
	Type.WATERWHEEL: Color(0.20, 0.50, 0.90),
}

var _data:   Dictionary = {}   # Vector2i → Type
var _meshes: Dictionary = {}   # Vector2i → Node3D

func place_building(x: int, z: int, type: Type) -> bool:
	var key := Vector2i(x, z)
	if _data.has(key):
		return false
	_data[key] = type
	_spawn_mesh(x, z, type)
	return true

func remove_building(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if not _data.has(key):
		return
	_data.erase(key)
	if _meshes.has(key):
		var node: Node3D = _meshes[key]
		if is_instance_valid(node):
			node.queue_free()
		_meshes.erase(key)

func has_building(x: int, z: int) -> bool:
	return _data.has(Vector2i(x, z))

func clear_all() -> void:
	for key in _meshes:
		var node: Node3D = _meshes[key]
		if is_instance_valid(node):
			node.queue_free()
	_meshes.clear()
	_data.clear()

func get_all_buildings() -> Array:
	var result: Array = []
	for key in _data:
		result.append({"x": key.x, "z": key.y, "type": int(_data[key])})
	return result

func restore_buildings(buildings: Array) -> void:
	clear_all()
	for entry: Dictionary in buildings:
		place_building(int(entry["x"]), int(entry["z"]), int(entry["type"]) as Type)

func _spawn_mesh(x: int, z: int, type: Type) -> void:
	var terrain: Terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	var h := 1.0
	if terrain:
		h = float(terrain.get_height_at(x, z))

	var root_node := Node3D.new()
	root_node.position = Vector3(float(x), h, float(z))

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.85, 1.0, 0.85)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TYPE_COLORS[type]
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.5, 0.0)
	root_node.add_child(mi)

	var lbl := Label3D.new()
	lbl.text = TYPE_NAMES[type]
	lbl.font_size = 28
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, 1.4, 0.0)
	root_node.add_child(lbl)

	get_tree().current_scene.add_child(root_node)
	_meshes[Vector2i(x, z)] = root_node
