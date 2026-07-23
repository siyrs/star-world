class_name BlockStructureIntegrityService
extends Node

signal structural_cleanup_completed(summary: Dictionary)

const PolicyScript = preload("res://src/interaction/block_structure_integrity_policy.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const PickupScript = preload("res://src/entity/item_pickup.gd")

const MAX_PENDING_CANDIDATES := 65536
const MAX_CANDIDATES_PER_FLUSH := 4096
const MAX_STRUCTURES_PER_FLUSH := 1024
const MAX_MUTATIONS_PER_FLUSH := 2048
const MAX_INITIAL_OVERRIDE_SCAN := 8192
const MAX_PENDING_DROP_TYPES := 16
const CLEANUP_REASON := "structural_integrity_cleanup"

var world: Node
var inventory: Node
var pickup_parent: Node3D

var _pending_candidates: Dictionary = {}
var _pending_drops: Dictionary = {}
var _applying_cleanup := false
var _shutdown := false

var _observed_change_count := 0
var _suppressed_internal_change_count := 0
var _queued_candidate_count := 0
var _deduped_candidate_count := 0
var _candidate_overflow_count := 0
var _candidate_scan_count := 0
var _flush_count := 0
var _cleanup_batch_count := 0
var _invalid_structure_count := 0
var _door_cleanup_count := 0
var _ladder_cleanup_count := 0
var _removed_block_count := 0
var _inventory_drop_count := 0
var _pickup_drop_count := 0
var _pickup_node_count := 0
var _drop_backlog_overflow_count := 0
var _max_pending_candidates_observed := 0
var _initial_override_scan_count := 0
var _initial_override_truncated_count := 0
var _last_flush: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)


func setup(p_inventory: Node = null, p_pickup_parent: Node3D = null) -> bool:
	inventory = p_inventory
	pickup_parent = p_pickup_parent
	return inventory != null or pickup_parent != null


func bind_world(p_world: Node) -> bool:
	_disconnect_world()
	world = p_world
	_shutdown = false
	if world == null or not is_instance_valid(world) or not world.has_signal("block_changed"):
		world = null
		clear(true)
		return false
	var callback := Callable(self, "_on_block_changed")
	if not world.is_connected("block_changed", callback):
		world.connect("block_changed", callback)
	clear(true)
	return true


func begin_world() -> void:
	clear(true)
	queue_persisted_structures()


func queue_persisted_structures() -> Dictionary:
	var scanned := 0
	var structural := 0
	var raw_overrides: Variant = _property_value(world, "block_overrides", {})
	if raw_overrides is not Dictionary:
		return {"scanned": 0, "structural": 0, "truncated": false}
	var override_keys: Array[String] = []
	for raw_key: Variant in (raw_overrides as Dictionary).keys():
		override_keys.append(str(raw_key))
	override_keys.sort()
	for key: String in override_keys:
		if scanned >= MAX_INITIAL_OVERRIDE_SCAN:
			_initial_override_truncated_count += 1
			break
		scanned += 1
		var block_id := str((raw_overrides as Dictionary).get(key, ""))
		if not PolicyScript.is_structural_block(block_id):
			continue
		structural += 1
		_queue_candidate_neighborhood(_position_from_key(key))
	_initial_override_scan_count += scanned
	_update_processing()
	return {
		"scanned": scanned,
		"structural": structural,
		"truncated": override_keys.size() > scanned,
		"scan_budget": MAX_INITIAL_OVERRIDE_SCAN,
	}


func clear(reset_counters: bool = true) -> void:
	_pending_candidates.clear()
	_pending_drops.clear()
	_applying_cleanup = false
	_last_flush.clear()
	set_process(false)
	if reset_counters:
		_reset_counters()


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	_disconnect_world()
	world = null
	inventory = null
	pickup_parent = null
	clear(true)


func flush_pending() -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var candidate_positions := _take_candidate_batch(MAX_CANDIDATES_PER_FLUSH)
	var structures: Array[Dictionary] = []
	var structure_keys: Dictionary = {}
	var claimed_positions: Dictionary = {}
	var mutation_positions: Dictionary = {}
	var deferred_from_index := -1

	for index in candidate_positions.size():
		var candidate: Vector3i = candidate_positions[index]
		_candidate_scan_count += 1
		var record: Dictionary = PolicyScript.inspect(world, candidate)
		if record.is_empty() or bool(record.get("supported", true)):
			continue
		var structure_key := str(record.get("structure_key", ""))
		if structure_key.is_empty() or structure_keys.has(structure_key):
			_deduped_candidate_count += 1
			continue
		var positions := _record_positions(record)
		if positions.is_empty():
			continue
		var overlaps := false
		for position: Vector3i in positions:
			if claimed_positions.has(_position_key(position)):
				overlaps = true
				break
		if overlaps:
			_deduped_candidate_count += 1
			continue
		var new_mutations := 0
		for position: Vector3i in positions:
			if not mutation_positions.has(_position_key(position)):
				new_mutations += 1
		if (
			structures.size() >= MAX_STRUCTURES_PER_FLUSH
			or mutation_positions.size() + new_mutations > MAX_MUTATIONS_PER_FLUSH
		):
			deferred_from_index = index
			break
		structure_keys[structure_key] = true
		structures.append(record)
		for position: Vector3i in positions:
			var key := _position_key(position)
			claimed_positions[key] = structure_key
			mutation_positions[key] = position

	if deferred_from_index >= 0:
		for index in range(deferred_from_index, candidate_positions.size()):
			_queue_candidate(candidate_positions[index])

	var changes: Array = []
	var mutation_keys: Array[String] = []
	for raw_key: Variant in mutation_positions.keys():
		mutation_keys.append(str(raw_key))
	mutation_keys.sort()
	for key: String in mutation_keys:
		changes.append({
			"position": mutation_positions[key],
			"block_id": BlockRegistryScript.AIR,
		})

	var apply_result := {
		"success": true,
		"requested": 0,
		"accepted": 0,
		"changed": 0,
		"unchanged": 0,
		"rejected": 0,
		"truncated": 0,
		"rebuild": {},
	}
	if not changes.is_empty():
		apply_result = _apply_mutations(changes)

	var cleanup_succeeded := (
		bool(apply_result.get("success", false))
		and int(apply_result.get("rejected", 0)) == 0
		and int(apply_result.get("truncated", 0)) == 0
	)
	var removed_structures := 0
	var drop_totals: Dictionary = {}
	if cleanup_succeeded:
		for record: Dictionary in structures:
			if not _record_reached_air(record):
				continue
			removed_structures += 1
			_invalid_structure_count += 1
			match str(record.get("kind", "")):
				"door":
					_door_cleanup_count += 1
				"ladder":
					_ladder_cleanup_count += 1
			_queue_drop_record(drop_totals, record)
		_removed_block_count += int(apply_result.get("changed", 0))
		if removed_structures > 0:
			_cleanup_batch_count += 1
	else:
		for record: Dictionary in structures:
			for position: Vector3i in _record_positions(record):
				_queue_candidate(position)

	for raw_item_id: Variant in drop_totals.keys():
		var entry: Dictionary = drop_totals[raw_item_id]
		_queue_drop(
			str(raw_item_id),
			int(entry.get("count", 0)),
			_vector3_from(entry.get("position_sum", Vector3.ZERO))
			/ maxf(1.0, float(entry.get("weight", 1)))
		)
	_flush_pending_drops()

	_flush_count += 1
	_last_flush = {
		"candidate_count": candidate_positions.size(),
		"structure_count": structures.size(),
		"removed_structure_count": removed_structures,
		"mutation_count": changes.size(),
		"changed_block_count": int(apply_result.get("changed", 0)),
		"pending_candidates": _pending_candidates.size(),
		"pending_drop_types": _pending_drops.size(),
		"elapsed_usec": Time.get_ticks_usec() - started_at,
		"apply": apply_result.duplicate(true),
	}
	if removed_structures > 0:
		structural_cleanup_completed.emit(_last_flush.duplicate(true))
	_update_processing()
	return _last_flush.duplicate(true)


func get_snapshot() -> Dictionary:
	var pending_drop_count := 0
	for raw_entry: Variant in _pending_drops.values():
		if raw_entry is Dictionary:
			pending_drop_count += maxi(0, int((raw_entry as Dictionary).get("count", 0)))
	return {
		"active": world != null and is_instance_valid(world) and not _shutdown,
		"shutdown": _shutdown,
		"process_mode": int(process_mode),
		"processing": is_processing(),
		"pending_candidates": _pending_candidates.size(),
		"pending_drop_types": _pending_drops.size(),
		"pending_drop_count": pending_drop_count,
		"observed_change_count": _observed_change_count,
		"suppressed_internal_change_count": _suppressed_internal_change_count,
		"queued_candidate_count": _queued_candidate_count,
		"deduped_candidate_count": _deduped_candidate_count,
		"candidate_overflow_count": _candidate_overflow_count,
		"candidate_scan_count": _candidate_scan_count,
		"flush_count": _flush_count,
		"cleanup_batch_count": _cleanup_batch_count,
		"invalid_structure_count": _invalid_structure_count,
		"door_cleanup_count": _door_cleanup_count,
		"ladder_cleanup_count": _ladder_cleanup_count,
		"removed_block_count": _removed_block_count,
		"inventory_drop_count": _inventory_drop_count,
		"pickup_drop_count": _pickup_drop_count,
		"pickup_node_count": _pickup_node_count,
		"drop_backlog_overflow_count": _drop_backlog_overflow_count,
		"max_pending_candidates_observed": _max_pending_candidates_observed,
		"initial_override_scan_count": _initial_override_scan_count,
		"initial_override_truncated_count": _initial_override_truncated_count,
		"candidate_queue_budget": MAX_PENDING_CANDIDATES,
		"candidates_per_flush": MAX_CANDIDATES_PER_FLUSH,
		"structures_per_flush": MAX_STRUCTURES_PER_FLUSH,
		"mutations_per_flush": MAX_MUTATIONS_PER_FLUSH,
		"initial_override_scan_budget": MAX_INITIAL_OVERRIDE_SCAN,
		"pending_drop_type_budget": MAX_PENDING_DROP_TYPES,
		"last_flush": _last_flush.duplicate(true),
	}


func _process(_delta: float) -> void:
	flush_pending()


func _on_block_changed(
	block_position: Vector3i,
	_old_block: String,
	_new_block: String
) -> void:
	if _shutdown:
		return
	_observed_change_count += 1
	if _applying_cleanup:
		_suppressed_internal_change_count += 1
		return
	_queue_candidate_neighborhood(block_position)
	_update_processing()


func _queue_candidate_neighborhood(block_position: Vector3i) -> void:
	for candidate: Vector3i in PolicyScript.candidate_positions(block_position):
		_queue_candidate(candidate)


func _queue_candidate(position: Vector3i) -> bool:
	var key := _position_key(position)
	if _pending_candidates.has(key):
		_deduped_candidate_count += 1
		return true
	if _pending_candidates.size() >= MAX_PENDING_CANDIDATES:
		_candidate_overflow_count += 1
		return false
	_pending_candidates[key] = position
	_queued_candidate_count += 1
	_max_pending_candidates_observed = maxi(
		_max_pending_candidates_observed,
		_pending_candidates.size()
	)
	return true


func _take_candidate_batch(limit: int) -> Array[Vector3i]:
	var keys: Array[String] = []
	for raw_key: Variant in _pending_candidates.keys():
		keys.append(str(raw_key))
	keys.sort()
	var result: Array[Vector3i] = []
	for index in mini(keys.size(), maxi(0, limit)):
		var key := keys[index]
		var raw_position: Variant = _pending_candidates.get(key, Vector3i.ZERO)
		_pending_candidates.erase(key)
		if raw_position is Vector3i:
			result.append(raw_position)
	return result


func _apply_mutations(changes: Array) -> Dictionary:
	if world == null or not is_instance_valid(world):
		return {
			"success": false,
			"reason": "world_unavailable",
			"requested": changes.size(),
			"accepted": 0,
			"changed": 0,
			"unchanged": 0,
			"rejected": changes.size(),
			"truncated": 0,
			"rebuild": {},
		}
	_applying_cleanup = true
	var result: Dictionary = {}
	if world.has_method("apply_block_mutations"):
		var raw_result: Variant = world.call("apply_block_mutations", changes, CLEANUP_REASON)
		if raw_result is Dictionary:
			result = raw_result
	else:
		var began_batch := (
			world.has_method("begin_chunk_rebuild_batch")
			and bool(world.call("begin_chunk_rebuild_batch", CLEANUP_REASON))
		)
		var changed := 0
		var unchanged := 0
		for raw_change: Variant in changes:
			if raw_change is not Dictionary:
				continue
			var change: Dictionary = raw_change
			var position: Variant = change.get("position", Vector3i.ZERO)
			if position is Vector3i and world.has_method("set_block"):
				if bool(world.call("set_block", position, str(change.get("block_id", "air")))):
					changed += 1
				else:
					unchanged += 1
		var rebuild: Dictionary = {}
		if began_batch and world.has_method("end_chunk_rebuild_batch"):
			var raw_end: Variant = world.call("end_chunk_rebuild_batch", true)
			if raw_end is Dictionary:
				rebuild = (raw_end as Dictionary).get("stats", {})
		result = {
			"success": true,
			"reason": "fallback",
			"requested": changes.size(),
			"accepted": changes.size(),
			"changed": changed,
			"unchanged": unchanged,
			"rejected": 0,
			"truncated": 0,
			"rebuild": rebuild,
		}
	_applying_cleanup = false
	return result


func _queue_drop_record(drop_totals: Dictionary, record: Dictionary) -> void:
	var item_id := str(record.get("drop_item", ""))
	var count := maxi(0, int(record.get("drop_count", 0)))
	if item_id.is_empty() or count <= 0:
		return
	var entry: Dictionary = drop_totals.get(item_id, {})
	entry["count"] = int(entry.get("count", 0)) + count
	entry["weight"] = int(entry.get("weight", 0)) + count
	entry["position_sum"] = (
		_vector3_from(entry.get("position_sum", Vector3.ZERO))
		+ _vector3_from(record.get("drop_position", Vector3.ZERO)) * float(count)
	)
	drop_totals[item_id] = entry


func _queue_drop(item_id: String, count: int, position: Vector3) -> bool:
	if item_id.is_empty() or count <= 0:
		return true
	var entry: Dictionary = _pending_drops.get(item_id, {})
	if entry.is_empty() and _pending_drops.size() >= MAX_PENDING_DROP_TYPES:
		_drop_backlog_overflow_count += 1
		return false
	var previous_count := maxi(0, int(entry.get("count", 0)))
	var total := previous_count + count
	var previous_position := _vector3_from(entry.get("position", position))
	entry["count"] = total
	entry["position"] = (
		(previous_position * float(previous_count) + position * float(count))
		/ maxf(1.0, float(total))
	)
	_pending_drops[item_id] = entry
	return true


func _flush_pending_drops() -> void:
	var item_ids: Array[String] = []
	for raw_item_id: Variant in _pending_drops.keys():
		item_ids.append(str(raw_item_id))
	item_ids.sort()
	for item_id: String in item_ids:
		var entry: Dictionary = _pending_drops.get(item_id, {})
		var count := maxi(0, int(entry.get("count", 0)))
		if count <= 0:
			_pending_drops.erase(item_id)
			continue
		var remaining := count
		if inventory != null and is_instance_valid(inventory) and inventory.has_method("add_item"):
			remaining = maxi(0, int(inventory.call("add_item", item_id, count)))
			_inventory_drop_count += count - remaining
		if remaining > 0 and pickup_parent != null and is_instance_valid(pickup_parent):
			var pickup = PickupScript.new()
			pickup.call("setup", item_id, remaining, inventory)
			pickup_parent.add_child(pickup)
			pickup.global_position = _vector3_from(entry.get("position", Vector3.ZERO))
			_pickup_drop_count += remaining
			_pickup_node_count += 1
			remaining = 0
		if remaining <= 0:
			_pending_drops.erase(item_id)
		else:
			entry["count"] = remaining
			_pending_drops[item_id] = entry


func _record_positions(record: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var raw_positions: Variant = record.get("positions", [])
	if raw_positions is not Array:
		return result
	for raw_position: Variant in raw_positions:
		if raw_position is Vector3i and raw_position not in result:
			result.append(raw_position)
	return result


func _record_reached_air(record: Dictionary) -> bool:
	if world == null or not is_instance_valid(world) or not world.has_method("get_block"):
		return false
	var removed := false
	for position: Vector3i in _record_positions(record):
		if str(world.call("get_block", position)) == BlockRegistryScript.AIR:
			removed = true
	return removed


func _update_processing() -> void:
	set_process(
		not _shutdown
		and world != null
		and is_instance_valid(world)
		and (not _pending_candidates.is_empty() or not _pending_drops.is_empty())
	)


func _disconnect_world() -> void:
	if world == null or not is_instance_valid(world) or not world.has_signal("block_changed"):
		return
	var callback := Callable(self, "_on_block_changed")
	if world.is_connected("block_changed", callback):
		world.disconnect("block_changed", callback)


func _reset_counters() -> void:
	_observed_change_count = 0
	_suppressed_internal_change_count = 0
	_queued_candidate_count = 0
	_deduped_candidate_count = 0
	_candidate_overflow_count = 0
	_candidate_scan_count = 0
	_flush_count = 0
	_cleanup_batch_count = 0
	_invalid_structure_count = 0
	_door_cleanup_count = 0
	_ladder_cleanup_count = 0
	_removed_block_count = 0
	_inventory_drop_count = 0
	_pickup_drop_count = 0
	_pickup_node_count = 0
	_drop_backlog_overflow_count = 0
	_max_pending_candidates_observed = 0
	_initial_override_scan_count = 0
	_initial_override_truncated_count = 0


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	if target == null or not is_instance_valid(target):
		return fallback
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback


func _position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


func _position_from_key(value: String) -> Vector3i:
	var parts := value.split(",")
	if parts.size() != 3:
		return Vector3i.ZERO
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector3i.ZERO
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector3i:
		return Vector3(value)
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
