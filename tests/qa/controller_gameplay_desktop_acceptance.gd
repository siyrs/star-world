extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://controller-gameplay-inventory.png"
const INVENTORY_OVERLAY := 1
const PAUSE_OVERLAY := 5

var checks := 0
var failures: Array[String] = []
var _inventory_capture := ""
var _pause_capture := ""
var _report_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_inventory_capture = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_pause_capture = _inventory_capture.get_base_dir().path_join("controller-gameplay-pause.png")
	_report_path = _inventory_capture.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	var player = PlayerScene.instantiate()
	root.add_child(player)
	for _frame in 10:
		await process_frame
	var gameplay_input: Node = hub.get("gameplay_input") as Node
	_check(gameplay_input != null, "production service hub exposes the authoritative gameplay input service")
	_check(hub.game_ui != null, "production service hub exposes the final game UI")
	if gameplay_input == null or hub.game_ui == null:
		await _finish(hub, player)
		return
	if hub.main_menu != null:
		hub.main_menu.visible = false
	hub.game_ui.begin_gameplay()
	player.set_process(false)
	player.set_physics_process(false)
	player.bind_input_service(gameplay_input)
	player.set_input_enabled(true)
	for _frame in 4:
		await process_frame
	_check(gameplay_input.is_active(), "gameplay context activates controller input")

	_parse_axis(JOY_AXIS_LEFT_X, 0.82)
	_parse_axis(JOY_AXIS_LEFT_Y, -0.66)
	await process_frame
	var movement: Vector2 = gameplay_input.call("get_movement_vector")
	_check(movement.x > 0.5 and movement.y < -0.3, "real left-stick events produce diagonal movement")
	_parse_axis(JOY_AXIS_LEFT_X, 0.0)
	_parse_axis(JOY_AXIS_LEFT_Y, 0.0)
	await process_frame

	var yaw_before: float = float(player.rotation.y)
	_parse_axis(JOY_AXIS_RIGHT_X, 0.86)
	await process_frame
	player.call("_process", 0.25)
	_parse_axis(JOY_AXIS_RIGHT_X, 0.0)
	await process_frame
	var player_snapshot: Dictionary = player.call("get_controller_gameplay_snapshot")
	_check(player.rotation.y < yaw_before, "real right-stick input rotates the production player camera")
	_check(int(player_snapshot.get("look_frame_count", 0)) == 1, "right-stick camera movement records one exact frame")

	_parse_button(JOY_BUTTON_A, true)
	await process_frame
	_check(bool(gameplay_input.call("is_jump_just_pressed")), "real controller A reaches the authoritative jump action")
	_parse_button(JOY_BUTTON_A, false)
	await process_frame

	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await process_frame
	player.call("_process", 0.016)
	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await process_frame
	player.call("_process", 0.016)
	player_snapshot = player.call("get_controller_gameplay_snapshot")
	_check(int(player_snapshot.get("primary_press_count", 0)) == 1, "real right trigger starts the shared attack/harvest path once")
	_check(int(player_snapshot.get("primary_release_count", 0)) == 1, "real right trigger releases the shared hold once")

	var hotbar_before := int(player_snapshot.get("selected_hotbar_index", 0))
	_parse_button(JOY_BUTTON_DPAD_RIGHT, true)
	await process_frame
	player.call("_process", 0.016)
	_parse_button(JOY_BUTTON_DPAD_RIGHT, false)
	await process_frame
	player_snapshot = player.call("get_controller_gameplay_snapshot")
	_check(int(player_snapshot.get("selected_hotbar_index", 0)) == posmod(hotbar_before + 1, 9), "real D-Pad right advances the production hotbar")

	_parse_button(JOY_BUTTON_Y, true)
	for _frame in 6:
		await process_frame
	_parse_button(JOY_BUTTON_Y, false)
	_check(hub.game_ui.get_active_overlay() == INVENTORY_OVERLAY, "real controller Y opens the production inventory")
	_check(not gameplay_input.is_active(), "inventory context blocks gameplay movement and triggers")
	await _capture(_inventory_capture, "controller inventory screenshot is saved")

	_parse_button(JOY_BUTTON_B, true)
	for _frame in 6:
		await process_frame
	_parse_button(JOY_BUTTON_B, false)
	_check(hub.game_ui.get_active_overlay() == 0, "real controller B closes the inventory")
	_check(gameplay_input.is_active(), "closing inventory restores gameplay controller input")

	_parse_button(JOY_BUTTON_START, true)
	for _frame in 6:
		await process_frame
	_parse_button(JOY_BUTTON_START, false)
	_check(hub.game_ui.get_active_overlay() == PAUSE_OVERLAY, "real controller Start opens the production pause menu")
	_check(not gameplay_input.is_active(), "pause context releases continuous gameplay controller state")
	await _capture(_pause_capture, "controller pause screenshot is saved")

	var input_snapshot: Dictionary = gameplay_input.call("get_binding_status")
	var accessibility_snapshot: Dictionary = hub.call("get_ui_accessibility_snapshot")
	var report := {
		"checks": checks,
		"failures": failures.duplicate(),
		"movement": [movement.x, movement.y],
		"player": player_snapshot,
		"input": input_snapshot,
		"accessibility": accessibility_snapshot,
		"inventory_overlay": INVENTORY_OVERLAY,
		"pause_overlay": PAUSE_OVERLAY,
		"inventory_capture": _inventory_capture,
		"pause_capture": _pause_capture,
	}
	_write_report(report)
	await _finish(hub, player)


func _parse_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _parse_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s renders a non-empty viewport" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), description)


func _write_report(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "controller gameplay JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "controller gameplay JSON report is saved")


func _finish(hub: Node, player: Node) -> void:
	_parse_axis(JOY_AXIS_LEFT_X, 0.0)
	_parse_axis(JOY_AXIS_LEFT_Y, 0.0)
	_parse_axis(JOY_AXIS_RIGHT_X, 0.0)
	_parse_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_parse_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_parse_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	if player != null:
		player.set_input_enabled(false)
		player.queue_free()
	if hub != null:
		hub.game_ui.end_gameplay()
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		var accessibility: Node = hub.get("ui_accessibility") as Node
		if accessibility != null and accessibility.has_method("dispose"):
			accessibility.call("dispose")
		hub.queue_free()
	for _frame in 40:
		await process_frame
	if failures.is_empty():
		print(
			"QA CONTROLLER GAMEPLAY DESKTOP PASS | checks=%d | inventory=%s | pause=%s | report=%s"
			% [checks, _inventory_capture, _pause_capture, _report_path]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA CONTROLLER GAMEPLAY DESKTOP FAILURE: %s" % failure)
	print("QA CONTROLLER GAMEPLAY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
