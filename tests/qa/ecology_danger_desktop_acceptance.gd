extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ecology-danger-desktop.png"
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
	_check(hub != null, "production game exposes the exploration service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Ecology-Danger-%d" % Time.get_ticks_msec(), "abyss_world", 61582493
	)
	_check(not state.is_empty(), "desktop ecology journey creates an abyss world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var spawner: Node = hub.creature_spawner
	var danger: Node = hub.get("exploration_danger_service")
	var prospecting: Node = hub.get("prospecting_service")
	var hud: Node = hub.game_ui.hud
	_check(player != null and bool(player.get("input_enabled")), "production player owns gameplay input")
	_check(world != null and bool(world.get("is_started")), "production abyss world starts")
	_check(spawner != null and danger != null and prospecting != null, "production exploration services are mounted")
	if player == null or world == null or spawner == null or danger == null or prospecting == null:
		await _finish(game, hub)
		return
	var initial_ecology: Dictionary = spawner.call("get_ecology_snapshot")
	_check(str(initial_ecology.get("profile_id", "")) == "abyss_world", "world metadata selects the abyss ecology profile")
	_check(int(initial_ecology.get("hostile_cap", 0)) == 2, "abyss daytime hostile cap is active in production")
	_check(is_equal_approx(float(initial_ecology.get("spawn_interval_seconds", 0.0)), 5.5), "abyss uses its faster spawn rhythm")

	hub.day_night.set_time(22.0)
	spawner.clear_creatures()
	for _frame in 3:
		await process_frame
	var first = spawner.spawn_creature("zombie", player.global_position + Vector3(5.0, 0.0, 1.0))
	var second = spawner.spawn_creature("zombie", player.global_position + Vector3(-5.0, 0.0, 1.0))
	_check(first != null and second != null, "production spawner creates fixed nearby abyss hostiles")
	for _frame in 4:
		await process_frame
		await physics_frame
	var night_ecology: Dictionary = spawner.call("get_ecology_snapshot")
	_check(int(night_ecology.get("hostile_cap", 0)) == 5, "night phase raises the abyss hostile cap")
	var severe: Dictionary = danger.call("refresh_now")
	_check(int(severe.get("hostile_count", 0)) >= 2, "live danger assessment counts nearby production hostiles")
	_check(str(severe.get("tier_id", "")) in ["dangerous", "severe"], "night abyss pressure reaches a dangerous tier")
	_check(int(severe.get("sample_count", 0)) <= 125, "real danger assessment respects the hard sample budget")
	var danger_panel: Control = hud.call("get_danger_panel")
	_check(danger_panel != null and danger_panel.visible, "production HUD displays the live danger panel")
	var danger_label: Label = hud.get("_danger_label")
	_check(danger_label != null and danger_label.text.contains(str(severe.get("tier_label", ""))), "HUD label matches the authoritative danger snapshot")

	hub.inventory.clear()
	hub.inventory.add_item("prospecting_kit", 1)
	hub.inventory.select_slot(0)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3(deg_to_rad(-45.0), 0.0, 0.0)
	await process_frame
	await _right_click_center()
	var prospect_snapshot: Dictionary = prospecting.call("get_snapshot")
	var last_result: Dictionary = prospect_snapshot.get("last_result", {})
	_check(int(prospect_snapshot.get("record_count", 0)) == 1, "real prospecting creates one danger-aware discovery")
	_check(str(last_result.get("danger_tier_id", "")) == str(severe.get("tier_id", "")), "prospecting captures the live danger tier")
	_check(int(last_result.get("danger_score", -1)) == int(severe.get("score", -2)), "prospecting captures the live danger score")
	_check(str(last_result.get("message", "")).contains("当前危险"), "player-facing scan result explains current danger")
	_check(bool(hub.save_current()), "danger-aware exploration record participates in the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var records: Array = loaded.get("exploration", {}).get("records", [])
	_check(records.size() == 1, "danger-aware discovery persists in the saved world")
	if records.size() == 1:
		_check(str(records[0].get("danger_tier_id", "")) == str(severe.get("tier_id", "")), "saved record retains danger tier")
		_check(int(records[0].get("danger_score", -1)) == int(severe.get("score", -2)), "saved record retains danger score")

	spawner.clear_creatures()
	hub.day_night.set_time(12.0)
	for _frame in 5:
		await process_frame
	var daytime: Dictionary = danger.call("refresh_now")
	_check(int(daytime.get("score", 100)) < int(severe.get("score", 0)), "removing hostiles and returning to day lowers live danger")
	_check(str(hud.get("_danger_label").text).contains(str(daytime.get("tier_label", ""))), "HUD refreshes after danger decreases")

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders danger feedback in the abyss world")
	if image != null and not image.is_empty():
		_save_image(image)
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
	_check(error == OK and FileAccess.file_exists(_capture_path), "danger desktop screenshot is saved")


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
		print("QA ECOLOGY DANGER DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA ECOLOGY DANGER DESKTOP FAILURE: %s" % failure)
		print("QA ECOLOGY DANGER DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
