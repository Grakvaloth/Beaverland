extends Node

const DAILY_CONSUMPTION_PER_BEAVER: float = 2.0   # WE pro Spieltag

var beaver_count: int = 0

signal water_consumed(amount_we: float, successful: bool)

func get_total_daily_demand() -> float:
	return float(beaver_count) * DAILY_CONSUMPTION_PER_BEAVER

func get_total_stored_we() -> float:
	var total: float = 0.0
	for node in get_tree().get_nodes_in_group("water_storage"):
		var s := node as WaterStorage
		if s != null:
			total += s.stored_we
	return total

func get_total_capacity_we() -> float:
	var total: float = 0.0
	for node in get_tree().get_nodes_in_group("water_storage"):
		var s := node as WaterStorage
		if s != null:
			total += s.capacity_we
	return total

func get_days_remaining() -> float:
	var demand := get_total_daily_demand()
	if demand <= 0.0:
		return INF
	return get_total_stored_we() / demand

func consume_water(amount_we: float) -> bool:
	var remaining: float = amount_we
	var storages := get_tree().get_nodes_in_group("water_storage")
	storages.sort_custom(func(a, b): return (a as WaterStorage).stored_we > (b as WaterStorage).stored_we)
	for node in storages:
		if remaining <= 0.0:
			break
		var s := node as WaterStorage
		if s == null:
			continue
		remaining -= s.withdraw(remaining)
	var success := remaining <= 0.0
	water_consumed.emit(amount_we - remaining, success)
	return success
