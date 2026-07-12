class_name ContainerStorageService
extends Node

signal container_changed(container_id: String)
signal active_container_changed(container_id: String)
signal item_transferred(container_id: String, direction: String, item_id: String, count: int)
signal container_removed(container_id: String)

const SERIAL_VERSION := 1
const DEFAULT_SLOT_COUNT := 27

var registry
var _containers: Dictionary = {}
var _active_container_id := ""


func setup(item_registry) -> void:
	registry = item_registry


func clear() -> void:
	_containers.clear()
	_set_active_container("")


func ensure_container(
	container_id: String, container_type: String = "chest", slot_count: int = DEFAULT_SLOT_COUNT
) -> Dictionary:
	if not _is_valid_container_id(container_id):
		return {}
	var normalized_count := clampi(slot_count, 1, 54)
	if not _containers.has(container_id):
		_containers[container_id] = {
			"type": container_type,
			"slot_count": normalized_count,
			"slots": _make_slots(normalized_count),
		}
	else:
		_normalize_existing_container(container_id, container_type, normalized_count)
	return get_container(container_id)


func open_container(
	container_id: String, container_type: String = "chest", slot_count: int = DEFAULT_SLOT_COUNT
) -> bool:
	if ensure_container(container_id, container_type, slot_count).is_empty():
		return false
	_set_active_container(container_id)
	return true


func close_container() -> void:
	_set_active_container("")


func get_active_container_id() -> String:
	return _active_container_id


func has_container(container_id: String) -> bool:
	return _containers.has(container_id)


func get_container(container_id: String) -> Dictionary:
	if not _containers.has(container_id):
		return {}
	return _containers[container_id].duplicate(true)


func get_slot_count(container_id: String = "") -> int:
	var resolved_id := _resolve_container_id(container_id)
	if not _containers.has(resolved_id):
		return 0
	return int(_containers[resolved_id].get("slot_count", 0))


func get_slot(container_id: String, index: int) -> Dictionary:
	if not _containers.has(container_id):
		return {}
	var slots: Array = _containers[container_id].get("slots", [])
	if index < 0 or index >= slots.size():
		return {}
	return slots[index].duplicate(true)


func is_empty(container_id: String) -> bool:
	if not _containers.has(container_id):
		return true
	for slot in _containers[container_id].get("slots", []):
		if slot is Dictionary and not slot.is_empty() and int(slot.get("count", 0)) > 0:
			return false
	return true


func add_item(
	container_id: String, item_id: String, count: int = 1, metadata: Dictionary = {}
) -> int:
	if count <= 0:
		return 0
	if registry == null or not registry.has_method("has_item") or not registry.has_item(item_id):
		return count
	if not _containers.has(container_id):
		return count
	var container: Dictionary = _containers[container_id]
	var slots: Array = container.get("slots", [])
	var remaining := count
	var max_stack := int(registry.get_max_stack(item_id))
	for index in slots.size():
		var slot: Dictionary = slots[index]
		if (
			str(slot.get("item_id", "")) == item_id
			and int(slot.get("count", 0)) < max_stack
			and slot.get("metadata", {}) == metadata
		):
			var accepted := mini(remaining, max_stack - int(slot.get("count", 0)))
			slot["count"] = int(slot.get("count", 0)) + accepted
			slots[index] = slot
			remaining -= accepted
			if remaining == 0:
				break
	if remaining > 0:
		for index in slots.size():
			if not slots[index].is_empty():
				continue
			var accepted := mini(remaining, max_stack)
			var new_slot := {"item_id": item_id, "count": accepted}
			if not metadata.is_empty():
				new_slot["metadata"] = metadata.duplicate(true)
			slots[index] = new_slot
			remaining -= accepted
			if remaining == 0:
				break
	container["slots"] = slots
	_containers[container_id] = container
	if remaining != count:
		container_changed.emit(container_id)
	return remaining


func remove_from_slot(container_id: String, index: int, count: int = 1) -> Dictionary:
	if not _containers.has(container_id) or count <= 0:
		return {}
	var container: Dictionary = _containers[container_id]
	var slots: Array = container.get("slots", [])
	if index < 0 or index >= slots.size() or slots[index].is_empty():
		return {}
	var slot: Dictionary = slots[index]
	var taken := mini(count, int(slot.get("count", 0)))
	var result := {
		"item_id": str(slot.get("item_id", "")),
		"count": taken,
		"metadata": slot.get("metadata", {}).duplicate(true),
	}
	slot["count"] = int(slot.get("count", 0)) - taken
	if int(slot.get("count", 0)) <= 0:
		slot = {}
	slots[index] = slot
	container["slots"] = slots
	_containers[container_id] = container
	container_changed.emit(container_id)
	return result


func transfer_from_inventory(inventory, inventory_index: int, container_id: String = "") -> bool:
	var resolved_id := _resolve_container_id(container_id)
	if inventory == null or not _containers.has(resolved_id):
		return false
	var source: Dictionary = inventory.get_slot(inventory_index)
	if source.is_empty():
		return false
	var removed: Dictionary = inventory.remove_from_slot(
		inventory_index, int(source.get("count", 0))
	)
	if removed.is_empty():
		return false
	var item_id := str(removed.get("item_id", ""))
	var removed_count := int(removed.get("count", 0))
	var metadata: Dictionary = removed.get("metadata", {})
	var remaining := add_item(resolved_id, item_id, removed_count, metadata)
	if remaining > 0:
		inventory.add_item(item_id, remaining, metadata)
	var moved := removed_count - remaining
	if moved > 0:
		item_transferred.emit(resolved_id, "inventory_to_container", item_id, moved)
	return moved > 0


func transfer_to_inventory(inventory, container_index: int, container_id: String = "") -> bool:
	var resolved_id := _resolve_container_id(container_id)
	if inventory == null or not _containers.has(resolved_id):
		return false
	var source := get_slot(resolved_id, container_index)
	if source.is_empty():
		return false
	var removed := remove_from_slot(resolved_id, container_index, int(source.get("count", 0)))
	if removed.is_empty():
		return false
	var item_id := str(removed.get("item_id", ""))
	var removed_count := int(removed.get("count", 0))
	var metadata: Dictionary = removed.get("metadata", {})
	var remaining := int(inventory.add_item(item_id, removed_count, metadata))
	if remaining > 0:
		add_item(resolved_id, item_id, remaining, metadata)
	var moved := removed_count - remaining
	if moved > 0:
		item_transferred.emit(resolved_id, "container_to_inventory", item_id, moved)
	return moved > 0


func remove_container(container_id: String, require_empty: bool = true) -> bool:
	if not _containers.has(container_id):
		return true
	if require_empty and not is_empty(container_id):
		return false
	_containers.erase(container_id)
	if _active_container_id == container_id:
		_set_active_container("")
	container_removed.emit(container_id)
	return true


func serialize() -> Dictionary:
	var saved_containers: Dictionary = {}
	for container_id in _containers:
		saved_containers[container_id] = _containers[container_id].duplicate(true)
	return {"version": SERIAL_VERSION, "containers": saved_containers}


func deserialize(data: Dictionary) -> bool:
	clear()
	var raw_containers = data.get("containers", {})
	if raw_containers is not Dictionary:
		return false
	for raw_id in raw_containers:
		var container_id := str(raw_id)
		var raw_container = raw_containers[raw_id]
		if not _is_valid_container_id(container_id) or raw_container is not Dictionary:
			continue
		var container_type := str(raw_container.get("type", "chest"))
		var slot_count := clampi(int(raw_container.get("slot_count", DEFAULT_SLOT_COUNT)), 1, 54)
		var slots := _make_slots(slot_count)
		var raw_slots = raw_container.get("slots", [])
		if raw_slots is Array:
			for index in mini(raw_slots.size(), slot_count):
				var normalized := _normalize_slot(raw_slots[index])
				if not normalized.is_empty():
					slots[index] = normalized
		_containers[container_id] = {
			"type": container_type,
			"slot_count": slot_count,
			"slots": slots,
		}
	return true


func _normalize_existing_container(
	container_id: String, container_type: String, slot_count: int
) -> void:
	var container: Dictionary = _containers[container_id]
	container["type"] = str(container.get("type", container_type))
	var slots: Array = container.get("slots", [])
	while slots.size() < slot_count:
		slots.append({})
	if slots.size() > slot_count:
		slots.resize(slot_count)
	container["slot_count"] = slot_count
	container["slots"] = slots
	_containers[container_id] = container


func _normalize_slot(raw_slot: Variant) -> Dictionary:
	if raw_slot is not Dictionary or registry == null:
		return {}
	var item_id := str(raw_slot.get("item_id", ""))
	var count := int(raw_slot.get("count", 0))
	if item_id.is_empty() or count <= 0 or not registry.has_item(item_id):
		return {}
	return {
		"item_id": item_id,
		"count": mini(count, int(registry.get_max_stack(item_id))),
		"metadata": raw_slot.get("metadata", {}).duplicate(true),
	}


func _make_slots(slot_count: int) -> Array:
	var slots: Array = []
	for index in slot_count:
		slots.append({})
	return slots


func _resolve_container_id(container_id: String) -> String:
	return _active_container_id if container_id.is_empty() else container_id


func _set_active_container(container_id: String) -> void:
	if _active_container_id == container_id:
		return
	_active_container_id = container_id
	active_container_changed.emit(_active_container_id)


func _is_valid_container_id(container_id: String) -> bool:
	return (
		not container_id.is_empty()
		and container_id.length() <= 128
		and "\n" not in container_id
		and "\r" not in container_id
	)
