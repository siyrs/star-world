extends SceneTree

const PolicyScript = preload("res://src/interaction/block_structure_integrity_policy.gd")
const ServiceScript = preload("res://src/interaction/block_structure_integrity_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node

	signal block_changed(block_position: Vector3i, old_block: String, new_block: String)

	var blocks: Dictionary = {}
	var block_overrides: Dictionary = {}
	var apply_call_count := 0
	var last_apply_reason := ""
	var last_apply_changes: Array = []

	func set_test_block(position: Vector3i, block_id: String, persist: bool = false) -> void:
		blocks[_key(position)] = block_id
		if persist:
			block_overrides[_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var old_block := get_block(position)
		if old_block == block_id:
			return false
		blocks[_key(position)] = block_id
		if block_id == "air":
			block_overrides.erase(_key(position))
		else:
			block_overrides[_key(position)] = block_id
		block_changed.emit(position, old_block, block_id)
		return true

	func apply_block_mutations(changes: Array, reason: String = "test") -> Dictionary:
		apply_call_count += 1
		last_apply_reason = reason
		last_apply_changes = changes.duplicate(true)
		var changed := 0
		var unchanged := 0
		var rejected := 0
		for raw_change: Variant in changes:
			if raw_change is not Dictionary:
				rejected += 1
				continue
			var change: Dictionary = raw_change
			var position: Variant = change.get("position", Vector3i.ZERO)
			if position is not Vector3i:
				rejected += 1
				continue
			if set_block(position, str(change.get("block_id", "air"))):
				changed += 1
			else:
				unchanged += 1
		return {
			"success": true,
			"requested": changes.size(),
			"accepted": changes.size(),
			"changed": changed,
			"unchanged": unchanged,
			"rejected": rejected,
			"truncated": 0,
			"rebuild": {
				"execution_count": 1 if changed > 0 else 0,
				"pending_chunks": 0,
				"batch_depth": 0,
			},
		}

	func block_key(position: Vector3i) -> String:
		return _key(position)

	func block_to_world(position: Vector3i) -> Vector3:
		return Vector3(position) + Vector3(0.5, 0.5, 0.5)

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_contract()
	await _test_batched_cleanup_and_dedupe()
	await _test_orphan_and_pickup_fallback()
	await _test_persisted_override_scan()
	if failures.is_empty():
		print("QA STRUCTURAL INTEGRITY PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA STRUCTURAL INTEGRITY FAILURE: %s" % failure)
		print(
			"QA STRUCTURAL INTEGRITY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_policy_contract() -> void:
	var changed_position := Vector3i(16, 20, 16)
	var candidates := PolicyScript.candidate_positions(changed_position)
	_check(candidates.size() == 7, "one changed cell produces seven bounded structural candidates")
	var unique: Dictionary = {}
	for position: Vector3i in candidates:
		unique[str(position)] = true
	_check(unique.size() == 7, "candidate neighborhood contains no duplicate positions")

	var world := FakeWorld.new()
	root.add_child(world)
	var lower := Vector3i(0, 10, 0)
	world.set_test_block(lower + Vector3i.DOWN, "stone")
	world.set_test_block(lower, "oak_door_open_east")
	world.set_test_block(lower + Vector3i.UP, "oak_door_upper_open_east")
	var door: Dictionary = PolicyScript.inspect(world, lower + Vector3i.UP)
	_check(
		bool(door.get("supported", false))
		and str(door.get("structure_key", "")) == "door:0,10,0",
		"matching open door halves resolve through one canonical lower structure key",
	)
	world.set_test_block(lower + Vector3i.DOWN, "air")
	door = PolicyScript.inspect(world, lower)
	_check(
		not bool(door.get("supported", true))
		and str(door.get("reason", "")) == "support_missing"
		and (door.get("positions", []) as Array).size() == 2,
		"door policy identifies both halves when floor support disappears",
	)

	var ladder_position := Vector3i(16, 12, 4)
	world.set_test_block(ladder_position, "ladder_west")
	world.set_test_block(ladder_position + Vector3i.LEFT, "stone")
	var ladder: Dictionary = PolicyScript.inspect(world, ladder_position)
	_check(bool(ladder.get("supported", false)), "directional ladder accepts its encoded backing wall")
	world.set_test_block(ladder_position + Vector3i.LEFT, "air")
	ladder = PolicyScript.inspect(world, ladder_position)
	_check(
		not bool(ladder.get("supported", true))
		and str(ladder.get("drop_item", "")) == "ladder",
		"orphan ladder resolves one canonical item return",
	)
	world.queue_free()


func _test_batched_cleanup_and_dedupe() -> void:
	var world := FakeWorld.new()
	var inventory = InventoryScript.new()
	var pickup_parent := Node3D.new()
	var service = ServiceScript.new()
	root.add_child(world)
	root.add_child(inventory)
	root.add_child(pickup_parent)
	root.add_child(service)
	await process_frame
	_check(service.setup(inventory, pickup_parent), "structural service accepts inventory and pickup delivery ports")
	_check(service.bind_world(world), "structural service binds the world block-change signal")

	var lower := Vector3i(15, 20, 15)
	var door_support := lower + Vector3i.DOWN
	world.set_test_block(door_support, "stone")
	world.set_test_block(lower, "oak_door")
	world.set_test_block(lower + Vector3i.UP, "oak_door_upper")
	var ladder_position := Vector3i(16, 20, 15)
	var ladder_support := ladder_position + Vector3i.LEFT
	world.set_test_block(ladder_support, "stone")
	world.set_test_block(ladder_position, "ladder_west")

	var before_cleanup_calls := world.apply_call_count
	world.set_block(door_support, "air")
	world.block_changed.emit(door_support, "stone", "air")
	world.set_block(ladder_support, "air")
	world.block_changed.emit(ladder_support, "stone", "air")
	var queued: Dictionary = service.get_snapshot()
	_check(
		int(queued.get("pending_candidates", 0)) > 0
		and bool(queued.get("processing", false)),
		"support changes activate one shared pausable integrity loop",
	)
	var result: Dictionary = service.flush_pending()
	_check(world.apply_call_count == before_cleanup_calls + 1, "door and ladder cleanup share one production mutation batch")
	_check(
		str(world.get_block(lower)) == "air"
		and str(world.get_block(lower + Vector3i.UP)) == "air"
		and str(world.get_block(ladder_position)) == "air",
		"one flush removes the complete unsupported door and ladder",
	)
	_check(
		inventory.count_item("oak_door") == 1
		and inventory.count_item("ladder") == 1,
		"batched cleanup returns exactly one canonical item per structure",
	)
	_check(
		int(result.get("removed_structure_count", 0)) == 2
		and int(result.get("mutation_count", 0)) == 3,
		"flush evidence distinguishes structures from removed block cells",
	)
	var snapshot: Dictionary = service.get_snapshot()
	_check(
		int(snapshot.get("door_cleanup_count", 0)) == 1
		and int(snapshot.get("ladder_cleanup_count", 0)) == 1
		and int(snapshot.get("cleanup_batch_count", 0)) == 1,
		"bounded diagnostics retain exact door, ladder and batch totals",
	)
	_check(
		int(snapshot.get("candidate_overflow_count", -1)) == 0
		and int(snapshot.get("deduped_candidate_count", 0)) > 0,
		"duplicate support events coalesce without overflowing the candidate budget",
	)
	_check(
		int(snapshot.get("process_mode", -1)) == Node.PROCESS_MODE_PAUSABLE,
		"integrity cleanup uses the pausable simulation contract",
	)
	service.clear(true)
	_check(not service.is_processing(), "integrity service disables processing when the queue is empty")
	service.shutdown()
	service.queue_free()
	world.queue_free()
	inventory.queue_free()
	pickup_parent.queue_free()
	await process_frame
	await process_frame


func _test_orphan_and_pickup_fallback() -> void:
	var world := FakeWorld.new()
	var inventory = InventoryScript.new()
	var pickup_parent := Node3D.new()
	var service = ServiceScript.new()
	root.add_child(world)
	root.add_child(inventory)
	root.add_child(pickup_parent)
	root.add_child(service)
	await process_frame
	service.setup(inventory, pickup_parent)
	service.bind_world(world)

	var orphan_upper := Vector3i(3, 22, 3)
	world.set_test_block(orphan_upper, "oak_door_upper_north")
	world.block_changed.emit(orphan_upper, "air", "oak_door_upper_north")
	service.flush_pending()
	_check(str(world.get_block(orphan_upper)) == "air", "orphan upper door half self-cleans")
	_check(inventory.count_item("oak_door") == 1, "orphan half returns one door instead of duplicating both halves")

	inventory.clear()
	var stone_remainder := inventory.add_item("stone", int(inventory.get("slot_count")) * 64)
	_check(stone_remainder == 0, "fallback fixture fills the complete player inventory")
	var ladder_position := Vector3i(8, 24, 8)
	world.set_test_block(ladder_position, "ladder")
	world.set_test_block(ladder_position + Vector3i.BACK, "stone")
	world.set_block(ladder_position + Vector3i.BACK, "air")
	service.flush_pending()
	_check(inventory.count_item("ladder") == 0, "full inventory does not partially grant a ladder")
	_check(pickup_parent.get_child_count() == 1, "full inventory produces one bounded physical fallback node")
	if pickup_parent.get_child_count() == 1:
		var pickup: Node = pickup_parent.get_child(0)
		_check(
			str(pickup.get("item_id")) == "ladder"
			and int(pickup.get("item_count")) == 1,
			"physical fallback preserves the exact canonical item count",
		)
	var snapshot: Dictionary = service.get_snapshot()
	_check(
		int(snapshot.get("pickup_drop_count", 0)) == 1
		and int(snapshot.get("pickup_node_count", 0)) == 1
		and int(snapshot.get("pending_drop_count", -1)) == 0,
		"fallback diagnostics prove no item remained in an undelivered backlog",
	)
	service.shutdown()
	service.queue_free()
	world.queue_free()
	inventory.queue_free()
	pickup_parent.queue_free()
	await process_frame
	await process_frame


func _test_persisted_override_scan() -> void:
	var world := FakeWorld.new()
	var inventory = InventoryScript.new()
	var pickup_parent := Node3D.new()
	var service = ServiceScript.new()
	root.add_child(world)
	root.add_child(inventory)
	root.add_child(pickup_parent)
	root.add_child(service)
	await process_frame
	service.setup(inventory, pickup_parent)
	service.bind_world(world)

	var orphan_ladder := Vector3i(-16, 18, 0)
	world.set_test_block(orphan_ladder, "ladder_east", true)
	var valid_lower := Vector3i(-15, 18, 0)
	world.set_test_block(valid_lower + Vector3i.DOWN, "stone", true)
	world.set_test_block(valid_lower, "oak_door_west", true)
	world.set_test_block(valid_lower + Vector3i.UP, "oak_door_upper_west", true)
	var scan: Dictionary = service.queue_persisted_structures()
	_check(
		int(scan.get("structural", 0)) == 3
		and not bool(scan.get("truncated", true)),
		"world-start scan only queues persisted structural overrides inside its budget",
	)
	service.flush_pending()
	_check(str(world.get_block(orphan_ladder)) == "air", "world-start scan repairs an old unsupported ladder")
	_check(
		str(world.get_block(valid_lower)) == "oak_door_west"
		and str(world.get_block(valid_lower + Vector3i.UP)) == "oak_door_upper_west",
		"world-start repair leaves a supported persisted door untouched",
	)
	var snapshot: Dictionary = service.get_snapshot()
	_check(
		int(snapshot.get("initial_override_scan_count", 0)) >= 3
		and int(snapshot.get("initial_override_truncated_count", -1)) == 0,
		"initial repair diagnostics remain bounded and non-truncated",
	)
	service.shutdown()
	service.queue_free()
	world.queue_free()
	inventory.queue_free()
	pickup_parent.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
