class_name HusbandryInteractionAdapter
extends Node

signal state_changed(entity_id: int)

var service: Node


func setup(p_service: Node) -> void:
	_disconnect_service()
	service = p_service
	if service != null and service.has_signal("state_changed"):
		service.connect("state_changed", Callable(self, "_on_state_changed"))


func interact_entity(entity: Node, inventory: Node = null) -> Dictionary:
	if service == null or not service.has_method("interact_entity"):
		return {"handled": false}
	var result: Variant = service.call("interact_entity", entity, inventory)
	return result.duplicate(true) if result is Dictionary else {"handled": false}


func get_entity_prompt(focus: Dictionary, selected_item_id: String) -> Dictionary:
	if service == null or not service.has_method("get_entity_prompt"):
		return {}
	var result: Variant = service.call("get_entity_prompt", focus, selected_item_id)
	return result.duplicate(true) if result is Dictionary else {}


func _exit_tree() -> void:
	_disconnect_service()


func _on_state_changed(entity_id: int) -> void:
	state_changed.emit(entity_id)


func _disconnect_service() -> void:
	if service == null or not service.has_signal("state_changed"):
		return
	var callback := Callable(self, "_on_state_changed")
	if service.is_connected("state_changed", callback):
		service.disconnect("state_changed", callback)
