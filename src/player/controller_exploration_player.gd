class_name ControllerExplorationPlayer
extends "res://src/player/exploration_player.gd"

var _controller_primary_active := false
var _controller_primary_press_count := 0
var _controller_primary_release_count := 0
var _controller_secondary_count := 0
var _controller_hotbar_cycle_count := 0
var _controller_look_frame_count := 0
var _last_controller_look := Vector2.ZERO


func set_input_enabled(enabled: bool) -> void:
	if not enabled:
		_release_controller_primary("input_disabled")
	super.set_input_enabled(enabled)


func reset_motion() -> void:
	_release_controller_primary("motion_reset")
	super.reset_motion()


func _process(delta: float) -> void:
	if input_enabled:
		_sync_controller_primary()
	super._process(delta)
	if not input_enabled:
		return
	_apply_controller_look(delta)
	_handle_controller_commands()


func get_controller_gameplay_snapshot() -> Dictionary:
	return {
		"primary_active": _controller_primary_active,
		"primary_press_count": _controller_primary_press_count,
		"primary_release_count": _controller_primary_release_count,
		"secondary_count": _controller_secondary_count,
		"hotbar_cycle_count": _controller_hotbar_cycle_count,
		"look_frame_count": _controller_look_frame_count,
		"last_look": _last_controller_look,
		"selected_hotbar_index": selected_hotbar_index,
	}


func _sync_controller_primary() -> void:
	if input_service == null or not input_service.has_method("is_primary_action_pressed"):
		_release_controller_primary("service_unavailable")
		return
	var pressed := bool(input_service.call("is_primary_action_pressed"))
	if pressed and not _controller_primary_active:
		_controller_primary_active = true
		_controller_primary_press_count += 1
		_primary_action_held = true
		_start_primary_action()
	elif not pressed and _controller_primary_active:
		_release_controller_primary("controller_released")


func _release_controller_primary(reason: String) -> void:
	if not _controller_primary_active:
		return
	_controller_primary_active = false
	_controller_primary_release_count += 1
	_primary_action_held = false
	_cancel_harvest(reason)


func _apply_controller_look(delta: float) -> void:
	if input_service == null or not input_service.has_method("get_look_vector"):
		_last_controller_look = Vector2.ZERO
		return
	var look_vector: Vector2 = input_service.call("get_look_vector")
	_last_controller_look = look_vector
	if look_vector.length_squared() <= 0.0001:
		return
	var look_speed := 2.8
	if input_service.has_method("get_look_speed_radians_per_second"):
		look_speed = maxf(
			0.0,
			float(input_service.call("get_look_speed_radians_per_second"))
		)
	var rotation_delta := look_vector * look_speed * maxf(0.0, delta)
	rotate_y(-rotation_delta.x)
	camera_pivot.rotate_x(-rotation_delta.y)
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x,
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	_controller_look_frame_count += 1
	_report_action_once(&"look")


func _handle_controller_commands() -> void:
	if input_service == null:
		return
	if (
		input_service.has_method("is_secondary_action_just_pressed")
		and bool(input_service.call("is_secondary_action_just_pressed"))
	):
		_controller_secondary_count += 1
		interact_or_use_selected_item()
	if input_service.has_method("get_hotbar_cycle_just_pressed"):
		var direction := int(input_service.call("get_hotbar_cycle_just_pressed"))
		if direction != 0:
			_controller_hotbar_cycle_count += 1
			select_hotbar(selected_hotbar_index + direction)
