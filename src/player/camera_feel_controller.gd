class_name CameraFeelController
extends Node

signal footstep_requested(block_id: String)
signal land_requested(impact_speed: float)
signal dig_tick_requested(progress: float)

const CONFIG_PATH := "res://data/camera_feel.json"
const PolicyScript = preload("res://src/player/camera_feel_policy.gd")

var bob_enabled := true
var config: Dictionary = PolicyScript.defaults()
var _player: CharacterBody3D
var _pivot: Node3D
var _camera: Camera3D
var _pivot_base_position := Vector3(0.0, 1.62, 0.0)
var _bob_phase := 0.0
var _bob_offset := Vector2.ZERO
var _land_offset := 0.0
var _land_velocity := 0.0
var _was_grounded := true
var _fall_speed := 0.0
var _shake_strength := 0.0
var _noise := FastNoiseLite.new()
var _noise_time := 0.0
var _harvest_service: Node
var _last_step_block_check := 0.0
var _current_floor_block := "grass"
var _dig_tick_bucket := -1
var _footstep_count := 0
var _land_count := 0
var _dig_tick_count := 0
var _damage_shake_count := 0


func _ready() -> void:
	_load_config()
	_noise.seed = 918273
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 4.5
	_player = get_parent() as CharacterBody3D
	if _player != null:
		_pivot = _player.get_node_or_null("CameraPivot") as Node3D
		if _pivot != null:
			_camera = _pivot.get_node_or_null("Camera3D") as Camera3D
			_pivot_base_position = _pivot.position
		_connect_player_damage()
	set_physics_process(_player != null and _pivot != null and _camera != null)


func _exit_tree() -> void:
	_disconnect_harvest_service()
	_disconnect_player_damage()


func add_shake(strength: float) -> void:
	_shake_strength = minf(1.6, _shake_strength + maxf(0.0, strength))


func get_snapshot() -> Dictionary:
	return {
		"enabled": is_physics_processing(),
		"bob_enabled": bob_enabled,
		"configured_key_count": config.size(),
		"expected_key_count": PolicyScript.DEFAULTS.size(),
		"footstep_count": _footstep_count,
		"land_count": _land_count,
		"dig_tick_count": _dig_tick_count,
		"damage_shake_count": _damage_shake_count,
		"harvest_connected": _harvest_service != null and is_instance_valid(_harvest_service),
		"shake_strength": _shake_strength,
		"bob_offset": [_bob_offset.x, _bob_offset.y],
		"land_offset": _land_offset,
		"base_fov": float(config["base_fov"]),
		"sprint_fov": float(config["sprint_fov"]),
	}


func _physics_process(delta: float) -> void:
	if _player == null or _pivot == null or _camera == null:
		return
	var elapsed := clampf(delta, 0.0, 0.25)
	if not bool(_player.get("input_enabled")):
		_reset_pose(elapsed)
		_poll_harvest_service()
		return
	_noise_time += elapsed
	var velocity: Vector3 = _player.velocity
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := _player.is_on_floor()
	_update_bob(elapsed, horizontal_speed, grounded)
	_update_landing(elapsed, velocity, grounded)
	_update_fov(elapsed, horizontal_speed, grounded)
	_update_shake(elapsed)
	_poll_harvest_service()


func _reset_pose(delta: float) -> void:
	_bob_phase = 0.0
	_bob_offset = _bob_offset.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	_land_offset = lerpf(_land_offset, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	_shake_strength = 0.0
	_pivot.position = _pivot_base_position
	_camera.rotation.z = 0.0
	_camera.fov = lerpf(
		_camera.fov,
		float(config["base_fov"]),
		clampf(delta * float(config["fov_transition_speed"]), 0.0, 1.0)
	)


func _update_bob(delta: float, horizontal_speed: float, grounded: bool) -> void:
	var target_offset := Vector2.ZERO
	if bob_enabled and grounded and horizontal_speed > 0.4:
		var sprinting := horizontal_speed > float(config["sprint_speed_threshold"])
		var amplitude := float(
			config["bob_sprint_amplitude"] if sprinting else config["bob_walk_amplitude"]
		)
		var previous_phase := _bob_phase
		_bob_phase += delta * horizontal_speed * float(config["bob_step_frequency"])
		if floorf(previous_phase / PI) != floorf(_bob_phase / PI):
			_emit_footstep()
		target_offset = Vector2(
			cos(_bob_phase) * amplitude * float(config["bob_lateral_factor"]),
			sin(_bob_phase * 2.0) * amplitude * 0.5 - amplitude * 0.5
		)
	else:
		_bob_phase = 0.0
	_bob_offset = _bob_offset.lerp(target_offset, clampf(delta * 10.0, 0.0, 1.0))


func _update_landing(delta: float, velocity: Vector3, grounded: bool) -> void:
	if not grounded:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif not _was_grounded:
		var impact := _fall_speed
		_fall_speed = 0.0
		if impact > float(config["land_min_impact_speed"]):
			_land_velocity = -impact * 0.028
			if impact > float(config["land_sound_min_impact_speed"]):
				_land_count += 1
				land_requested.emit(impact)
	_was_grounded = grounded
	var depth := float(config["land_dip_depth"])
	_land_velocity += (-_land_offset * 90.0 - _land_velocity * 14.0) * delta
	_land_offset = clampf(_land_offset + _land_velocity * delta, -depth, depth)


func _update_fov(delta: float, horizontal_speed: float, grounded: bool) -> void:
	var sprinting := grounded and horizontal_speed > float(config["sprint_speed_threshold"])
	var target_fov := float(config["sprint_fov"] if sprinting else config["base_fov"])
	_camera.fov = lerpf(
		_camera.fov,
		target_fov,
		clampf(delta * float(config["fov_transition_speed"]), 0.0, 1.0)
	)


func _update_shake(delta: float) -> void:
	var roll := 0.0
	if _shake_strength > 0.003:
		var max_roll := deg_to_rad(float(config["shake_max_roll_degrees"]))
		roll = _noise.get_noise_1d(_noise_time * 14.0) * max_roll * _shake_strength
		_shake_strength = maxf(
			0.0,
			_shake_strength
			- float(config["shake_decay_per_second"]) * delta * _shake_strength
			- delta * 0.35
		)
	_camera.rotation.z = roll
	_pivot.position = _pivot_base_position + Vector3(
		_bob_offset.x, _bob_offset.y + _land_offset, 0.0
	)


func _poll_harvest_service() -> void:
	if _harvest_service != null and not is_instance_valid(_harvest_service):
		_harvest_service = null
	if _harvest_service != null:
		return
	var candidate: Variant = _player.get("harvest_service") if _player != null else null
	if candidate is not Node:
		return
	_harvest_service = candidate
	var callback := Callable(self, "_on_harvest_progress")
	if _harvest_service.has_signal("harvest_progress_changed") and not _harvest_service.is_connected(
		"harvest_progress_changed", callback
	):
		_harvest_service.connect("harvest_progress_changed", callback)


func _disconnect_harvest_service() -> void:
	if _harvest_service == null or not is_instance_valid(_harvest_service):
		_harvest_service = null
		return
	var callback := Callable(self, "_on_harvest_progress")
	if _harvest_service.has_signal("harvest_progress_changed") and _harvest_service.is_connected(
		"harvest_progress_changed", callback
	):
		_harvest_service.disconnect("harvest_progress_changed", callback)
	_harvest_service = null


func _connect_player_damage() -> void:
	if _player == null or not _player.has_signal("damage_requested"):
		return
	var callback := Callable(self, "_on_player_damage")
	if not _player.is_connected("damage_requested", callback):
		_player.connect("damage_requested", callback)


func _disconnect_player_damage() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_signal("damage_requested"):
		return
	var callback := Callable(self, "_on_player_damage")
	if _player.is_connected("damage_requested", callback):
		_player.disconnect("damage_requested", callback)


func _on_harvest_progress(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or str(snapshot.get("status", "progress")) != "progress":
		_dig_tick_bucket = -1
		return
	var progress := clampf(float(snapshot.get("progress", 0.0)), 0.0, 1.0)
	var bucket := floori(progress * 9.0)
	if bucket == _dig_tick_bucket:
		return
	_dig_tick_bucket = bucket
	_dig_tick_count += 1
	dig_tick_requested.emit(progress)


func _emit_footstep() -> void:
	_refresh_floor_block()
	_footstep_count += 1
	footstep_requested.emit(_current_floor_block)


func _refresh_floor_block() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_step_block_check < float(config["floor_poll_interval_seconds"]):
		return
	_last_step_block_check = now
	var world: Variant = _player.get("world") if _player != null else null
	if world == null or not world.has_method("get_block") or not world.has_method("world_to_block"):
		return
	var below: Vector3i = world.call(
		"world_to_block", _player.global_position + Vector3(0.0, -0.08, 0.0)
	)
	var block_id := str(world.call("get_block", below))
	if not block_id.is_empty() and block_id != "air":
		_current_floor_block = block_id


func _on_player_damage(_amount: float, _source: String) -> void:
	_damage_shake_count += 1
	add_shake(float(config["hurt_shake_strength"]))


func _load_config() -> void:
	var raw: Dictionary = {}
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				raw = parsed
	config = PolicyScript.normalize(raw)
	bob_enabled = bool(config["bob_enabled_default"])
