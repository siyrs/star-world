class_name CameraFeelController
extends Node

# First-person "game feel" layer: subtle head bob, sprint FOV kick, landing
# dip and damage shake. All magnitudes are data-driven (camera_feel.json),
# the bob is deliberately small and can be disabled for motion-sensitive
# players, and the controller owns no gameplay state.

signal footstep_requested(block_id: String)
signal land_requested(impact_speed: float)
signal dig_tick_requested(progress: float)

const CONFIG_PATH := "res://data/camera_feel.json"

var bob_enabled := true
var config: Dictionary = {}
var _player: CharacterBody3D
var _pivot: Node3D
var _camera: Camera3D
var _pivot_base_y := 1.62
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


func _ready() -> void:
	_load_config()
	_noise.seed = 918273
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 4.5
	_player = get_parent() as CharacterBody3D
	if _player != null:
		_pivot = _player.get_node_or_null("CameraPivot")
		if _pivot != null:
			_camera = _pivot.get_node_or_null("Camera3D")
			_pivot_base_y = _pivot.position.y
		if _player.has_signal("damage_requested"):
			_player.connect("damage_requested", Callable(self, "_on_player_damage"))
	set_physics_process(_player != null and _pivot != null and _camera != null)


func add_shake(strength: float) -> void:
	_shake_strength = minf(1.6, _shake_strength + maxf(0.0, strength))


func _physics_process(delta: float) -> void:
	if _player == null or _pivot == null or _camera == null:
		return
	if not bool(_player.get("input_enabled")):
		_pivot.position = Vector3(0.0, _pivot_base_y, 0.0)
		_camera.rotation.z = 0.0
		return
	_noise_time += delta
	var velocity: Vector3 = _player.velocity
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := _player.is_on_floor()
	_update_bob(delta, horizontal_speed, grounded)
	_update_landing(velocity, grounded)
	_update_fov(delta, horizontal_speed, grounded)
	_update_shake(delta)
	_poll_dig_ticks()


func _update_bob(delta: float, horizontal_speed: float, grounded: bool) -> void:
	var target_offset := Vector2.ZERO
	if bob_enabled and grounded and horizontal_speed > 0.4:
		var sprinting: bool = horizontal_speed > float(config.get("sprint_speed_threshold", 6.4))
		var amplitude := float(
			config.get("bob_sprint_amplitude", 0.052) if sprinting
			else config.get("bob_walk_amplitude", 0.035)
		)
		var step_frequency := float(config.get("bob_step_frequency", 1.85))
		var previous_phase := _bob_phase
		_bob_phase += delta * horizontal_speed * step_frequency
		if floorf(previous_phase / PI) != floorf(_bob_phase / PI):
			_emit_footstep()
		target_offset = Vector2(
			cos(_bob_phase) * amplitude * float(config.get("bob_lateral_factor", 0.55)),
			sinf(_bob_phase * 2.0) * amplitude * 0.5 - amplitude * 0.5
		)
	else:
		_bob_phase = 0.0
	_bob_offset = _bob_offset.lerp(target_offset, clampf(delta * 10.0, 0.0, 1.0))


func _update_landing(velocity: Vector3, grounded: bool) -> void:
	if not grounded:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif not _was_grounded and grounded:
		var impact := _fall_speed
		_fall_speed = 0.0
		if impact > float(config.get("land_min_impact_speed", 3.2)):
			_land_velocity = -impact * 0.028
			if impact > float(config.get("land_sound_min_impact_speed", 4.6)):
				land_requested.emit(impact)
	_was_grounded = grounded
	# Critically-damped-ish spring back to rest for the landing dip.
	var depth := float(config.get("land_dip_depth", 0.085))
	var dt := get_physics_process_delta_time()
	_land_velocity += (-_land_offset * 90.0 - _land_velocity * 14.0) * dt
	_land_offset = clampf(_land_offset + _land_velocity * dt, -depth, depth)


func _update_fov(delta: float, horizontal_speed: float, grounded: bool) -> void:
	var sprinting: bool = (
		grounded and horizontal_speed > float(config.get("sprint_speed_threshold", 6.4))
	)
	var target_fov := float(
		config.get("sprint_fov", 82.0) if sprinting else config.get("base_fov", 75.0)
	)
	var speed := float(config.get("fov_transition_speed", 7.0))
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * speed, 0.0, 1.0))


func _update_shake(delta: float) -> void:
	var roll := 0.0
	if _shake_strength > 0.003:
		var max_roll := deg_to_rad(float(config.get("shake_max_roll_degrees", 1.6)))
		roll = _noise.get_noise_1d(_noise_time * 14.0) * max_roll * _shake_strength
		_shake_strength = maxf(
			0.0,
			_shake_strength - float(config.get("shake_decay_per_second", 6.5) * delta) * _shake_strength
				- delta * 0.35
		)
	_camera.rotation.z = roll
	_pivot.position.y = _pivot_base_y + _bob_offset.y + _land_offset
	_pivot.position.x = _bob_offset.x


func _poll_dig_ticks() -> void:
	# The harvest service advances continuously while the primary button is
	# held; surface one tick per progress chunk so mining sounds like work.
	if _harvest_service == null:
		var candidate: Variant = _player.get("harvest_service")
		if candidate is Node:
			_harvest_service = candidate
			if _harvest_service.has_signal("harvest_progress_changed"):
				_harvest_service.connect(
					"harvest_progress_changed", Callable(self, "_on_harvest_progress")
				)
	elif not is_instance_valid(_harvest_service):
		_harvest_service = null


func _on_harvest_progress(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or str(snapshot.get("status", "progress")) != "progress":
		set_meta("last_dig_tick_bucket", -1.0)
		return
	var progress := float(snapshot.get("progress", 0.0))
	var last := float(get_meta("last_dig_tick_bucket", -1.0))
	var bucket := floorf(progress * 9.0)
	if bucket != last:
		set_meta("last_dig_tick_bucket", bucket)
		dig_tick_requested.emit(progress)


func _emit_footstep() -> void:
	_refresh_floor_block()
	footstep_requested.emit(_current_floor_block)


func _refresh_floor_block() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_step_block_check < 0.12:
		return
	_last_step_block_check = now
	var world: Variant = _player.get("world")
	if world == null or not world.has_method("get_block"):
		return
	var below: Vector3i = world.call(
		"world_to_block", _player.global_position + Vector3(0.0, -0.08, 0.0)
	)
	var block_id := str(world.call("get_block", below))
	if block_id.is_empty() or block_id == "air":
		return
	_current_floor_block = block_id


func _on_player_damage(_amount: float, _source: String) -> void:
	add_shake(float(config.get("hurt_shake_strength", 0.9)))


func _load_config() -> void:
	config = {
		"bob_walk_amplitude": 0.035,
		"bob_sprint_amplitude": 0.052,
		"bob_lateral_factor": 0.55,
		"bob_step_frequency": 1.85,
		"sprint_fov": 82.0,
		"base_fov": 75.0,
		"fov_transition_speed": 7.0,
		"sprint_speed_threshold": 6.4,
		"land_dip_depth": 0.085,
		"land_min_impact_speed": 3.2,
		"land_sound_min_impact_speed": 4.6,
		"shake_decay_per_second": 6.5,
		"shake_max_roll_degrees": 1.6,
		"hurt_shake_strength": 0.9,
	}
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				config.merge(parsed, true)
	bob_enabled = bool(config.get("bob_enabled_default", true))
