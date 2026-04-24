class_name WaterPump
extends Node3D

@export var grid_x: int = 0
@export var grid_z: int = 0
@export var pump_rate_we: float = 5.0    # WE pro Sekunde (klein=5, groß=20)
@export var active: bool = true
@export var target_storage: NodePath

signal pump_dry
signal pump_active(we_per_second: float)

var _water_grid: WaterGrid = null
var _was_dry: bool = false

func _ready() -> void:
	add_to_group("water_pump")
	await get_tree().process_frame
	_water_grid = get_tree().get_first_node_in_group("water_grid") as WaterGrid

func _process(delta: float) -> void:
	if not active or _water_grid == null:
		return
	var demand_m: float = _water_grid.we_to_meters(pump_rate_we * delta)
	var available: float = _water_grid.get_water_level(grid_x, grid_z)
	if available < WaterGrid.MIN_WATER:
		if not _was_dry:
			_was_dry = true
			pump_dry.emit()
		return
	_was_dry = false
	var taken_m: float = _water_grid.remove_water(grid_x, grid_z, minf(demand_m, available))
	var taken_we: float = _water_grid.meters_to_we(taken_m)
	if taken_we > 0.0:
		var storage := get_node_or_null(target_storage) as WaterStorage
		if storage != null:
			storage.deposit(taken_we)
		pump_active.emit(taken_we / maxf(delta, 0.0001))
