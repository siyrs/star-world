class_name GameplayInputService
extends Node

signal bindings_ready(repaired_actions: Array[StringName])

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const ControllerProfileScript = preload("res://src/input/gameplay_controller_profile.gd")

var _bindings_initialized := false
var _active := false
var _raw_key_state: Dictionary = {}
var _last_key_event := "无"
var _last_controller_event := "无"
var _last_movement_vector := Vector2.ZERO
var _last_nonzero_movement_vector := Vector2.ZERO
var _last_look_vector := Vector2.ZERO
var _controller_event_count := 0
var _controller_profile = ControllerProfileScript.new()


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_bindings(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_raw_state()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.echo:
			return
		var key_event := event as InputEventKey
		for keycode: Key in [
			KEY_W, KEY_A, KEY_S, KEY_D,
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
			KEY_SHIFT, KEY_SPACE,
		]:
			if _matches_key(key_event, keycode):
				_raw_key_state[keycode] = key_event.pressed if _active else false
				_last_key_event = "%s %s" % [
					OS.get_keycode_string(keycode),
					"按下" if key_event.pressed else "松开",
				]
		return
	if not _active:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_controller_event_count += 1
		_last_controller_event = _describe_controller_event(event)


func ensure_bindings(force: bool = false) -> Array[StringName]:
	if _bindings_initialized and not force:
		return []
	var repaired := Actions.ensure_default_bindings()
	_bindings_initialized = true
	bindings_ready.emit(repaired)
	return repaired


func repair_bindings() -> Array[StringName]:
	return ensure_bindings(true)


func set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	if not _active:
		release_raw_state()


func is_active() -> bool:
	return _active


func release_raw_state() -> void:
	_raw_key_state.clear()
	_last_movement_vector = Vector2.ZERO
	_last_look_vector = Vector2.ZERO


func get_movement_vector() -> Vector2:
	var action_vector := Input.get_vector(
		Actions.MOVE_LEFT,
		Actions.MOVE_RIGHT,
		Actions.MOVE_FORWARD,
		Actions.MOVE_BACKWARD,
		_controller_profile.movement_deadzone
	)
	if _active and action_vector.length_squared() > 0.0001:
		return _remember_movement(action_vector)
	var raw_vector := Vector2.ZERO
	if _active:
		raw_vector = Vector2(
			float(_key_pressed(KEY_D) or _key_pressed(KEY_RIGHT))
				- float(_key_pressed(KEY_A) or _key_pressed(KEY_LEFT)),
			float(_key_pressed(KEY_S) or _key_pressed(KEY_DOWN))
				- float(_key_pressed(KEY_W) or _key_pressed(KEY_UP))
		)
		if raw_vector.length_squared() > 1.0:
			raw_vector = raw_vector.normalized()
	return _remember_movement(raw_vector)


func get_look_vector() -> Vector2:
	if not _active:
		_last_look_vector = Vector2.ZERO
		return Vector2.ZERO
	var raw_vector := Input.get_vector(
		Actions.LOOK_LEFT,
		Actions.LOOK_RIGHT,
		Actions.LOOK_UP,
		Actions.LOOK_DOWN,
		0.0
	)
	_last_look_vector = _controller_profile.apply_look_curve(raw_vector)
	return _last_look_vector


func get_look_speed_radians_per_second() -> float:
	return _controller_profile.look_speed_radians_per_second


func is_jump_just_pressed() -> bool:
	return _active and Input.is_action_just_pressed(Actions.JUMP)


func is_jump_pressed() -> bool:
	return _active and (
		Input.is_action_pressed(Actions.JUMP) or _key_pressed(KEY_SPACE)
	)


func is_sprint_pressed() -> bool:
	return _active and (
		Input.is_action_pressed(Actions.SPRINT) or _key_pressed(KEY_SHIFT)
	)


func is_primary_action_pressed() -> bool:
	return _active and Input.is_action_pressed(Actions.PRIMARY_ACTION)


func is_secondary_action_just_pressed() -> bool:
	return _active and Input.is_action_just_pressed(Actions.SECONDARY_ACTION)


func is_reload_just_pressed() -> bool:
	return _active and Input.is_action_just_pressed(Actions.RELOAD)


func is_quick_save_just_pressed() -> bool:
	return _active and Input.is_action_just_pressed(Actions.QUICK_SAVE)


func get_hotbar_selection_just_pressed() -> int:
	if not _active:
		return -1
	for index: int in Actions.HOTBAR_ACTIONS.size():
		if Input.is_action_just_pressed(Actions.HOTBAR_ACTIONS[index]):
			return index
	return -1


func get_hotbar_cycle_just_pressed() -> int:
	if not _active:
		return 0
	if Input.is_action_just_pressed(Actions.HOTBAR_PREVIOUS):
		return -1
	if Input.is_action_just_pressed(Actions.HOTBAR_NEXT):
		return 1
	return 0


func event_toggles_inventory(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_INVENTORY)


func event_toggles_crafting(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_CRAFTING)


func event_toggles_exploration_journal(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_EXPLORATION_JOURNAL)


func event_toggles_diagnostics(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_DIAGNOSTICS)


func event_toggles_guidance(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_GUIDANCE)


func get_controller_profile_snapshot() -> Dictionary:
	return _controller_profile.get_snapshot()


func get_binding_status() -> Dictionary:
	return {
		"initialized": _bindings_initialized,
		"valid": Actions.has_required_bindings(),
		"active": _active,
		"movement": get_movement_vector(),
		"look": get_look_vector(),
		"last_movement": _last_movement_vector,
		"last_nonzero_movement": _last_nonzero_movement_vector,
		"last_look": _last_look_vector,
		"last_key_event": _last_key_event,
		"last_controller_event": _last_controller_event,
		"controller_event_count": _controller_event_count,
		"controller_profile": get_controller_profile_snapshot(),
		"forward_action_pressed": Input.is_action_pressed(Actions.MOVE_FORWARD),
		"reload_action_pressed": Input.is_action_pressed(Actions.RELOAD),
		"w_key_pressed": _key_pressed(KEY_W),
		"actions": DEFAULT_ACTION_NAMES(),
	}


func DEFAULT_ACTION_NAMES() -> Array:
	var actions: Array = Actions.DEFAULT_KEY_BINDINGS.keys()
	for binding: Dictionary in _controller_profile.get_bindings():
		var action := StringName(binding.get("action", ""))
		if action not in actions:
			actions.append(action)
	return actions


func _raw_pressed(keycode: Key) -> bool:
	return bool(_raw_key_state.get(keycode, false))


func _key_pressed(keycode: Key) -> bool:
	return (
		_raw_pressed(keycode)
		or Input.is_key_pressed(keycode)
		or Input.is_physical_key_pressed(keycode)
	)


func _matches_key(event: InputEventKey, keycode: Key) -> bool:
	return event.keycode == keycode or event.physical_keycode == keycode


func _remember_movement(value: Vector2) -> Vector2:
	_last_movement_vector = value
	if value.length_squared() > 0.0001:
		_last_nonzero_movement_vector = value
	return value


func _describe_controller_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		return "button:%d:%s" % [
			button_event.button_index,
			"pressed" if button_event.pressed else "released",
		]
	if event is InputEventJoypadMotion:
		var motion_event := event as InputEventJoypadMotion
		return "axis:%d:%.3f" % [motion_event.axis, motion_event.axis_value]
	return "无"
