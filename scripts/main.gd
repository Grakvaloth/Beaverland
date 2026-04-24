extends Node3D

# ── Pause / Save / Load overlays ────────────────────────────
var _pause_menu:      Control
var _save_overlay:    Control
var _load_overlay:    Control
var _save_name_field: LineEdit
var _saves_list_vb:   VBoxContainer
var _load_list_vb:    VBoxContainer

# ── HUD ─────────────────────────────────────────────────────
var _hud_season_label:  Label
var _hud_bar:           ProgressBar
var _hud_players_label: Label
var _hud_speed_label:   Label

# ── Build palette ────────────────────────────────────────────
var _build_mode:    bool = false
var _selected_type: BuildingManager.Type = BuildingManager.Type.LUMBERJACK
var _type_btns:     Dictionary = {}

# ── Selection / Info ─────────────────────────────────────────
var _info_panel:        PanelContainer
var _info_name_lbl:     Label
var _info_pos_lbl:      Label
var _info_desc_lbl:     Label
var _delete_overlay:    Control

# ── Camera ───────────────────────────────────────────────────
var _cam_pivot:    Vector3 = Vector3(10.0, 0.0, 10.0)
var _cam_yaw:      float   = 0.0
var _cam_pitch:    float   = deg_to_rad(52.0)   # Neigungswinkel (20°–80°)
var _cam_arm:      float   = 22.8               # Abstand Pivot → Kamera
var _cam_size:     float   = 18.0
var _cam_speed:    float   = 10.0
var _cam_rot_spd:  float   = 1.8
var _rmb_held:     bool    = false
var _rmb_last_pos: Vector2 = Vector2.ZERO
var _mmb_held:     bool    = false

# ── Speed ────────────────────────────────────────────────────
var _game_speed:   float = 1.0
var _paused:       bool  = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_map_on_start()
	_build_hud()
	_build_pause_menu()
	_build_info_panel()
	_build_delete_overlay()
	SaveManager.start_autosave_timer()
	SeasonManager.start()
	SeasonManager.season_changed.connect(_on_season_changed)
	SeasonManager.day_changed.connect(_on_day_changed)
	NetworkManager.player_joined.connect(_on_players_changed)
	NetworkManager.player_left.connect(_on_players_changed)
	BuildingManager.selection_changed.connect(_on_selection_changed)
	_update_hud()
	_build_build_palette()
	_update_camera()

func _process(delta: float) -> void:
	if _paused:
		return
	_handle_camera(delta)
	_handle_speed_keys()

# ── Map load ─────────────────────────────────────────────────

func _load_map_on_start() -> void:
	var map_name := SaveManager.get_current_map_name()
	if map_name.is_empty():
		return
	var map_data := SaveManager.load_map(map_name)
	if map_data.is_empty():
		return
	await get_tree().process_frame
	var terrain: Terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	if terrain:
		for cell: Dictionary in map_data.get("cells", []):
			terrain.set_cell_height(int(cell["x"]), int(cell["z"]), int(cell.get("height", 1)))

# ── Camera ───────────────────────────────────────────────────

func _handle_camera(delta: float) -> void:
	var moved := false
	var forward := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
	var right   := Vector3( cos(_cam_yaw), 0.0, -sin(_cam_yaw))

	if Input.is_action_pressed("cam_forward"):
		_cam_pivot += forward * _cam_speed * delta; moved = true
	if Input.is_action_pressed("cam_backward"):
		_cam_pivot -= forward * _cam_speed * delta; moved = true
	if Input.is_action_pressed("cam_left"):
		_cam_pivot -= right * _cam_speed * delta;   moved = true
	if Input.is_action_pressed("cam_right"):
		_cam_pivot += right * _cam_speed * delta;   moved = true
	if Input.is_action_pressed("cam_rotate_left"):
		_cam_yaw -= _cam_rot_spd * delta; moved = true
	if Input.is_action_pressed("cam_rotate_right"):
		_cam_yaw += _cam_rot_spd * delta; moved = true

	if moved:
		_update_camera()

func _update_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var horiz := cos(_cam_pitch) * _cam_arm
	var vert   := sin(_cam_pitch) * _cam_arm
	cam.global_position = _cam_pivot + Vector3(
		sin(_cam_yaw) * horiz,
		vert,
		cos(_cam_yaw) * horiz
	)
	cam.look_at(_cam_pivot, Vector3.UP)
	cam.size = _cam_size

func _change_pitch(delta: float) -> void:
	_cam_pitch = clampf(_cam_pitch + delta, deg_to_rad(15.0), deg_to_rad(85.0))
	_update_camera()

# ── Speed keys ───────────────────────────────────────────────

func _handle_speed_keys() -> void:
	if Input.is_action_just_pressed("game_speed_1"):
		_set_speed(1.0)
	elif Input.is_action_just_pressed("game_speed_2"):
		_set_speed(2.0)
	elif Input.is_action_just_pressed("game_speed_3"):
		_set_speed(3.0)

func _set_speed(s: float) -> void:
	_game_speed = s
	if not _paused:
		Engine.time_scale = _game_speed
	_update_speed_label()

func _update_speed_label() -> void:
	if not is_instance_valid(_hud_speed_label):
		return
	if _paused:
		_hud_speed_label.text = "⏸"
	else:
		_hud_speed_label.text = "%.0f×" % _game_speed

# ── HUD ──────────────────────────────────────────────────────

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left   = -280.0
	panel.offset_top    =   8.0
	panel.offset_right  =  -8.0
	panel.offset_bottom =  90.0
	canvas.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	_hud_season_label = Label.new()
	_hud_season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_season_label.add_theme_font_size_override("font_size", 15)
	vb.add_child(_hud_season_label)

	_hud_bar = ProgressBar.new()
	_hud_bar.min_value = 0.0
	_hud_bar.max_value = 1.0
	_hud_bar.value     = 0.0
	_hud_bar.custom_minimum_size = Vector2(240, 18)
	_hud_bar.show_percentage = false
	vb.add_child(_hud_bar)

	var hb := HBoxContainer.new()
	vb.add_child(hb)

	_hud_players_label = Label.new()
	_hud_players_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_players_label.add_theme_font_size_override("font_size", 12)
	hb.add_child(_hud_players_label)

	_hud_speed_label = Label.new()
	_hud_speed_label.text = "1×"
	_hud_speed_label.add_theme_font_size_override("font_size", 13)
	_hud_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(_hud_speed_label)

	var water_btn := Button.new()
	water_btn.text = "Wasser"
	water_btn.toggle_mode = true
	water_btn.button_pressed = true
	water_btn.custom_minimum_size = Vector2(70, 22)
	water_btn.add_theme_font_size_override("font_size", 11)
	water_btn.toggled.connect(func(_on: bool) -> void:
		var wg := get_tree().get_first_node_in_group("water_grid") as WaterGrid
		if wg:
			wg.toggle_visible())
	canvas.add_child(water_btn)
	water_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	water_btn.offset_left   = -82.0
	water_btn.offset_top    =  96.0
	water_btn.offset_right  =  -8.0
	water_btn.offset_bottom = 122.0

func _update_hud() -> void:
	var is_drought := SeasonManager.current_season == SeasonManager.Season.DROUGHT
	var season_len := SeasonManager.DROUGHT_DAYS if is_drought else SeasonManager.TEMPERATE_DAYS
	var label := "Dürre" if is_drought else "Grüne Zeit"
	_hud_season_label.text = "%s  –  Tag %d / %d" % [label, SeasonManager.current_day, season_len]
	_hud_season_label.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.1) if is_drought else Color(0.3, 0.9, 0.3))
	_hud_bar.value = SeasonManager.get_progress()
	if NetworkManager.is_active():
		_hud_players_label.text = "Spieler: %d" % NetworkManager.get_player_count()
		_hud_players_label.visible = true
	else:
		_hud_players_label.visible = false

func _on_players_changed(_id: int) -> void:
	_update_hud()

func _on_season_changed(_season: SeasonManager.Season) -> void:
	_update_hud()

func _on_day_changed(_day: int, _season: SeasonManager.Season) -> void:
	_update_hud()

# ── Build palette ─────────────────────────────────────────────

func _build_build_palette() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top    = -64.0
	panel.offset_bottom = -4.0
	panel.offset_left   =  4.0
	panel.offset_right  = -4.0
	canvas.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	for type in BuildingManager.Type.values():
		var t := type as BuildingManager.Type
		var btn := Button.new()
		btn.text = BuildingManager.TYPE_NAMES[t]
		btn.custom_minimum_size = Vector2(110, 44)
		btn.toggle_mode = true
		btn.button_pressed = false
		btn.toggled.connect(func(on: bool) -> void:
			if on:
				_selected_type = t
				_build_mode = true
				_deselect_other_type_btns(t)
				BuildingManager.deselect()
			else:
				_build_mode = false)
		_type_btns[t] = btn
		hbox.add_child(btn)

func _deselect_other_type_btns(keep: BuildingManager.Type) -> void:
	for t in _type_btns:
		if t != keep:
			(_type_btns[t] as Button).set_pressed_no_signal(false)

func _deactivate_build_mode() -> void:
	_build_mode = false
	for t in _type_btns:
		(_type_btns[t] as Button).set_pressed_no_signal(false)

# ── Info-Panel (rechts) ───────────────────────────────────────

func _build_info_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_info_panel.offset_left   = -230.0
	_info_panel.offset_right  =  -8.0
	_info_panel.offset_top    = -120.0
	_info_panel.offset_bottom =  120.0
	_info_panel.visible = false
	canvas.add_child(_info_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_info_panel.add_child(vb)

	_info_name_lbl = Label.new()
	_info_name_lbl.add_theme_font_size_override("font_size", 18)
	_info_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info_name_lbl)

	vb.add_child(HSeparator.new())

	_info_pos_lbl = Label.new()
	_info_pos_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(_info_pos_lbl)

	_info_desc_lbl = Label.new()
	_info_desc_lbl.add_theme_font_size_override("font_size", 12)
	_info_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_desc_lbl.custom_minimum_size = Vector2(180, 0)
	vb.add_child(_info_desc_lbl)

	vb.add_child(HSeparator.new())

	var del_btn := Button.new()
	del_btn.text = "Löschen"
	del_btn.pressed.connect(_on_delete_request)
	vb.add_child(del_btn)

func _on_selection_changed(key: Vector2i) -> void:
	if key == Vector2i(-1, -1) or not BuildingManager.has_building(key.x, key.y):
		_info_panel.visible = false
		return
	var info := BuildingManager.get_info(key.x, key.y)
	_info_name_lbl.text = info.get("name", "")
	_info_pos_lbl.text  = "Position: " + info.get("position", "")
	_info_desc_lbl.text = info.get("desc", "")
	_info_panel.visible = true

# ── Lösch-Bestätigung ─────────────────────────────────────────

func _build_delete_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_delete_overlay = Control.new()
	_delete_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_delete_overlay.visible = false
	_delete_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_delete_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_delete_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -170.0
	panel.offset_right  =  170.0
	panel.offset_top    =  -80.0
	panel.offset_bottom =   80.0
	_delete_overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Gebäude wirklich löschen?"
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)

	var hint := Label.new()
	hint.text = "Enter = Ja   ·   Escape = Nein"
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)

	var yes_btn := Button.new()
	yes_btn.text = "Ja"
	yes_btn.custom_minimum_size = Vector2(100, 38)
	yes_btn.pressed.connect(_on_delete_confirmed)
	hb.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Nein"
	no_btn.custom_minimum_size = Vector2(100, 38)
	no_btn.pressed.connect(func() -> void: _delete_overlay.visible = false)
	hb.add_child(no_btn)

func _on_delete_request() -> void:
	var sel := BuildingManager.get_selected()
	if sel == Vector2i(-1, -1):
		return
	_delete_overlay.visible = true

func _on_delete_confirmed() -> void:
	_delete_overlay.visible = false
	var sel := BuildingManager.get_selected()
	if sel == Vector2i(-1, -1):
		return
	NetworkManager.request_remove_building(sel.x, sel.y)
	BuildingManager.deselect()
	_info_panel.visible = false

# ── Input ─────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Lösch-Dialog hat Priorität
	if _delete_overlay.visible:
		if event.is_action_pressed("ui_accept"):
			_on_delete_confirmed()
		elif event.is_action_pressed("ui_cancel"):
			_delete_overlay.visible = false
		return

	# Mausrad → Zoom oder (Shift) Pitch
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var shift := Input.is_key_pressed(KEY_SHIFT)
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if shift:
					_change_pitch(deg_to_rad(3.0))
				else:
					_cam_size = clampf(_cam_size - 1.5, 4.0, 50.0)
					_update_camera()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if shift:
					_change_pitch(deg_to_rad(-3.0))
				else:
					_cam_size = clampf(_cam_size + 1.5, 4.0, 50.0)
					_update_camera()
				return
		# RMB gedrückt / losgelassen tracken
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held     = mb.pressed
			_rmb_last_pos = mb.position
			return
		# MMB gedrückt / losgelassen tracken
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_held = mb.pressed
			return

	# RMB-Ziehen → Kamera schwenken
	if event is InputEventMouseMotion and _rmb_held:
		var motion := event as InputEventMouseMotion
		var pan_scale := _cam_size * 0.0015
		var right   := Vector3( cos(_cam_yaw), 0.0, -sin(_cam_yaw))
		var forward := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
		_cam_pivot -= right   * motion.relative.x * pan_scale
		_cam_pivot += forward * motion.relative.y * pan_scale
		_update_camera()
		return

	# MMB-Ziehen → Yaw (horizontal) + Pitch (vertikal)
	if event is InputEventMouseMotion and _mmb_held:
		var motion := event as InputEventMouseMotion
		_cam_yaw += motion.relative.x * 0.005
		_change_pitch(-motion.relative.y * 0.004)
		return

	if event.is_action_pressed("game_pause"):
		if _save_overlay.visible or _load_overlay.visible:
			return
		_toggle_pause()
		return

	if event.is_action_pressed("build_delete"):
		_on_delete_request()
		return

	if event.is_action_pressed("ui_cancel"):
		if _save_overlay.visible:
			_save_overlay.visible = false
		elif _load_overlay.visible:
			_load_overlay.visible = false
		elif _delete_overlay.visible:
			_delete_overlay.visible = false
		elif _build_mode:
			_deactivate_build_mode()
		elif BuildingManager.get_selected() != Vector2i(-1, -1):
			BuildingManager.deselect()
		else:
			_toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if _pause_menu.visible or _delete_overlay.visible or _rmb_held or _mmb_held:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := _raycast_cell(mb.position)
	if _build_mode:
		if cell:
			NetworkManager.request_place_building(
				cell.get_meta("grid_x"), cell.get_meta("grid_z"), int(_selected_type))
	else:
		if cell and BuildingManager.has_building(cell.get_meta("grid_x"), cell.get_meta("grid_z")):
			BuildingManager.select(cell.get_meta("grid_x"), cell.get_meta("grid_z"))
		else:
			BuildingManager.deselect()

func _raycast_cell(screen_pos: Vector2) -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return null
	var space  := get_world_3d().direct_space_state
	var origin := cam.project_ray_origin(screen_pos)
	var dir    := cam.project_ray_normal(screen_pos)
	var query  := PhysicsRayQueryParameters3D.create(origin, origin + dir * 500.0)
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var body: Object = hit.get("collider")
	if body is Node3D and (body as Node3D).has_meta("grid_x"):
		return body as Node3D
	return null

# ── Pause ─────────────────────────────────────────────────────

func _toggle_pause() -> void:
	_paused = !_paused
	_pause_menu.visible = _paused
	get_tree().paused = _paused
	if _paused:
		Engine.time_scale = 1.0
	else:
		Engine.time_scale = _game_speed
	_update_speed_label()

func _on_resume() -> void:
	_toggle_pause()

# ── Pause-Menü ────────────────────────────────────────────────

func _build_pause_menu() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	_pause_menu = Control.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_pause_menu)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -140.0
	vbox.offset_right  =  140.0
	vbox.offset_top    = -110.0
	vbox.offset_bottom =  110.0
	vbox.add_theme_constant_override("separation", 14)
	_pause_menu.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Pause"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	for entry: Array in [
		["Weiter spielen",  _on_resume],
		["Spiel speichern", _on_save_game],
		["Spiel laden",     _on_load_game],
		["Hauptmenü",       _on_main_menu],
	]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(280, 46)
		btn.pressed.connect(entry[1])
		vbox.add_child(btn)

	_build_save_overlay(canvas)
	_build_load_overlay(canvas)

func _build_save_overlay(parent: Node) -> void:
	_save_overlay = _make_overlay(parent)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -220.0
	panel.offset_right  =  220.0
	panel.offset_top    = -280.0
	panel.offset_bottom =  280.0
	_save_overlay.add_child(panel)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	panel.add_child(pvb)

	var title_lbl := Label.new()
	title_lbl.text = "Spiel speichern"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(title_lbl)
	pvb.add_child(HSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	pvb.add_child(name_lbl)

	_save_name_field = LineEdit.new()
	_save_name_field.placeholder_text = "Spielstand-Name"
	_save_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pvb.add_child(_save_name_field)

	pvb.add_child(HSeparator.new())

	var hint_lbl := Label.new()
	hint_lbl.text = "Vorhandene Spielstände:"
	pvb.add_child(hint_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 180)
	pvb.add_child(scroll)

	_saves_list_vb = VBoxContainer.new()
	_saves_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_saves_list_vb)

	pvb.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pvb.add_child(hbox)

	var save_btn := Button.new()
	save_btn.text = "Speichern"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_confirmed)
	hbox.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Abbrechen"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func() -> void: _save_overlay.visible = false)
	hbox.add_child(cancel_btn)

func _build_load_overlay(parent: Node) -> void:
	_load_overlay = _make_overlay(parent)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -220.0
	panel.offset_right  =  220.0
	panel.offset_top    = -230.0
	panel.offset_bottom =  230.0
	_load_overlay.add_child(panel)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	panel.add_child(pvb)

	var title_lbl := Label.new()
	title_lbl.text = "Spiel laden"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(title_lbl)
	pvb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	pvb.add_child(scroll)

	_load_list_vb = VBoxContainer.new()
	_load_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_load_list_vb)

	pvb.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Abbrechen"
	close_btn.pressed.connect(func() -> void: _load_overlay.visible = false)
	pvb.add_child(close_btn)

func _make_overlay(parent: Node) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	return overlay

func _refresh_save_list() -> void:
	for c in _saves_list_vb.get_children():
		c.queue_free()
	for entry: Dictionary in SaveManager.list_saves_named():
		var n: String = entry["name"]
		var ts: String = entry.get("timestamp", "")
		var btn := Button.new()
		btn.text = "%s  (%s)" % [n, ts] if ts != "" else n
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: _save_name_field.text = n)
		_saves_list_vb.add_child(btn)

func _refresh_load_list() -> void:
	for c in _load_list_vb.get_children():
		c.queue_free()
	var entries := SaveManager.list_saves_named()
	if entries.is_empty():
		var lbl := Label.new()
		lbl.text = "(Keine Spielstände vorhanden)"
		_load_list_vb.add_child(lbl)
		return
	for entry: Dictionary in entries:
		var n: String = entry["name"]
		var ts: String = entry.get("timestamp", "")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_load_list_vb.add_child(row)

		var load_btn := Button.new()
		load_btn.text = "%s  (%s)" % [n, ts] if ts != "" else n
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.pressed.connect(func() -> void:
			_load_overlay.visible = false
			_toggle_pause()
			SaveManager.load_game_named(n))
		row.add_child(load_btn)

		var del_btn := Button.new()
		del_btn.text = "🗑"
		del_btn.custom_minimum_size = Vector2(36, 0)
		del_btn.tooltip_text = "Löschen"
		del_btn.pressed.connect(func() -> void:
			SaveManager.delete_save_named(n)
			_refresh_load_list())
		row.add_child(del_btn)

func _on_save_game() -> void:
	_refresh_save_list()
	_save_overlay.visible = true

func _on_save_confirmed() -> void:
	var name := _save_name_field.text.strip_edges()
	if name.is_empty():
		return
	SaveManager.save_game_named(name)
	_save_overlay.visible = false

func _on_load_game() -> void:
	_refresh_load_list()
	_load_overlay.visible = true

func _on_main_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	SaveManager.stop_autosave_timer()
	SeasonManager.stop()
	SceneManager.goto("res://scenes/ui/main_menu.tscn")
