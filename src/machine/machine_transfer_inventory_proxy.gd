class_name MachineTransferInventoryProxy
extends RefCounted

const MODE_INSERT := "insert"
const MODE_EXTRACT := "extract"

var inventory: Node
var mode := ""
var source_index := -1
var requested_count := 0
var expected_stack: Dictionary = {}
var moved_count := 0
var failure_reason := ""
var _committed := false


func setup_insert(
	p_inventory: Node,
	p_source_index: int,
	p_requested_count: int,
	p_expected_stack: Dictionary
) -> bool:
	_reset()
	if p_inventory == null or p_requested_count <= 0 or p_expected_stack.is_empty():
		failure_reason = "invalid_insert_proxy"
		return false
	inventory = p_inventory
	mode = MODE_INSERT
	source_index = p_source_index
	requested_count = p_requested_count
	expected_stack = p_expected_stack.duplicate(true)
	return true


func setup_extract(
	p_inventory: Node,
	p_requested_count: int,
	p_expected_stack: Dictionary
) -> bool:
	_reset()
	if p_inventory == null or p_requested_count <= 0 or p_expected_stack.is_empty():
		failure_reason = "invalid_extract_proxy"
		return false
	inventory = p_inventory
	mode = MODE_EXTRACT
	requested_count = p_requested_count
	expected_stack = p_expected_stack.duplicate(true)
	return true


func get_slot(index: int) -> Dictionary:
	if mode != MODE_INSERT or index != 0 or inventory == null:
		return {}
	var current: Dictionary = inventory.call("get_slot", source_index)
	if not _matches_expected(current) or int(current.get("count", 0)) < requested_count:
		failure_reason = "source_changed"
		return {}
	var result := current.duplicate(true)
	result["count"] = requested_count
	return result


func remove_from_slot(index: int, count: int = 1) -> Dictionary:
	if (
		mode != MODE_INSERT
		or index != 0
		or inventory == null
		or _committed
		or count != requested_count
	):
		failure_reason = "invalid_insert_commit"
		return {}
	var current: Dictionary = inventory.call("get_slot", source_index)
	if not _matches_expected(current) or int(current.get("count", 0)) < requested_count:
		failure_reason = "source_changed"
		return {}
	var removed: Dictionary = inventory.call(
		"remove_from_slot", source_index, requested_count
	)
	if (
		str(removed.get("item_id", "")) != str(expected_stack.get("item_id", ""))
		or int(removed.get("count", 0)) != requested_count
		or removed.get("metadata", {}) != expected_stack.get("metadata", {})
	):
		failure_reason = "insert_commit_failed"
		return {}
	_committed = true
	moved_count = requested_count
	return removed


func add_item(item_id: String, count: int = 1, metadata: Dictionary = {}) -> int:
	if mode != MODE_EXTRACT or inventory == null or _committed:
		failure_reason = "invalid_extract_commit"
		return count
	if (
		item_id != str(expected_stack.get("item_id", ""))
		or metadata != expected_stack.get("metadata", {})
		or requested_count > count
	):
		failure_reason = "extract_source_changed"
		return count
	var transaction: Dictionary = inventory.call(
		"transact_items",
		{},
		[{
			"item_id": item_id,
			"count": requested_count,
			"metadata": metadata.duplicate(true),
		}]
	)
	if not bool(transaction.get("success", false)):
		failure_reason = str(transaction.get("reason", "inventory_rejected"))
		return count
	_committed = true
	moved_count = requested_count
	return count - requested_count


func get_moved_count() -> int:
	return moved_count


func was_committed() -> bool:
	return _committed


func _matches_expected(current: Dictionary) -> bool:
	return (
		str(current.get("item_id", "")) == str(expected_stack.get("item_id", ""))
		and current.get("metadata", {}) == expected_stack.get("metadata", {})
		and int(current.get("count", 0)) >= requested_count
	)


func _reset() -> void:
	inventory = null
	mode = ""
	source_index = -1
	requested_count = 0
	expected_stack.clear()
	moved_count = 0
	failure_reason = ""
	_committed = false
