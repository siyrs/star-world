extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const PickupScript = preload("res://src/entity/item_pickup.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://pickup-shared-runtime-desktop.png"
const PICKUP_COUNT := 128
const PICKUP_ITEM_COUNT := 2
const GRID_COLUMNS := 16
const GRID_SPACING := 2.2
const READY_FRAMES := 720
const CLEANUP_FRAMES := 12
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_BYTES := 3000000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}


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
	_check(hub != null, "production shared pickup runtime exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Pickup-Shared-Runtime-%d" % Time.get_ticks_msec(),
		"star_continent",
		78342017
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "shared pickup runtime acceptance creates a temporary world")
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"shared pickup runtime world reaches a bounded playable state",
	)
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var spawner: Node3D = hub.get("creature_spawner") as Node3D
	var coordinator: Node = hub.get("pickup_stack_coordinator") as Node
	var simulation_pause: Node = hub.get("simulation_pause") as Node
	_check(
		world != null
		and player != null
		and spawner != null
		and coordinator != null
		and simulation_pause != null,
		"production world mounts pickup coordinator, spawner, pause, and player services",
	)
	if world == null or player == null or spawner == null or coordinator == null:
		await _finish(game, hub)
		return
	spawner.call("set_active", false)
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(player_block.y + 12, 20, 55)
	var base_x := floori(float(player_block.x) / 16.0) * 16 - 8
	var base_z := floori(float(player_block.z) / 16.0) * 16 - 8
	var mutations := _build_arena(base_x, base_z, floor_y)
	_force_load_mutation_chunks(world, mutations)
	var setup_result: Dictionary = world.call(
		"apply_block_mutations", mutations, "pickup_shared_runtime_arena"
	)
	_check(
		bool(setup_result.get("success", false))
		and int(setup_result.get("changed", 0)) >= 700,
		"pickup runtime arena commits its full stone floor through the production batch API",
	)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var center := Vector3(float(base_x) + 19.0, float(floor_y) + 1.0, float(base_z) + 10.0)
	player.global_position = center + Vector3(0.0, 25.0, -28.0)
	var camera: Camera3D = player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(center, Vector3.UP)
	var pickups: Array[Node3D] = []
	for index in PICKUP_COUNT:
		var column := index % GRID_COLUMNS
		var row := int(index / GRID_COLUMNS)
		var pickup = PickupScript.new()
		pickup.setup("rotten_flesh", PICKUP_ITEM_COUNT, hub.inventory)
		spawner.add_child(pickup)
		pickup.global_position = Vector3(
			float(base_x) + 2.0 + float(column) * GRID_SPACING,
			float(floor_y) + 1.0,
			float(base_z) + 2.0 + float(row) * GRID_SPACING
		)
		pickups.append(pickup as Node3D)
		if index % 16 == 15:
			await process_frame
	for _frame in 8:
		await process_frame
	var runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(runtime.get("pickup_node_count", 0)) == PICKUP_COUNT
		and int(runtime.get("tracked_runtime_pickup_count", 0)) == PICKUP_COUNT,
		"production shared runtime tracks one hundred twenty-eight physical pickups",
	)
	_check(
		int(runtime.get("visible_item_total", 0)) == PICKUP_COUNT * PICKUP_ITEM_COUNT
		and int(runtime.get("pending_item_total", -1)) == 0,
		"shared pickup runtime preserves all two hundred fifty-six visible items",
	)
	_check(
		int(runtime.get("individual_process_count", -1)) == 0
		and bool(runtime.get("runtime_processing", false))
		and int(runtime.get("runtime_process_mode", -1)) == Node.PROCESS_MODE_PAUSABLE,
		"one pausable coordinator replaces all individual pickup process callbacks",
	)
	_check(
		int(runtime.get("max_runtime_nodes_observed", 0)) <= PICKUP_COUNT
		and int(runtime.get("runtime_node_budget", 0)) == PICKUP_COUNT,
		"pickup runtime remains inside its one-hundred-twenty-eight-node hard budget",
	)
	var first: Node3D = pickups[0]
	var middle: Node3D = pickups[int(PICKUP_COUNT / 2)]
	var last: Node3D = pickups[PICKUP_COUNT - 1]
	var samples: Array[Dictionary] = [
		{"node": first, "anchor": first.global_position},
		{"node": middle, "anchor": middle.global_position},
		{"node": last, "anchor": last.global_position},
	]
	var first_visual: Node3D = first.call("get_visual_root") as Node3D
	var visual_before := first_visual.position.y if first_visual != null else 0.0
	for _frame in 12:
		await process_frame
	var max_anchor_drift := 0.0
	for sample: Dictionary in samples:
		var pickup_node := sample.get("node") as Node3D
		var original_anchor: Vector3 = sample.get("anchor", Vector3.ZERO)
		if pickup_node == null or not is_instance_valid(pickup_node):
			continue
		max_anchor_drift = maxf(
			max_anchor_drift,
			pickup_node.global_position.distance_to(original_anchor)
		)
	var visual_after := first_visual.position.y if first_visual != null else 0.0
	_check(
		max_anchor_drift <= 0.0001,
		"real pickup bobbing keeps all sampled collision anchors stationary",
	)
	_check(
		first_visual != null
		and absf(visual_after) <= PickupScript.BOB_AMPLITUDE + 0.001
		and not is_equal_approx(visual_after, visual_before),
		"real shared runtime animates only the pickup visual root",
	)
	var first_resources: Dictionary = first.call("get_visual_resource_ids")
	var last_resources: Dictionary = last.call("get_visual_resource_ids")
	var visual_resources: Dictionary = runtime.get("visual_resources", {})
	_check(
		first_resources == last_resources
		and int(visual_resources.get("mesh_create_count", 0)) == 1
		and int(visual_resources.get("shape_create_count", 0)) == 1
		and int(visual_resources.get("material_create_count", 0)) == 1,
		"one hundred twenty-eight same-color pickups share one mesh, shape, and material",
	)
	var pause_steps_before := int((coordinator.call("get_snapshot") as Dictionary).get("runtime_step_count", 0))
	var life_before_pause := float(first.get("life_seconds"))
	simulation_pause.call("set_paused", true)
	for _frame in 12:
		await process_frame
	var paused_runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(paused_runtime.get("runtime_step_count", -1)) == pause_steps_before
		and is_equal_approx(float(first.get("life_seconds")), life_before_pause),
		"production simulation pause freezes pickup visuals and lifetime",
	)
	simulation_pause.call("set_paused", false)
	for _frame in 12:
		await process_frame
	var resumed_runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(resumed_runtime.get("runtime_step_count", 0)) > pause_steps_before
		and float(first.get("life_seconds")) < life_before_pause,
		"production pickup runtime resumes cleanly after pause",
	)
	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"pickup_nodes": int(resumed_runtime.get("pickup_node_count", 0)),
		"visible_items": int(resumed_runtime.get("visible_item_total", 0)),
		"individual_process_count": int(resumed_runtime.get("individual_process_count", -1)),
		"runtime_step_count": int(resumed_runtime.get("runtime_step_count", 0)),
		"runtime_advance_count": int(resumed_runtime.get("runtime_advance_count", 0)),
		"max_runtime_nodes_observed": int(resumed_runtime.get("max_runtime_nodes_observed", 0)),
		"max_anchor_drift": max_anchor_drift,
		"visual_resources": resumed_runtime.get("visual_resources", {}).duplicate(true),
		"world_mutations": mutations.size(),
		"world_changed": int(setup_result.get("changed", 0)),
	}
	_add_metric_overlay(game, resumed_runtime, max_anchor_drift)
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "pickup runtime viewport renders the full physical field")
	if image != null and not image.is_empty():
		_check(
			image.get_size() == root.size,
			"pickup shared runtime visual evidence uses 1024x576 resolution",
		)
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var image_error := image.save_png(_capture_path)
		_check(
			image_error == OK and FileAccess.file_exists(_capture_path),
			"pickup shared runtime screenshot is saved",
		)
	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.call("save_current"))
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(saved, "pickup runtime world joins the production atomic save transaction")
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "pickup runtime save remains below three megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "pickup runtime save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "pickup runtime world reloads through the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "pickup runtime JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("pickup_runtime")
		and not serialized.contains("runtime_advance_count")
		and not serialized.contains("visual_resources")
		and not serialized.contains("pending_pickups"),
		"shared pickup visuals, lifetime, cache, and pending state never enter persistence",
	)
	_report["save_bytes"] = save_bytes
	_report["save_milliseconds"] = save_milliseconds
	_report["load_milliseconds"] = load_milliseconds
	var reload_started := Time.get_ticks_usec()
	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	var menu_runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		not bool(menu_runtime.get("active", true))
		and int(menu_runtime.get("tracked_runtime_pickup_count", -1)) == 0
		and spawner.get_child_count() == 0,
		"returning to menu clears pickup nodes and shared runtime references",
	)
	game.call("begin_world_state", loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full pickup-runtime reload reaches a bounded playable state",
	)
	var reload_milliseconds := float(Time.get_ticks_usec() - reload_started) / 1000.0
	_check(reload_milliseconds <= MAX_RELOAD_MILLISECONDS, "pickup runtime first-playable reload remains inside thirty seconds")
	coordinator = hub.get("pickup_stack_coordinator") as Node
	var fresh_runtime: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(fresh_runtime.get("pickup_node_count", -1)) == 0
		and int(fresh_runtime.get("tracked_runtime_pickup_count", -1)) == 0
		and int(fresh_runtime.get("runtime_step_count", -1)) == 0
		and int(fresh_runtime.get("expired_pickup_count", -1)) == 0,
		"new world session does not restore transient pickups or shared runtime counters",
	)
	_report["reload_ready_milliseconds"] = reload_milliseconds
	_write_report()
	await _finish(game, hub)


func _build_arena(base_x: int, base_z: int, floor_y: int) -> Array:
	var mutations: Array = []
	for x_offset in 38:
		for z_offset in 20:
			var floor_position := Vector3i(base_x + x_offset, floor_y, base_z + z_offset)
			mutations.append({"position": floor_position, "block_id": "stone_bricks"})
			mutations.append({"position": floor_position + Vector3i.UP, "block_id": "air"})
			mutations.append({"position": floor_position + Vector3i.UP * 2, "block_id": "air"})
	return mutations


func _force_load_mutation_chunks(world: Node, mutations: Array) -> void:
	var coords: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position := _vector3i_from((raw_change as Dictionary).get("position", []))
		coords[world.call("block_to_chunk", position)] = true
	for raw_coord: Variant in coords.keys():
		world.call("force_load_chunk", Vector2i(raw_coord))


func _add_metric_overlay(game: Node, runtime: Dictionary, anchor_drift: float) -> void:
	var layer := CanvasLayer.new()
	layer.name = "PickupSharedRuntimeEvidence"
	layer.layer = 96
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(485, 236)
	var label := Label.new()
	var resources: Dictionary = runtime.get("visual_resources", {})
	label.text = (
		"SHARED PICKUP RUNTIME ACCEPTANCE\n"
		+ "Physical nodes  %d / %d\n"
		+ "Visible items  %d\n"
		+ "Individual process callbacks  %d\n"
		+ "Shared steps  %d  |  advances %d\n"
		+ "Anchor drift  %.6f m\n"
		+ "Shared resources  mesh %d / shape %d / material %d\n"
		+ "Pause freeze + resume  PASS"
	) % [
		int(runtime.get("pickup_node_count", 0)),
		int(runtime.get("runtime_node_budget", 0)),
		int(runtime.get("visible_item_total", 0)),
		int(runtime.get("individual_process_count", -1)),
		int(runtime.get("runtime_step_count", 0)),
		int(runtime.get("runtime_advance_count", 0)),
		anchor_drift,
		int(resources.get("mesh_create_count", 0)),
		int(resources.get("shape_create_count", 0)),
		int(resources.get("material_create_count", 0)),
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


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "pickup runtime benchmark report opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "  "))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "pickup runtime benchmark report is saved")


func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return int(length)


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _finish(game: Node, hub: Node) -> void:
	paused = false
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
			"QA PICKUP SHARED RUNTIME DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PICKUP SHARED RUNTIME DESKTOP FAILURE: %s" % failure)
		print(
			"QA PICKUP SHARED RUNTIME DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
