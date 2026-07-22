extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const ConnectionPolicy = preload("res://src/block/block_connection_policy.gd")

const OUTPUT_PATH := "user://recent-chunk-cache-desktop.png"
const GRID_SIZE := 40
const LADDER_HEIGHT := 6
const WARM_CYCLES := 3
const READY_FRAMES := 900
const UNLOAD_FRAMES := 300
const MAX_WARM_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_SAVE_BYTES := 2500000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}
var _sample_blocks: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 5:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Recent-Chunk-Cache-%d" % Time.get_ticks_msec(),
		"star_continent",
		82590117
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop cache acceptance creates a temporary world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded playable state",
	)
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	_check(
		world != null
		and world.has_method("get_recent_chunk_cache_stats")
		and world.has_method("apply_block_mutations"),
		"production GameScene composes batching and recent chunk snapshots",
	)
	if world == null or player == null or not world.has_method("get_recent_chunk_cache_stats"):
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var center_chunk: Vector2i = world.call("block_to_chunk", player_block)
	var floor_y := clampi(player_block.y - 1, 12, 56)
	var base_x := (center_chunk.x - 1) * 16 + 4
	var base_z := (center_chunk.y - 1) * 16 + 4
	var mutations := _build_connected_fixture(base_x, base_z, floor_y)
	_check(
		mutations.size() >= 3000 and mutations.size() <= 4096,
		"connected revisit fixture uses more than three thousand bounded mutations",
	)
	var target_coords := _unique_chunk_coords(world, mutations)
	_check(
		target_coords.size() >= 9 and target_coords.size() <= 16,
		"fixture spans a bounded multi-chunk connected region",
	)
	_force_load_chunks(world, target_coords)
	world.call("reset_chunk_rebuild_stats")
	var setup_result: Dictionary = world.call(
		"apply_block_mutations",
		mutations,
		"recent_chunk_cache_connected_fixture"
	)
	_check(bool(setup_result.get("success", false)), "connected fixture commits through the production batch API")
	_check(
		int(setup_result.get("changed", 0)) >= 2400,
		"connected fixture changes at least twenty-four hundred real cells",
	)

	var center_world := Vector3(
		base_x + GRID_SIZE * 0.5,
		floor_y + 4.0,
		base_z + GRID_SIZE * 0.5
	)
	var far_world := center_world + Vector3(16.0 * 10.0, 0.0, 16.0 * 10.0)
	var cycle_milliseconds: Array[float] = []
	var cycle_hit_deltas: Array[int] = []
	var patch_position := Vector3i(base_x + 17, floor_y + 1, base_z + 17)
	var expected_patch := "glass_pane_ns"

	for cycle in WARM_CYCLES:
		var before_cache: Dictionary = world.call("get_recent_chunk_cache_stats")
		var before_hits := int(before_cache.get("hit_count", 0))
		world.call("set_focus", far_world)
		_check(
			await _wait_for_chunks_unloaded(world, target_coords),
			"warm cycle %d unloads the complete connected region" % (cycle + 1),
		)
		var stored: Dictionary = world.call("get_recent_chunk_cache_stats")
		_check(
			int(stored.get("entry_count", 0)) >= target_coords.size(),
			"warm cycle %d stores every connected-region chunk" % (cycle + 1),
		)
		if cycle == 0:
			_check(
				world.call("set_block", patch_position, expected_patch),
				"an unloaded connected cell can change through the authoritative world API",
			)
		var reload_started := Time.get_ticks_usec()
		world.call("set_focus", center_world)
		_check(
			await _wait_for_chunks_loaded(world, target_coords),
			"warm cycle %d streams the complete connected region back" % (cycle + 1),
		)
		var reload_ms := float(Time.get_ticks_usec() - reload_started) / 1000.0
		cycle_milliseconds.append(reload_ms)
		_check(
			reload_ms <= MAX_WARM_RELOAD_MILLISECONDS,
			"warm cycle %d reaches a playable region inside thirty seconds" % (cycle + 1),
		)
		var after_cache: Dictionary = world.call("get_recent_chunk_cache_stats")
		var hit_delta := int(after_cache.get("hit_count", 0)) - before_hits
		cycle_hit_deltas.append(hit_delta)
		_check(
			hit_delta >= target_coords.size(),
			"warm cycle %d hydrates every target chunk from a recent snapshot" % (cycle + 1),
		)
		_check(
			_all_target_chunks_snapshot_hydrated(world, target_coords),
			"warm cycle %d skips procedural generation for all target chunks" % (cycle + 1),
		)
		_check(
			str(world.call("get_block", patch_position)) == expected_patch,
			"warm cycle %d preserves the unloaded cached edit" % (cycle + 1),
		)

	var cross_boundary_pane := Vector3i((center_chunk.x + 1) * 16 - 1, floor_y + 1, base_z + 1)
	var mask := _connection_mask(world, cross_boundary_pane, "glass_pane")
	_check(
		mask != 0,
		"cross-chunk glass panes re-derive a non-empty connection mask after repeated reloads",
	)
	_check(
		_target_chunks_have_mesh(world, target_coords),
		"revisited chunks publish visible connected geometry",
	)
	var cache_stats: Dictionary = world.call("get_recent_chunk_cache_stats")
	_check(
		int(cache_stats.get("entry_count", 0)) <= int(cache_stats.get("capacity", 0))
		and int(cache_stats.get("max_entries", 0)) <= int(cache_stats.get("capacity", 0)),
		"recent chunk cache never exceeds its sixty-four snapshot memory budget",
	)
	_check(
		int(cache_stats.get("patch_count", 0)) >= 1,
		"cache diagnostics retain the unloaded edit patch",
	)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.call("save_current"))
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	_check(saved, "revisited connected region joins the production atomic save transaction")
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "connected revisit save remains below two and a half megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "connected revisit save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "connected revisit world reloads from the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "connected revisit JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("recent_chunk_cache")
		and not serialized.contains("cached_coord_samples")
		and not serialized.contains("snapshot_hydrated"),
		"recent chunk snapshots and diagnostics never enter world persistence",
	)

	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"fixture_mutations": mutations.size(),
		"changed_mutations": int(setup_result.get("changed", 0)),
		"target_chunk_count": target_coords.size(),
		"warm_cycles": WARM_CYCLES,
		"warm_reload_milliseconds": cycle_milliseconds,
		"warm_hit_deltas": cycle_hit_deltas,
		"cache": cache_stats,
		"generation_cells_skipped": int(cache_stats.get("hit_count", 0)) * 16 * 64 * 16,
		"save_bytes": save_bytes,
		"save_milliseconds": save_milliseconds,
		"load_milliseconds": load_milliseconds,
		"cross_boundary_connection_mask": mask,
	}
	await _capture_visual_evidence(game, player, center_world, floor_y)

	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	game.call("begin_world_state", loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full persisted world reload reaches a playable state",
	)
	world = game.get("world") as Node
	_check(
		str(world.call("get_block", patch_position)) == expected_patch,
		"full world reload preserves the connected-region edit exactly once",
	)
	for raw_position: Variant in _sample_blocks.keys():
		var position: Vector3i = raw_position
		_check(
			str(world.call("get_block", position)) == str(_sample_blocks[position]),
			"full reload restores sample %s exactly once" % str(position),
		)
	var fresh_cache: Dictionary = world.call("get_recent_chunk_cache_stats")
	_check(
		int(fresh_cache.get("hit_count", -1)) == 0
		and int(fresh_cache.get("entry_count", -1)) == 0,
		"new world session starts without stale in-memory chunk snapshots",
	)
	_write_report()
	await _finish(game, hub)


func _build_connected_fixture(base_x: int, base_z: int, floor_y: int) -> Array:
	var mutations: Array = []
	for x_offset in GRID_SIZE:
		for z_offset in GRID_SIZE:
			var position := Vector3i(base_x + x_offset, floor_y, base_z + z_offset)
			mutations.append({"position": position, "block_id": "stone_bricks"})
			var shape_position := position + Vector3i.UP
			match (x_offset + z_offset) % 5:
				0:
					mutations.append({"position": shape_position, "block_id": "glass_pane"})
				1:
					mutations.append({"position": shape_position, "block_id": "oak_fence"})
				2:
					mutations.append({"position": shape_position, "block_id": "oak_door"})
					mutations.append({"position": shape_position + Vector3i.UP, "block_id": "oak_door_upper"})
				3:
					mutations.append({"position": shape_position, "block_id": "glass_pane_ns"})
				_:
					mutations.append({"position": shape_position, "block_id": "oak_fence"})
	for x_offset in GRID_SIZE:
		mutations.append({
			"position": Vector3i(base_x + x_offset, floor_y + 1, base_z + 1),
			"block_id": "glass_pane",
		})
		mutations.append({
			"position": Vector3i(base_x + x_offset, floor_y + 1, base_z + GRID_SIZE - 2),
			"block_id": "oak_fence",
		})
	var ladder_origins := [
		Vector3i(base_x - 2, floor_y + 1, base_z + 4),
		Vector3i(base_x + GRID_SIZE + 1, floor_y + 1, base_z + 8),
		Vector3i(base_x + 8, floor_y + 1, base_z - 2),
		Vector3i(base_x + 12, floor_y + 1, base_z + GRID_SIZE + 1),
	]
	var ladder_ids := ["ladder", "ladder_west", "ladder_east", "ladder_north"]
	var supports := [Vector3i.BACK, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD]
	for column_index in ladder_origins.size():
		for y_offset in LADDER_HEIGHT:
			var ladder_position: Vector3i = ladder_origins[column_index] + Vector3i.UP * y_offset
			mutations.append({
				"position": ladder_position + supports[column_index],
				"block_id": "stone_bricks",
			})
			mutations.append({
				"position": ladder_position,
				"block_id": ladder_ids[column_index],
			})
	_sample_blocks[Vector3i(base_x, floor_y + 1, base_z + 1)] = "glass_pane"
	_sample_blocks[Vector3i(base_x + GRID_SIZE - 1, floor_y + 1, base_z + 1)] = "glass_pane"
	_sample_blocks[Vector3i(base_x, floor_y + 1, base_z + GRID_SIZE - 2)] = "oak_fence"
	_sample_blocks[ladder_origins[0]] = "ladder"
	return mutations


func _unique_chunk_coords(world: Node, mutations: Array) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position: Vector3i = (raw_change as Dictionary).get("position", Vector3i.ZERO)
		unique[Vector2i(world.call("block_to_chunk", position))] = true
	var result: Array[Vector2i] = []
	for raw_coord: Variant in unique.keys():
		result.append(Vector2i(raw_coord))
	result.sort_custom(
		func(first: Vector2i, second: Vector2i) -> bool:
			return first.x < second.x or (first.x == second.x and first.y < second.y)
	)
	return result


func _force_load_chunks(world: Node, coords: Array[Vector2i]) -> void:
	for coord: Vector2i in coords:
		world.call("force_load_chunk", coord)


func _wait_for_chunks_unloaded(world: Node, coords: Array[Vector2i]) -> bool:
	for _frame in UNLOAD_FRAMES:
		await process_frame
		var all_unloaded := true
		for coord: Vector2i in coords:
			if world.chunks.has(coord) or world.get("_building_chunks").has(coord):
				all_unloaded = false
				break
		if all_unloaded:
			return true
	return false


func _wait_for_chunks_loaded(world: Node, coords: Array[Vector2i]) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		var all_loaded := true
		for coord: Vector2i in coords:
			if not world.chunks.has(coord):
				all_loaded = false
				break
		if all_loaded:
			return true
	return false


func _all_target_chunks_snapshot_hydrated(world: Node, coords: Array[Vector2i]) -> bool:
	for coord: Vector2i in coords:
		var chunk: Variant = world.chunks.get(coord)
		if (
			not is_instance_valid(chunk)
			or not chunk.has_method("was_hydrated_from_snapshot")
			or not bool(chunk.call("was_hydrated_from_snapshot"))
		):
			return false
	return true


func _target_chunks_have_mesh(world: Node, coords: Array[Vector2i]) -> bool:
	for coord: Vector2i in coords:
		var chunk: Variant = world.chunks.get(coord)
		if not is_instance_valid(chunk) or int(chunk.get("surface_face_count")) <= 0:
			return false
	return true


func _connection_mask(world: Node, position: Vector3i, block_id: String) -> int:
	var neighbors := ConnectionPolicy.empty_neighbors()
	for spec: Dictionary in ConnectionPolicy.DIRECTION_SPECS:
		var direction_name := str(spec.get("name", ""))
		var offset: Vector3i = spec.get("offset", Vector3i.ZERO)
		neighbors[direction_name] = str(world.call("get_block", position + offset))
	return ConnectionPolicy.resolve_mask(block_id, neighbors)


func _capture_visual_evidence(
	game: Node3D,
	player: CharacterBody3D,
	center_world: Vector3,
	floor_y: int
) -> void:
	player.set_physics_process(false)
	player.global_position = center_world + Vector3(0.0, 16.0, -28.0)
	player.velocity = Vector3.ZERO
	player.get_view_camera().look_at(
		Vector3(center_world.x, floor_y + 1.5, center_world.z),
		Vector3.UP
	)
	_add_metric_overlay(game)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the revisited connected region")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "chunk-cache visual evidence uses 1024x576 resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "chunk-cache screenshot is saved")
	player.set_physics_process(true)


func _add_metric_overlay(game: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "RecentChunkCacheEvidence"
	layer.layer = 95
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(470, 220)
	var label := Label.new()
	var cache: Dictionary = _report.get("cache", {})
	label.text = (
		"RECENT CHUNK CACHE ACCEPTANCE\n"
		+ "Connected fixture  %d mutations / %d chunks\n"
		+ "Warm cycles  %d  |  Hits %d  |  Stores %d\n"
		+ "Generation cells skipped  %d\n"
		+ "Patches %d  |  Evictions %d  |  Peak entries %d/%d\n"
		+ "Warm reloads  %s ms\n"
		+ "Save  %.1f KiB / %.1f ms  |  Load %.1f ms"
	) % [
		int(_report.get("fixture_mutations", 0)),
		int(_report.get("target_chunk_count", 0)),
		int(_report.get("warm_cycles", 0)),
		int(cache.get("hit_count", 0)),
		int(cache.get("store_count", 0)),
		int(_report.get("generation_cells_skipped", 0)),
		int(cache.get("patch_count", 0)),
		int(cache.get("eviction_count", 0)),
		int(cache.get("max_entries", 0)),
		int(cache.get("capacity", 0)),
		str(_report.get("warm_reload_milliseconds", [])),
		float(_report.get("save_bytes", 0)) / 1024.0,
		float(_report.get("save_milliseconds", 0.0)),
		float(_report.get("load_milliseconds", 0.0)),
	]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	layer.add_child(panel)
	game.add_child(layer)


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _write_report() -> void:
	_report["capture_path"] = _capture_path
	_report["report_path"] = _report_path
	_report["checks"] = checks
	_report["failure_count"] = failures.size()
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "chunk-cache JSON report can be opened")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t", false))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "chunk-cache JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in 10:
		await process_frame
	if failures.is_empty():
		print(
			"QA RECENT CHUNK CACHE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RECENT CHUNK CACHE DESKTOP FAILURE: %s" % failure)
		print(
			"QA RECENT CHUNK CACHE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
