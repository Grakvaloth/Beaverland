extends Node3D

var _pause_menu: Control
var _save_overlay: Control
var _load_overlay: Control
var _save_name_field: LineEdit
var _saves_list_vb: VBoxContainer
var _load_list_vb: VBoxContainer

var _hud_season_label: Label
var _hud_bar: ProgressBar
var _hud_players_label: Label

var _build_mode: bool = false
var _selected_type: BuildingManager.Type = BuildingManager.Type.LUMBERJACK
var _type_btns: Dictionary = {}
var _build_toggle_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_map_on_start()
	_build_hud()
	_build_pause_menu()
	SaveManager.start_autosave_timer()
	SeasonManager.start()
	SeasonManager.season_changed.connect(_on_season_changed)
	SeasonManager.day_changed.connect(_on_day_changed)
	NetworkManager.player_joined.connect(_on_players_changed)
	NetworkManager.player_left.connect(_on_players_changed)
	_update_hud()
	_build_build_palette()

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

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left   = -260.0
	panel.offset_top    =   8.0
	panel.offset_right  =  -8.0
	panel.offset_bottom =  70.0
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
	_hud_bar.custom_minimum_size = Vector2(220, 18)
	_hud_bar.show_percentage = false
	vb.add_child(_hud_bar)

	_hud_players_label = Label.new()
	_hud_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_players_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(_hud_players_label)

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

	_build_toggle_btn = Button.new()
	_build_toggle_btn.text = "Bauen: AUS"
	_build_toggle_btn.toggle_mode = true
	_build_toggle_btn.custom_minimum_size = Vector2(110, 44)
	_build_toggle_btn.toggled.connect(func(on: bool) -> void:
		_build_mode = on
		_build_toggle_btn.text = "Bauen: EIN" if on else "Bauen: AUS"
		_update_type_btns())
	hbox.add_child(_build_toggle_btn)

	var sep := VSeparator.new()
	hbox.add_child(sep)

	for type in BuildingManager.Type.values():
		var t := type as BuildingManager.Type
		var btn := Button.new()
		btn.text = BuildingManager.TYPE_NAMES[t]
		btn.custom_minimum_size = Vector2(100, 44)
		btn.toggle_mode = true
		btn.button_pressed = (t == _selected_type)
		btn.pressed.connect(func() -> void:
			_selected_type = t
			_update_type_btns())
		_type_btns[t] = btn
		hbox.add_child(btn)

func _update_type_btns() -> void:
	for t in _type_btns:
		(_type_btns[t] as Button).button_pressed = (_build_mode and t == _selected_type)

func _on_season_changed(_season: SeasonManager.Season) -> void:
	_update_hud()

func _on_day_changed(_day: int, _season: SeasonManager.Season) -> void:
	_update_hud()

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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _save_overlay.visible:
			_save_overlay.visible = false
		elif _load_overlay.visible:
			_load_overlay.visible = false
		elif _build_mode:
			_build_toggle_btn.button_pressed = false
			_build_mode = false
			_build_toggle_btn.text = "Bauen: AUS"
			_update_type_btns()
		else:
			_toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if not _build_mode or _pause_menu.visible:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var cell := _raycast_cell(mb.position)
	if cell == null:
		return
	var cx: int = cell.get_meta("grid_x")
	var cz: int = cell.get_meta("grid_z")
	if mb.button_index == MOUSE_BUTTON_LEFT:
		NetworkManager.request_place_building(cx, cz, int(_selected_type))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		NetworkManager.request_remove_building(cx, cz)

func _raycast_cell(screen_pos: Vector2) -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return null
	var space := get_world_3d().direct_space_state
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

func _toggle_pause() -> void:
	_pause_menu.visible = !_pause_menu.visible
	get_tree().paused = _pause_menu.visible

func _on_resume() -> void:
	_toggle_pause()

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
	SaveManager.stop_autosave_timer()
	SeasonManager.stop()
	SceneManager.goto("res://scenes/ui/main_menu.tscn")
