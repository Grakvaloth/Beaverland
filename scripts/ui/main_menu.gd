extends Control

var _ip_field: LineEdit
var _vol_slider: HSlider
var _ip_dialog: AcceptDialog

var _settings_overlay: Control = null
var _bind_btns: Dictionary = {}       # "action_slot" -> Button
var _listening_action: String = ""
var _listening_slot:   int    = -1
var _listening_btn:    Button = null

var _map_overlay: Control = null
var _map_list_vb: VBoxContainer = null
var _saves_overlay: Control = null
var _saves_list_vb: VBoxContainer = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_title()
	_build_center_buttons()
	_build_corner_buttons()
	_build_dialogs()
	NetworkManager.connection_error.connect(_on_connection_error)

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.22, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

func _build_title() -> void:
	var lbl := Label.new()
	lbl.text = "Timberborn Clone"
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = 60.0
	lbl.offset_bottom = 130.0
	add_child(lbl)

func _build_center_buttons() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -160.0
	vbox.offset_right  = 160.0
	vbox.offset_top    = -130.0
	vbox.offset_bottom = 130.0
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	for e: Array in [
		["Neues Spiel",       _on_new_game],
		["Spielstand laden",  _on_load_save],
		["Map Editor",        _on_map_editor],
		["Spiel hosten",      _on_host_game],
		["Spiel beitreten",   _on_join_game],
	]:
		var btn := Button.new()
		btn.text = e[0]
		btn.custom_minimum_size = Vector2(320, 52)
		btn.pressed.connect(e[1])
		vbox.add_child(btn)

func _build_corner_buttons() -> void:
	var quit_btn := Button.new()
	quit_btn.text = "Beenden"
	quit_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	quit_btn.offset_left   = 20.0
	quit_btn.offset_top    = -60.0
	quit_btn.offset_right  = 170.0
	quit_btn.offset_bottom = -20.0
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	add_child(quit_btn)

	var set_btn := Button.new()
	set_btn.text = "Einstellungen"
	set_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	set_btn.offset_left   = -170.0
	set_btn.offset_top    = -60.0
	set_btn.offset_right  = -20.0
	set_btn.offset_bottom = -20.0
	set_btn.pressed.connect(_on_settings)
	add_child(set_btn)

func _build_dialogs() -> void:
	# IP-Eingabe
	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "127.0.0.1"
	_ip_field.custom_minimum_size = Vector2(240, 36)
	_ip_dialog = AcceptDialog.new()
	_ip_dialog.title = "Server-IP eingeben"
	_ip_dialog.add_child(_ip_field)
	_ip_dialog.confirmed.connect(_on_ip_confirmed)
	add_child(_ip_dialog)

	# Einstellungen-Overlay
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_overlay)

	var set_bg := ColorRect.new()
	set_bg.color = Color(0, 0, 0, 0.75)
	set_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(set_bg)

	var set_panel := PanelContainer.new()
	set_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	set_panel.offset_left   = -340.0
	set_panel.offset_right  =  340.0
	set_panel.offset_top    = -320.0
	set_panel.offset_bottom =  320.0
	_settings_overlay.add_child(set_panel)

	var set_vb := VBoxContainer.new()
	set_vb.add_theme_constant_override("separation", 10)
	set_panel.add_child(set_vb)

	var set_title := Label.new()
	set_title.text = "Einstellungen"
	set_title.add_theme_font_size_override("font_size", 22)
	set_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_vb.add_child(set_title)
	set_vb.add_child(HSeparator.new())

	# Audio + Auflösung
	var gen_lbl := Label.new()
	gen_lbl.text = "Allgemein"
	gen_lbl.add_theme_font_size_override("font_size", 15)
	set_vb.add_child(gen_lbl)

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	set_vb.add_child(vol_row)
	var vol_lbl := Label.new()
	vol_lbl.text = "Lautstärke"
	vol_lbl.custom_minimum_size = Vector2(110, 0)
	vol_row.add_child(vol_lbl)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(v)))
	vol_row.add_child(_vol_slider)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 8)
	set_vb.add_child(res_row)
	var res_lbl := Label.new()
	res_lbl.text = "Auflösung"
	res_lbl.custom_minimum_size = Vector2(110, 0)
	res_row.add_child(res_lbl)
	var res_opt := OptionButton.new()
	res_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in ["1280 × 720", "1920 × 1080", "2560 × 1440"]:
		res_opt.add_item(r)
	res_opt.item_selected.connect(_on_resolution_selected)
	res_row.add_child(res_opt)

	set_vb.add_child(HSeparator.new())

	# Tastenbelegung
	var key_lbl := Label.new()
	key_lbl.text = "Tastenbelegung"
	key_lbl.add_theme_font_size_override("font_size", 15)
	set_vb.add_child(key_lbl)

	var header := HBoxContainer.new()
	set_vb.add_child(header)
	var h_action := Label.new(); h_action.text = "Aktion"
	h_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(h_action)
	for h in ["Primär", "Sekundär"]:
		var hl := Label.new(); hl.text = h
		hl.custom_minimum_size = Vector2(90, 0)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(hl)

	var key_scroll := ScrollContainer.new()
	key_scroll.custom_minimum_size = Vector2(0, 200)
	key_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_vb.add_child(key_scroll)

	var key_vb := VBoxContainer.new()
	key_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_vb.add_theme_constant_override("separation", 4)
	key_scroll.add_child(key_vb)

	for action in InputManager.ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		key_vb.add_child(row)

		var act_lbl := Label.new()
		act_lbl.text = InputManager.ACTION_LABELS.get(action, action)
		act_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(act_lbl)

		for slot in [0, 1]:
			var key_txt := InputManager.get_key_label(action, slot)
			var bind_btn := Button.new()
			bind_btn.text = key_txt
			bind_btn.custom_minimum_size = Vector2(88, 28)
			var a: String = action; var s: int = slot
			bind_btn.pressed.connect(func() -> void: _start_listening(a, s, bind_btn))
			_bind_btns[action + "_" + str(slot)] = bind_btn
			row.add_child(bind_btn)

	set_vb.add_child(HSeparator.new())

	var set_close_btn := Button.new()
	set_close_btn.text = "Schließen"
	set_close_btn.pressed.connect(func() -> void:
		_stop_listening()
		_settings_overlay.visible = false)
	set_vb.add_child(set_close_btn)

	# Karten-Overlay – muss als letztes hinzugefügt werden (liegt oben)
	_map_overlay = Control.new()
	_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.visible = false
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -220.0
	panel.offset_right  =  220.0
	panel.offset_top    = -230.0
	panel.offset_bottom =  230.0
	_map_overlay.add_child(panel)

	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 8)
	panel.add_child(pvb)

	var title_lbl := Label.new()
	title_lbl.text = "Karte wählen"
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

	var map_close_btn := Button.new()
	map_close_btn.text = "Abbrechen"
	map_close_btn.pressed.connect(func() -> void: _map_overlay.visible = false)
	pvb.add_child(map_close_btn)

	# Spielstand-Lade-Overlay
	_saves_overlay = Control.new()
	_saves_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saves_overlay.visible = false
	_saves_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_saves_overlay)

	var sv_bg := ColorRect.new()
	sv_bg.color = Color(0, 0, 0, 0.75)
	sv_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saves_overlay.add_child(sv_bg)

	var sv_panel := PanelContainer.new()
	sv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sv_panel.offset_left   = -220.0
	sv_panel.offset_right  =  220.0
	sv_panel.offset_top    = -230.0
	sv_panel.offset_bottom =  230.0
	_saves_overlay.add_child(sv_panel)

	var sv_pvb := VBoxContainer.new()
	sv_pvb.add_theme_constant_override("separation", 8)
	sv_panel.add_child(sv_pvb)

	var sv_title := Label.new()
	sv_title.text = "Spielstand laden"
	sv_title.add_theme_font_size_override("font_size", 22)
	sv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv_pvb.add_child(sv_title)
	sv_pvb.add_child(HSeparator.new())

	var sv_scroll := ScrollContainer.new()
	sv_scroll.custom_minimum_size = Vector2(400, 300)
	sv_pvb.add_child(sv_scroll)

	_saves_list_vb = VBoxContainer.new()
	_saves_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv_scroll.add_child(_saves_list_vb)

	sv_pvb.add_child(HSeparator.new())

	var sv_close := Button.new()
	sv_close.text = "Abbrechen"
	sv_close.pressed.connect(func() -> void: _saves_overlay.visible = false)
	sv_pvb.add_child(sv_close)

# ── Button-Handler ───────────────────────────────────────────

func _on_new_game() -> void:
	for c in _map_list_vb.get_children():
		c.queue_free()
	var maps := SaveManager.list_maps()
	if maps.is_empty():
		var lbl := Label.new()
		lbl.text = "(Keine Maps vorhanden – bitte zuerst im Editor eine Map erstellen)"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_map_list_vb.add_child(lbl)
	else:
		for m: String in maps:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_map_list_vb.add_child(row)

			var play_btn := Button.new()
			play_btn.text = m
			play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			play_btn.pressed.connect(func() -> void:
				_map_overlay.visible = false
				SaveManager.set_current_map(m)
				SceneManager.goto("res://scenes/main.tscn"))
			row.add_child(play_btn)

			var del_btn := Button.new()
			del_btn.text = "🗑"
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.tooltip_text = "Map löschen"
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_map(m)
				_on_new_game())
			row.add_child(del_btn)
	_map_overlay.visible = true

func _on_load_save() -> void:
	for c in _saves_list_vb.get_children():
		c.queue_free()
	var entries := SaveManager.list_saves_named()
	if entries.is_empty():
		var lbl := Label.new()
		lbl.text = "(Keine Spielstände vorhanden)"
		_saves_list_vb.add_child(lbl)
	else:
		for entry: Dictionary in entries:
			var n: String = entry["name"]
			var ts: String = entry.get("timestamp", "")
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_saves_list_vb.add_child(row)

			var load_btn := Button.new()
			load_btn.text = "%s  (%s)" % [n, ts] if ts != "" else n
			load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			load_btn.pressed.connect(func() -> void:
				_saves_overlay.visible = false
				SaveManager.load_game_named(n)
				SceneManager.goto("res://scenes/main.tscn"))
			row.add_child(load_btn)

			var del_btn := Button.new()
			del_btn.text = "🗑"
			del_btn.custom_minimum_size = Vector2(36, 0)
			del_btn.tooltip_text = "Löschen"
			del_btn.pressed.connect(func() -> void:
				SaveManager.delete_save_named(n)
				_on_load_save())
			row.add_child(del_btn)
	_saves_overlay.visible = true

func _on_map_editor() -> void:
	SceneManager.goto("res://scenes/editor/map_editor.tscn")

func _on_host_game() -> void:
	NetworkManager.host_game()
	SceneManager.goto("res://scenes/main.tscn")

func _on_connection_error() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Verbindungsfehler"
	dlg.dialog_text = "Konnte keine Verbindung zum Server herstellen."
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _on_join_game() -> void:
	_ip_dialog.popup_centered()

func _on_ip_confirmed() -> void:
	var ip := _ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	NetworkManager.join_game(ip)

func _on_settings() -> void:
	_refresh_bind_btns()
	_settings_overlay.visible = true

func _refresh_bind_btns() -> void:
	for action in InputManager.ACTIONS:
		for slot in [0, 1]:
			var key: String = action + "_" + str(slot)
			if _bind_btns.has(key):
				(_bind_btns[key] as Button).text = InputManager.get_key_label(action, slot)

func _start_listening(action: String, slot: int, btn: Button) -> void:
	if _listening_btn:
		_listening_btn.text = InputManager.get_key_label(_listening_action, _listening_slot)
	_listening_action = action
	_listening_slot   = slot
	_listening_btn    = btn
	btn.text = "[ Taste drücken ]"

func _stop_listening() -> void:
	if _listening_btn:
		_listening_btn.text = InputManager.get_key_label(_listening_action, _listening_slot)
	_listening_action = ""
	_listening_slot   = -1
	_listening_btn    = null

func _input(event: InputEvent) -> void:
	if not _settings_overlay or not _settings_overlay.visible:
		return
	if _listening_action.is_empty():
		return
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed:
		return
	if ke.keycode == KEY_ESCAPE:
		_stop_listening()
	else:
		InputManager.rebind(_listening_action, _listening_slot, ke.keycode)
		_listening_btn.text = InputManager.get_key_label(_listening_action, _listening_slot)
		_stop_listening()
	get_viewport().set_input_as_handled()

func _on_resolution_selected(index: int) -> void:
	var res := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
	DisplayServer.window_set_size(res[index])
