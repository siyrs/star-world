extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://experience-hardening-desktop.png"

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 6:
		await process_frame
	var menu: Node = hub.get("main_menu") as Node
	var settings: Control = menu.get("_settings_panel") as Control if menu != null else null
	_check(menu != null and settings != null, "production service hub exposes the real settings workspace")
	if menu == null or settings == null:
		await _finish(hub, {})
		return
	var original_settings: Dictionary = hub.current_settings.duplicate(true)
	menu.call("_show_panel", settings)
	for _frame in 4:
		await process_frame
	var difficulty := settings.get("_survival_difficulty") as OptionButton
	var camera_bob := settings.get("_camera_bob") as CheckButton
	_check(
		difficulty != null and difficulty.item_count == 3,
		"settings renders exactly three bounded survival difficulty choices"
	)
	_check(
		camera_bob != null and camera_bob.visible,
		"camera motion accessibility remains visible beside the new difficulty control"
	)
	var labels: Array[String] = []
	if difficulty != null:
		for index in difficulty.item_count:
			labels.append(difficulty.get_item_text(index))
	_check(
		labels == ["轻松建造", "平衡生存", "挑战生存"],
		"difficulty choices use direct player-facing labels"
	)
	_select_difficulty(difficulty, "balanced")
	var actions: Array[Button] = settings.call("get_action_buttons")
	var apply_button: Button = actions[0] if not actions.is_empty() else null
	_check(apply_button != null and apply_button.visible, "fixed save-and-apply action remains visible at 1024x576")
	if apply_button != null:
		await _click_control(apply_button)
	for _frame in 5:
		await process_frame
	var tuning: Dictionary = hub.survival.call("get_tuning_snapshot")
	_check(
		str(hub.current_settings.get("survival_difficulty", "")) == "balanced"
		and str(tuning.get("profile_id", "")) == "balanced",
		"real pointer input applies balanced difficulty through the authoritative settings path"
	)
	_check(
		is_equal_approx(float(tuning.get("passive_hunger_interval", 0.0)), 70.0)
		and is_equal_approx(float(tuning.get("starvation_damage_interval", 0.0)), 4.0),
		"production survival service receives the selected balanced tuning"
	)
	var layout: Dictionary = settings.call("get_layout_snapshot")
	var panel_rect: Rect2 = layout.get("panel_rect", Rect2())
	var design_viewport_rect: Rect2 = menu.get_viewport_rect()
	var physical_viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var physical_panel_rect := _scale_rect_to_physical(
		panel_rect,
		design_viewport_rect.size,
		Vector2(root.size)
	)
	_check(
		design_viewport_rect.encloses(panel_rect),
		"settings workspace remains fully inside the design viewport"
	)
	_check(
		physical_viewport_rect.encloses(physical_panel_rect),
		"settings workspace remains fully inside the rendered 1024x576 viewport"
	)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the hardened settings experience")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "desktop evidence uses the requested 1024x576 physical resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "desktop evidence screenshot is saved")
	var report := {
		"checks": checks,
		"failures": failures.duplicate(),
		"physical_viewport": [root.size.x, root.size.y],
		"design_viewport": [design_viewport_rect.size.x, design_viewport_rect.size.y],
		"difficulty_labels": labels,
		"selected_profile": str(tuning.get("profile_id", "")),
		"passive_hunger_interval": float(tuning.get("passive_hunger_interval", 0.0)),
		"starvation_damage_interval": float(tuning.get("starvation_damage_interval", 0.0)),
		"design_panel_rect": _rect_to_array(panel_rect),
		"physical_panel_rect": _rect_to_array(physical_panel_rect),
	}
	_write_report(report)
	await _finish(hub, original_settings)


func _select_difficulty(option: OptionButton, profile_id: String) -> void:
	if option == null:
		return
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == profile_id:
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
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func _scale_rect_to_physical(
	design_rect: Rect2,
	design_size: Vector2,
	physical_size: Vector2
) -> Rect2:
	if design_size.x <= 0.0 or design_size.y <= 0.0:
		return Rect2()
	var scale := Vector2(
		physical_size.x / design_size.x,
		physical_size.y / design_size.y
	)
	return Rect2(design_rect.position * scale, design_rect.size * scale)


func _rect_to_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _write_report(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "desktop JSON report can be opened")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "desktop JSON report is saved")


func _finish(hub: Node, original_settings: Dictionary) -> void:
	if hub != null and is_instance_valid(hub):
		if not original_settings.is_empty():
			hub.main_menu.settings_changed.emit(original_settings)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		hub.queue_free()
	for _frame in 8:
		await process_frame
	if failures.is_empty():
		print("QA EXPERIENCE HARDENING DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA EXPERIENCE HARDENING DESKTOP FAILURE: %s" % failure)
	print("QA EXPERIENCE HARDENING DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
