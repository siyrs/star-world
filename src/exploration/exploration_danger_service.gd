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
	var sample := _sample_environment(center, config)
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
		"lava_samples": int(sample.get("lava_samples", 0)),
		"air_samples": int(sample.get("air_samples", 0)),
		"total_samples": int(sample.get("total_samples", 0)),
	}
	var next_snapshot := PolicyScript.assess(context, config)
	next_snapshot["updated_at_msec"] = Time.get_ticks_msec()
	next_snapshot["ecology"] = ecology.duplicate(true)
	var changed := _snapshot.is_empty() or _meaningfully_changed(_snapshot, next_snapshot)
	_snapshot = next_snapshot.duplicate(true)
	if changed:
		danger_changed.emit(_snapshot.duplicate(true))
	return _snapshot.duplicate(true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


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
		or str(previous.get("phase", "")) != str(current.get("phase", ""))
		or absf(float(previous.get("score", 0)) - float(current.get("score", 0))) >= 5.0
	)
