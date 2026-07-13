extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const SOAK_CYCLES := 3
const FRAMES_PER_CYCLE := 72
const SAMPLE_INTERVAL_FRAMES := 12

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var hub: Node = game.get("service_hub")
	var diagnostics: Node = game.get("runtime_diagnostics")
	var initial_render_distance := int(hub.get("current_settings").get("render_distance", 3))
	var menu_node_baseline := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for cycle in SOAK_CYCLES:
		await _run_world_cycle(game, hub, diagnostics, cycle, initial_render_distance)
		var menu_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_check(
			menu_nodes <= menu_node_baseline + 40,
			"world cycle %d returns to a bounded menu node count" % (cycle + 1),
		)
	var telemetry = diagnostics.get("telemetry")
	_check(
		telemetry != null and telemetry.call("get_history").size() <= 120,
		"long-running telemetry history remains bounded",
	)
	var audio = hub.get("audio_service")
	if audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("QA RUNTIME SOAK PASS | checks=%d | cycles=%d" % [checks, SOAK_CYCLES])
		quit(0)
	else:
		for failure in failures:
			push_error("QA RUNTIME SOAK FAILURE: %s" % failure)
		print("QA RUNTIME SOAK FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _run_world_cycle(
	game: Node,
	hub: Node,
	diagnostics: Node,
	cycle: int,
	expected_render_distance: int
) -> void:
	var world_id := "qa-soak-%d-%d" % [Time.get_ticks_msec(), cycle]
	game.call("begin_world_state", _world_state(world_id, 991100 + cycle))
	await process_frame
	await physics_frame
	await process_frame
	var world: Node = game.get("world")
	var player: Node3D = game.get("player")
	_check(
		world != null and bool(world.get("is_started")),
		"world cycle %d starts a real voxel world" % (cycle + 1),
	)
	_check(
		player != null and player.visible,
		"world cycle %d keeps the player visible" % (cycle + 1),
	)
	var controller_status: Dictionary = diagnostics.call("get_adaptive_streaming_status")
	_check(
		bool(controller_status.get("attached", false)),
		"world cycle %d attaches adaptive streaming" % (cycle + 1),
	)
	var max_pending := 0
	var max_loaded := 0
	var critical_samples := 0
	var origin: Vector3 = world.call("get_spawn_position")
	for frame_index in FRAMES_PER_CYCLE:
		if frame_index > 0 and frame_index % 24 == 0:
			var leg := floori(float(frame_index) / 24.0)
			var candidate := origin + Vector3(float(leg * 20), 4.0, float((leg % 2) * 18))
			var grounded: Vector3 = world.call("resolve_ground_position", candidate)
			player.global_position = grounded
			if player.has_method("reset_motion"):
				player.call("reset_motion")
		await process_frame
		if frame_index % SAMPLE_INTERVAL_FRAMES != 0:
			continue
		var snapshot: Dictionary = diagnostics.call("sample_now")
		var streaming: Dictionary = snapshot.get("streaming", {})
		max_pending = maxi(max_pending, int(streaming.get("pending", 0)))
		max_loaded = maxi(max_loaded, int(streaming.get("loaded", 0)))
		if frame_index >= 24 and str(snapshot.get("health", {}).get("status", "")) == "critical":
			critical_samples += 1
		var adaptive: Dictionary = snapshot.get("adaptive_streaming", {})
		var profile: Dictionary = adaptive.get("profile", {})
		_check(
			float(profile.get("budget_ms", 0.0)) >= 0.5
			and float(profile.get("budget_ms", 0.0)) <= 12.0,
			"adaptive budget remains inside the world safety range",
		)
	_check(max_pending <= 128, "streaming queue remains bounded during repeated travel")
	_check(max_loaded <= 96, "loaded chunk population remains bounded during repeated travel")
	_check(
		critical_samples <= 1,
		"sustained runtime health does not remain critical after the warmup window",
	)
	controller_status = diagnostics.call("get_adaptive_streaming_status")
	_check(
		int(controller_status.get("change_count", 0)) <= 12,
		"adaptive controller does not thrash while travelling",
	)
	_check(
		int(hub.get("current_settings").get("render_distance", 0)) == expected_render_distance,
		"adaptive streaming never rewrites the player's render-distance setting",
	)
	hub.call("return_to_menu")
	await process_frame
	await process_frame
	await process_frame
	_check(
		not bool(world.get("is_started")) and int(world.call("get_loaded_chunk_count")) == 0,
		"returning from world cycle %d clears chunks and collisions" % (cycle + 1),
	)
	_check(
		not bool(diagnostics.call("get_adaptive_streaming_status").get("attached", true)),
		"returning from world cycle %d releases adaptive world references" % (cycle + 1),
	)
	var input_context = hub.get("input_context")
	_check(
		input_context != null and str(input_context.call("get_context")) == "menu",
		"returning from world cycle %d restores the menu input context" % (cycle + 1),
	)
	var simulation_pause = hub.get("simulation_pause")
	_check(
		not paused and simulation_pause != null and not bool(simulation_pause.call("is_paused")),
		"returning from world cycle %d clears simulation pause" % (cycle + 1),
	)
	var spawner = hub.get("creature_spawner")
	_check(
		spawner != null and spawner.get_child_count() == 0,
		"returning from world cycle %d clears managed creatures" % (cycle + 1),
	)
	var save_service = hub.get("save_service")
	if save_service != null:
		save_service.call("delete_world", world_id)


func _world_state(world_id: String, seed_value: int) -> Dictionary:
	return {
		"save_version": 2,
		"metadata": {
			"id": world_id,
			"name": "Runtime Soak",
			"map_id": "star_continent",
			"seed": seed_value,
		},
		"player": {"position": [], "rotation": [0.0, 0.0, 0.0], "look_pitch": 0.0},
		"inventory": {},
		"containers": {"version": 1, "containers": {}},
		"world": {"block_overrides": {}, "loaded_chunks": []},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 9.0, "day": 1},
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
