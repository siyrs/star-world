extends SceneTree

const PolicyScript = preload("res://src/performance/adaptive_streaming_policy.gd")
const AdapterScript = preload("res://src/performance/streaming_budget_adapter.gd")
const ControllerScript = preload("res://src/performance/adaptive_streaming_controller.gd")
const GameScene = preload("res://scenes/game/game.tscn")

var checks := 0
var failures: Array[String] = []


class FakeTelemetry:
	extends Node
	signal snapshot_updated(snapshot: Dictionary)


class FakeWorld:
	extends Node

	var chunk_build_budget_ms := 4.0
	var chunk_build_cells_per_step := 2048
	var max_chunk_build_steps_per_frame := 2
	var chunks_per_frame := 1

	func get_streaming_stats() -> Dictionary:
		return {
			"loaded": 9,
			"building": 1,
			"pending": 24,
			"last_work_usec": 2400,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_and_adapter()
	await _test_controller_hysteresis()
	await _test_integrated_runtime()
	if failures.is_empty():
		print("QA ADAPTIVE STREAMING PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA ADAPTIVE STREAMING FAILURE: %s" % failure)
		print("QA ADAPTIVE STREAMING FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy_and_adapter() -> void:
	var policy = PolicyScript.new()
	var baseline := {
		"budget_ms": 4.0,
		"cells_per_step": 2048,
		"max_steps_per_frame": 2,
		"chunks_per_frame": 1,
	}
	var conservative: Dictionary = policy.profile_for_level(
		baseline, PolicyScript.LEVEL_CONSERVATIVE
	)
	var throughput: Dictionary = policy.profile_for_level(
		baseline, PolicyScript.LEVEL_THROUGHPUT
	)
	_check(
		float(conservative.get("budget_ms", 0.0)) < float(baseline.budget_ms),
		"conservative profile lowers the frame budget",
	)
	_check(
		int(conservative.get("cells_per_step", 0)) < int(baseline.cells_per_step),
		"conservative profile lowers cells per step",
	)
	_check(
		float(throughput.get("budget_ms", 0.0)) > float(baseline.budget_ms),
		"throughput profile uses available frame headroom",
	)
	_check(
		float(throughput.get("budget_ms", 0.0)) <= 6.0,
		"throughput profile remains inside the safety ceiling",
	)
	var world := FakeWorld.new()
	var adapter = AdapterScript.new()
	_check(adapter.supports(world), "budget adapter recognizes the world capability contract")
	_check(
		adapter.apply_profile(
			world,
			{
				"budget_ms": 99.0,
				"cells_per_step": 99,
				"max_steps_per_frame": 99,
				"chunks_per_frame": 99,
			}
		),
		"budget adapter applies a profile",
	)
	var clamped: Dictionary = adapter.read_profile(world)
	_check(
		is_equal_approx(float(clamped.get("budget_ms", 0.0)), 12.0)
		and int(clamped.get("cells_per_step", 0)) == 256
		and int(clamped.get("max_steps_per_frame", 0)) == 8
		and int(clamped.get("chunks_per_frame", 0)) == 4,
		"budget adapter clamps every runtime value to the world safety range",
	)


func _test_controller_hysteresis() -> void:
	var host := Node.new()
	root.add_child(host)
	var telemetry := FakeTelemetry.new()
	var world := FakeWorld.new()
	var controller = ControllerScript.new()
	controller.warmup_snapshots = 0
	controller.cooldown_snapshots = 0
	controller.pressure_confirmation_snapshots = 2
	controller.headroom_confirmation_snapshots = 3
	for node in [telemetry, world, controller]:
		host.add_child(node)
	await process_frame
	controller.setup(telemetry)
	_check(controller.attach_world(world), "controller attaches through the budget adapter contract")
	_check(
		str(controller.get_status().get("level_name", "")) == "balanced",
		"controller starts from the configured baseline",
	)
	for index in 3:
		controller.process_snapshot(_snapshot(16.0, 24.0, 0, 40, 1000 + index))
	_check(
		str(controller.get_status().get("level_name", "")) == "throughput",
		"sustained headroom with backlog raises throughput only after confirmation",
	)
	_check(
		float(world.chunk_build_budget_ms) > 4.0,
		"throughput state changes the real world budget",
	)
	controller.process_snapshot(_snapshot(27.0, 48.0, 2, 30, 2000))
	_check(
		str(controller.get_status().get("level_name", "")) == "throughput",
		"one warning sample does not immediately oscillate the budget",
	)
	controller.process_snapshot(_snapshot(27.0, 48.0, 2, 30, 2100))
	_check(
		str(controller.get_status().get("level_name", "")) == "balanced",
		"confirmed frame pressure lowers one level",
	)
	controller.process_snapshot(_snapshot(46.0, 92.0, 9, 30, 2200))
	_check(
		str(controller.get_status().get("level_name", "")) == "conservative",
		"critical frame pressure bypasses confirmation and drops load quickly",
	)
	var paused_budget := world.chunk_build_budget_ms
	controller.process_snapshot(_snapshot(12.0, 18.0, 0, 0, 2300, true))
	_check(
		is_equal_approx(world.chunk_build_budget_ms, paused_budget),
		"paused snapshots never change the streaming budget",
	)
	for index in 6:
		controller.process_snapshot(_snapshot(14.0, 22.0, 0, 0, 3000 + index))
	_check(
		str(controller.get_status().get("level_name", "")) == "balanced",
		"stable frames recover a throttled world gradually back to baseline",
	)
	controller.set_controller_enabled(false)
	_check(
		is_equal_approx(world.chunk_build_budget_ms, 4.0)
		and world.chunk_build_cells_per_step == 2048,
		"disabling adaptation restores the captured baseline",
	)
	controller.set_controller_enabled(true)
	controller.detach_world()
	_check(
		not bool(controller.get_status().get("attached", true))
		and is_equal_approx(world.chunk_build_budget_ms, 4.0),
		"detaching restores baseline and releases the world reference",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_integrated_runtime() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var diagnostics: Node = game.get("runtime_diagnostics")
	_check(diagnostics != null, "game mounts runtime diagnostics")
	_check(
		diagnostics != null and diagnostics.get("streaming_controller") != null,
		"diagnostics coordinator mounts adaptive streaming",
	)
	var world_id := "qa-adaptive-%d" % Time.get_ticks_msec()
	game.begin_world_state(_world_state(world_id))
	await process_frame
	await physics_frame
	await process_frame
	var status: Dictionary = diagnostics.call("get_adaptive_streaming_status")
	_check(bool(status.get("attached", false)), "adaptive controller attaches to the live voxel world")
	var snapshot: Dictionary = diagnostics.call("sample_now")
	_check(
		snapshot.get("adaptive_streaming", {}) is Dictionary,
		"telemetry publishes the adaptive streaming state",
	)
	var overlay = diagnostics.get("overlay")
	if overlay != null:
		overlay.call("set_overlay_visible", true)
		await process_frame
		_check(
			"流式策略" in str(overlay.call("get_display_text")),
			"F3 diagnostics renders the current adaptive budget",
		)
	var hub: Node = game.get("service_hub")
	hub.call("return_to_menu")
	await process_frame
	_check(
		not bool(diagnostics.call("get_adaptive_streaming_status").get("attached", true)),
		"returning to the menu detaches adaptive runtime state",
	)
	var save_service = hub.get("save_service")
	if save_service != null:
		save_service.call("delete_world", world_id)
	var audio = hub.get("audio_service")
	if audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	game.queue_free()
	await process_frame
	await process_frame


func _snapshot(
	average_ms: float,
	peak_ms: float,
	stutters: int,
	pending: int,
	timestamp_msec: int,
	paused_state: bool = false
) -> Dictionary:
	return {
		"timestamp_msec": timestamp_msec,
		"frame_sample_count": 30,
		"frame_ms_avg": average_ms,
		"frame_ms_peak": peak_ms,
		"stutter_count": stutters,
		"streaming": {"pending": pending},
		"input_context": "gameplay",
		"paused": paused_state,
		"world_attached": true,
	}


func _world_state(world_id: String) -> Dictionary:
	return {
		"save_version": 2,
		"metadata": {
			"id": world_id,
			"name": "Adaptive QA",
			"map_id": "star_continent",
			"seed": 667788,
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
