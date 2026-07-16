class_name GameplayInputService
extends Node

signal bindings_ready(repaired_actions: Array[StringName])

const Actions = preload("res://src/input/gameplay_input_actions.gd")

var _bindings_initialized := false
var _active := false
var _raw_key_state: Dictionary = {}
var _last_key_event := "无"
var _last_movement_vector := Vector2.ZERO
var _last_nonzero_movement_vector := Vector2.ZERO


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_bindings(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_raw_state()


func _input(event: InputEvent) -> void:
	if event is not InputEventKey or event.echo:
		return
	var key_event := event as InputEventKey
	for keycode in [
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


func get_movement_vector() -> Vector2:
	var action_vector := Input.get_vector(
		Actions.MOVE_LEFT, Actions.MOVE_RIGHT, Actions.MOVE_FORWARD, Actions.MOVE_BACKWARD
	)
	if action_vector.length_squared() > 0.0001:
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


func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed(Actions.JUMP)


func is_jump_pressed() -> bool:
	return Input.is_action_pressed(Actions.JUMP) or (_active and _key_pressed(KEY_SPACE))


func is_sprint_pressed() -> bool:
	return Input.is_action_pressed(Actions.SPRINT) or (_active and _key_pressed(KEY_SHIFT))


func is_quick_save_just_pressed() -> bool:
	return Input.is_action_just_pressed(Actions.QUICK_SAVE)


func get_hotbar_selection_just_pressed() -> int:
	for index in Actions.HOTBAR_ACTIONS.size():
		if Input.is_action_just_pressed(Actions.HOTBAR_ACTIONS[index]):
			return index
	return -1


func event_toggles_inventory(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_INVENTORY)


func event_toggles_crafting(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_CRAFTING)


func event_toggles_diagnostics(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_DIAGNOSTICS)


func event_toggles_guidance(event: InputEvent) -> bool:
	return event.is_action_pressed(Actions.TOGGLE_GUIDANCE)


func get_binding_status() -> Dictionary:
	return {
		"initialized": _bindings_initialized,
		"valid": Actions.has_required_bindings(),
		"active": _active,
		"movement": get_movement_vector(),
		"last_movement": _last_movement_vector,
		"last_nonzero_movement": _last_nonzero_movement_vector,
		"last_key_event": _last_key_event,
		"forward_action_pressed": Input.is_action_pressed(Actions.MOVE_FORWARD),
		"w_key_pressed": _key_pressed(KEY_W),
		"actions": Actions.DEFAULT_KEY_BINDINGS.keys(),
	}


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
