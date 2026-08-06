extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://combat-feedback-intensity-settings.png"
const CLEANUP_FRAMES := 32

var checks := 0
var failures: Array[String] = []
var _settings_path := ""
var _hud_path := ""
var _report_path := ""


class FakeCombat:
	extends Node
	signal outgoing_attack_resolved(result: Dictionary)
	signal incoming_damage_resolved(result: Dictionary)
	signal attack_rejected(result: Dictionary)
	signal cooldown_changed(snapshot: Dictionary)

	func get_cooldown_snapshot() -> Dictionary:
		return {"ready":true, "ready_ratio":1.0}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_settings_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_hud_path = _settings_path.get_base_dir().path_join("combat-feedback-direction-text.png")
	_report_path = _settings_path.get_base_dir().path_join("combat-feedback-intensity-report.json")
	root.size = Vector2i(1280, 720)
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 8:
		await process_frame
	var original: Dictionary = hub.current_settings.duplicate(true)
	var menu: Control = hub.main_menu
	var settings: Control = menu.get("_settings_panel") as Control if menu != null else null
	_check(menu != null and settings != null, "production menu exposes the hardened settings workspace")
	if menu == null or settings == null:
		await _finish(hub, original, {})
		return
	menu.call("_show_panel", settings)
	for _frame in 4:
		await process_frame
	var intensity: OptionButton = settings.call("get_encounter_intensity_control")
	var pulses: CheckButton = settings.call("get_damage_direction_pulses_control")
	var impact: HSlider = settings.call("get_damage_camera_impact_control")
	_check(intensity != null and intensity.item_count == 3, "settings exposes exactly three versioned encounter intensities")
	_check(pulses != null, "settings exposes a local direction-pulse switch")
	_check(impact != null and is_equal_approx(impact.min_value, 0.0) and is_equal_approx(impact.max_value, 1.5), "settings exposes a bounded camera-impact slider")
	if intensity == null or pulses == null or impact == null:
		await _finish(hub, original, {})
		return
	_select_option_by_metadata(intensity, "high_risk")
	pulses.button_pressed = false
	impact.value = 0.4
	await RenderingServer.frame_post_draw
	_save_viewport(_settings_path, "combat feedback and encounter intensity settings screenshot")
	settings.call("_apply")
	for _frame in 5:
		await process_frame
	_check(str(hub.current_settings.get("encounter_intensity", "")) == "high_risk", "production settings persist high-risk encounter intensity")
	_check(not bool(hub.current_settings.get("show_damage_direction_pulses", true)), "production settings persist disabled visual pulses")
	_check(is_equal_approx(float(hub.current_settings.get("damage_camera_impact", 0.0)), 0.4), "production settings persist reduced camera impact")
	var director: Node = hub.get_node_or_null("HostileEncounterDirector")
	var director_snapshot: Dictionary = director.call("get_snapshot") if director != null else {}
	_check(str(director_snapshot.get("intensity_profile_id", "")) == "high_risk", "production encounter director receives the runtime intensity switch")

	menu.visible = false
	hub.game_ui.begin_gameplay()
	var combat := FakeCombat.new()
	root.add_child(combat)
	var overlay: Node = hub.game_ui.call("get_combat_feedback_overlay")
	_check(overlay != null, "production game UI exposes one combat feedback overlay")
	if overlay != null:
		overlay.call("setup", combat)
		overlay.call("apply_settings", hub.current_settings)
		overlay.call("set_active", true)
		combat.incoming_damage_resolved.emit({
			"final_damage":6.0,
			"absorbed":3.0,
			"source":"abyss_brute",
			"damage_direction":"rear",
		})
		for _frame in 3:
			await process_frame
	var overlay_snapshot: Dictionary = overlay.call("get_snapshot") if overlay != null else {}
	_check(int(overlay_snapshot.get("direction_indicator_pool_size", 0)) == 4, "production HUD keeps a fixed four-slot direction pool")
	_check(not bool(overlay_snapshot.get("direction_pulses_enabled", true)), "disabled pulse setting reaches the production HUD")
	_check(bool(overlay_snapshot.get("incoming_visible", false)), "accessible incoming-damage text remains visible when pulses are disabled")
	_check(str(overlay_snapshot.get("incoming_text", "")).contains("后方"), "production HUD localizes rear damage direction")
	_check(str(overlay_snapshot.get("incoming_text", "")).contains("护甲吸收 3.0"), "production HUD shows armour absorption")
	await RenderingServer.frame_post_draw
	_save_viewport(_hud_path, "combat feedback accessible text screenshot")
	combat.queue_free()
	await process_frame
	await _finish(hub, original, overlay_snapshot)


func _select_option_by_metadata(option: OptionButton, expected: String) -> void:
	if option == null:
		return
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == expected:
			option.select(index)
			return


func _save_viewport(path: String, description: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), description)


func _finish(hub: Node, original: Dictionary, overlay_snapshot: Dictionary) -> void:
	_write_report({
		"checks":checks,
		"failures":failures.duplicate(),
		"settings_capture":_settings_path,
		"hud_capture":_hud_path,
		"settings":hub.current_settings.duplicate(true) if hub != null else {},
		"overlay":overlay_snapshot.duplicate(true),
	})
	if hub != null and is_instance_valid(hub):
		hub.main_menu.settings_changed.emit(original)
		hub.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA COMBAT FEEDBACK INTENSITY DESKTOP PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA COMBAT FEEDBACK INTENSITY DESKTOP FAILURE: %s" % failure)
	print("QA COMBAT FEEDBACK INTENSITY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "combat feedback desktop report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "combat feedback desktop report is persisted")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
