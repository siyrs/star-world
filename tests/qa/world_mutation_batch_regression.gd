extends SceneTree

const BatchedWorldScript = preload("res://src/world/batched_voxel_world.gd")

var checks := 0
var failures: Array[String] = []


class FakeChunk:
	extends Node
	var blocks: Dictionary = {}
	var rebuild_count := 0

	func get_local_block(local_position: Vector3i) -> String:
		return str(blocks.get(_key(local_position), "air"))

	func set_local_block(
		local_position: Vector3i,
		block_id: String,
		_rebuild: bool = true
	) -> bool:
		var key := _key(local_position)
		if str(blocks.get(key, "air")) == block_id:
			return false
		blocks[key] = block_id
		return true

	func rebuild_mesh() -> void:
		rebuild_count += 1

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_immediate_and_single_chunk_batch()
	await _test_boundary_and_nested_batches()
	await _test_bounded_bulk_api_and_transient_state()
	if failures.is_empty():
		print("QA WORLD MUTATION BATCH PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD MUTATION BATCH FAILURE: %s" % failure)
		print(
			"QA WORLD MUTATION BATCH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_immediate_and_single_chunk_batch() -> void:
	var world = BatchedWorldScript.new()
	root.add_child(world)
	var chunk := _install_chunk(world, Vector2i.ZERO)
	world.reset_chunk_rebuild_stats()
	_check(
		world.set_block(Vector3i(2, 24, 2), "glass_pane"),
		"single mutation changes the production world state",
	)
	var immediate: Dictionary = world.get_chunk_rebuild_stats()
	_check(chunk.rebuild_count == 1, "single mutation preserves immediate mesh correctness")
	_check(
		int(immediate.get("request_count", 0)) == 1
		and int(immediate.get("execution_count", 0)) == 1,
		"single mutation records one request and one actual rebuild",
	)

	chunk.rebuild_count = 0
	world.reset_chunk_rebuild_stats()
	_check(world.begin_chunk_rebuild_batch("single_chunk_128"), "explicit rebuild batch opens")
	for index in 128:
		var position := Vector3i(1 + index % 14, 26, 1 + int(index / 14))
		var block_id := "glass_pane" if index % 2 == 0 else "oak_fence"
		_check(world.set_block(position, block_id), "batched mutation %d changes a unique cell" % index)
	var open_stats: Dictionary = world.get_chunk_rebuild_stats()
	_check(chunk.rebuild_count == 0, "open batch defers expensive chunk rebuilding")
	_check(
		int(open_stats.get("pending_chunks", 0)) == 1,
		"one hundred twenty-eight edits deduplicate to one dirty chunk",
	)
	var closed: Dictionary = world.end_chunk_rebuild_batch(true)
	var closed_stats: Dictionary = closed.get("stats", {})
	_check(bool(closed.get("flushed", false)), "outer batch completion flushes pending chunks")
	_check(chunk.rebuild_count == 1, "single dirty chunk rebuilds exactly once")
	_check(
		int(closed_stats.get("request_count", 0)) == 128
		and int(closed_stats.get("execution_count", 0)) == 1
		and int(closed_stats.get("coalesced_count", 0)) == 127,
		"batch diagnostics retain raw, executed and coalesced rebuild counts",
	)
	world.clear_world()
	world.queue_free()
	await process_frame


func _test_boundary_and_nested_batches() -> void:
	var world = BatchedWorldScript.new()
	root.add_child(world)
	var left := _install_chunk(world, Vector2i.ZERO)
	var right := _install_chunk(world, Vector2i(1, 0))
	world.reset_chunk_rebuild_stats()
	_check(world.begin_chunk_rebuild_batch("cross_chunk_boundary"), "boundary batch opens")
	for y in range(10, 20):
		_check(
			world.set_block(Vector3i(15, y, 3), "glass_pane"),
			"boundary mutation changes y=%d" % y,
		)
	world.end_chunk_rebuild_batch(true)
	var boundary: Dictionary = world.get_chunk_rebuild_stats()
	_check(left.rebuild_count == 1 and right.rebuild_count == 1, "both loaded boundary chunks rebuild once")
	_check(
		int(boundary.get("request_count", 0)) == 20
		and int(boundary.get("execution_count", 0)) == 2
		and int(boundary.get("coalesced_count", 0)) == 18,
		"ten boundary edits collapse twenty requests into two rebuilds",
	)

	left.rebuild_count = 0
	right.rebuild_count = 0
	world.reset_chunk_rebuild_stats()
	_check(world.begin_chunk_rebuild_batch("outer"), "outer nested batch opens")
	_check(world.begin_chunk_rebuild_batch("inner"), "inner nested batch opens")
	_check(world.set_block(Vector3i(4, 22, 4), "oak_fence"), "nested batch changes a cell")
	var inner: Dictionary = world.end_chunk_rebuild_batch(true)
	_check(not bool(inner.get("flushed", true)), "inner completion does not flush an outer transaction")
	_check(left.rebuild_count == 0, "nested batch keeps rebuild deferred")
	world.end_chunk_rebuild_batch(true)
	_check(left.rebuild_count == 1, "outer completion performs the single rebuild")
	_check(
		int(world.get_chunk_rebuild_stats().get("batch_depth", -1)) == 0,
		"nested depth returns to zero",
	)
	world.clear_world()
	world.queue_free()
	await process_frame


func _test_bounded_bulk_api_and_transient_state() -> void:
	var world = BatchedWorldScript.new()
	root.add_child(world)
	var chunk := _install_chunk(world, Vector2i.ZERO)
	var mutations: Array = []
	for index in BatchedWorldScript.MAX_BLOCK_MUTATIONS_PER_BATCH + 1:
		var layer := int(index / (14 * 14))
		var offset := index % (14 * 14)
		mutations.append({
			"position": Vector3i(1 + offset % 14, 1 + layer, 1 + int(offset / 14)),
			"block_id": "glass_pane" if index % 2 == 0 else "oak_fence",
		})
	world.reset_chunk_rebuild_stats()
	var result: Dictionary = world.apply_block_mutations(mutations, "bounded_4096")
	_check(bool(result.get("success", false)), "bounded bulk mutation API completes")
	_check(
		int(result.get("accepted", 0)) == BatchedWorldScript.MAX_BLOCK_MUTATIONS_PER_BATCH
		and int(result.get("truncated", 0)) == 1,
		"bulk mutation API enforces its four-thousand-ninety-six item limit",
	)
	_check(chunk.rebuild_count == 1, "four thousand mutations still rebuild one loaded chunk once")
	var stats: Dictionary = world.get_chunk_rebuild_stats()
	_check(
		int(stats.get("execution_count", 0)) == 1
		and int(stats.get("coalesced_count", 0)) >= 4095,
		"bulk diagnostics prove rebuild work is independent of mutation count",
	)
	var streaming: Dictionary = world.get_streaming_stats()
	_check(
		streaming.get("rebuild", {}) is Dictionary
		and int(streaming.get("rebuild_executions", 0)) == 1,
		"existing streaming diagnostics expose rebuild batching without a parallel telemetry path",
	)
	var serialized := JSON.stringify(world.serialize())
	_check(
		not serialized.contains("rebuild")
		and not serialized.contains("mutation_batch")
		and not serialized.contains("dirty_chunks"),
		"rebuild diagnostics remain transient and never enter world saves",
	)
	_check(world.begin_chunk_rebuild_batch("clear_boundary"), "clear-boundary batch opens")
	world.set_block(Vector3i(5, 40, 5), "stone_bricks")
	world.clear_world()
	var cleared: Dictionary = world.get_chunk_rebuild_stats()
	_check(
		int(cleared.get("batch_depth", -1)) == 0
		and int(cleared.get("pending_chunks", -1)) == 0
		and int(cleared.get("request_count", -1)) == 0,
		"world clear removes pending rebuild state and counters",
	)
	world.queue_free()
	await process_frame


func _install_chunk(world: Node, coord: Vector2i) -> FakeChunk:
	var chunk := FakeChunk.new()
	chunk.name = "FakeChunk_%d_%d" % [coord.x, coord.y]
	world.add_child(chunk)
	world.chunks[coord] = chunk
	return chunk


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
