class_name WaterStorage
extends Node3D

@export var capacity_we: float = 100.0

var stored_we: float = 0.0

signal storage_changed(current_we: float)
signal storage_empty
signal storage_full

func _ready() -> void:
	add_to_group("water_storage")

func deposit(amount_we: float) -> float:
	var space: float = capacity_we - stored_we
	var accepted: float = minf(maxf(0.0, amount_we), space)
	stored_we += accepted
	storage_changed.emit(stored_we)
	if is_equal_approx(stored_we, capacity_we):
		storage_full.emit()
	return amount_we - accepted

func withdraw(amount_we: float) -> float:
	var taken: float = minf(stored_we, maxf(0.0, amount_we))
	stored_we -= taken
	storage_changed.emit(stored_we)
	if stored_we <= 0.0:
		storage_empty.emit()
	return taken

func get_fill_percent() -> float:
	if capacity_we <= 0.0:
		return 0.0
	return stored_we / capacity_we
