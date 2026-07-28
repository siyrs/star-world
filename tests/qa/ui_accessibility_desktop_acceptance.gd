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


class FocusWaitState:
	extends RefCounted
	var completed := false
	var success := false
	var expected_overlay := 0

	func _init(overlay: int) -> void:
		expected_overlay = overlay

	func on_success(overlay: int) -> void:
		if overlay == expected_overlay:
			completed = true
			success = true

	func on_failure(overlay: int) -> void:
		if overlay == expected_overlay:
			completed = true


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
	await _push_joypad_axis(JOY_AXIS_LEFT_X, 0.8)
	for _frame in 3:
		await process_frame
	var navigation: Dictionary = menu.call("get_accessibility_navigation_snapshot")
	_check(str(navigation.get("input_mode", "")) == "controller", "real stick input selects controller mode")
	_check(str(navigation.get("focus_text", "")) == "继续游戏", "controller mode establishes the primary menu focus")
	await _push_joypad_button(JOY_BUTTON_DPAD_DOWN)
	for _frame in 3:
		await process_frame
	navigation = menu.call("get_accessibility_navigation_snapshot")
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

	# Windows may emit a synthetic relative mouse movement while the menu is
	# hidden and high-DPI controls are relaid out. The real input path must keep
	# controller ownership during the bounded guard.
	var ignored_before := int(accessibility.call("get_snapshot").get("ignored_mouse_motion_count", 0))
	var synthetic_motion := InputEventMouseMotion.new()
	synthetic_motion.relative = Vector2(8.0, 0.0)
	root.push_input(synthetic_motion, true)
	await process_frame
	var guarded_snapshot: Dictionary = accessibility.call("get_snapshot")
	_check(
		str(guarded_snapshot.get("input_mode", "")) == "controller"
		and int(guarded_snapshot.get("ignored_mouse_motion_count", 0)) == ignored_before + 1,
		"synthetic high-DPI mouse motion cannot steal controller ownership"
	)

	menu.visible = false
	hub.game_ui.begin_gameplay()
	var focused := await _open_and_wait_for_overlay_focus(
		hub.game_ui,
		Callable(hub.game_ui, "open_inventory"),
		1
	)
	var overlay_snapshot: Dictionary = hub.game_ui.call("get_accessibility_focus_snapshot")
	_check(int(overlay_snapshot.get("overlay", 0)) == 1, "gameplay inventory opens under controller mode")
	_check(focused and bool(overlay_snapshot.get("focus_inside_active_overlay", false)), "controller mode focuses a visible inventory control after the production entrance animation")
	_check(int(overlay_snapshot.get("focus_restore_failure_count", -1)) == 0, "first inventory presentation does not record a failed focus restore")

	# A mouse button is explicit intent and must take over immediately even while
	# motion hysteresis is active.
	await _push_mouse_button(MOUSE_BUTTON_MIDDLE)
	await process_frame
	_check(
		str(accessibility.call("get_input_mode")) == "mouse"
		and root.gui_get_focus_owner() == null,
		"real mouse button immediately releases controller focus"
	)
	var restore_state := _create_focus_wait_state(hub.game_ui, 1)
	await _push_joypad_axis(JOY_AXIS_LEFT_X, 0.8)
	var restored := await _finish_focus_wait(hub.game_ui, restore_state)
	_check(
		restored
		and bool(hub.game_ui.call("get_accessibility_focus_snapshot").get("focus_inside_active_overlay", false)),
		"returning to controller input restores inventory focus"
	)

	overlay_snapshot = hub.game_ui.call("get_accessibility_focus_snapshot")
	var accessibility_snapshot: Dictionary = accessibility.call("get_snapshot")
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
		"overlay_focus_success_count": int(overlay_snapshot.get("focus_restore_success_count", 0)),
		"overlay_focus_failure_count": int(overlay_snapshot.get("focus_restore_failure_count", 0)),
		"ignored_mouse_motion_count": int(accessibility_snapshot.get("ignored_mouse_motion_count", 0)),
		"controller_mouse_motion_guard_msec": int(accessibility_snapshot.get("controller_mouse_motion_guard_msec", 0)),
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


func _push_joypad_axis(axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	root.push_input(motion, true)
	await process_frame
	var release := InputEventJoypadMotion.new()
	release.axis = axis
	release.axis_value = 0.0
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


func _push_mouse_button(button: MouseButton) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = Vector2.ZERO
	press.global_position = Vector2.ZERO
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = Vector2.ZERO
	release.global_position = Vector2.ZERO
	root.push_input(release, true)
	await process_frame


func _open_and_wait_for_overlay_focus(
	game_ui: Node,
	opener: Callable,
	expected_overlay: int
) -> bool:
	var state := _create_focus_wait_state(game_ui, expected_overlay)
	opener.call()
	return await _finish_focus_wait(game_ui, state)


func _create_focus_wait_state(game_ui: Node, expected_overlay: int) -> FocusWaitState:
	var state := FocusWaitState.new(expected_overlay)
	game_ui.connect("accessibility_focus_restored", Callable(state, "on_success"))
	game_ui.connect("accessibility_focus_restore_failed", Callable(state, "on_failure"))
	return state


func _finish_focus_wait(game_ui: Node, state: FocusWaitState) -> bool:
	var deadline_msec := Time.get_ticks_msec() + 1500
	while not state.completed and Time.get_ticks_msec() < deadline_msec:
		await process_frame
	var success_callback := Callable(state, "on_success")
	var failure_callback := Callable(state, "on_failure")
	if game_ui.is_connected("accessibility_focus_restored", success_callback):
		game_ui.disconnect("accessibility_focus_restored", success_callback)
	if game_ui.is_connected("accessibility_focus_restore_failed", failure_callback):
		game_ui.disconnect("accessibility_focus_restore_failed", failure_callback)
	return state.success


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
