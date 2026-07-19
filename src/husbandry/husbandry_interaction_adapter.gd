class_name HusbandryInteractionAdapter
extends Node

signal state_changed(entity_id: int)

var service: Node
var product_service: Node


func setup(p_service: Node, p_product_service: Node = null) -> void:
	_disconnect_services()
	service = p_service
	product_service = p_product_service
	_connect_services()


func is_ready() -> bool:
	return service != null and is_instance_valid(service)


func set_product_service(p_product_service: Node) -> void:
	_disconnect_product_service()
	product_service = p_product_service
	_connect_product_service()


func interact_entity(entity: Node, inventory: Node = null) -> Dictionary:
	if service == null or not service.has_method("interact_entity"):
		return {"handled": false}
	var result: Variant = service.call("interact_entity", entity, inventory)
	return result.duplicate(true) if result is Dictionary else {"handled": false}


func get_entity_prompt(focus: Dictionary, selected_item_id: String) -> Dictionary:
	if service == null or not service.has_method("get_entity_prompt"):
		return {}
	var raw_result: Variant = service.call("get_entity_prompt", focus, selected_item_id)
	var result: Dictionary = raw_result.duplicate(true) if raw_result is Dictionary else {}
	if (
		product_service != null
		and product_service.has_method("get_status_for_focus")
		and not result.is_empty()
	):
		var status := str(product_service.call("get_status_for_focus", focus))
		if not status.is_empty():
			var subtitle := str(result.get("subtitle", ""))
			result["subtitle"] = status if subtitle.is_empty() else "%s · %s" % [subtitle, status]
	return result


func shutdown() -> void:
	_disconnect_services()
	service = null
	product_service = null


func _exit_tree() -> void:
	shutdown()


func _on_state_changed(entity_id: int) -> void:
	state_changed.emit(entity_id)


func _connect_services() -> void:
	if service != null and service.has_signal("state_changed"):
		var service_callback := Callable(self, "_on_state_changed")
		if not service.is_connected("state_changed", service_callback):
			service.connect("state_changed", service_callback)
	_connect_product_service()


func _connect_product_service() -> void:
	if product_service != null and product_service.has_signal("state_changed"):
		var callback := Callable(self, "_on_state_changed")
		if not product_service.is_connected("state_changed", callback):
			product_service.connect("state_changed", callback)


func _disconnect_services() -> void:
	if service != null and service.has_signal("state_changed"):
		var service_callback := Callable(self, "_on_state_changed")
		if service.is_connected("state_changed", service_callback):
			service.disconnect("state_changed", service_callback)
	_disconnect_product_service()


func _disconnect_product_service() -> void:
	if product_service == null or not product_service.has_signal("state_changed"):
		return
	var callback := Callable(self, "_on_state_changed")
	if product_service.is_connected("state_changed", callback):
		product_service.disconnect("state_changed", callback)
