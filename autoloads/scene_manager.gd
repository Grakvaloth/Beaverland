extends Node

var _overlay: ColorRect
var _canvas: CanvasLayer

func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100
	add_child(_canvas)
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_overlay)
	# Größe nach add_child setzen, damit Viewport-Größe bekannt ist
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func goto(scene_path: String) -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 1.0, 0.3)
	await tw.finished
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneManager: Szene nicht geladen '%s' (Fehler %d)" % [scene_path, err])
		tw = create_tween()
		tw.tween_property(_overlay, "color:a", 0.0, 0.3)
		return
	tw = create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, 0.3)
