class_name ExplorationDangerService
extends Node

signal danger_changed(snapshot: Dictionary)

const RegistryScript = preload("res://src/exploration/exploration_danger_registry.gd")
const PolicyScript = preload("res://src/exploration/exploration_danger_policy.gd")

var registry = RegistryScript.new()
var day_night: Node
var creature_spawner: Node
var world: Node
var player: Node3D
var active := false
var _snapshot: Dictionary = {}
var _remaining := 0.0
var _cached_sample: Dictionary = {}
var _cached_sample_center := Vector3i.ZERO
var _has_cached_sample := false
var _assessment_count := 0
var _environment_scan_count := 0
var _environment_reuse_count := 0
var _environment_sample_total := 0
var _max_samples_observed := 0
var _last_sample_count := 0
var _last_budget_exhausted := false
var _last_reused_environment := false


func _ready() -> void:
	set_process(false)


func setup(p_day_night: Node, p_creature_spawner: Node) -> bool:
	day_night = p_day_night
	creature_spawner = p_creature_spawner
	return registry.get_validation_errors().is_empty()


func attach_world(p_world: Node, p_player: Node3D) -> void:
	world = p_world
	player = p_player
	_snapshot.clear()
	_remaining = 0.0
	_reset_environment_cache()
	_reset_diagnostics()
	if active:
		refresh_now()


func activate() -> void:
	active = true
	set_process(true)
	_remaining = 0.0
	refresh_now()


func deactivate() -> void:
	active = false
	set_process(false)
	_remaining = 0.0


func clear() -> void:
	deactivate()
	world = null
	player = null
	_snapshot.clear()
	_reset_environment_cache()
	_reset_diagnostics()


func _process(delta: float) -> void:
	if not active:
		return
	_remaining -= maxf(0.0, delta)
	if _remaining > 0.0:
		return
	var config := registry.get_config()
	_remaining = maxf(0.25, float(config.get("assessment_interval_seconds", 0.75)))
	refresh_now()


func refresh_now() -> Dictionary:
	return _refresh(false)


func refresh_for_events() -> Dictionary:
	return _refresh(true)


func _refresh(reuse_environment: bool) -> Dictionary:
	if (
		world == null
		or player == null
		or not is_instance_valid(world)
		or not is_instance_valid(player)
		or not world.has_method("world_to_block")
		or not world.has_method("get_initial_block")
	):
		return _snapshot.duplicate(true)
	var config := registry.get_config()
	var center: Vector3i = world.call("world_to_block", player.global_position)
	var can_reuse := (
		reuse_environment
		and _has_cached_sample
		and center == _cached_sample_center
		and not _cached_sample.is_empty()
	)
	var sample: Dictionary
	if can_reuse:
		sample = _cached_sample.duplicate(true)
		_environment_reuse_count += 1
	else:
		sample = _sample_environment(center, config)
		_cached_sample = sample.duplicate(true)
		_cached_sample_center = center
		_has_cached_sample = true
		_environment_scan_count += 1
		_environment_sample_total += int(sample.get("total_samples", 0))
		_max_samples_observed = maxi(
			_max_samples_observed, int(sample.get("total_samples", 0))
		)
	_assessment_count += 1
	_last_sample_count = int(sample.get("total_samples", 0))
	_last_budget_exhausted = bool(sample.get("budget_exhausted", false))
	_last_reused_environment = can_reuse
	var phase := "day"
	if day_night != null and day_night.has_method("get_phase"):
		phase = str(day_night.call("get_phase"))
	var hostile_count := 0
	if creature_spawner != null and creature_spawner.has_method("get_nearby_hostile_count"):
		hostile_count = int(
			creature_spawner.call(
				"get_nearby_hostile_count",
				player.global_position,
				float(config.get("hostile_radius", 18.0))
			)
		)
	var hostile_pressure := float(hostile_count)
	if creature_spawner != null and creature_spawner.has_method("get_nearby_hostile_pressure"):
		hostile_pressure = maxf(
			float(hostile_count),
			float(
				creature_spawner.call(
					"get_nearby_hostile_pressure",
					player.global_position,
					float(config.get("hostile_radius", 18.0))
				)
			)
		)
	var windup_summary: Dictionary = {}
	if (
		creature_spawner != null
		and creature_spawner.has_method("get_nearby_hostile_windup_summary")
	):
		var raw_windup: Variant = creature_spawner.call(
			"get_nearby_hostile_windup_summary",
			player.global_position,
			float(config.get("hostile_radius", 18.0))
		)
		if raw_windup is Dictionary:
			windup_summary = raw_windup
	var ecology: Dictionary = {}
	if creature_spawner != null and creature_spawner.has_method("get_ecology_snapshot"):
		var raw_ecology: Variant = creature_spawner.call("get_ecology_snapshot")
		if raw_ecology is Dictionary:
			ecology = raw_ecology
	var map_id := str(world.get("profile_id"))
	var context := {
		"map_id": map_id,
		"map_base": int(ecology.get("danger_base", 0)),
		"player_y": center.y,
		"phase": phase,
		"hostile_count": hostile_count,
		"hostile_pressure": hostile_pressure,
		"windup_count": int(windup_summary.get("active_windup_count", 0)),
		"elite_windup_count": int(windup_summary.get("elite_windup_count", 0)),
		"windup_pressure": float(windup_summary.get("windup_pressure", 0.0)),
		"soonest_impact_seconds": float(
			windup_summary.get("soonest_impact_seconds", -1.0)
		),
		"windup_source_counts": (
			windup_summary.get("source_counts", {}).duplicate(true)
			if windup_summary.get("source_counts", {}) is Dictionary
			else {}
		),
		"windup_scanned_nodes": int(windup_summary.get("visited_nodes", 0)),
		"windup_query_cap": int(windup_summary.get("query_node_cap", 0)),
		"windup_scan_cap_reached": bool(windup_summary.get("scan_cap_reached", false)),
		"lava_samples": int(sample.get("lava_samples", 0)),
		"air_samples": int(sample.get("air_samples", 0)),
		"total_samples": int(sample.get("total_samples", 0)),
	}
	var next_snapshot := PolicyScript.assess(context, config)
	next_snapshot["updated_at_msec"] = Time.get_ticks_msec()
	next_snapshot["ecology"] = ecology.duplicate(true)
	next_snapshot["assessment"] = get_diagnostics()
	var changed := _snapshot.is_empty() or _meaningfully_changed(_snapshot, next_snapshot)
	_snapshot = next_snapshot.duplicate(true)
	if changed:
		danger_changed.emit(_snapshot.duplicate(true))
	return _snapshot.duplicate(true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_diagnostics() -> Dictionary:
	var config := registry.get_config()
	return {
		"assessment_count": _assessment_count,
		"environment_scan_count": _environment_scan_count,
		"environment_reuse_count": _environment_reuse_count,
		"environment_sample_total": _environment_sample_total,
		"max_samples_observed": _max_samples_observed,
		"last_sample_count": _last_sample_count,
		"sample_budget": maxi(1, int(config.get("max_samples", 125))),
		"last_budget_exhausted": _last_budget_exhausted,
		"last_reused_environment": _last_reused_environment,
	}


func _sample_environment(center: Vector3i, config: Dictionary) -> Dictionary:
	var horizontal_radius := maxi(1, int(config.get("horizontal_radius", 4)))
	var vertical_radius := maxi(1, int(config.get("vertical_radius", 4)))
	var horizontal_step := maxi(1, int(config.get("horizontal_step", 2)))
	var vertical_step := maxi(1, int(config.get("vertical_step", 2)))
	var max_samples := maxi(1, int(config.get("max_samples", 125)))
	var total_samples := 0
	var air_samples := 0
	var lava_samples := 0
	var minimum_y := maxi(1, center.y - vertical_radius)
	var maximum_y := mini(63, center.y + vertical_radius)
	var exhausted := false
	for x in range(center.x - horizontal_radius, center.x + horizontal_radius + 1, horizontal_step):
		for z in range(center.z - horizontal_radius, center.z + horizontal_radius + 1, horizontal_step):
			for y in range(minimum_y, maximum_y + 1, vertical_step):
				if total_samples >= max_samples:
					exhausted = true
					break
				var block_id := str(world.call("get_initial_block", Vector3i(x, y, z)))
				total_samples += 1
				if block_id == "air":
					air_samples += 1
				elif block_id == "lava":
					lava_samples += 1
			if exhausted:
				break
		if exhausted:
			break
	return {
		"total_samples":total_samples,
		"air_samples":air_samples,
		"lava_samples":lava_samples,
		"budget_exhausted":exhausted,
	}


func _meaningfully_changed(previous: Dictionary, current: Dictionary) -> bool:
	return (
		str(previous.get("tier_id", "")) != str(current.get("tier_id", ""))
		or int(previous.get("hostile_count", 0)) != int(current.get("hostile_count", 0))
		or absf(
			float(previous.get("hostile_pressure", 0.0))
			- float(current.get("hostile_pressure", 0.0))
		) >= 0.5
		or int(previous.get("windup_count", 0)) != int(current.get("windup_count", 0))
		or int(previous.get("elite_windup_count", 0))
		!= int(current.get("elite_windup_count", 0))
		or _impact_changed(previous, current)
		or str(previous.get("phase", "")) != str(current.get("phase", ""))
		or absf(float(previous.get("score", 0)) - float(current.get("score", 0))) >= 5.0
	)


func _impact_changed(previous: Dictionary, current: Dictionary) -> bool:
	var previous_value := float(previous.get("soonest_impact_seconds", -1.0))
	var current_value := float(current.get("soonest_impact_seconds", -1.0))
	if previous_value < 0.0 or current_value < 0.0:
		return (previous_value < 0.0) != (current_value < 0.0)
	return absf(previous_value - current_value) >= 0.2


func _reset_environment_cache() -> void:
	_cached_sample.clear()
	_cached_sample_center = Vector3i.ZERO
	_has_cached_sample = false


func _reset_diagnostics() -> void:
	_assessment_count = 0
	_environment_scan_count = 0
	_environment_reuse_count = 0
	_environment_sample_total = 0
	_max_samples_observed = 0
	_last_sample_count = 0
	_last_budget_exhausted = false
	_last_reused_environment = false
