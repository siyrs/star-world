extends "res://tests/qa/structural_integrity_regression.gd"

const BatchedServiceScript = preload(
	"res://src/interaction/batched_block_structure_integrity_service.gd"
)


class PreFlushWorld extends FakeWorld:
	signal block_mutation_batch_pre_flush(reason: String, summary: Dictionary)

	var apply_reasons: Array[String] = []

	func apply_block_mutations(
		changes: Array,
		reason: String = "test"
	) -> Dictionary:
		apply_reasons.append(reason)
		var result: Dictionary = super.apply_block_mutations(changes, reason)
		block_mutation_batch_pre_flush.emit(reason, result.duplicate(true))
		return result


func _test_batched_cleanup_and_dedupe() -> void:
	var world := PreFlushWorld.new()
	var inventory = InventoryScript.new()
	var pickup_parent := Node3D.new()
	var service = BatchedServiceScript.new()
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
		"structural service binds block changes and the outer batch pre-flush hook",
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
	var outer_result: Dictionary = world.apply_block_mutations(
		[
			{"position": door_support, "block_id": "air"},
			{"position": ladder_support, "block_id": "air"},
		],
		"structural_integrity_unit_supports",
	)
	_check(
		bool(outer_result.get("success", false)),
		"outer support mutation batch completes successfully",
	)
	var snapshot: Dictionary = service.get_snapshot()
	var result: Dictionary = snapshot.get("last_flush", {})
	_check(
		int(snapshot.get("pending_candidates", -1)) == 0
		and not bool(snapshot.get("processing", true)),
		"outer batch pre-flush drains the structural queue before the API returns",
	)
	_check(
		world.apply_call_count == before_cleanup_calls + 2
		and world.apply_reasons == [
			"structural_integrity_unit_supports",
			"structural_integrity_cleanup",
		],
		"one outer support batch owns exactly one nested structural mutation batch",
	)
	_check(
		int(snapshot.get("pre_flush_signal_count", 0)) == 2
		and int(snapshot.get("pre_flush_cleanup_count", 0)) == 1,
		"nested cleanup emits diagnostics without recursively starting another cleanup",
	)
	_check(
		str(world.get_block(lower)) == "air"
		and str(world.get_block(lower + Vector3i.UP)) == "air"
		and str(world.get_block(ladder_position)) == "air",
		"one pre-flush cleanup removes the complete unsupported door and ladder",
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
