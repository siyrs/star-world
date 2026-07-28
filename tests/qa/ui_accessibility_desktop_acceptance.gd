extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ui-accessibility-high-dpi-settings.png"
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _settings_capture := ""
var _controller_capture := ""
var _report_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_settings_capture = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_controller_capture = _settings_capture.get_base_dir().path_join(
		"ui-accessibility-controller-focus.png"
	)
	_report_path = _settings_capture.get_basename() + ".json"
	root.size = Vector2i(2560, 1440)
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 10:
		await process_frame
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	var accessibility: Node = hub.get("ui_accessibility") as Node
	var menu: Control = hub.main_menu
	var settings: Control = menu.get("_settings_panel") as Control if menu != null else null
	_check(accessibility != null, "production hub exposes the accessibility service")
	_check(menu != null and settings != null, "production menu exposes the hardened settings workspace")
	if accessibility == null or menu == null or settings == null:
		await _finish(hub, original_settings)
		return

	menu.call("_show_panel", settings)
	for _frame in 5:
		await process_frame
	var scale_control: OptionButton = settings.call("get_ui_scale_control")
	_check(scale_control != null and scale_control.item_count == 4, "settings exposes four bounded interface scales")
	_select_scale(scale_control, 1.5)
	var actions: Array[Button] = settings.call("get_action_buttons")
	var apply_button: Button = actions[0] if not actions.is_empty() else null
	_check(apply_button != null and apply_button.visible, "high-DPI settings keeps the save action visible")
	if apply_button != null:
		await _click_control(apply_button)
	for _frame in 8:
		await process_frame
	_check(is_equal_approx(float(hub.current_settings.get("ui_scale", 0.0)), 1.5), "real pointer input persists 150 percent UI scale")
	_check(is_equal_approx(float(accessibility.call("get_ui_scale")), 1.5), "accessibility service applies the persisted scale")
	_check(is_equal_approx(ThemeDB.fallback_base_scale, 1.5), "global theme fallback reflects the high-DPI scale")
	var layout: Dictionary = settings.call("get_layout_snapshot")
	var settings_rect: Rect2 = layout.get("panel_rect", Rect2())
	var design_viewport := root.get_visible_rect()
	_check(design_viewport.encloses(settings_rect), "scaled settings remains inside the logical viewport")
	await _capture(_settings_capture, "high-DPI settings screenshot is saved")

	menu.show_main()
	await _push_joypad_button(JOY_BUTTON_DPAD_DOWN)
	for _frame in 3:
		await process_frame
	var navigation: Dictionary = menu.call("get_accessibility_navigation_snapshot")
	_check(str(navigation.get("input_mode", "")) == "controller", "real D-Pad input selects controller mode")
	_check(str(navigation.get("focus_text", "")) == "创建新世界", "D-Pad moves focus to the second main command")
	await _capture(_controller_capture, "controller focus screenshot is saved")

	await _push_joypad_button(JOY_BUTTON_A)
	for _frame in 5:
		await process_frame
	navigation = menu.call("get_accessibility_navigation_snapshot")
	_check(bool(navigation.get("map_visible", false)), "controller A opens the real world creation workspace")
	var map_panel: Control = menu.get("_map_panel") as Control
	var focus_owner: Control = root.gui_get_focus_owner()
	_check(
		focus_owner != null and map_panel != null and map_panel.is_ancestor_of(focus_owner),
		"controller navigation transfers focus into the opened workspace"
	)

	await _push_joypad_button(JOY_BUTTON_B)
	for _frame in 5:
		await process_frame
	navigation = menu.call("get_accessibility_navigation_snapshot")
	_check(bool(navigation.get("main_visible", false)), "controller B returns to the main command deck")
	_check(str(navigation.get("focus_text", "")) == "继续游戏", "controller return restores the primary command focus")

	menu.visible = false
	hub.game_ui.begin_gameplay()
	hub.game_ui.open_inventory()
	for _frame in 5:
		await process_frame
	var overlay_snapshot: Dictionary = hub.game_ui.call("get_accessibility_focus_snapshot")
	_check(int(overlay_snapshot.get("overlay", 0)) == 1, "gameplay inventory opens under controller mode")
	_check(bool(overlay_snapshot.get("focus_inside_game_ui", false)), "controller mode focuses a visible inventory control")

	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(8.0, 0.0)
	root.push_input(mouse, true)
	await process_frame
	_check(root.gui_get_focus_owner() == null, "real mouse motion releases controller focus")
	await _push_joypad_button(JOY_BUTTON_DPAD_DOWN)
	for _frame in 3:
		await process_frame
	_check(
		bool(hub.game_ui.call("get_accessibility_focus_snapshot").get("focus_inside_game_ui", false)),
		"returning to controller input restores inventory focus"
	)

	var report := {
		"checks": checks,
		"failures": failures.duplicate(),
		"physical_viewport": [root.size.x, root.size.y],
		"logical_viewport": [design_viewport.size.x, design_viewport.size.y],
		"ui_scale": float(accessibility.call("get_ui_scale")),
		"input_mode": str(accessibility.call("get_input_mode")),
		"settings_rect": [settings_rect.position.x, settings_rect.position.y, settings_rect.size.x, settings_rect.size.y],
		"settings_capture": _settings_capture,
		"controller_capture": _controller_capture,
	}
	_write_report(report)
	await _finish(hub, original_settings)


func _select_scale(option: OptionButton, expected: float) -> void:
	if option == null:
		return
	for index in option.item_count:
		if is_equal_approx(float(option.get_item_metadata(index)), expected):
			option.select(index)
			return


func _click_control(control: Control) -> void:
	await process_frame
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = target
	press.global_position = target
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _push_joypad_button(button: JoyButton) -> void:
	var press := InputEventJoypadButton.new()
	press.button_index = button
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s renders a non-empty frame" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), description)


func _write_report(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "accessibility JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "accessibility JSON report is saved")


func _finish(hub: Node, original_settings: Dictionary) -> void:
	if hub != null and is_instance_valid(hub):
		hub.game_ui.end_gameplay()
		if not original_settings.is_empty():
			hub.call("_on_settings_changed", original_settings)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		var accessibility: Node = hub.get("ui_accessibility") as Node
		if accessibility != null and accessibility.has_method("dispose"):
			accessibility.call("dispose")
		hub.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA UI ACCESSIBILITY DESKTOP PASS | checks=%d | settings=%s | controller=%s"
			% [checks, _settings_capture, _controller_capture]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA UI ACCESSIBILITY DESKTOP FAILURE: %s" % failure)
	print("QA UI ACCESSIBILITY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
