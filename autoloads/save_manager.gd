extends Node

const VERSION := 1
const MAPS_DIR := "user://maps/"
const SAVES_DIR := "user://saves/"
const AUTOSAVE_SLOT := 0

var _autosave_timer: Timer
var _current_map_name: String = ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAPS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVES_DIR))
	_setup_autosave()

func _setup_autosave() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 300.0  # 5 Spielminuten = 5 * 60s
	_autosave_timer.autostart = false
	_autosave_timer.timeout.connect(func() -> void: save_game(AUTOSAVE_SLOT))
	add_child(_autosave_timer)

# ── MAP SPEICHERN ──────────────────────────────────────────

func save_map(map_data: Dictionary, map_name: String) -> void:
	var path := MAPS_DIR + map_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Kann Map nicht speichern: " + path)
		return
	file.store_string(JSON.stringify(map_data, "\t"))
	file.close()

func load_map(map_name: String) -> Dictionary:
	var path := MAPS_DIR + map_name + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: Map nicht gefunden: " + path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

func delete_map(map_name: String) -> void:
	var path := MAPS_DIR + map_name + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func list_maps() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(MAPS_DIR)
	if not dir:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			result.append(fname.trim_suffix(".json"))
		fname = dir.get_next()
	dir.list_dir_end()
	return result

# ── SPIELSTAND SPEICHERN ────────────────────────────────────

func save_game(slot: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var data := {
		"version": VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"map_name": _current_map_name,
		"season": _collect_season_data(),
		"water":   _collect_water_data(),
		"buildings": _collect_building_data(),
	}

	var path := SAVES_DIR + "save_slot_%d.json" % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Kann Slot %d nicht speichern" % slot)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_game(slot: int) -> void:
	var path := SAVES_DIR + "save_slot_%d.json" % slot
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: Slot %d nicht gefunden" % slot)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return

	var data: Dictionary = parsed
	_current_map_name = data.get("map_name", "")

	# 1. Map laden & Terrain aufbauen
	if _current_map_name != "":
		var map_data := load_map(_current_map_name)
		_restore_terrain(map_data)

	# 2. Wasser wiederherstellen (TODO: WaterGrid)
	_restore_water(data.get("water", []))

	# 3. Gebäude platzieren (TODO: BuildingManager)
	_restore_buildings(data.get("buildings", []))

	# 4. SeasonManager-State setzen (TODO: SeasonManager)
	_restore_season(data.get("season", {}))

func save_game_named(save_name: String) -> void:
	if save_name.strip_edges().is_empty():
		return
	var data := {
		"version": VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"map_name": _current_map_name,
		"season": _collect_season_data(),
		"water":   _collect_water_data(),
		"buildings": _collect_building_data(),
	}
	var path := SAVES_DIR + save_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Kann '%s' nicht speichern" % save_name)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_game_named(save_name: String) -> void:
	var path := SAVES_DIR + save_name + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: '%s' nicht gefunden" % save_name)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	_current_map_name = data.get("map_name", "")
	if _current_map_name != "":
		var map_data := load_map(_current_map_name)
		_restore_terrain(map_data)
	_restore_water(data.get("water", []))
	_restore_buildings(data.get("buildings", []))
	_restore_season(data.get("season", {}))

func delete_save_named(save_name: String) -> void:
	var path := SAVES_DIR + save_name + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func list_saves_named() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVES_DIR)
	if not dir:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json") and not fname.begins_with("save_slot_"):
			var path := SAVES_DIR + fname
			var entry := {"name": fname.trim_suffix(".json"), "timestamp": ""}
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				var p: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				if p is Dictionary:
					entry["timestamp"] = (p as Dictionary).get("timestamp", "")
			result.append(entry)
		fname = dir.get_next()
	dir.list_dir_end()
	return result

func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(1, 6):
		var path := SAVES_DIR + "save_slot_%d.json" % slot
		var entry := {"slot": slot, "map": "", "timestamp": "", "empty": true}
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				entry["map"] = parsed.get("map_name", "")
				entry["timestamp"] = parsed.get("timestamp", "")
				entry["empty"] = false
		result.append(entry)
	return result

func has_autosave() -> bool:
	return FileAccess.file_exists(SAVES_DIR + "save_slot_%d.json" % AUTOSAVE_SLOT)

func start_autosave_timer() -> void:
	_autosave_timer.start()

func stop_autosave_timer() -> void:
	_autosave_timer.stop()

func set_current_map(map_name: String) -> void:
	_current_map_name = map_name

func get_current_map_name() -> String:
	return _current_map_name

# ── Private Helfer (TODO-Platzhalter) ───────────────────────

func _collect_season_data() -> Dictionary:
	return SeasonManager.get_save_data()

func _collect_water_data() -> Array:
	var wg: WaterGrid = _find_water_grid()
	if wg:
		return wg.get_all_cells_with_water()
	return []

func _collect_building_data() -> Array:
	return BuildingManager.get_all_buildings()

func _find_water_grid() -> WaterGrid:
	var root := get_tree().current_scene
	if root:
		return root.get_node_or_null("Water") as WaterGrid
	return null

func _restore_terrain(map_data: Dictionary) -> void:
	if map_data.is_empty():
		return
	var terrain: Terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	if not terrain:
		return
	for cell: Dictionary in map_data.get("cells", []):
		terrain.set_cell_height(cell["x"], cell["z"], cell.get("height", 1))

func _restore_water(water_data: Array) -> void:
	var wg: WaterGrid = _find_water_grid()
	if wg:
		wg.restore_water(water_data)

func _restore_buildings(building_data: Array) -> void:
	BuildingManager.restore_buildings(building_data)

func _restore_season(season_data: Dictionary) -> void:
	SeasonManager.restore_from_data(season_data)
