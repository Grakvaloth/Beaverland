extends Node

enum Type { LUMBERJACK, STORAGE, HOUSE, WATERWHEEL, WATER_PUMP, WATER_STORAGE }

const TYPE_NAMES: Dictionary = {
	Type.LUMBERJACK:    "Holzfäller",
	Type.STORAGE:       "Lager",
	Type.HOUSE:         "Haus",
	Type.WATERWHEEL:    "Wasserrad",
	Type.WATER_PUMP:    "Pumpe",
	Type.WATER_STORAGE: "Wasserspeicher",
}
const TYPE_COLORS: Dictionary = {
	Type.LUMBERJACK:    Color(0.55, 0.35, 0.15),
	Type.STORAGE:       Color(0.60, 0.60, 0.60),
	Type.HOUSE:         Color(0.90, 0.80, 0.20),
	Type.WATERWHEEL:    Color(0.20, 0.50, 0.90),
	Type.WATER_PUMP:    Color(0.10, 0.40, 0.75),
	Type.WATER_STORAGE: Color(0.25, 0.70, 0.90),
}

const TYPE_DESC: Dictionary = {
	Type.LUMBERJACK:    "Holzt Bäume in der Umgebung ab.",
	Type.STORAGE:       "Lagert Ressourcen sicher.",
	Type.HOUSE:         "Bietet Bibern eine Unterkunft.",
	Type.WATERWHEEL:    "Erzeugt Energie aus fließendem Wasser.",
	Type.WATER_PUMP:    "Entnimmt Wasser aus dem Grid und füllt einen Wasserspeicher.",
	Type.WATER_STORAGE: "Lagert Wasser als Rohstoff für Biber.",
}

var _data:     Dictionary = {}              # Vector2i → Type
var _meshes:   Dictionary = {}              # Vector2i → Node3D
var _selected: Vector2i   = Vector2i(-1,-1)

signal selection_changed(key: Vector2i)

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

func select(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if _selected == key:
		return
	_clear_highlight(_selected)
	_selected = key
	_set_highlight(key, Color(1.0, 0.9, 0.2))
	selection_changed.emit(key)

func deselect() -> void:
	_clear_highlight(_selected)
	_selected = Vector2i(-1, -1)
	selection_changed.emit(_selected)

func get_selected() -> Vector2i:
	return _selected

func get_info(x: int, z: int) -> Dictionary:
	var key := Vector2i(x, z)
	if not _data.has(key):
		return {}
	var t: Type = _data[key]
	return {
		"name":     TYPE_NAMES[t],
		"type":     int(t),
		"desc":     TYPE_DESC[t],
		"position": "%d / %d" % [x, z],
	}

func _set_highlight(key: Vector2i, color: Color) -> void:
	if not _meshes.has(key):
		return
	var root: Node3D = _meshes[key]
	if not is_instance_valid(root):
		return
	var mi := root.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mi.material_override = mat

func _clear_highlight(key: Vector2i) -> void:
	if not _data.has(key) or not _meshes.has(key):
		return
	var root: Node3D = _meshes[key]
	if not is_instance_valid(root):
		return
	var mi := root.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		var t: Type = _data[key]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TYPE_COLORS[t]
		mi.material_override = mat

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

	_spawn_component(root_node, x, z, type)

func _spawn_component(root_node: Node3D, x: int, z: int, type: Type) -> void:
	var comp_scene: PackedScene = null
	if type == Type.WATER_PUMP:
		comp_scene = preload("res://scenes/buildings/water_pump.tscn")
	elif type == Type.WATER_STORAGE:
		comp_scene = preload("res://scenes/buildings/water_storage.tscn")
	if comp_scene == null:
		return

	var comp: Node3D = comp_scene.instantiate()
	root_node.add_child(comp)

	if comp is WaterPump:
		var pump := comp as WaterPump
		pump.grid_x = x
		pump.grid_z = z
		var nearest_storage := _find_nearest_storage(x, z)
		if nearest_storage != null:
			pump.target_storage = pump.get_path_to(nearest_storage)

func _find_nearest_storage(x: int, z: int) -> WaterStorage:
	var best: WaterStorage = null
	var best_d: float = INF
	for node in get_tree().get_nodes_in_group("water_storage"):
		var s := node as WaterStorage
		if s == null:
			continue
		var gp := s.global_position
		var d := Vector2(gp.x - float(x), gp.z - float(z)).length()
		if d < best_d:
			best_d = d
			best = s
	return best
