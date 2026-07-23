extends "res://tests/qa/structural_integrity_regression.gd"


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
	_check(
		service.setup(inventory, pickup_parent),
		"structural service accepts inventory and pickup delivery ports",
	)
	_check(
		service.bind_world(world),
		"structural service binds the world block-change signal",
	)

	var lower := Vector3i(15, 20, 15)
	var door_support := lower + Vector3i.DOWN
	var ladder_position := Vector3i(17, 20, 15)
	var ladder_support := ladder_position + Vector3i.LEFT
	var fixture_positions := {
		str(door_support): true,
		str(lower): true,
		str(lower + Vector3i.UP): true,
		str(ladder_support): true,
		str(ladder_position): true,
	}
	_check(
		fixture_positions.size() == 5,
		"unit fixture keeps every support and structural cell distinct",
	)
	world.set_test_block(door_support, "stone")
	world.set_test_block(lower, "oak_door")
	world.set_test_block(lower + Vector3i.UP, "oak_door_upper")
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
	_check(
		world.apply_call_count == before_cleanup_calls + 1,
		"door and ladder cleanup share one production mutation batch",
	)
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
	_check(
		not service.is_processing(),
		"integrity service disables processing when the queue is empty",
	)
	service.shutdown()
	service.queue_free()
	world.queue_free()
	inventory.queue_free()
	pickup_parent.queue_free()
	await process_frame
	await process_frame
