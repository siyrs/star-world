class_name PickupStackCoordinator
extends Node

signal pickup_stack_consolidated(summary: Dictionary)

const PickupScript = preload("res://src/entity/item_pickup.gd")
const MAX_PICKUP_NODES := 128
const MAX_MERGE_SCAN_NODES := 64
const MAX_PENDING_ITEM_TYPES := 256
const MAX_PENDING_MATERIALIZATIONS := 16
const MERGE_RADIUS := 1.75
const MAX_ITEMS_PER_PICKUP := 65535

var spawner: Node3D
var inventory_service
var _active := false
var _shutdown := false
var _pending_pickups: Dictionary = {}
var _flush_scheduled := false
var _spawned_node_count := 0
var _merged_pickup_count := 0
var _merged_item_count := 0
var _queued_item_count := 0
var _materialized_item_count := 0
var _budget_deferral_count := 0
var _pending_type_rejection_count := 0
var _max_pickup_nodes_observed := 0
var _last_summary: Dictionary = {}


func setup(p_spawner: Node3D, p_inventory = null) -> bool:
	_disconnect_spawner()
	spawner = p_spawner
	inventory_service = p_inventory
	_shutdown = false
	if spawner == null or not is_instance_valid(spawner):
		return false
	var entered := Callable(self, "_on_spawner_child_entered")
	var exiting := Callable(self, "_on_spawner_child_exiting")
	if not spawner.child_entered_tree.is_connected(entered):
		spawner.child_entered_tree.connect(entered)
	if not spawner.child_exiting_tree.is_connected(exiting):
		spawner.child_exiting_tree.connect(exiting)
	return true


func activate() -> void:
	if _shutdown:
		return
	_active = true
	_schedule_pending_flush()


func clear(reset_counters: bool = true) -> void:
	_active = false
	_pending_pickups.clear()
	_flush_scheduled = false
	_last_summary.clear()
	if not reset_counters:
		return
	_spawned_node_count = 0
	_merged_pickup_count = 0
	_merged_item_count = 0
	_queued_item_count = 0
	_materialized_item_count = 0
	_budget_deferral_count = 0
	_pending_type_rejection_count = 0
	_max_pickup_nodes_observed = 0


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(true)
	_disconnect_spawner()
	spawner = null
	inventory_service = null


func flush_pending_pickups() -> Dictionary:
	_flush_scheduled = false
	if not _active or _shutdown or spawner == null or not is_instance_valid(spawner):
		return get_snapshot()
	var materialized_types := 0
	var keys: Array[String] = []
	for raw_key: Variant in _pending_pickups.keys():
		keys.append(str(raw_key))
	keys.sort()
	for item_id: String in keys:
		if materialized_types >= MAX_PENDING_MATERIALIZATIONS:
			break
		if _live_pickup_count() >= MAX_PICKUP_NODES:
			break
		var entry: Dictionary = _pending_pickups.get(item_id, {})
		var remaining := maxi(0, int(entry.get("count", 0)))
		if remaining <= 0:
			_pending_pickups.erase(item_id)
			continue
		var spawn_count := mini(remaining, MAX_ITEMS_PER_PICKUP)
		var pickup = PickupScript.new()
		pickup.setup(item_id, spawn_count, inventory_service)
		spawner.add_child(pickup)
		pickup.global_position = _vector3_from(entry.get("position", Vector3.ZERO))
		remaining -= spawn_count
		_materialized_item_count += spawn_count
		_spawned_node_count += 1
		materialized_types += 1
		if remaining <= 0:
			_pending_pickups.erase(item_id)
		else:
			entry["count"] = remaining
			_pending_pickups[item_id] = entry
	_update_node_peak()
	if not _pending_pickups.is_empty() and _live_pickup_count() < MAX_PICKUP_NODES:
		_schedule_pending_flush()
	return get_snapshot()


func get_snapshot() -> Dictionary:
	var node_count := 0
	var stacked_nodes := 0
	var visible_item_total := 0
	if spawner != null and is_instance_valid(spawner):
		for child: Node in spawner.get_children():
			if not _is_pickup(child):
				continue
			node_count += 1
			var count := maxi(0, int(child.get("item_count")))
			visible_item_total += count
			if count > 1:
				stacked_nodes += 1
	var pending_item_total := 0
	for raw_entry: Variant in _pending_pickups.values():
		if raw_entry is Dictionary:
			pending_item_total += maxi(0, int((raw_entry as Dictionary).get("count", 0)))
	return {
		"active": _active,
		"shutdown": _shutdown,
		"pickup_node_count": node_count,
		"stacked_pickup_node_count": stacked_nodes,
		"visible_item_total": visible_item_total,
		"pending_item_total": pending_item_total,
		"pending_item_types": _pending_pickups.size(),
		"spawned_node_count": _spawned_node_count,
		"merged_pickup_count": _merged_pickup_count,
		"merged_item_count": _merged_item_count,
		"queued_item_count": _queued_item_count,
		"materialized_item_count": _materialized_item_count,
		"budget_deferral_count": _budget_deferral_count,
		"pending_type_rejection_count": _pending_type_rejection_count,
		"max_pickup_nodes_observed": _max_pickup_nodes_observed,
		"max_pickup_nodes": MAX_PICKUP_NODES,
		"merge_scan_nodes": MAX_MERGE_SCAN_NODES,
		"max_pending_item_types": MAX_PENDING_ITEM_TYPES,
		"pending_materializations_per_flush": MAX_PENDING_MATERIALIZATIONS,
		"merge_radius": MERGE_RADIUS,
		"max_items_per_pickup": MAX_ITEMS_PER_PICKUP,
		"last_summary": _last_summary.duplicate(true),
	}


func _on_spawner_child_entered(child: Node) -> void:
	if not _active or _shutdown or not _is_pickup(child):
		return
	call_deferred("_consolidate_pickup", child)


func _on_spawner_child_exiting(child: Node) -> void:
	if not _is_pickup(child):
		return
	_schedule_pending_flush()


func _consolidate_pickup(pickup: Node) -> void:
	if (
		not _active
		or _shutdown
		or not _is_pickup(pickup)
		or pickup.get_parent() != spawner
	):
		return
	var item_id := str(pickup.get("item_id")).strip_edges()
	var original_count := maxi(0, int(pickup.get("item_count")))
	if item_id.is_empty() or original_count <= 0:
		return
	var remaining := original_count
	var scanned := 0
	var merged_nodes := 0
	var merge_radius_squared := MERGE_RADIUS * MERGE_RADIUS
	for candidate: Node in spawner.get_children():
		if candidate == pickup or not _is_pickup(candidate):
			continue
		scanned += 1
		if scanned > MAX_MERGE_SCAN_NODES:
			break
		if str(candidate.get("item_id")) != item_id:
			continue
		var candidate_3d := candidate as Node3D
		var pickup_3d := pickup as Node3D
		if candidate_3d == null or pickup_3d == null:
			continue
		if candidate_3d.global_position.distance_squared_to(pickup_3d.global_position) > merge_radius_squared:
			continue
		if not candidate.has_method("merge_items"):
			continue
		var before := remaining
		remaining = int(candidate.call("merge_items", remaining, true))
		if remaining < before:
			merged_nodes += 1
			_merged_item_count += before - remaining
		if remaining <= 0:
			break
	if remaining <= 0:
		_merged_pickup_count += 1
		_last_summary = {
			"action": "merged",
			"item_id": item_id,
			"item_count": original_count,
			"merged_into_nodes": merged_nodes,
			"scanned_nodes": mini(scanned, MAX_MERGE_SCAN_NODES),
		}
		pickup_stack_consolidated.emit(_last_summary.duplicate(true))
		pickup.queue_free()
		_update_node_peak()
		return
	if remaining != original_count:
		pickup.set("item_count", remaining)
		if pickup.has_method("_update_count_label"):
			pickup.call("_update_count_label")
	var live_nodes := _live_pickup_count()
	if live_nodes <= MAX_PICKUP_NODES:
		_spawned_node_count += 1
		_update_node_peak()
		_last_summary = {
			"action": "kept",
			"item_id": item_id,
			"item_count": remaining,
			"merged_items": original_count - remaining,
			"pickup_nodes": live_nodes,
		}
		return
	_budget_deferral_count += 1
	if _queue_pending(item_id, remaining, (pickup as Node3D).global_position):
		_last_summary = {
			"action": "deferred",
			"item_id": item_id,
			"item_count": remaining,
			"pickup_nodes": live_nodes,
		}
		pickup.queue_free()
		_schedule_pending_flush()
	else:
		_pending_type_rejection_count += 1
		_last_summary = {
			"action": "budget_overflow_kept",
			"item_id": item_id,
			"item_count": remaining,
			"pickup_nodes": live_nodes,
		}
	_update_node_peak()


func _queue_pending(item_id: String, count: int, position: Vector3) -> bool:
	if count <= 0:
		return true
	var entry: Dictionary = _pending_pickups.get(item_id, {})
	if entry.is_empty() and _pending_pickups.size() >= MAX_PENDING_ITEM_TYPES:
		return false
	var previous_count := maxi(0, int(entry.get("count", 0)))
	var previous_position := _vector3_from(entry.get("position", position))
	var total := previous_count + count
	var blended := position
	if total > 0 and previous_count > 0:
		blended = (previous_position * float(previous_count) + position * float(count)) / float(total)
	entry["count"] = total
	entry["position"] = blended
	_pending_pickups[item_id] = entry
	_queued_item_count += count
	return true


func _live_pickup_count() -> int:
	if spawner == null or not is_instance_valid(spawner):
		return 0
	var count := 0
	for child: Node in spawner.get_children():
		if _is_pickup(child):
			count += 1
	return count


func _update_node_peak() -> void:
	_max_pickup_nodes_observed = maxi(_max_pickup_nodes_observed, _live_pickup_count())


func _schedule_pending_flush() -> void:
	if _flush_scheduled or not _active or _shutdown:
		return
	_flush_scheduled = true
	call_deferred("flush_pending_pickups")


func _is_pickup(node: Node) -> bool:
	return (
		node != null
		and is_instance_valid(node)
		and node is Node3D
		and node.has_method("merge_items")
		and node.has_method("get_pickup_snapshot")
	)


func _disconnect_spawner() -> void:
	if spawner == null or not is_instance_valid(spawner):
		return
	var entered := Callable(self, "_on_spawner_child_entered")
	var exiting := Callable(self, "_on_spawner_child_exiting")
	if spawner.child_entered_tree.is_connected(entered):
		spawner.child_entered_tree.disconnect(entered)
	if spawner.child_exiting_tree.is_connected(exiting):
		spawner.child_exiting_tree.disconnect(exiting)


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
