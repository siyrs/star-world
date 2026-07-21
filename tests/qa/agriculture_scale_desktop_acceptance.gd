extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://agriculture-scale-desktop.png"
const FIELD_WIDTH := 64
const FIELD_DEPTH := 32
const FIELD_CROP_COUNT := FIELD_WIDTH * FIELD_DEPTH
const READY_FRAMES := 600
const CLEANUP_FRAMES := 10
const MAX_SETUP_MILLISECONDS := 30000.0
const MAX_ATTACH_MILLISECONDS := 30000.0
const MAX_GROWTH_MILLISECONDS := 30000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_BYTES := 4000000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}
var _sample_positions: Dictionary = {}


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
		"Agriculture-Scale-%d" % Time.get_ticks_msec(),
		"star_continent",
		83276145
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "agriculture scale acceptance creates a temporary world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded ready state",
	)
	var world: Node = game.world
	var player: CharacterBody3D = game.player
	var service: Node = hub.get("agriculture_service") as Node
	var participant: Node = hub.get("agriculture_runtime_participant") as Node
	_check(
		world != null
		and world.has_method("apply_block_mutations")
		and world.has_method("get_chunk_rebuild_stats"),
		"production game uses the bounded mutation world",
	)
	_check(
		service != null
		and service.has_method("get_world_mutation_batch_snapshot")
		and service.get("soil_moisture") != null,
		"production agriculture exposes scale batching and cached hydration",
	)
	_check(participant != null, "production hub exposes the agriculture participant")
	if world == null or player == null or service == null or participant == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(player_block.y - 1, 12, 58)
	var base_x := (floori(float(player_block.x) / 16.0) + 1) * 16
	var base_z := (floori(float(player_block.z) / 16.0) - 1) * 16
	var fixture: Dictionary = _build_field_fixture(base_x, base_z, floor_y)
	var mutations: Array = fixture.get("mutations", [])
	var agriculture_state: Dictionary = fixture.get("agriculture", {})
	_check(
		mutations.size() == FIELD_CROP_COUNT * 2,
		"production field contains two thousand forty-eight crops",
	)
	_force_load_mutation_chunks(world, mutations)
	world.call("reset_chunk_rebuild_stats")
	var setup_started := Time.get_ticks_usec()
	var setup_result: Dictionary = world.call(
		"apply_block_mutations",
		mutations,
		"agriculture_scale_fixture"
	)
	var setup_milliseconds := float(Time.get_ticks_usec() - setup_started) / 1000.0
	_check(bool(setup_result.get("success", false)), "production field blocks commit through the shared batch API")
	_check(
		int(setup_result.get("changed", 0)) >= FIELD_CROP_COUNT * 2 - 8,
		"large field changes the expected production cells",
	)
	_check(setup_milliseconds <= MAX_SETUP_MILLISECONDS, "large field setup remains inside thirty seconds")

	service.call("deactivate")
	service.call("detach_world")
	_check(service.call("deserialize", agriculture_state), "production agriculture accepts the large saved-state shape")
	world.call("reset_chunk_rebuild_stats")
	var attach_started := Time.get_ticks_usec()
	service.call("attach_world", world, hub.inventory)
	var attach_milliseconds := float(Time.get_ticks_usec() - attach_started) / 1000.0
	service.call("activate")
	var attached_runtime: Dictionary = service.call("get_runtime_snapshot")
	var cache: Dictionary = attached_runtime.get("soil_refresh_cache", {})
	var cache_last: Dictionary = cache.get("last_refresh", {})
	_check(
		int(cache.get("refresh_batch_count", 0)) == 1,
		"production attach performs one authoritative large-field hydration refresh",
	)
	_check(
		int(cache_last.get("cache_hits", 0)) > int(cache_last.get("sample_reads", 0))
		and int(cache_last.get("cache_cells", 0)) <= 65536,
		"large-field hydration reuses overlapping samples inside its hard cache budget",
	)
	_check(attach_milliseconds <= MAX_ATTACH_MILLISECONDS, "large field attach remains inside thirty seconds")

	var before_lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	world.call("reset_chunk_rebuild_stats")
	var growth_started := Time.get_ticks_usec()
	service.call("advance_time", 200.0)
	var growth_milliseconds := float(Time.get_ticks_usec() - growth_started) / 1000.0
	for _frame in 4:
		await process_frame
	var summary: Dictionary = participant.call("flush_pending_maturity_batch")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	var mature_count := _count_mature_crops(service, base_x, base_z, floor_y)
	var rebuild: Dictionary = world.call("get_chunk_rebuild_stats")
	var rebuild_requests := int(rebuild.get("request_count", 0))
	var rebuild_executions := int(rebuild.get("execution_count", 0))
	var rebuild_coalesced := int(rebuild.get("coalesced_count", 0))
	var max_dirty_chunks := int(rebuild.get("max_dirty_chunks", 0))
	_check(mature_count == FIELD_CROP_COUNT, "all two thousand forty-eight production crops reach maturity")
	_check(
		int(summary.get("matured_count", 0)) == FIELD_CROP_COUNT
		and int(summary.get("dropped_event_count", -1)) == 0,
		"all mature crops are reported in one accurate player batch",
	)
	_check(
		int(lifecycle.get("maturity_batch_count", 0))
		== int(before_lifecycle.get("maturity_batch_count", 0)) + 1
		and int(lifecycle.get("maturity_audio_count", 0))
		== int(before_lifecycle.get("maturity_audio_count", 0)) + 1,
		"large maturity produces one player summary and one audio cue",
	)
	_check(
		int(summary.get("sampled_position_count", 0)) == 64
		and int(summary.get("dropped_position_samples", 0)) == FIELD_CROP_COUNT - 64,
		"maturity positions stay bounded without losing aggregate counts",
	)
	_check(
		rebuild_executions > 0 and rebuild_executions <= maxi(1, max_dirty_chunks),
		"large-field growth rebuilds each dirty chunk at most once",
	)
	_check(
		rebuild_requests >= FIELD_CROP_COUNT * 3
		and rebuild_coalesced >= rebuild_requests - maxi(1, max_dirty_chunks),
		"growth telemetry proves thousands of stage writes are coalesced",
	)
	_check(growth_milliseconds <= MAX_GROWTH_MILLISECONDS, "large field maturity remains inside thirty seconds")
	var growth_runtime: Dictionary = service.call("get_runtime_snapshot")
	var world_batch: Dictionary = growth_runtime.get("world_mutation_batch", {})
	_check(
		int(world_batch.get("flush_count", 0)) >= 1
		and int(world_batch.get("rejection_count", 0)) == 0,
		"production agriculture reports successful shared-world batching",
	)

	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"crop_count": FIELD_CROP_COUNT,
		"setup_milliseconds": setup_milliseconds,
		"attach_milliseconds": attach_milliseconds,
		"growth_milliseconds": growth_milliseconds,
		"rebuild_requests": rebuild_requests,
		"rebuild_executions": rebuild_executions,
		"rebuild_coalesced": rebuild_coalesced,
		"max_dirty_chunks": max_dirty_chunks,
		"hydration_sample_reads": int(cache_last.get("sample_reads", 0)),
		"hydration_cache_hits": int(cache_last.get("cache_hits", 0)),
		"hydration_cache_cells": int(cache_last.get("cache_cells", 0)),
		"maturity_summary": summary.duplicate(true),
	}
	await _capture_visual_evidence(game, player, base_x, base_z, floor_y)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.save_current())
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(saved, "large farm joins the production atomic save transaction")
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "large farm save remains below four megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "large farm save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "large farm reloads through the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "large farm JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("world_mutation_batch")
		and not serialized.contains("soil_refresh_cache")
		and not serialized.contains("maturity_position_samples"),
		"scale batching, caches and position samples remain transient",
	)
	_report["save_bytes"] = save_bytes
	_report["save_milliseconds"] = save_milliseconds
	_report["load_milliseconds"] = load_milliseconds

	var reload_started := Time.get_ticks_usec()
	hub.return_to_menu()
	for _frame in 10:
		await process_frame
	game.begin_world_state(loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full farm reload reaches a bounded playable state",
	)
	var reload_milliseconds := float(Time.get_ticks_usec() - reload_started) / 1000.0
	_check(reload_milliseconds <= MAX_RELOAD_MILLISECONDS, "large farm first playable remains inside thirty seconds")
	service = hub.get("agriculture_service") as Node
	participant = hub.get("agriculture_runtime_participant") as Node
	_check(service != null and int(service.call("get_crop_count")) == FIELD_CROP_COUNT, "full reload restores every crop once")
	_check(
		_count_mature_crops(service, base_x, base_z, floor_y) == FIELD_CROP_COUNT,
		"full reload preserves all mature crop stages",
	)
	var reloaded_lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(
		int(reloaded_lifecycle.get("maturity_batch_count", -1)) == 0
		and int(reloaded_lifecycle.get("matured_crop_total", -1)) == 0,
		"full reload does not replay historical maturity feedback",
	)
	_report["reload_ready_milliseconds"] = reload_milliseconds
	_write_report()
	await _finish(game, hub)


func _build_field_fixture(base_x: int, base_z: int, floor_y: int) -> Dictionary:
	var mutations: Array = []
	var crops: Dictionary = {}
	var soils: Dictionary = {}
	var crop_ids := ["wheat", "carrot", "potato"]
	var stage_blocks := ["wheat_stage_0", "carrot_stage_0", "potato_stage_0"]
	for x_offset in FIELD_WIDTH:
		for z_offset in FIELD_DEPTH:
			var index := x_offset * FIELD_DEPTH + z_offset
			var soil_position := Vector3i(base_x + x_offset, floor_y, base_z + z_offset)
			var crop_position := soil_position + Vector3i.UP
			var crop_index := index % crop_ids.size()
			var crop_id: String = crop_ids[crop_index]
			var stage_block: String = stage_blocks[crop_index]
			mutations.append({"position": soil_position, "block_id": "farmland_wet"})
			mutations.append({"position": crop_position, "block_id": stage_block})
			crops["crop@%d,%d,%d" % [crop_position.x, crop_position.y, crop_position.z]] = {
				"crop_id": crop_id,
				"position": [crop_position.x, crop_position.y, crop_position.z],
				"stage": 0,
				"elapsed_seconds": 0.0,
			}
			soils["soil@%d,%d,%d" % [soil_position.x, soil_position.y, soil_position.z]] = {
				"position": [soil_position.x, soil_position.y, soil_position.z],
				"manual_remaining_seconds": 600.0,
				"hydrated": true,
			}
	_sample_positions[Vector3i(base_x, floor_y + 1, base_z)] = "wheat"
	_sample_positions[Vector3i(base_x + 1, floor_y + 1, base_z)] = "potato"
	_sample_positions[Vector3i(base_x + FIELD_WIDTH - 1, floor_y + 1, base_z + FIELD_DEPTH - 1)] = "wheat"
	return {
		"mutations": mutations,
		"agriculture": {
			"version": 2,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"crops": crops,
			"soil_moisture": {"version": 1, "soils": soils},
		},
	}


func _count_mature_crops(service: Node, base_x: int, base_z: int, floor_y: int) -> int:
	if service == null:
		return 0
	var count := 0
	for x_offset in FIELD_WIDTH:
		for z_offset in FIELD_DEPTH:
			var position := Vector3i(base_x + x_offset, floor_y + 1, base_z + z_offset)
			if int(service.call("get_crop_state", position).get("stage", -1)) == 3:
				count += 1
	return count


func _force_load_mutation_chunks(world: Node, mutations: Array) -> void:
	var coords: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position: Vector3i = (raw_change as Dictionary).get("position", Vector3i.ZERO)
		coords[Vector2i(world.call("block_to_chunk", position))] = true
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
		base_x + FIELD_WIDTH * 0.5,
		floor_y + 24.0,
		base_z - 20.0
	)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.get_view_camera().look_at(
		Vector3(base_x + FIELD_WIDTH * 0.5, floor_y + 1.0, base_z + FIELD_DEPTH * 0.5),
		Vector3.UP
	)
	_add_metric_overlay(game)
	for _frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the large mature field")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "agriculture scale evidence uses 1024x576 product resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "agriculture scale screenshot is saved")
	player.set_physics_process(true)


func _add_metric_overlay(game: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "AgricultureScaleEvidence"
	layer.layer = 95
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(470, 210)
	var label := Label.new()
	label.text = (
		"AGRICULTURE SCALE ACCEPTANCE\n"
		+ "Crops  %d mature / %d persisted\n"
		+ "Chunk rebuilds  %d requests → %d executions\n"
		+ "Coalesced  %d  |  Dirty chunks %d\n"
		+ "Hydration  %d reads / %d cache hits\n"
		+ "Attach  %.1f ms  |  Growth %.1f ms\n"
		+ "Maturity  %d exact / %d position samples"
	) % [
		FIELD_CROP_COUNT,
		FIELD_CROP_COUNT,
		int(_report.get("rebuild_requests", 0)),
		int(_report.get("rebuild_executions", 0)),
		int(_report.get("rebuild_coalesced", 0)),
		int(_report.get("max_dirty_chunks", 0)),
		int(_report.get("hydration_sample_reads", 0)),
		int(_report.get("hydration_cache_hits", 0)),
		float(_report.get("attach_milliseconds", 0.0)),
		float(_report.get("growth_milliseconds", 0.0)),
		int(_report.get("maturity_summary", {}).get("matured_count", 0)),
		int(_report.get("maturity_summary", {}).get("sampled_position_count", 0)),
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
	_check(file != null, "agriculture scale JSON report can be opened")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t", false))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "agriculture scale JSON report is saved")


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
			"QA AGRICULTURE SCALE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AGRICULTURE SCALE DESKTOP FAILURE: %s" % failure)
		print(
			"QA AGRICULTURE SCALE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
