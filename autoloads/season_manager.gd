extends Node

enum Season { TEMPERATE, DROUGHT }

signal season_changed(season: Season)
signal day_changed(day: int, season: Season)

const TEMPERATE_DAYS  := 8
const DROUGHT_DAYS    := 5
const SECONDS_PER_DAY := 30.0

var current_season: Season = Season.TEMPERATE
var current_day:    int    = 1
var _day_timer:     float  = 0.0
var _running:       bool   = false

func _process(delta: float) -> void:
	if not _running:
		return
	_day_timer += delta
	if _day_timer >= SECONDS_PER_DAY:
		_day_timer -= SECONDS_PER_DAY
		_advance_day()

func start() -> void:
	_running = true

func stop() -> void:
	_running = false

func _advance_day() -> void:
	current_day += 1
	var season_len := TEMPERATE_DAYS if current_season == Season.TEMPERATE else DROUGHT_DAYS
	if current_day > season_len:
		current_day = 1
		_switch_season()
	day_changed.emit(current_day, current_season)

func _switch_season() -> void:
	current_season = Season.DROUGHT if current_season == Season.TEMPERATE else Season.TEMPERATE
	season_changed.emit(current_season)
	_apply_to_water_grid()

func _apply_to_water_grid() -> void:
	var wg := _find_water_grid()
	if wg:
		wg.set_drought(current_season == Season.DROUGHT)

func _find_water_grid() -> WaterGrid:
	var root := get_tree().current_scene
	if root:
		return root.get_node_or_null("Water") as WaterGrid
	return null

func get_progress() -> float:
	var total := float(TEMPERATE_DAYS if current_season == Season.TEMPERATE else DROUGHT_DAYS)
	return float(current_day - 1) / total

func get_save_data() -> Dictionary:
	return {
		"season": "DROUGHT" if current_season == Season.DROUGHT else "TEMPERATE",
		"day": current_day,
		"timer": _day_timer,
	}

func restore_from_data(data: Dictionary) -> void:
	current_season = Season.DROUGHT if data.get("season", "") == "DROUGHT" else Season.TEMPERATE
	current_day    = int(data.get("day", 1))
	_day_timer     = float(data.get("timer", 0.0))
	_apply_to_water_grid()
