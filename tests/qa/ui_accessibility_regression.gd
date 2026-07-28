extends SceneTree

const Policy = preload("res://src/settings/ui_accessibility_policy.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


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
	_check(
		Policy.allowed_scales() == [0.8, 1.0, 1.25, 1.5],
		"accessibility policy owns four stable interface scales"
	)
	_check(is_equal_approx(Policy.normalize_scale(null), 1.0), "invalid scale uses the canonical default")
	_check(is_equal_approx(Policy.normalize_scale(NAN), 1.0), "non-finite scale uses the canonical default")
	_check(is_equal_approx(Policy.normalize_scale(1.12), 1.0), "scale normalization chooses the nearest stable option")
	_check(is_equal_approx(Policy.normalize_scale(1.13), 1.25), "scale normalization advances after the midpoint")
	_check(Policy.scale_label(1.5) == "150%", "scale labels remain player-facing and deterministic")

	var joy_button := InputEventJoypadButton.new()
	joy_button.button_index = JOY_BUTTON_DPAD_DOWN
	joy_button.pressed = true
	_check(
		Policy.classify_event(joy_button) == Policy.MODE_CONTROLLER,
		"pressed joypad buttons select controller mode"
	)
	var quiet_axis := InputEventJoypadMotion.new()
	quiet_axis.axis = JOY_AXIS_LEFT_X
	quiet_axis.axis_value = 0.2
	_check(
		Policy.classify_event(quiet_axis, Policy.MODE_KEYBOARD) == Policy.MODE_KEYBOARD,
		"small stick drift does not steal the input mode"
	)
	var active_axis := InputEventJoypadMotion.new()
	active_axis.axis = JOY_AXIS_LEFT_X
	active_axis.axis_value = 0.8
	_check(
		Policy.classify_event(active_axis, Policy.MODE_MOUSE) == Policy.MODE_CONTROLLER,
		"intentional stick movement selects controller mode"
	)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(4.0, 0.0)
	_check(
		Policy.classify_event(mouse_motion, Policy.MODE_CONTROLLER) == Policy.MODE_MOUSE,
		"real mouse motion selects mouse mode"
	)
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	_check(
		Policy.classify_event(key, Policy.MODE_MOUSE) == Policy.MODE_KEYBOARD,
		"pressed keyboard input restores keyboard mode"
	)

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
	_check(
		str(hub.get_character_snapshot().get("ui_accessibility", {}).get("ui_scale_label", "")) == "125%",
		"character diagnostics expose the accessibility snapshot"
	)

	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_DPAD_DOWN
	joy.pressed = true
	accessibility.call("_input", joy)
	hub.main_menu.show_main()
	for _frame in 3:
		await process_frame
	var navigation: Dictionary = hub.main_menu.call("get_accessibility_navigation_snapshot")
	_check(str(navigation.get("input_mode", "")) == "controller", "controller mode reaches the production menu")
	_check(str(navigation.get("focus_text", "")) == "继续游戏", "controller mode restores the primary menu focus")

	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(6.0, 0.0)
	accessibility.call("_input", mouse)
	await process_frame
	_check(get_root().gui_get_focus_owner() == null, "mouse mode releases menu keyboard focus")

	accessibility.call("_input", joy)
	for _frame in 3:
		await process_frame
	_check(
		str(hub.main_menu.call("get_accessibility_navigation_snapshot").get("focus_text", "")) == "继续游戏",
		"returning to controller mode restores menu focus deterministically"
	)

	hub.game_ui.begin_gameplay()
	hub.game_ui.open_inventory()
	for _frame in 4:
		await process_frame
	var overlay_snapshot: Dictionary = hub.game_ui.call("get_accessibility_focus_snapshot")
	_check(int(overlay_snapshot.get("overlay", 0)) == 1, "production inventory overlay opens for accessibility focus")
	_check(bool(overlay_snapshot.get("focus_inside_game_ui", false)), "controller mode focuses a visible gameplay overlay control")

	accessibility.call("_input", mouse)
	await process_frame
	_check(get_root().gui_get_focus_owner() == null, "mouse mode releases gameplay overlay focus")
	accessibility.call("_input", joy)
	for _frame in 3:
		await process_frame
	_check(
		bool(hub.game_ui.call("get_accessibility_focus_snapshot").get("focus_inside_game_ui", false)),
		"controller mode restores gameplay overlay focus"
	)

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


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
