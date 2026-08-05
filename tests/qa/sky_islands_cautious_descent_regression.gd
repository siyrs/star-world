extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const RouteProbeScript = preload("res://src/diagnostics/production_route_probe.gd")

const PROFILE_ID := "sky_islands"
const REGRESSION_SEED := 112361
const READY_FRAMES := 720
const CLEANUP_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	var save: Node = hub.get("save_service") as Node if hub != null else null
	_check(hub != null and save != null, "production game and save service mount")
	if hub == null or save == null:
		await _finish(game, hub, save)
		return
	var state: Dictionary = save.call(
		"create_world",
		"Sky-Descent-Regression-%d" % Time.get_ticks_msec(),
		PROFILE_ID,
		REGRESSION_SEED
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "regression creates an authoritative sky-island world")
	game.call("begin_world_state", state)
	var ready := false
	for _frame in READY_FRAMES:
		await process_frame
		var candidate_world: Node = game.get("world") as Node
		var candidate_player: Node = game.get("player") as Node
		if (
			candidate_world != null
			and candidate_player != null
			and bool(candidate_world.get("is_started"))
			and bool(candidate_player.get("input_enabled"))
		):
			ready = true
			break
	_check(ready, "sky-island production world reaches a bounded ready state")
	if not ready:
		await _finish(game, hub, save)
		return
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var route_probe = RouteProbeScript.new()
	var result: Dictionary = await route_probe.execute(
		self,
		world,
		player,
		PROFILE_ID,
		REGRESSION_SEED,
		{
			"min_route_steps": 12,
			"target_route_steps": 18,
			"min_route_displacement": 8.0,
		}
	)
	_check(bool(result.get("ok", false)), "seed 112361 completes the real production-input route")
	_check(int(result.get("successful_steps", 0)) == 18, "all eighteen planned steps complete")
	_check(float(result.get("horizontal_displacement", 0.0)) >= 8.0, "route retains meaningful displacement")
	_check(int(result.get("unique_chunks", 0)) >= 2, "route still crosses multiple chunks")
	_check(float(result.get("maximum_single_fall", 99.0)) <= 4.0, "cautious descent prevents the historical island-edge fall")
	_check((result.get("route_failures", []) as Array).is_empty(), "route produces no hidden failure")
	_check(not bool(result.get("transport_after_spawn", true)), "route performs no post-spawn transport")
	_check(int(result.get("player_transform_writes", -1)) == 0, "route performs zero player transform writes")
	var cautious_steps := 0
	for raw_step: Variant in result.get("step_diagnostics", []):
		if raw_step is Dictionary and bool(raw_step.get("cautious_descent", false)):
			cautious_steps += 1
	_check(cautious_steps >= 1, "fixture exercises the cautious one-block descent path")
	await _finish(game, hub, save)


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub) and not str(hub.get("current_world_id")).is_empty():
		hub.call("return_to_menu")
		for _frame in CLEANUP_FRAMES:
			await process_frame
	if save != null and is_instance_valid(save) and not _world_id.is_empty():
		if bool(save.call("world_exists", _world_id)):
			save.call("delete_world", _world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("SKY ISLAND CAUTIOUS DESCENT PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("SKY ISLAND CAUTIOUS DESCENT FAILURE: %s" % failure)
		print("SKY ISLAND CAUTIOUS DESCENT FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
