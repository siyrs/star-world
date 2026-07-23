extends SceneTree

const BatchedWorldScript = preload("res://src/world/batched_voxel_world.gd")

var checks := 0
var failures: Array[String] = []
var _world: Node
var _nested_applied := false
var _pre_flush_reasons: Array[String] = []
var _nested_result: Dictionary = {}


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
	await _test_nested_mutation_joins_outer_flush()
	if failures.is_empty():
		print("QA WORLD MUTATION PRE-FLUSH PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD MUTATION PRE-FLUSH FAILURE: %s" % failure)
		print(
			"QA WORLD MUTATION PRE-FLUSH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_nested_mutation_joins_outer_flush() -> void:
	_world = BatchedWorldScript.new()
	root.add_child(_world)
	var left := _install_chunk(_world, Vector2i.ZERO)
	var right := _install_chunk(_world, Vector2i(1, 0))
	_world.reset_chunk_rebuild_stats()
	var callback := Callable(self, "_on_batch_pre_flush")
	_world.block_mutation_batch_pre_flush.connect(callback)

	var outer_result: Dictionary = _world.apply_block_mutations(
		[
			{"position": Vector3i(15, 20, 4), "block_id": "stone"},
			{"position": Vector3i(15, 21, 4), "block_id": "glass_pane"},
		],
		"outer_supports",
	)
	_check(bool(outer_result.get("success", false)), "outer mutation batch completes")
	_check(_nested_applied, "outer pre-flush callback applies one nested mutation batch")
	_check(
		_pre_flush_reasons == ["outer_supports", "nested_dependents"],
		"outer and nested batches emit deterministic pre-flush summaries",
	)
	_check(
		str(_world.get_block(Vector3i(15, 22, 4))) == "oak_fence",
		"nested dependent mutation is visible before the outer API returns",
	)

	var nested_rebuild: Dictionary = _nested_result.get("rebuild", {})
	_check(
		bool(nested_rebuild.get("batch_active", false))
		and int(nested_rebuild.get("batch_depth", -1)) == 1
		and int(nested_rebuild.get("pending_chunks", -1)) == 2,
		"nested mutation returns while the outer dirty-chunk transaction remains open",
	)
	var stats: Dictionary = _world.get_chunk_rebuild_stats()
	_check(
		int(stats.get("flush_count", -1)) == 1
		and int(stats.get("execution_count", -1)) == 2
		and int(stats.get("last_flush_chunk_count", -1)) == 2,
		"outer and nested boundary edits share one two-chunk mesh flush",
	)
	_check(
		left.rebuild_count == 1 and right.rebuild_count == 1,
		"each loaded boundary chunk rebuilds exactly once",
	)
	_check(
		int(stats.get("pre_flush_emit_count", -1)) == 2
		and int(stats.get("batch_depth", -1)) == 0
		and not bool(stats.get("batch_active", true)),
		"pre-flush diagnostics close with balanced batch depth",
	)
	_check(
		int(stats.get("request_count", 0)) == 6
		and int(stats.get("coalesced_count", 0)) == 4,
		"three boundary edits collapse six rebuild requests into two executions",
	)
	var serialized := JSON.stringify(_world.serialize())
	_check(
		not serialized.contains("pre_flush")
		and not serialized.contains("dirty_chunks")
		and not serialized.contains("mutation_batch"),
		"pre-flush hooks and counters remain transient",
	)

	if _world.block_mutation_batch_pre_flush.is_connected(callback):
		_world.block_mutation_batch_pre_flush.disconnect(callback)
	_world.clear_world()
	_world.queue_free()
	_world = null
	await process_frame


func _on_batch_pre_flush(reason: String, summary: Dictionary) -> void:
	_pre_flush_reasons.append(reason)
	_check(
		int(summary.get("batch_depth", 0)) >= 1
		and int(summary.get("pending_chunks", 0)) == 2,
		"pre-flush summary exposes bounded active-batch evidence",
	)
	if reason != "outer_supports" or _nested_applied:
		return
	_nested_applied = true
	_nested_result = _world.apply_block_mutations(
		[
			{"position": Vector3i(15, 22, 4), "block_id": "oak_fence"},
		],
		"nested_dependents",
	)


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
