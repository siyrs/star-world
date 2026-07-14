class_name DayNightService
extends Node

signal time_changed(time_of_day: float, day: int)
signal phase_changed(phase: String)
signal night_state_changed(is_night: bool)
signal time_skipped(previous_time: float, previous_day: int, time_of_day: float, day: int)

const SERIAL_VERSION := 1

@export_range(60.0, 3600.0, 1.0) var cycle_duration_seconds: float = 600.0
@export_range(0.0, 24.0, 0.1) var time_of_day: float = 8.0
@export var day_count: int = 1
@export var running: bool = true

var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var map_id: String = "star_continent"
var _last_phase: String = ""
var _last_night: bool = false


func _ready() -> void:
	_apply_lighting()


func _process(delta: float) -> void:
	if not running:
		return
	var previous_day := day_count
	time_of_day += delta * 24.0 / maxf(1.0, cycle_duration_seconds)
	while time_of_day >= 24.0:
		time_of_day -= 24.0
		day_count += 1
	_apply_lighting()
	if previous_day != day_count or Engine.get_process_frames() % 12 == 0:
		time_changed.emit(time_of_day, day_count)


func attach_lighting(p_sun: DirectionalLight3D, p_environment: WorldEnvironment = null) -> void:
	sun = p_sun
	world_environment = p_environment
	_apply_lighting()


func set_map_profile(p_map_id: String) -> void:
	map_id = p_map_id
	_apply_lighting()


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)


func skip_to_time(hours: float) -> Dictionary:
	var previous_time := time_of_day
	var previous_day := day_count
	var target := fposmod(hours, 24.0)
	if target <= time_of_day:
		day_count += 1
	time_of_day = target
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)
	time_skipped.emit(previous_time, previous_day, time_of_day, day_count)
	return {
		"previous_time": previous_time,
		"previous_day": previous_day,
		"time_of_day": time_of_day,
		"day": day_count,
	}


func is_night() -> bool:
	return time_of_day < 6.0 or time_of_day >= 19.0


func get_phase() -> String:
	if time_of_day < 5.0:
		return "night"
	if time_of_day < 7.0:
		return "dawn"
	if time_of_day < 18.0:
		return "day"
	if time_of_day < 20.0:
		return "dusk"
	return "night"


func get_sun_strength() -> float:
	var angle := (time_of_day - 6.0) / 24.0 * TAU
	return clampf(sin(angle), 0.0, 1.0)


func _apply_lighting() -> void:
	var strength := get_sun_strength()
	if map_id == "abyss_world":
		strength *= 0.18
	if sun != null and is_instance_valid(sun):
		sun.rotation_degrees = Vector3(time_of_day / 24.0 * 360.0 - 90.0, -35.0, 0.0)
		sun.light_energy = lerpf(0.08, 1.15, strength)
		sun.light_color = Color("#9CB7E8").lerp(Color("#FFF1CD"), strength)
	if (
		world_environment != null
		and is_instance_valid(world_environment)
		and world_environment.environment != null
	):
		var environment := world_environment.environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("#17213A").lerp(Color("#AFC7D2"), strength)
		environment.ambient_light_energy = lerpf(0.25, 0.85, strength)
		environment.background_mode = Environment.BG_COLOR
		var day_color := Color("#72B5E8")
		if map_id == "desert_ruins":
			day_color = Color("#E2B96C")
		elif map_id == "frozen_wastes":
			day_color = Color("#A9D1E7")
		elif map_id == "sky_islands":
			day_color = Color("#78C8FA")
		elif map_id == "abyss_world":
			day_color = Color("#191D31")
		environment.background_color = Color("#091020").lerp(day_color, strength)
	var phase := get_phase()
	if phase != _last_phase:
		_last_phase = phase
		phase_changed.emit(phase)
	var night := is_night()
	if night != _last_night:
		_last_night = night
		night_state_changed.emit(night)


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"time_of_day": time_of_day,
		"day": day_count,
		"cycle_duration": cycle_duration_seconds,
		"map_id": map_id,
	}


func deserialize(data: Dictionary) -> bool:
	time_of_day = fposmod(float(data.get("time_of_day", 8.0)), 24.0)
	day_count = maxi(1, int(data.get("day", 1)))
	cycle_duration_seconds = maxf(60.0, float(data.get("cycle_duration", 600.0)))
	map_id = str(data.get("map_id", map_id))
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)
	return true
