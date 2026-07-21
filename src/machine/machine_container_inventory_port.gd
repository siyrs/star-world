class_name MachineContainerInventoryPort
extends Node

var storage: Node
var container_id := ""


func configure(p_storage: Node, p_container_id: String) -> bool:
	storage = p_storage
	container_id = p_container_id.strip_edges()
	return (
		storage != null
		and is_instance_valid(storage)
		and not container_id.is_empty()
		and storage.has_method("get_slot")
		and storage.has_method("remove_from_slot")
		and storage.has_method("add_item")
		and storage.has_method("can_transact_items")
		and storage.has_method("transact_items")
	)


func clear() -> void:
	storage = null
	container_id = ""


func get_slot(index: int) -> Dictionary:
	if storage == null or not is_instance_valid(storage):
		return {}
	var raw: Variant = storage.call("get_slot", container_id, index)
	return raw.duplicate(true) if raw is Dictionary else {}


func get_slot_count() -> int:
	if storage == null or not is_instance_valid(storage):
		return 0
	return maxi(0, int(storage.call("get_slot_count", container_id)))


func remove_from_slot(index: int, count: int = 1) -> Dictionary:
	if storage == null or not is_instance_valid(storage):
		return {}
	var raw: Variant = storage.call("remove_from_slot", container_id, index, count)
	return raw.duplicate(true) if raw is Dictionary else {}


func add_item(item_id: String, count: int = 1, metadata: Dictionary = {}) -> int:
	if storage == null or not is_instance_valid(storage):
		return maxi(0, count)
	return maxi(0, int(storage.call(
		"add_item", container_id, item_id, count, metadata.duplicate(true)
	)))


func can_transact_items(removals: Dictionary = {}, additions: Array = []) -> bool:
	if storage == null or not is_instance_valid(storage):
		return false
	return bool(storage.call(
		"can_transact_items", container_id, removals.duplicate(true), additions.duplicate(true)
	))


func transact_items(removals: Dictionary = {}, additions: Array = []) -> Dictionary:
	if storage == null or not is_instance_valid(storage):
		return {"success": false, "reason": "container_storage_unavailable"}
	var raw: Variant = storage.call(
		"transact_items", container_id, removals.duplicate(true), additions.duplicate(true)
	)
	return raw.duplicate(true) if raw is Dictionary else {
		"success": false,
		"reason": "container_transaction_invalid",
	}


func get_snapshot() -> Dictionary:
	return {
		"configured": storage != null and is_instance_valid(storage) and not container_id.is_empty(),
		"container_id": container_id,
		"slot_count": get_slot_count(),
	}
