class_name GameplayInputActions
extends RefCounted

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACKWARD: StringName = &"move_backward"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const JUMP: StringName = &"jump"
const SPRINT: StringName = &"sprint"
const QUICK_SAVE: StringName = &"quick_save"
const TOGGLE_INVENTORY: StringName = &"toggle_inventory"
const TOGGLE_CRAFTING: StringName = &"toggle_crafting"
const TOGGLE_DIAGNOSTICS: StringName = &"toggle_diagnostics"

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
	TOGGLE_DIAGNOSTICS: [KEY_F3],
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
	for raw_action in DEFAULT_KEY_BINDINGS:
		var action := StringName(raw_action)
		var changed := false
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			changed = true
		for raw_keycode in DEFAULT_KEY_BINDINGS[action]:
			var keycode: Key = raw_keycode
			changed = _ensure_key_binding(action, keycode, true) or changed
			changed = _ensure_key_binding(action, keycode, false) or changed
		if changed:
			repaired.append(action)
	return repaired


static func has_required_bindings() -> bool:
	for raw_action in DEFAULT_KEY_BINDINGS:
		var action := StringName(raw_action)
		if not InputMap.has_action(action):
			return false
		for raw_keycode in DEFAULT_KEY_BINDINGS[action]:
			var keycode: Key = raw_keycode
			if not _has_key_binding(action, keycode, true):
				return false
			if not _has_key_binding(action, keycode, false):
				return false
	return true


static func get_hotbar_action(index: int) -> StringName:
	if index < 0 or index >= HOTBAR_ACTIONS.size():
		return StringName()
	return HOTBAR_ACTIONS[index]


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
	for event in InputMap.action_get_events(action):
		if event is not InputEventKey:
			continue
		if physical and event.physical_keycode == keycode:
			return true
		if not physical and event.keycode == keycode:
			return true
	return false
