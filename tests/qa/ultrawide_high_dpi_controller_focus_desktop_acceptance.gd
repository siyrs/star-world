extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ultrawide-high-dpi-controller-focus.png"
const PHYSICAL_SIZE := Vector2i(3440, 1440)
const LOGICAL_SIZE := Vector2i(1720, 720)
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _focus_route: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_base_dir().path_join(
		"ultrawide-high-dpi-controller-focus-report.json"
	)
	root.size = PHYSICAL_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = LOGICAL_SIZE

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 10:
		await process_frame
	var hub := game.get("service_hub") as Node
	var main_menu := hub.get("main_menu") as Control if hub != null else null
	_check(hub != null and main_menu != null, "production command deck mounts at 3440x1440 with a 2x logical scale")
	if hub == null or main_menu == null:
		await _finish(game, hub)
		return

	var scale_x := float(PHYSICAL_SIZE.x) / float(LOGICAL_SIZE.x)
	var scale_y := float(PHYSICAL_SIZE.y) / float(LOGICAL_SIZE.y)
	_check(is_equal_approx(scale_x, 2.0) and is_equal_approx(scale_y, 2.0), "desktop fixture retains an exact two-times high-DPI logical scale")
	var focused := root.gui_get_focus_owner() as Control
	_check(focused is Button and focused.visible, "startup exposes one visible focused primary controller target")
	if focused != null:
		_focus_route.append(_focus_label(focused))
		_check(
			focused.focus_mode == Control.FOCUS_ALL and focused.has_theme_stylebox("focus"),
			"focused primary action consumes the shared visible focus-ring contract"
		)

	var visible_rect := root.get_visible_rect()
	_check(_all_visible_buttons_inside(main_menu, visible_rect), "every visible command remains inside the ultrawide logical viewport")
	var first_focus := focused
	await _press_joy(JOY_BUTTON_DPAD_DOWN)
	var second_focus := root.gui_get_focus_owner() as Control
	_check(
		second_focus != null and second_focus != first_focus and second_focus.visible,
		"real controller D-pad moves focus to the next visible command"
	)
	if second_focus != null:
		_focus_route.append(_focus_label(second_focus))
	await _press_joy(JOY_BUTTON_DPAD_UP)
	var returned_focus := root.gui_get_focus_owner() as Control
	_check(returned_focus == first_focus, "opposite D-pad input returns to the original primary command")

	var settings_button := _find_button(main_menu, "设置")
	_check(settings_button != null and settings_button.visible, "ultrawide command deck keeps Settings reachable")
	if settings_button != null:
		settings_button.grab_focus()
		await process_frame
		_focus_route.append(_focus_label(settings_button))
		await _press_joy(JOY_BUTTON_A)
	var settings_panel := main_menu.get("_settings_panel") as Control
	_check(settings_panel != null and settings_panel.visible, "controller accept opens the production settings workspace")
	if settings_panel != null:
		_check(_all_visible_buttons_inside(settings_panel, visible_rect), "settings controls stay inside the ultrawide high-DPI viewport")
		var settings_focus := root.gui_get_focus_owner() as Control
		_check(settings_focus != null and settings_focus.visible, "settings workspace establishes a visible controller focus target")
		await _press_joy(JOY_BUTTON_DPAD_DOWN)
		var next_settings_focus := root.gui_get_focus_owner() as Control
		_check(next_settings_focus != null and next_settings_focus.visible, "controller navigation remains live inside the scrolled settings workspace")
		if next_settings_focus != null:
			_focus_route.append(_focus_label(next_settings_focus))
		await _capture()
		await _press_joy(JOY_BUTTON_B)
		_check(main_menu.visible and not settings_panel.visible, "controller cancel returns from settings without losing the command deck")
		_check(root.gui_get_focus_owner() != null, "controller cancel restores a valid command-deck focus owner")

	var report := {
		"schema_version":1,
		"physical_size":{"width":PHYSICAL_SIZE.x, "height":PHYSICAL_SIZE.y},
		"logical_size":{"width":LOGICAL_SIZE.x, "height":LOGICAL_SIZE.y},
		"logical_scale":{"x":scale_x, "y":scale_y},
		"visible_rect":_rect_payload(visible_rect),
		"focus_route":_focus_route.duplicate(),
		"focus_route_count":_focus_route.size(),
		"main_menu":main_menu.call("get_visual_snapshot"),
		"settings":settings_panel.call("get_layout_snapshot") if settings_panel != null else {},
		"capture":_capture_path,
	}
	_check(_write_json(_report_path, report), "ultrawide high-DPI controller-focus JSON report is saved")
	await _finish(game, hub)


func _press_joy(button_index: JoyButton) -> void:
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = button_index
	press.pressed = true
	press.pressure = 1.0
	root.push_input(press)
	await process_frame
	var release := InputEventJoypadButton.new()
	release.device = 0
	release.button_index = button_index
	release.pressed = false
	release.pressure = 0.0
	root.push_input(release)
	for _frame in 4:
		await process_frame


func _all_visible_buttons_inside(node: Node, viewport_rect: Rect2) -> bool:
	var buttons: Array[Button] = []
	_collect_visible_buttons(node, buttons)
	if buttons.is_empty():
		return false
	for button: Button in buttons:
		var rect := button.get_global_rect()
		if (
			rect.size.x <= 0.0
			or rect.size.y <= 0.0
			or rect.position.x < viewport_rect.position.x - 1.0
			or rect.position.y < viewport_rect.position.y - 1.0
			or rect.end.x > viewport_rect.end.x + 1.0
			or rect.end.y > viewport_rect.end.y + 1.0
		):
			return false
	return true


func _collect_visible_buttons(node: Node, result: Array[Button]) -> void:
	if node == null:
		return
	if node is Button and (node as Button).visible:
		result.append(node as Button)
	for child: Node in node.get_children():
		_collect_visible_buttons(child, result)


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _focus_label(control: Control) -> String:
	if control is Button:
		return (control as Button).text.left(64)
	return control.name.left(64)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "ultrawide viewport produces a real desktop image")
	if image == null or image.is_empty():
		return
	_check(image.get_size() == PHYSICAL_SIZE, "desktop evidence retains the full 3440x1440 physical surface")
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "ultrawide high-DPI controller-focus screenshot is saved")


func _write_json(path: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return FileAccess.file_exists(path)


func _rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x":rect.position.x,
		"y":rect.position.y,
		"width":rect.size.x,
		"height":rect.size.y,
	}


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA ULTRAWIDE HIGH DPI CONTROLLER FOCUS DESKTOP PASS | checks=%d | report=%s" % [checks, _report_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA ULTRAWIDE HIGH DPI CONTROLLER FOCUS DESKTOP FAILURE: %s" % failure)
	print("QA ULTRAWIDE HIGH DPI CONTROLLER FOCUS DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
