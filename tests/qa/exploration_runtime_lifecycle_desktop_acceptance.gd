extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://exploration-runtime-lifecycle-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	var coordinator: Node = hub.get("feature_lifecycle") if hub != null else null
	var runtime: Node = hub.get("exploration_runtime_participant") if hub != null else null
	_check(hub != null and coordinator != null and runtime != null, "production game mounts the exploration runtime participant")
	if hub == null or coordinator == null or runtime == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Exploration-Runtime-%d" % Time.get_ticks_msec(),
		"star_continent",
		7219463
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop runtime journey creates a temporary world")
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var prospecting: Node = hub.get("prospecting_service")
	var danger: Node = hub.get("exploration_danger_service")
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(prospecting != null and danger != null, "legacy exploration runtime service ports remain available")
	_check(hub.get_node_or_null("ProspectingService") == prospecting, "prospecting preserves its production node path")
	_check(hub.get_node_or_null("ExplorationDangerService") == danger, "danger preserves its production node path")
	_check(
		coordinator.call("get_participant_dependencies", &"exploration_journal_rewards") == ["exploration_runtime"],
		"production dependency graph orders journal after exploration runtime"
	)
	if player == null or prospecting == null or danger == null:
		await _finish(game, hub)
		return
	var lifecycle_before: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_before.get("bound_player_id", 0)) == player.get_instance_id(), "runtime participant binds prospecting to the production player")
	_check(bool(lifecycle_before.get("active", false)), "runtime participant activates with gameplay")

	var transitions: Array[String] = []
	var refresh_triggers: Array[String] = []
	runtime.connect(
		"danger_transition_announced",
		func(kind: String, _snapshot: Dictionary) -> void: transitions.append(kind)
	)
	runtime.connect(
		"immediate_danger_refreshed",
		func(trigger: String, _snapshot: Dictionary) -> void: refresh_triggers.append(trigger)
	)
	hub.creature_spawner.clear_creatures()
	hub.day_night.set_time(21.0)
	var first_hostile: Variant = hub.creature_spawner.call(
		"spawn_creature", "zombie", player.global_position + Vector3(10.0, 0.0, 0.0)
	)
	var second_hostile: Variant = hub.creature_spawner.call(
		"spawn_creature", "zombie", player.global_position + Vector3(-10.0, 0.0, 0.0)
	)
	_check(first_hostile is Node3D and second_hostile is Node3D, "production spawner creates two nearby hostile bodies")
	for hostile: Variant in [first_hostile, second_hostile]:
		if hostile is Node3D:
			hostile.set_physics_process(false)
			hostile.set("target", null)
	hub.creature_spawner.set_active(false)
	for _frame in 4:
		await process_frame
	var danger_high: Dictionary = danger.call("get_snapshot")
	_check(str(danger_high.get("tier_id", "")) in ["dangerous", "severe"], "phase and ecology signals immediately raise production danger")
	_check(int(danger_high.get("hostile_count", 0)) == 2, "immediate danger refresh sees both real hostile bodies")
	_check("phase_changed" in refresh_triggers and "ecology_changed" in refresh_triggers, "runtime participant reacts to both immediate refresh sources")
	_check("danger" in transitions, "danger escalation reaches the player-facing transition signal")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the immediate high-danger HUD state")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "runtime lifecycle evidence uses the 1024x576 product resolution")
		_save_image(image)

	hub.creature_spawner.clear_creatures()
	hub.day_night.set_time(8.0)
	for _frame in 4:
		await process_frame
	var danger_low: Dictionary = danger.call("get_snapshot")
	_check(int(danger_low.get("score", 100)) < int(danger_high.get("score", 0)), "clearing hostiles and returning to day immediately lowers danger")
	_check(str(danger_low.get("tier_id", "")) in ["safe", "guarded"], "production danger returns to a lower tier")
	_check(transitions.count("recovered") == 1, "danger recovery is announced exactly once")
	var lifecycle_after_recovery: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(lifecycle_after_recovery.get("danger_recovery_count", 0)) == 1, "runtime diagnostics retain the recovery transition")
	_check(int(lifecycle_after_recovery.get("immediate_refresh_count", 0)) >= 4, "runtime diagnostics count phase and ecology refreshes")

	hub.inventory.clear()
	hub.inventory.add_item("prospecting_kit", 1)
	hub.inventory.select_slot(0)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-42.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	var prospecting_snapshot: Dictionary = prospecting.call("get_snapshot")
	_check(int(prospecting_snapshot.get("record_count", 0)) == 1, "real right click records a discovery through the runtime participant")
	_check(int(runtime.call("get_lifecycle_snapshot").get("scan_success_count", 0)) == 1, "runtime diagnostics count the real scan once")
	_check(bool(hub.save_current()), "runtime exploration state joins the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check((loaded.get("exploration", {}).get("records", []) as Array).size() == 1, "saved world contains the participant-owned exploration record")

	var old_player := player
	hub.return_to_menu()
	for _frame in 6:
		await process_frame
	var runtime_after_menu: Dictionary = runtime.call("get_lifecycle_snapshot")
	_check(int(runtime_after_menu.get("bound_player_id", -1)) == 0, "return-to-menu removes the old player binding")
	if old_player != null and is_instance_valid(old_player):
		_check(old_player.get("prospecting_service") == null, "old production player no longer holds the prospecting service")
	_check(int((prospecting.call("get_snapshot") as Dictionary).get("record_count", 0)) == 0, "return-to-menu clears runtime prospecting state")
	_check((danger.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears runtime danger state")

	game.begin_world_state(loaded)
	for _frame in 10:
		await process_frame
	await physics_frame
	player = game.player
	_check(player != null and player.get("prospecting_service") == prospecting, "full reload rebinds the same production prospecting port")
	_check(int((prospecting.call("get_snapshot") as Dictionary).get("record_count", 0)) == 1, "full reload restores the saved exploration record")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(int(character_snapshot.get("feature_lifecycle", {}).get("participant_count", 0)) == 3, "production diagnostics expose ranch, runtime and journal participants")
	_check(character_snapshot.has("animal_attraction") and character_snapshot.has("animal_products"), "production character diagnostics include the ranch participant fields")
	_check(character_snapshot.has("exploration") and character_snapshot.has("danger"), "production character diagnostics retain legacy runtime fields")

	game.call("_abort_world_start", "qa_exploration_runtime_failure")
	for _frame in 4:
		await process_frame
	_check(hub.current_world_id.is_empty(), "real failed-start path resets the hub identity")
	_check(int(runtime.call("get_lifecycle_snapshot").get("bound_player_id", -1)) == 0, "failed-start cleanup removes the current player binding")
	await _finish(game, hub)


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (1 << (int(button) - 1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event)


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "exploration runtime lifecycle screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA EXPLORATION RUNTIME LIFECYCLE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION RUNTIME LIFECYCLE DESKTOP FAILURE: %s" % failure)
		print("QA EXPLORATION RUNTIME LIFECYCLE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
