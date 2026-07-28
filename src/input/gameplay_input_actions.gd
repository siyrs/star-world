class_name GameplayInputActions
extends RefCounted

const ControllerProfileScript = preload("res://src/input/gameplay_controller_profile.gd")

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACKWARD: StringName = &"move_backward"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const LOOK_LEFT: StringName = &"look_left"
const LOOK_RIGHT: StringName = &"look_right"
const LOOK_UP: StringName = &"look_up"
const LOOK_DOWN: StringName = &"look_down"
const JUMP: StringName = &"jump"
const SPRINT: StringName = &"sprint"
const PRIMARY_ACTION: StringName = &"primary_action"
const SECONDARY_ACTION: StringName = &"secondary_action"
const HOTBAR_PREVIOUS: StringName = &"hotbar_previous"
const HOTBAR_NEXT: StringName = &"hotbar_next"
const QUICK_SAVE: StringName = &"quick_save"
const TOGGLE_INVENTORY: StringName = &"toggle_inventory"
const TOGGLE_CRAFTING: StringName = &"toggle_crafting"
const TOGGLE_EXPLORATION_JOURNAL: StringName = &"toggle_exploration_journal"
const TOGGLE_DIAGNOSTICS: StringName = &"toggle_diagnostics"
const TOGGLE_GUIDANCE: StringName = &"toggle_guidance"

const HOTBAR_ACTIONS: Array[StringName] = [
	&"hotbar_1",
	&"hotbar_2",
	&"hotbar_3",
	&"hotbar_4",
	&"hotbar_5",
	&"hotbar_6",
	&"hotbar_7",
	&"hotbar_8",
	&"hotbar_9",
]

const DEFAULT_KEY_BINDINGS := {
	MOVE_FORWARD: [KEY_W, KEY_UP],
	MOVE_BACKWARD: [KEY_S, KEY_DOWN],
	MOVE_LEFT: [KEY_A, KEY_LEFT],
	MOVE_RIGHT: [KEY_D, KEY_RIGHT],
	JUMP: [KEY_SPACE],
	SPRINT: [KEY_SHIFT],
	QUICK_SAVE: [KEY_F5],
	TOGGLE_INVENTORY: [KEY_E],
	TOGGLE_CRAFTING: [KEY_C],
	TOGGLE_EXPLORATION_JOURNAL: [KEY_J],
	TOGGLE_DIAGNOSTICS: [KEY_F3],
	TOGGLE_GUIDANCE: [KEY_F1],
	&"hotbar_1": [KEY_1],
	&"hotbar_2": [KEY_2],
	&"hotbar_3": [KEY_3],
	&"hotbar_4": [KEY_4],
	&"hotbar_5": [KEY_5],
	&"hotbar_6": [KEY_6],
	&"hotbar_7": [KEY_7],
	&"hotbar_8": [KEY_8],
	&"hotbar_9": [KEY_9],
}


static func ensure_default_bindings() -> Array[StringName]:
	var repaired: Array[StringName] = []
	for raw_action: Variant in DEFAULT_KEY_BINDINGS:
		var action := StringName(raw_action)
		var changed := _ensure_action(action)
		for raw_keycode: Variant in DEFAULT_KEY_BINDINGS[action]:
			var keycode: Key = raw_keycode
			changed = _ensure_key_binding(action, keycode, true) or changed
			changed = _ensure_key_binding(action, keycode, false) or changed
		if changed:
			_append_unique(repaired, action)
	var profile = ControllerProfileScript.new()
	for binding: Dictionary in profile.get_bindings():
		var action := StringName(binding.get("action", ""))
		if str(action).is_empty():
			continue
		var changed := _ensure_action(action)
		changed = _ensure_controller_binding(action, binding) or changed
		InputMap.action_set_deadzone(action, profile.deadzone_for_action(action))
		if changed:
			_append_unique(repaired, action)
	return repaired


static func has_required_bindings() -> bool:
	for raw_action: Variant in DEFAULT_KEY_BINDINGS:
		var action := StringName(raw_action)
		if not InputMap.has_action(action):
			return false
		for raw_keycode: Variant in DEFAULT_KEY_BINDINGS[action]:
			var keycode: Key = raw_keycode
			if not _has_key_binding(action, keycode, true):
				return false
			if not _has_key_binding(action, keycode, false):
				return false
	var profile = ControllerProfileScript.new()
	if not profile.get_validation_errors().is_empty():
		return false
	for binding: Dictionary in profile.get_bindings():
		var action := StringName(binding.get("action", ""))
		if not InputMap.has_action(action) or not _has_controller_binding(action, binding):
			return false
	return true


static func get_hotbar_action(index: int) -> StringName:
	if index < 0 or index >= HOTBAR_ACTIONS.size():
		return StringName()
	return HOTBAR_ACTIONS[index]


static func get_controller_profile_snapshot() -> Dictionary:
	return ControllerProfileScript.new().get_snapshot()


static func _ensure_action(action: StringName) -> bool:
	if str(action).is_empty() or InputMap.has_action(action):
		return false
	InputMap.add_action(action)
	return true


static func _ensure_key_binding(action: StringName, keycode: Key, physical: bool) -> bool:
	if _has_key_binding(action, keycode, physical):
		return false
	var event := InputEventKey.new()
	if physical:
		event.physical_keycode = keycode
	else:
		event.keycode = keycode
	InputMap.action_add_event(action, event)
	return true


static func _has_key_binding(action: StringName, keycode: Key, physical: bool) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is not InputEventKey:
			continue
		var key_event := event as InputEventKey
		if physical and key_event.physical_keycode == keycode:
			return true
		if not physical and key_event.keycode == keycode:
			return true
	return false


static func _ensure_controller_binding(action: StringName, binding: Dictionary) -> bool:
	if _has_controller_binding(action, binding):
		return false
	var kind := str(binding.get("kind", ""))
	if kind == "button":
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = int(binding.get("button", -1))
		InputMap.action_add_event(action, button_event)
		return true
	if kind == "axis":
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = int(binding.get("axis", -1))
		axis_event.axis_value = float(binding.get("value", 0.0))
		InputMap.action_add_event(action, axis_event)
		return true
	return false


static func _has_controller_binding(action: StringName, binding: Dictionary) -> bool:
	var kind := str(binding.get("kind", ""))
	for event: InputEvent in InputMap.action_get_events(action):
		if kind == "button" and event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == int(binding.get("button", -1)):
				return true
		if kind == "axis" and event is InputEventJoypadMotion:
			var axis_event := event as InputEventJoypadMotion
			if (
				axis_event.axis == int(binding.get("axis", -1))
				and is_equal_approx(axis_event.axis_value, float(binding.get("value", 0.0)))
			):
				return true
	return false


static func _append_unique(values: Array[StringName], value: StringName) -> void:
	if value not in values:
		values.append(value)
