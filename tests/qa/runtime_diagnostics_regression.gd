extends SceneTree

const Actions = preload("res://src/input/gameplay_input_actions.gd")
const HealthPolicyScript = preload("res://src/diagnostics/runtime_health_policy.gd")
const TelemetryScript = preload("res://src/diagnostics/runtime_telemetry_service.gd")
const OverlayScript = preload("res://src/ui/diagnostics_overlay.gd")
const GameScene = preload("res://scenes/game/game.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node

	func get_streaming_stats() -> Dictionary:
		return {
			"loaded": 9,
			"building": 1,
			"pending": 4,
			"last_work_usec": 2100,
			"focus_chunk": Vector2i.ZERO,
		}


class FakeInputContext:
	extends Node
	var context: StringName = &"gameplay"

	func get_context() -> StringName:
		return context


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_health_policy()
	await _test_telemetry_and_overlay()
	await _test_game_mounts_diagnostics()
	if failures.is_empty():
		print("QA RUNTIME DIAGNOSTICS PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA RUNTIME DIAGNOSTICS FAILURE: %s" % failure)
		print("QA RUNTIME DIAGNOSTICS FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_health_policy() -> void:
	var policy = HealthPolicyScript.new()
	var result: Dictionary = policy.evaluate(
		{
			"frame_sample_count": 30,
			"frame_ms_avg": 46.0,
			"frame_ms_peak": 90.0,
			"stutter_count": 12,
			"memory_mib": 1700.0,
			"node_count": 10000,
			"streaming": {"pending": 120},
		}
	)
	_check(str(result.get("status", "")) == "critical", "critical runtime pressure is detected")
	_check(not result.get("issues", []).is_empty(), "health evaluation explains its findings")
	var healthy: Dictionary = policy.evaluate(
		{
			"frame_sample_count": 60,
			"frame_ms_avg": 16.7,
			"frame_ms_peak": 24.0,
			"stutter_count": 0,
			"memory_mib": 256.0,
			"node_count": 600,
			"streaming": {"pending": 2},
		}
	)
	_check(str(healthy.get("status", "")) == "healthy", "normal runtime values remain healthy")


func _test_telemetry_and_overlay() -> void:
	Actions.ensure_default_bindings()
	var host := Node.new()
	root.add_child(host)
	var world := FakeWorld.new()
	var player := Node3D.new()
	player.global_position = Vector3(2.5, 24.0, -6.5)
	var context := FakeInputContext.new()
	var spawner := Node3D.new()
	var creature := Node3D.new()
	creature.add_to_group("creatures")
	spawner.add_child(creature)
	var pickup := Node.new()
	pickup.add_to_group("pickups")
	var telemetry = TelemetryScript.new()
	var overlay = OverlayScript.new()
	for node in [world, player, context, spawner, pickup, telemetry, overlay]:
		host.add_child(node)
	await process_frame
	telemetry.setup(context, spawner)
	telemetry.attach_runtime(world, player)
	for _index in 12:
		telemetry.record_frame(0.016)
	telemetry.record_frame(0.052)
	var snapshot: Dictionary = telemetry.sample_now()
	_check(int(snapshot.get("frame_sample_count", 0)) == 13, "telemetry records real frame samples")
	_check(
		int(snapshot.get("streaming", {}).get("loaded", 0)) == 9,
		"telemetry reads the world streaming contract",
	)
	_check(int(snapshot.get("creature_count", 0)) == 1, "telemetry counts managed creatures")
	_check(int(snapshot.get("pickup_count", 0)) == 1, "telemetry counts registered pickups")
	_check(snapshot.get("player_position", []).size() == 3, "telemetry includes player position")
	_check(snapshot.get("health", {}) is Dictionary, "telemetry includes evaluated health")
	_check(not telemetry.get_history().is_empty(), "telemetry retains bounded history")

	overlay.setup(telemetry)
	await process_frame
	var f3_event := InputEventKey.new()
	f3_event.keycode = KEY_F3
	f3_event.physical_keycode = KEY_F3
	f3_event.pressed = true
	_check(
		InputMap.event_is_action(f3_event, Actions.TOGGLE_DIAGNOSTICS),
		"F3 is registered as the diagnostics action",
	)
	root.push_input(f3_event)
	await process_frame
	_check(overlay.is_overlay_visible(), "a real F3 input event opens diagnostics")
	_check("运行诊断" in overlay.get_display_text(), "overlay renders the latest snapshot")
	_check(_all_controls_are_passthrough(overlay), "diagnostics UI cannot intercept mouse input")
	root.push_input(f3_event)
	await process_frame
	_check(not overlay.is_overlay_visible(), "F3 toggles diagnostics closed")
	host.queue_free()
	await process_frame
	await process_frame


func _test_game_mounts_diagnostics() -> void:
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var coordinator: Node = game.get("runtime_diagnostics")
	_check(coordinator != null, "game mounts the runtime diagnostics coordinator")
	if coordinator != null:
		_check(coordinator.get("telemetry") != null, "coordinator mounts telemetry")
		_check(coordinator.get("overlay") != null, "coordinator mounts the F3 overlay")
		_check(
			_all_controls_are_passthrough(coordinator.get("overlay")),
			"integrated diagnostics overlay remains mouse passthrough",
		)
	var hub: Node = game.get("service_hub")
	if hub != null and hub.get("audio_service") != null:
		hub.audio_service.stop_ambient()
	game.queue_free()
	await process_frame
	await process_frame


func _all_controls_are_passthrough(node: Node) -> bool:
	if node == null:
		return false
	if node is Control:
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE:
			return false
	for child in node.get_children():
		if not _all_controls_are_passthrough(child):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
