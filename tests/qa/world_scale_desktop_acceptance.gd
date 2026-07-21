extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://world-scale-desktop.png"
const GRID_WIDTH := 32
const GRID_DEPTH := 24
const LADDER_COLUMN_HEIGHT := 8
const READY_FRAMES := 600
const CLEANUP_FRAMES := 10
const MAX_BATCH_MILLISECONDS := 30000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_BYTES := 2000000

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
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes its service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"World-Scale-%d" % Time.get_ticks_msec(),
		"star_continent",
		78234019
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "scale acceptance creates a temporary production world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded ready state",
	)
	var world: Node = game.world
	var player: CharacterBody3D = game.player
	_check(world != null and bool(world.get("is_started")), "production voxel world is ready")
	_check(
		world != null
		and world.has_method("apply_block_mutations")
		and world.has_method("get_chunk_rebuild_stats"),
		"production game composes the bounded mutation world",
	)
	if world == null or player == null or not world.has_method("apply_block_mutations"):
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(player_block.y - 1, 12, 58)
	var base_x := player_block.x + 8
	var base_z := player_block.z - 12
	var mutations := _build_scale_mutations(base_x, base_z, floor_y)
	_check(mutations.size() >= 3000, "scale fixture contains more than three thousand bounded mutations")
	_force_load_mutation_chunks(world, mutations)
	world.call("reset_chunk_rebuild_stats")

	var batch_started := Time.get_ticks_usec()
	var batch_result: Dictionary = world.call(
		"apply_block_mutations",
		mutations,
		"desktop_mixed_shapes_%d" % mutations.size()
	)
	var batch_milliseconds := float(Time.get_ticks_usec() - batch_started) / 1000.0
	var rebuild: Dictionary = batch_result.get("rebuild", {})
	var changed := int(batch_result.get("changed", 0))
	var rebuild_requests := int(rebuild.get("request_count", 0))
	var rebuild_executions := int(rebuild.get("execution_count", 0))
	var rebuild_coalesced := int(rebuild.get("coalesced_count", 0))
	var max_dirty_chunks := int(rebuild.get("max_dirty_chunks", 0))
	_check(bool(batch_result.get("success", false)), "bounded production mutation batch completes")
	_check(changed >= 1500, "scale fixture changes at least fifteen hundred real world cells")
	_check(
		rebuild_executions > 0 and rebuild_executions <= maxi(1, max_dirty_chunks),
		"actual rebuilds never exceed unique dirty chunks",
	)
	_check(
		rebuild_coalesced >= maxi(0, rebuild_requests - max_dirty_chunks),
		"duplicate rebuild requests are retained as coalesced diagnostics",
	)
	_check(
		batch_milliseconds <= MAX_BATCH_MILLISECONDS,
		"mixed shape batch remains inside the thirty-second desktop budget",
	)
	_check(
		int(rebuild.get("pending_chunks", -1)) == 0
		and int(rebuild.get("batch_depth", -1)) == 0,
		"batch completion leaves no hidden rebuild work",
	)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.save_current())
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	_check(saved, "large mixed-shape world joins the production atomic save transaction")
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "large world save remains below two megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "large world save remains inside ten seconds")

	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "large world reloads from the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "large world JSON load remains inside ten seconds")
	var loaded_overrides: Dictionary = loaded.get("world", {}).get("block_overrides", {})
	_check(loaded_overrides.size() >= 1500, "save retains the expected sparse mutation scale")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("rebuild_requests")
		and not serialized.contains("dirty_rebuild_chunks")
		and not serialized.contains("mutation_batch"),
		"rebuild batching diagnostics remain transient",
	)

	var streaming: Dictionary = world.call("get_streaming_stats")
	_check(
		streaming.get("rebuild", {}) is Dictionary
		and int(streaming.get("rebuild_executions", -1)) == rebuild_executions,
		"existing runtime telemetry exposes scale rebuild evidence",
	)
	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"requested_mutations": mutations.size(),
		"changed_mutations": changed,
		"rebuild_requests": rebuild_requests,
		"rebuild_executions": rebuild_executions,
		"rebuild_coalesced": rebuild_coalesced,
		"max_dirty_chunks": max_dirty_chunks,
		"batch_milliseconds": batch_milliseconds,
		"save_bytes": save_bytes,
		"save_milliseconds": save_milliseconds,
		"load_milliseconds": load_milliseconds,
		"override_count": loaded_overrides.size(),
		"loaded_chunks": int(streaming.get("loaded", 0)),
	}

	await _capture_visual_evidence(game, player, base_x, base_z, floor_y)
	var reload_started := Time.get_ticks_usec()
	hub.return_to_menu()
	for _frame in 10:
		await process_frame
	game.begin_world_state(loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full scale-world reload reaches a bounded playable state",
	)
	var reload_milliseconds := float(Time.get_ticks_usec() - reload_started) / 1000.0
	_report["reload_ready_milliseconds"] = reload_milliseconds
	_check(reload_milliseconds <= MAX_RELOAD_MILLISECONDS, "first playable reload remains inside thirty seconds")
	world = game.world
	player = game.player
	for raw_key: Variant in _sample_blocks.keys():
		var position: Vector3i = raw_key
		_check(
			str(world.call("get_block", position)) == str(_sample_blocks[position]),
			"full reload restores sample %s exactly once" % str(position),
		)
	var reloaded_rebuild: Dictionary = world.call("get_chunk_rebuild_stats")
	_check(
		int(reloaded_rebuild.get("request_count", -1)) == 0
		and int(reloaded_rebuild.get("pending_chunks", -1)) == 0,
		"new world session starts with clean transient rebuild diagnostics",
	)
	_write_report()
	await _finish(game, hub)


func _build_scale_mutations(base_x: int, base_z: int, floor_y: int) -> Array:
	var mutations: Array = []
	for x_offset in GRID_WIDTH:
		for z_offset in GRID_DEPTH:
			var x := base_x + x_offset
			var z := base_z + z_offset
			mutations.append({"position": Vector3i(x, floor_y, z), "block_id": "stone_bricks"})
			mutations.append({"position": Vector3i(x, floor_y + 1, z), "block_id": "air"})
			mutations.append({"position": Vector3i(x, floor_y + 2, z), "block_id": "air"})
	for x_offset in GRID_WIDTH:
		for z_offset in GRID_DEPTH:
			var position := Vector3i(base_x + x_offset, floor_y + 1, base_z + z_offset)
			match (x_offset + z_offset) % 4:
				0:
					mutations.append({"position": position, "block_id": "glass_pane"})
				1:
					mutations.append({"position": position, "block_id": "oak_fence"})
				2:
					var east := (x_offset + z_offset) % 8 >= 4
					mutations.append({
						"position": position,
						"block_id": "oak_door_east" if east else "oak_door",
					})
					mutations.append({
						"position": position + Vector3i.UP,
						"block_id": "oak_door_upper_east" if east else "oak_door_upper",
					})
				_:
					mutations.append({"position": position, "block_id": "glass_pane_ns"})

	var ladder_origins := [
		Vector3i(base_x - 3, floor_y + 1, base_z),
		Vector3i(base_x + GRID_WIDTH + 2, floor_y + 1, base_z),
		Vector3i(base_x, floor_y + 1, base_z - 3),
		Vector3i(base_x, floor_y + 1, base_z + GRID_DEPTH + 2),
	]
	var ladder_ids := ["ladder", "ladder_west", "ladder_east", "ladder_north"]
	var support_offsets := [Vector3i.BACK, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD]
	for column_index in ladder_origins.size():
		var origin: Vector3i = ladder_origins[column_index]
		var ladder_id: String = ladder_ids[column_index]
		var support_offset: Vector3i = support_offsets[column_index]
		for y_offset in LADDER_COLUMN_HEIGHT:
			var ladder_position := origin + Vector3i.UP * y_offset
			mutations.append({
				"position": ladder_position + support_offset,
				"block_id": "stone_bricks",
			})
			mutations.append({"position": ladder_position, "block_id": ladder_id})

	_sample_blocks[Vector3i(base_x, floor_y + 1, base_z)] = "glass_pane"
	_sample_blocks[Vector3i(base_x + 1, floor_y + 1, base_z)] = "oak_fence"
	_sample_blocks[Vector3i(base_x + 2, floor_y + 1, base_z)] = "oak_door"
	_sample_blocks[Vector3i(base_x + 2, floor_y + 2, base_z)] = "oak_door_upper"
	_sample_blocks[ladder_origins[0]] = "ladder"
	return mutations


func _force_load_mutation_chunks(world: Node, mutations: Array) -> void:
	var coords: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position := _vector3i_from((raw_change as Dictionary).get("position", []))
		var coord: Vector2i = world.call("block_to_chunk", position)
		coords[coord] = true
	for raw_coord: Variant in coords.keys():
		world.call("force_load_chunk", Vector2i(raw_coord))


func _capture_visual_evidence(
	game: Node3D,
	player: CharacterBody3D,
	base_x: int,
	base_z: int,
	floor_y: int
) -> void:
	player.set_physics_process(false)
	player.global_position = Vector3(
		base_x + GRID_WIDTH * 0.5,
		floor_y + 14.0,
		base_z - 16.0
	)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.get_view_camera().look_at(
		Vector3(base_x + GRID_WIDTH * 0.5, floor_y + 1.5, base_z + GRID_DEPTH * 0.5),
		Vector3.UP
	)
	_add_metric_overlay(game)
	for _frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the mixed-shape scale fixture")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "visual evidence uses 1024x576 product resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "world-scale screenshot is saved")
	player.set_physics_process(true)


func _add_metric_overlay(game: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "WorldScaleEvidence"
	layer.layer = 95
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(430, 190)
	var label := Label.new()
	label.text = (
		"WORLD SCALE ACCEPTANCE\n"
		+ "Mutations  %d requested / %d changed\n"
		+ "Chunk rebuilds  %d requests → %d executions\n"
		+ "Coalesced  %d  |  Dirty chunks %d\n"
		+ "Batch  %.1f ms\n"
		+ "Save  %.1f KiB / %.1f ms\n"
		+ "Load  %.1f ms"
	) % [
		int(_report.get("requested_mutations", 0)),
		int(_report.get("changed_mutations", 0)),
		int(_report.get("rebuild_requests", 0)),
		int(_report.get("rebuild_executions", 0)),
		int(_report.get("rebuild_coalesced", 0)),
		int(_report.get("max_dirty_chunks", 0)),
		float(_report.get("batch_milliseconds", 0.0)),
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
	_check(file != null, "world-scale JSON report can be opened")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t", false))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "world-scale JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA WORLD SCALE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD SCALE DESKTOP FAILURE: %s" % failure)
		print(
			"QA WORLD SCALE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
