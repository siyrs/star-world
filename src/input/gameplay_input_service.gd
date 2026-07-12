class_name GameplayInputService
extends Node

signal bindings_ready(repaired_actions: Array[StringName])

const Actions = preload("res://src/input/gameplay_input_actions.gd")

var _bindings_initialized := false


func _enter_tree() -> void:
	ensure_bindings()


func ensure_bindings() -> Array[StringName]:
	var repaired := Actions.ensure_default_bindings()
	if not _bindings_initialized or not repaired.is_empty():
		_bindings_initialized = true
		bindings_ready.emit(repaired)
	return repaired


func get_movement_vector() -> Vector2:
	ensure_bindings()
	return Input.get_vector(
		Actions.MOVE_LEFT, Actions.MOVE_RIGHT, Actions.MOVE_FORWARD, Actions.MOVE_BACKWARD
	)


func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed(Actions.JUMP)


func is_sprint_pressed() -> bool:
	return Input.is_action_pressed(Actions.SPRINT)


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


func get_binding_status() -> Dictionary:
	return {
		"initialized": _bindings_initialized,
		"valid": Actions.has_required_bindings(),
		"actions": Actions.DEFAULT_KEY_BINDINGS.keys(),
	}
