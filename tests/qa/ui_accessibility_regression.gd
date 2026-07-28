extends SceneTree

const Policy = preload("res://src/settings/ui_accessibility_policy.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


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
	var original_scale := ThemeDB.fallback_base_scale
	_test_policy()
	await _test_runtime_composition()
	ThemeDB.fallback_base_scale = original_scale
	if failures.is_empty():
		print("QA UI ACCESSIBILITY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA UI ACCESSIBILITY FAILURE: %s" % failure)
	print("QA UI ACCESSIBILITY FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_policy() -> void:
	_check(Policy.allowed_scales() == [0.8, 1.0, 1.25, 1.5], "accessibility policy owns four stable interface scales")
	_check(is_equal_approx(Policy.normalize_scale(null), 1.0), "invalid scale uses the canonical default")
	_check(is_equal_approx(Policy.normalize_scale(NAN), 1.0), "non-finite scale uses the canonical default")
	_check(is_equal_approx(Policy.normalize_scale(1.12), 1.0), "scale normalization chooses the nearest stable option")
	_check(is_equal_approx(Policy.normalize_scale(1.13), 1.25), "scale normalization advances after the midpoint")
	_check(Policy.scale_label(1.5) == "150%", "scale labels remain player-facing and deterministic")

	var joy_button := _joy_button(JOY_BUTTON_DPAD_DOWN)
	_check(Policy.classify_event(joy_button) == Policy.MODE_CONTROLLER, "pressed joypad buttons select controller mode")
	var quiet_axis := InputEventJoypadMotion.new()
	quiet_axis.axis = JOY_AXIS_LEFT_X
	quiet_axis.axis_value = 0.2
	_check(Policy.classify_event(quiet_axis, Policy.MODE_KEYBOARD) == Policy.MODE_KEYBOARD, "small stick drift does not steal the input mode")
	var active_axis := InputEventJoypadMotion.new()
	active_axis.axis = JOY_AXIS_LEFT_X
	active_axis.axis_value = 0.8
	_check(Policy.classify_event(active_axis, Policy.MODE_MOUSE) == Policy.MODE_CONTROLLER, "intentional stick movement selects controller mode")
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(4.0, 0.0)
	_check(Policy.classify_event(mouse_motion, Policy.MODE_CONTROLLER) == Policy.MODE_MOUSE, "real mouse motion selects mouse mode")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	_check(Policy.classify_event(key, Policy.MODE_MOUSE) == Policy.MODE_KEYBOARD, "pressed keyboard input restores keyboard mode")

	var normalized := SettingsPolicy.normalize({
		"ui_scale": 1.49,
		"unknown_accessibility_payload": true,
	})
	_check(is_equal_approx(float(normalized.get("ui_scale", 0.0)), 1.5), "settings whitelist normalizes interface scale")
	_check(not normalized.has("unknown_accessibility_payload"), "settings whitelist rejects unknown accessibility payload")


func _test_runtime_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 8:
		await process_frame
	var accessibility: Node = hub.get("ui_accessibility") as Node
	_check(accessibility != null, "production service hub mounts one accessibility state owner")
	if accessibility == null:
		hub.queue_free()
		return
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	hub.call("_on_settings_changed", {"ui_scale": 1.25})
	for _frame in 3:
		await process_frame
	var snapshot: Dictionary = accessibility.call("get_snapshot")
	_check(is_equal_approx(float(snapshot.get("ui_scale", 0.0)), 1.25), "authoritative settings apply the selected interface scale")
	_check(is_equal_approx(ThemeDB.fallback_base_scale, 1.25), "runtime applies scale through the global theme fallback")
	_check(str(hub.get_character_snapshot().get("ui_accessibility", {}).get("ui_scale_label", "")) == "125%", "character diagnostics expose the accessibility snapshot")

	var controller_event := _joy_button(JOY_BUTTON_DPAD_DOWN)
	accessibility.call("_input", controller_event)
	hub.main_menu.show_main()
	for _frame in 3:
		await process_frame
	var navigation: Dictionary = hub.main_menu.call("get_accessibility_navigation_snapshot")
	_check(str(navigation.get("input_mode", "")) == "controller", "controller mode reaches the production menu")
	_check(str(navigation.get("focus_text", "")) == "继续游戏", "controller mode restores the primary menu focus")

	var menu_buttons: Array = hub.main_menu.get("_menu_buttons")
	var create_button: Button = menu_buttons[1] as Button if menu_buttons.size() > 1 else null
	_check(create_button != null, "production menu exposes the second controller command")
	if create_button != null:
		create_button.grab_focus()
		hub.main_menu.call("_unhandled_input", _joy_button(JOY_BUTTON_A))
		for _frame in 3:
			await process_frame
		navigation = hub.main_menu.call("get_accessibility_navigation_snapshot")
		_check(bool(navigation.get("map_visible", false)), "raw controller A activates the focused menu command")
		hub.main_menu.call("_unhandled_input", _joy_button(JOY_BUTTON_B))
		for _frame in 3:
			await process_frame
		navigation = hub.main_menu.call("get_accessibility_navigation_snapshot")
		_check(bool(navigation.get("main_visible", false)), "raw controller B returns from a menu workspace")
		_check(str(navigation.get("focus_text", "")) == "继续游戏", "controller return restores the primary menu focus")

	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(6.0, 0.0)
	accessibility.call("_input", mouse)
	await process_frame
	_check(root.gui_get_focus_owner() == null, "mouse mode releases menu keyboard focus")
	accessibility.call("_input", controller_event)
	for _frame in 3:
		await process_frame
	_check(str(hub.main_menu.call("get_accessibility_navigation_snapshot").get("focus_text", "")) == "继续游戏", "returning to controller mode restores menu focus deterministically")

	hub.game_ui.begin_gameplay()
	var focused := await _open_and_wait_for_overlay_focus(
		hub.game_ui,
		Callable(hub.game_ui, "open_inventory"),
		1
	)
	var overlay_snapshot: Dictionary = hub.game_ui.call("get_accessibility_focus_snapshot")
	_check(int(overlay_snapshot.get("overlay", 0)) == 1, "production inventory overlay opens for accessibility focus")
	_check(focused and bool(overlay_snapshot.get("focus_inside_active_overlay", false)), "controller mode focuses a visible control inside the active overlay after presentation")
	_check(int(overlay_snapshot.get("focus_restore_failure_count", -1)) == 0, "presented inventory focus does not consume a failed restore")
	hub.game_ui.call("_unhandled_input", _joy_button(JOY_BUTTON_A))
	for _frame in 3:
		await process_frame
	_check(hub.game_ui.get_active_overlay() == 0, "raw controller A activates the focused overlay close command")

	focused = await _open_and_wait_for_overlay_focus(
		hub.game_ui,
		Callable(hub.game_ui, "open_inventory"),
		1
	)
	_check(focused, "reopened inventory completes the same presentation focus contract")
	hub.game_ui.call("_unhandled_input", _joy_button(JOY_BUTTON_B))
	for _frame in 3:
		await process_frame
	_check(hub.game_ui.get_active_overlay() == 0, "raw controller B closes a gameplay overlay")

	focused = await _open_and_wait_for_overlay_focus(
		hub.game_ui,
		Callable(hub.game_ui, "open_inventory"),
		1
	)
	_check(focused, "third inventory opening remains deterministically focusable")
	accessibility.call("_input", mouse)
	await process_frame
	_check(root.gui_get_focus_owner() == null, "mouse mode releases gameplay overlay focus")
	var restore_state := _create_focus_wait_state(hub.game_ui, 1)
	accessibility.call("_input", controller_event)
	var restored_after_device_change := await _finish_focus_wait(hub.game_ui, restore_state)
	_check(restored_after_device_change and bool(hub.game_ui.call("get_accessibility_focus_snapshot").get("focus_inside_active_overlay", false)), "controller mode restores focus inside the active overlay")

	hub.game_ui.end_gameplay()
	hub.call("_on_settings_changed", original_settings)
	var audio: Node = hub.get("audio_service") as Node
	if audio != null and audio.has_method("dispose"):
		audio.call("dispose")
	if accessibility.has_method("dispose"):
		accessibility.call("dispose")
	hub.queue_free()
	for _frame in 40:
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


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
