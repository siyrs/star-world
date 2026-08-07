class_name WeatherService
extends Node

signal weather_changed(snapshot: Dictionary)
signal exposure_applied(amount: float, state_id: String, snapshot: Dictionary)
signal weather_transitioned(previous_state_id: String, state_id: String, transition_index: int)

const RegistryScript = preload("res://src/weather/weather_registry.gd")
const SERIAL_VERSION := 1
const MAX_PROCESS_DELTA_SECONDS := 1.0
const MAX_ADVANCE_SECONDS := 300.0
const MAX_TRANSITIONS_PER_ADVANCE := 8
const EXPOSURE_INTERVAL_SECONDS := 5.0
const MAX_EXPOSURE_APPLICATIONS_PER_ADVANCE := 12

var registry = RegistryScript.new()
var survival: Node
var day_night: Node
var map_id := "star_continent"
var world_seed := 0
var current_state_id := "clear"
var remaining_seconds := 0.0
var transition_index := 0
var active := false
var _installed := false
var _exposure_elapsed := 0.0
var _transition_count := 0
var _exposure_application_count := 0
var _exhaustion_total := 0.0


func _ready() -> void:
	set_process(true)


func setup(p_survival: Node, p_day_night: Node) -> bool:
	survival = p_survival
	day_night = p_day_night
	_installed = registry.get_validation_errors().is_empty()
	return _installed


func begin_world(p_map_id: String, p_world_seed: int, saved_state: Dictionary = {}) -> void:
	active = false
	map_id = p_map_id if registry.get_profile(p_map_id).size() > 0 else "star_continent"
	world_seed = p_world_seed
	transition_index = 0
	_transition_count = 0
	_exposure_application_count = 0
	_exhaustion_total = 0.0
	_exposure_elapsed = 0.0
	if not _restore(saved_state):
		current_state_id = registry.get_default_state_id(map_id)
		remaining_seconds = registry.duration_for_state(
			map_id, current_state_id, world_seed, transition_index
		)
	_apply_current_state(true)


func activate() -> void:
	if not _installed or registry.get_state(map_id, current_state_id).is_empty():
		return
	active = true
	_apply_current_state(true)


func clear() -> void:
	active = false
	map_id = "star_continent"
	world_seed = 0
	current_state_id = "clear"
	remaining_seconds = 0.0
	transition_index = 0
	_exposure_elapsed = 0.0
	if day_night != null and day_night.has_method("set_weather_profile"):
		day_night.call("set_weather_profile", {})
	weather_changed.emit({})


func shutdown() -> void:
	clear()
	survival = null
	day_night = null
	set_process(false)


func _process(delta: float) -> void:
	if not active:
		return
	advance(minf(maxf(0.0, delta), MAX_PROCESS_DELTA_SECONDS))


func advance(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	var remaining_delta := minf(delta, MAX_ADVANCE_SECONDS)
	var transitions := 0
	while remaining_delta > 0.0001:
		if remaining_seconds <= 0.0001:
			if transitions >= MAX_TRANSITIONS_PER_ADVANCE:
				break
			_transition_weather()
			transitions += 1
		var step := minf(remaining_delta, remaining_seconds)
		remaining_seconds = maxf(0.0, remaining_seconds - step)
		remaining_delta -= step
		_exposure_elapsed += step
		_flush_exposure()
		if remaining_seconds <= 0.0001 and remaining_delta > 0.0001:
			if transitions >= MAX_TRANSITIONS_PER_ADVANCE:
				break
			_transition_weather()
			transitions += 1


func force_weather_state(state_id: String, duration_seconds: float = -1.0) -> bool:
	var state := registry.get_state(map_id, state_id)
	if state.is_empty():
		return false
	var previous := current_state_id
	current_state_id = state_id
	remaining_seconds = (
		clampf(duration_seconds, 1.0, 600.0)
		if duration_seconds > 0.0
		else registry.duration_for_state(map_id, state_id, world_seed, transition_index)
	)
	_exposure_elapsed = 0.0
	_apply_current_state(true)
	if previous != current_state_id:
		weather_transitioned.emit(previous, current_state_id, transition_index)
	return true


func get_snapshot() -> Dictionary:
	var state := registry.get_state(map_id, current_state_id)
	if state.is_empty():
		return {}
	var snapshot := state.duplicate(true)
	snapshot.merge(
		{
			"schema_version": SERIAL_VERSION,
			"map_id": map_id,
			"state_id": current_state_id,
			"remaining_seconds": remaining_seconds,
			"transition_index": transition_index,
			"transition_count": _transition_count,
			"exposure_application_count": _exposure_application_count,
			"exhaustion_total": _exhaustion_total,
			"active": active,
		},
		true
	)
	return snapshot


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"map_id": map_id,
		"state_id": current_state_id,
		"remaining_seconds": remaining_seconds,
		"transition_index": transition_index,
	}


func _restore(saved_state: Dictionary) -> bool:
	if saved_state.is_empty():
		return false
	if int(saved_state.get("version", 0)) > SERIAL_VERSION:
		return false
	var saved_map := str(saved_state.get("map_id", map_id))
	if saved_map != map_id:
		return false
	var saved_state_id := str(saved_state.get("state_id", ""))
	if registry.get_state(map_id, saved_state_id).is_empty():
		return false
	current_state_id = saved_state_id
	transition_index = clampi(int(saved_state.get("transition_index", 0)), 0, 1000000)
	var deterministic_duration := registry.duration_for_state(
		map_id, current_state_id, world_seed, transition_index
	)
	remaining_seconds = clampf(
		float(saved_state.get("remaining_seconds", deterministic_duration)),
		0.1,
		600.0
	)
	return true


func _transition_weather() -> void:
	var previous := current_state_id
	transition_index = mini(1000000, transition_index + 1)
	current_state_id = registry.choose_state_id(map_id, world_seed, transition_index)
	remaining_seconds = registry.duration_for_state(
		map_id, current_state_id, world_seed, transition_index
	)
	_transition_count += 1
	_exposure_elapsed = 0.0
	_apply_current_state(true)
	weather_transitioned.emit(previous, current_state_id, transition_index)


func _apply_current_state(emit_change: bool) -> void:
	var snapshot := get_snapshot()
	if day_night != null and day_night.has_method("set_weather_profile"):
		day_night.call("set_weather_profile", snapshot)
	if emit_change:
		weather_changed.emit(snapshot)


func _flush_exposure() -> void:
	var applications := 0
	while (
		_exposure_elapsed >= EXPOSURE_INTERVAL_SECONDS
		and applications < MAX_EXPOSURE_APPLICATIONS_PER_ADVANCE
	):
		_exposure_elapsed -= EXPOSURE_INTERVAL_SECONDS
		applications += 1
		_apply_exposure(EXPOSURE_INTERVAL_SECONDS)
	if applications >= MAX_EXPOSURE_APPLICATIONS_PER_ADVANCE:
		_exposure_elapsed = minf(_exposure_elapsed, EXPOSURE_INTERVAL_SECONDS)


func _apply_exposure(elapsed_seconds: float) -> void:
	var state := registry.get_state(map_id, current_state_id)
	var rate := clampf(float(state.get("exhaustion_per_minute", 0.0)), 0.0, 0.5)
	if rate <= 0.0 or survival == null or not is_instance_valid(survival):
		return
	if not survival.has_method("add_exhaustion"):
		return
	var amount := minf(0.25, rate * maxf(0.0, elapsed_seconds) / 60.0)
	if amount <= 0.0:
		return
	survival.call("add_exhaustion", amount)
	_exposure_application_count += 1
	_exhaustion_total += amount
	exposure_applied.emit(amount, current_state_id, get_snapshot())
