extends Node

const CONFIG_PATH := "user://input_bindings.cfg"

const ACTIONS: Array = [
	"cam_forward", "cam_backward", "cam_left", "cam_right",
	"cam_rotate_left", "cam_rotate_right",
	"game_pause", "game_speed_1", "game_speed_2", "game_speed_3",
	"build_rotate", "build_mirror", "build_delete",
]

const ACTION_LABELS: Dictionary = {
	"cam_forward":       "Kamera vorwärts",
	"cam_backward":      "Kamera rückwärts",
	"cam_left":          "Kamera links",
	"cam_right":         "Kamera rechts",
	"cam_rotate_left":   "Kamera drehen links",
	"cam_rotate_right":  "Kamera drehen rechts",
	"game_pause":        "Pause",
	"game_speed_1":      "Geschwindigkeit 1×",
	"game_speed_2":      "Geschwindigkeit 2×",
	"game_speed_3":      "Geschwindigkeit 3×",
	"build_rotate":      "Objekt drehen",
	"build_mirror":      "Objekt spiegeln",
	"build_delete":      "Löschen",
}

const _DEFAULTS: Dictionary = {
	"cam_forward":      {primary = KEY_W,      secondary = -1},
	"cam_backward":     {primary = KEY_S,      secondary = -1},
	"cam_left":         {primary = KEY_A,      secondary = -1},
	"cam_right":        {primary = KEY_D,      secondary = -1},
	"cam_rotate_left":  {primary = KEY_Q,      secondary = -1},
	"cam_rotate_right": {primary = KEY_E,      secondary = -1},
	"game_pause":       {primary = KEY_SPACE,  secondary = -1},
	"game_speed_1":     {primary = KEY_1,      secondary = -1},
	"game_speed_2":     {primary = KEY_2,      secondary = -1},
	"game_speed_3":     {primary = KEY_3,      secondary = -1},
	"build_rotate":     {primary = KEY_R,      secondary = -1},
	"build_mirror":     {primary = KEY_F,      secondary = -1},
	"build_delete":     {primary = KEY_DELETE, secondary = -1},
}

var _bindings: Dictionary = {}

func _ready() -> void:
	_bindings = {}
	for action in _DEFAULTS:
		_bindings[action] = {primary = _DEFAULTS[action].primary, secondary = _DEFAULTS[action].secondary}
	_load()
	_apply()

func _apply() -> void:
	for action in _bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		_add_key(action, _bindings[action].primary)
		_add_key(action, _bindings[action].secondary)

func _add_key(action: String, keycode: int) -> void:
	if keycode <= 0:
		return
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action, ev)

func rebind(action: String, slot: int, keycode: int) -> void:
	if not action in _bindings:
		return
	if slot == 0:
		_bindings[action].primary = keycode
	else:
		_bindings[action].secondary = keycode
	_apply()
	_save()

func get_key_label(action: String, slot: int) -> String:
	if not action in _bindings:
		return "—"
	var kc: int = _bindings[action].primary if slot == 0 else _bindings[action].secondary
	if kc <= 0:
		return "—"
	return OS.get_keycode_string(kc)

func _save() -> void:
	var cfg := ConfigFile.new()
	for action in _bindings:
		cfg.set_value("bindings", action + "_primary",   _bindings[action].primary)
		cfg.set_value("bindings", action + "_secondary", _bindings[action].secondary)
	cfg.save(CONFIG_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for action in _bindings:
		_bindings[action].primary   = cfg.get_value("bindings", action + "_primary",   _bindings[action].primary)
		_bindings[action].secondary = cfg.get_value("bindings", action + "_secondary",  _bindings[action].secondary)
