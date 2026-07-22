class_name BoundedPickupStackCoordinator
extends "res://src/entity/pickup_stack_coordinator.gd"

const MERGE_TRIGGER_NODES := 8


func get_snapshot() -> Dictionary:
	var result: Dictionary = super.get_snapshot()
	result["merge_trigger_nodes"] = MERGE_TRIGGER_NODES
	return result


func _consolidate_pickup(pickup: Node) -> void:
	if (
		not _active
		or _shutdown
		or not _is_pickup(pickup)
		or pickup.get_parent() != spawner
	):
		return
	var live_nodes := _live_pickup_count()
	if live_nodes <= MERGE_TRIGGER_NODES:
		_spawned_node_count += 1
		_update_node_peak()
		_last_summary = {
			"action": "kept_below_merge_trigger",
			"item_id": str(pickup.get("item_id")),
			"item_count": maxi(0, int(pickup.get("item_count"))),
			"pickup_nodes": live_nodes,
			"merge_trigger_nodes": MERGE_TRIGGER_NODES,
		}
		return
	super._consolidate_pickup(pickup)
