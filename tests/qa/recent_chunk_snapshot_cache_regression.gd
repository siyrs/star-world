extends SceneTree

const CacheScript = preload("res://src/world/recent_chunk_snapshot_cache.gd")
const CachedChunkScript = preload("res://src/chunk/cached_voxel_chunk.gd")
const CachedWorldScript = preload("res://src/world/cached_batched_voxel_world.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bounded_cache_policy()
	await _test_world_unload_reload_and_patch()
	if failures.is_empty():
		print("QA RECENT CHUNK SNAPSHOT CACHE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RECENT CHUNK SNAPSHOT CACHE FAILURE: %s" % failure)
		print(
			"QA RECENT CHUNK SNAPSHOT CACHE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_bounded_cache_policy() -> void:
	var cache = CacheScript.new()
	var snapshot := _empty_snapshot()
	for index in CacheScript.MAX_SNAPSHOTS + 1:
		_check(
			cache.store(Vector2i(index, 0), snapshot),
			"bounded cache accepts snapshot %d" % index,
		)
	var stats: Dictionary = cache.get_stats()
	_check(
		int(stats.get("entry_count", 0)) == CacheScript.MAX_SNAPSHOTS
		and int(stats.get("eviction_count", 0)) == 1,
		"sixty-five stores retain sixty-four recent snapshots and evict one",
	)
	_check(
		not cache.has(Vector2i.ZERO) and cache.has(Vector2i(CacheScript.MAX_SNAPSHOTS, 0)),
		"bounded cache evicts the oldest coordinate first",
	)
	var patch_coord := Vector2i(8, 0)
	var patch_index := CachedChunkScript.local_cell_index(Vector3i(3, 40, 4))
	var pane_numeric := BlockRegistryScript.get_numeric_id("glass_pane")
	_check(cache.patch(patch_coord, patch_index, pane_numeric), "cached block snapshots accept bounded patching")
	var patched: PackedInt32Array = cache.take(patch_coord)
	_check(
		patched.size() == CacheScript.CHUNK_CELL_COUNT and patched[patch_index] == pane_numeric,
		"patched snapshot preserves the authoritative unloaded block edit",
	)
	var missing: PackedInt32Array = cache.take(Vector2i(999, 999))
	stats = cache.get_stats()
	_check(
		missing.is_empty()
		and int(stats.get("hit_count", 0)) == 1
		and int(stats.get("miss_count", 0)) == 1,
		"cache diagnostics distinguish warm hits from cold misses",
	)
	_check(
		int(stats.get("estimated_bytes", 0))
		<= CacheScript.MAX_SNAPSHOTS * CacheScript.CHUNK_CELL_COUNT * CacheScript.BYTES_PER_CELL,
		"cache memory estimate remains inside the fixed four-mebibyte cell budget",
	)


func _test_world_unload_reload_and_patch() -> void:
	var world = CachedWorldScript.new()
	root.add_child(world)
	var coord := Vector2i(2, -1)
	var local_position := Vector3i(3, 40, 4)
	var global_position := Vector3i(
		coord.x * world.CHUNK_SIZE + local_position.x,
		local_position.y,
		coord.y * world.CHUNK_SIZE + local_position.z
	)
	var snapshot := _empty_snapshot()
	var stone_numeric := BlockRegistryScript.get_numeric_id("stone_bricks")
	snapshot[CachedChunkScript.local_cell_index(local_position)] = stone_numeric
	var chunk = CachedChunkScript.new()
	world.add_child(chunk)
	_check(
		chunk.begin_initialize_from_snapshot(coord, world, snapshot),
		"snapshot-backed chunk begins directly in mesh construction",
	)
	world.chunks[coord] = chunk
	world.call("_unload_chunk", coord)
	await process_frame
	var cached: Dictionary = world.get_recent_chunk_cache_stats()
	_check(
		int(cached.get("entry_count", 0)) == 1 and int(cached.get("store_count", 0)) == 1,
		"unloading a complete chunk stores one bounded block snapshot",
	)
	var restored: Node = world.call("_load_chunk_synchronously", coord)
	_check(
		restored != null
		and restored.has_method("was_hydrated_from_snapshot")
		and bool(restored.call("was_hydrated_from_snapshot")),
		"warm chunk reload skips sixteen-thousand-three-hundred-eighty-four generation cells",
	)
	_check(
		str(restored.call("get_local_block", local_position)) == "stone_bricks",
		"warm reload restores the exact cached block array",
	)
	cached = world.get_recent_chunk_cache_stats()
	_check(
		int(cached.get("hit_count", 0)) == 1 and int(cached.get("entry_count", -1)) == 0,
		"warm reload consumes the recent snapshot and records one cache hit",
	)

	world.call("_unload_chunk", coord)
	await process_frame
	var patch_local := Vector3i(4, 63, 5)
	var patch_global := Vector3i(
		coord.x * world.CHUNK_SIZE + patch_local.x,
		patch_local.y,
		coord.y * world.CHUNK_SIZE + patch_local.z
	)
	_check(
		world.set_block(patch_global, "glass_pane"),
		"authoritative edits can target a recently unloaded cached chunk",
	)
	var patched_restore: Node = world.call("_load_chunk_synchronously", coord)
	_check(
		str(patched_restore.call("get_local_block", patch_local)) == "glass_pane",
		"unloaded edits patch the cached block array before the next warm reload",
	)
	cached = world.get_recent_chunk_cache_stats()
	_check(
		int(cached.get("patch_count", 0)) == 1 and int(cached.get("hit_count", 0)) == 2,
		"cache diagnostics retain patch and repeated-hit evidence",
	)
	var streaming: Dictionary = world.get_streaming_stats()
	_check(
		streaming.get("recent_chunk_cache", {}) is Dictionary
		and int(streaming.get("recent_chunk_cache", {}).get("hit_count", 0)) == 2,
		"existing streaming diagnostics expose the recent chunk cache",
	)
	var serialized := JSON.stringify(world.serialize())
	_check(
		not serialized.contains("recent_chunk_cache")
		and not serialized.contains("snapshot_hydrated")
		and not serialized.contains("cached_coord_samples"),
		"recent chunk snapshots and diagnostics remain transient and never enter world saves",
	)
	world.clear_world()
	cached = world.get_recent_chunk_cache_stats()
	_check(
		int(cached.get("entry_count", -1)) == 0
		and int(cached.get("hit_count", -1)) == 0
		and int(cached.get("store_count", -1)) == 0,
		"world clear removes cached chunks and resets per-world counters",
	)
	world.queue_free()
	await process_frame


func _empty_snapshot() -> PackedInt32Array:
	var snapshot := PackedInt32Array()
	snapshot.resize(CacheScript.CHUNK_CELL_COUNT)
	snapshot.fill(BlockRegistryScript.get_numeric_id("air"))
	return snapshot


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
