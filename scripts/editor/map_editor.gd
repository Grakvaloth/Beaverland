extends Node3D

enum Tool { RAISE, LOWER, SOURCE, SPAWN, ERASE }

const GRID_W := 20
const GRID_H := 20

var _tool: Tool = Tool.RAISE
var _brush_size: int = 1
var _map_name: String = "neue_map"
var _spawn_points: Array[Dictionary] = []
var _source_cells: Dictionary = {}

var _terrain: Terrain = null
var _camera: Camera3D = null
var _markers: Dictionary = {}   # Vector2i -> MeshInstance3D

# Orbit-Kamera
var _cam_yaw: float   = 45.0    # horizontale Rotation in Grad
var _cam_pitch: float = 35.0    # Neigungswinkel (15..80)
var _cam_size: float  = 22.0    # Orthographic-Größe = Zoom
var _cam_target: Vector3        # Mittelpunkt der Ansicht

var _is_rotating: bool = false
var _is_panning:  bool = false
var _mouse_last:  Vector2 = Vector2.ZERO

var _map_name_field: LineEdit = null
var _brush_btns: Array[Button] = []
var _tool_btns: Dictionary = {}

var _map_overlay: Control = null
var _map_list_vb: VBoxContainer = null

func _ready() -> void:
	_cam_target = Vector3(9.5, 0.0, 9.5)
	_setup_camera()
	_load_terrain()
	_build_ui()

# ── Kamera ──────────────────────────────────────────────────

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _cam_size
	add_child(_camera)
	_camera.make_current()
	_update_camera()

func _update_camera() -> void:
	var yaw_rad   := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(_cam_pitch)
	var dist      := 50.0

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * dist

	_camera.global_position = _cam_target + offset
	_camera.look_at(_cam_target, Vector3.UP)

# ── Terrain laden ───────────────────────────────────────────

func _load_terrain() -> void:
	var packed := load("res://scenes/world/terrain.tscn") as PackedScene
	if packed:
		_terrain = packed.instantiate() as Terrain
		add_child(_terrain)

# ── UI aufbauen ─────────────────────────────────────────────

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	_build_top_bar(root)
	_build_left_toolbar(root)

func _build_top_bar(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 52.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = "Map:"
	hbox.add_child(name_lbl)

	_map_name_field = LineEdit.new()
	_map_name_field.text = _map_name
	_map_name_field.custom_minimum_size = Vector2(160, 0)
	_map_name_field.text_changed.connect(func(t: String) -> void: _map_name = t)
	hbox.add_child(_map_name_field)

	_add_spacer(hbox, 12)

	var brush_lbl := Label.new()
	brush_lbl.text = "Pinsel:"
	hbox.add_child(brush_lbl)

	for sz in [1, 2, 3]:
		var btn := Button.new()
		btn.text = "%dx%d" % [sz, sz]
		btn.toggle_mode = true
		btn.button_pressed = (sz == 1)
		btn.pressed.connect(_on_brush_pressed.bind(sz))
		_brush_btns.append(btn)
		hbox.add_child(btn)

	_add_spacer(hbox, 12)

	for entry: Array in [
		["Speichern", _on_save],
		["Laden",     _on_load_pick],
		["Testen",    _on_test],
		["Zurück",    _on_back],
	]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.pressed.connect(entry[1])
		hbox.add_child(btn)

	_map_overlay = Control.new()
	_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.visible = false
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_map_overlay)

	var ov_bg := ColorRect.new()
	ov_bg.color = Color(0, 0, 0, 0.75)
	ov_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.add_child(ov_bg)

	var ov_panel := PanelContainer.new()
	ov_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ov_panel.offset_left   = -220.0
	ov_panel.offset_right  =  220.0
	ov_panel.offset_top    = -230.0
	ov_panel.offset_bottom =  230.0
	_map_overlay.add_child(ov_panel)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	ov_panel.add_child(pvb)

	var title_lbl := Label.new()
	title_lbl.text = "Karte laden"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(title_lbl)
	pvb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	pvb.add_child(scroll)

	_map_list_vb = VBoxContainer.new()
	_map_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_map_list_vb)

	pvb.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Abbrechen"
	close_btn.pressed.connect(func() -> void: _map_overlay.visible = false)
	pvb.add_child(close_btn)

func _build_left_toolbar(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top   = 56.0
	panel.offset_right = 70.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_add_tool_btn(vbox, Tool.RAISE,  "▲ Heben")
	_add_tool_btn(vbox, Tool.LOWER,  "▼ Senken")
	_add_tool_btn(vbox, Tool.SOURCE, "~ Quelle")
	_add_tool_btn(vbox, Tool.SPAWN,  "● Start")
	_add_tool_btn(vbox, Tool.ERASE,  "✕ Löschen")

	# Kamera-Hilfe
	var help := Label.new()
	help.text = "\nKamera:\nRMB: Drehen\nMMB: Pan\nScroll: Zoom"
	help.add_theme_font_size_override("font_size", 11)
	vbox.add_child(help)

func _add_tool_btn(parent: VBoxContainer, tool: Tool, label: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_pressed = (tool == Tool.RAISE)
	btn.pressed.connect(func() -> void: _on_tool_pressed(tool))
	_tool_btns[tool] = btn
	parent.add_child(btn)

func _add_spacer(parent: HBoxContainer, width: int) -> void:
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(width, 0)
	parent.add_child(sep)

# ── Button-Handler ──────────────────────────────────────────

func _on_tool_pressed(tool: Tool) -> void:
	_tool = tool
	for key in _tool_btns:
		(_tool_btns[key] as Button).button_pressed = (key == tool)

func _on_brush_pressed(size: int) -> void:
	_brush_size = size
	for i in range(_brush_btns.size()):
		_brush_btns[i].button_pressed = (i + 1 == size)

func _on_save() -> void:
	if _map_name.strip_edges().is_empty():
		return
	SaveManager.save_map(_build_map_data(), _map_name)

func _on_load_pick() -> void:
	for c in _map_list_vb.get_children():
		c.queue_free()
	var maps := SaveManager.list_maps()
	if maps.is_empty():
		var lbl := Label.new()
		lbl.text = "(Keine Maps vorhanden)"
		_map_list_vb.add_child(lbl)
	else:
		for m: String in maps:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_map_list_vb.add_child(row)

			var load_btn := Button.new()
			load_btn.text = m
			load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			load_btn.pressed.connect(func() -> void:
				_map_overlay.visible = false
				_load_map_by_name(m))
			row.add_child(load_btn)

			var del_btn := Button.new()
			del_btn.text = "🗑"
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.tooltip_text = "Löschen"
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_map(m)
				_on_load_pick())
			row.add_child(del_btn)
	_map_overlay.visible = true

func _load_map_by_name(name: String) -> void:
	var data := SaveManager.load_map(name)
	if data.is_empty():
		return
	_map_name = name
	if _map_name_field:
		_map_name_field.text = name
	_source_cells.clear()
	_spawn_points.clear()
	for key in _markers:
		(_markers[key] as MeshInstance3D).queue_free()
	_markers.clear()
	for cell: Dictionary in data.get("cells", []):
		_terrain.set_cell_height(int(cell["x"]), int(cell["z"]), int(cell.get("height", 1)))
		if cell.get("is_source", false):
			var cx := int(cell["x"])
			var cz := int(cell["z"])
			_source_cells[Vector2i(cx, cz)] = true
			_place_marker(cx, cz, Color(0.1, 0.4, 1.0))
	for sp: Dictionary in data.get("spawn_points", []):
		_spawn_points.append(sp)
		_place_marker(int(sp["x"]), int(sp["z"]), Color(0.1, 0.85, 0.2))

func _on_test() -> void:
	_on_save()
	SaveManager.set_current_map(_map_name)
	SceneManager.goto("res://scenes/main.tscn")

func _on_back() -> void:
	SceneManager.goto("res://scenes/ui/main_menu.tscn")

# ── Input ───────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)

func _handle_button(ev: InputEventMouseButton) -> void:
	match ev.button_index:
		MOUSE_BUTTON_LEFT:
			if ev.pressed and not _is_over_ui(ev.position):
				_apply_tool_at(ev.position)
		MOUSE_BUTTON_RIGHT:
			_is_rotating = ev.pressed
			_mouse_last  = ev.position
		MOUSE_BUTTON_MIDDLE:
			_is_panning  = ev.pressed
			_mouse_last  = ev.position
		MOUSE_BUTTON_WHEEL_UP:
			if ev.pressed:
				_cam_size = maxf(5.0, _cam_size - 2.0)
				_camera.size = _cam_size
		MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				_cam_size = minf(50.0, _cam_size + 2.0)
				_camera.size = _cam_size

func _handle_motion(ev: InputEventMouseMotion) -> void:
	if _is_rotating:
		_cam_yaw   -= ev.relative.x * 0.4
		_cam_pitch  = clampf(_cam_pitch - ev.relative.y * 0.3, 15.0, 80.0)
		_update_camera()
	elif _is_panning:
		var right   := _camera.global_transform.basis.x
		var forward := -_camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		var speed := _cam_size * 0.015
		_cam_target -= right * ev.relative.x * speed
		_cam_target -= forward * ev.relative.y * speed
		_update_camera()

func _is_over_ui(pos: Vector2) -> bool:
	# Toolbar-Bereiche (Top-Bar und linke Leiste) manuell prüfen
	if pos.y < 56.0:
		return true
	if pos.x < 74.0:
		return true
	return false

# ── Werkzeug ────────────────────────────────────────────────

func _apply_tool_at(screen_pos: Vector2) -> void:
	if not _terrain:
		return
	var cell := _raycast_terrain(screen_pos)
	if not cell:
		return
	var cx: int = cell.get_meta("grid_x")
	var cz: int = cell.get_meta("grid_z")
	var half := _brush_size / 2
	for dx in range(-half, _brush_size - half):
		for dz in range(-half, _brush_size - half):
			_apply_to_cell(cx + dx, cz + dz)

func _apply_to_cell(x: int, z: int) -> void:
	if x < 0 or z < 0 or x >= GRID_W or z >= GRID_H:
		return
	match _tool:
		Tool.RAISE:
			_terrain.set_cell_height(x, z, _terrain.get_height_at(x, z) + 1)
		Tool.LOWER:
			_terrain.set_cell_height(x, z, maxi(1, _terrain.get_height_at(x, z) - 1))
		Tool.SOURCE:
			_toggle_source(x, z)
		Tool.SPAWN:
			_toggle_spawn(x, z)
		Tool.ERASE:
			_terrain.set_cell_height(x, z, 1)  # Boden bleibt immer erhalten
			_source_cells.erase(Vector2i(x, z))

func _raycast_terrain(screen_pos: Vector2) -> Node3D:
	var space  := get_world_3d().direct_space_state
	var origin := _camera.project_ray_origin(screen_pos)
	var dir    := _camera.project_ray_normal(screen_pos)
	var query  := PhysicsRayQueryParameters3D.create(origin, origin + dir * 500.0)
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var body: Object = hit.get("collider")
	if body is Node3D and (body as Node3D).has_meta("grid_x"):
		return body as Node3D
	return null

func _toggle_source(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if _source_cells.has(key):
		_source_cells.erase(key)
		_remove_marker(x, z)
	else:
		_source_cells[key] = true
		_place_marker(x, z, Color(0.1, 0.4, 1.0))

func _toggle_spawn(x: int, z: int) -> void:
	for i in range(_spawn_points.size()):
		if _spawn_points[i]["x"] == x and _spawn_points[i]["z"] == z:
			_spawn_points.remove_at(i)
			_remove_marker(x, z)
			return
	if _spawn_points.size() >= 2:
		return
	_spawn_points.append({"x": x, "z": z})
	_place_marker(x, z, Color(0.1, 0.85, 0.2))

func _place_marker(x: int, z: int, color: Color) -> void:
	_remove_marker(x, z)
	var h := _terrain.get_height_at(x, z)
	var mi   := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.22
	cyl.bottom_radius = 0.22
	cyl.height        = 0.6
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color           = color
	mat.emission_enabled       = true
	mat.emission               = color
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	mi.position = Vector3(x, float(h) + 0.3, z)
	add_child(mi)
	_markers[Vector2i(x, z)] = mi

func _remove_marker(x: int, z: int) -> void:
	var key := Vector2i(x, z)
	if _markers.has(key):
		(_markers[key] as MeshInstance3D).queue_free()
		_markers.erase(key)

# ── Map-Daten ───────────────────────────────────────────────

func _build_map_data() -> Dictionary:
	var cells: Array = []
	for x in range(GRID_W):
		for z in range(GRID_H):
			cells.append({
				"x": x, "y": 0, "z": z,
				"height": _terrain.get_height_at(x, z),
				"is_source": _source_cells.has(Vector2i(x, z)),
			})
	return {
		"name": _map_name,
		"size": {"x": GRID_W, "y": 20, "z": GRID_H},
		"cells": cells,
		"spawn_points": _spawn_points,
	}
