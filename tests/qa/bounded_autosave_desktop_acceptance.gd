extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://bounded-autosave-desktop.png"
const READY_FRAMES := 720
const CLEANUP_FRAMES := 36

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _settings_capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_settings_capture_path = "%s-settings.png" % _capture_path.get_basename()
	_report_path = "%s.json" % _capture_path.get_basename()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var main_menu := hub.get("main_menu") as Node if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	var runtime := hub.get("autosave_runtime_participant") as Node if hub != null else null
	_check(
		hub != null
		and save != null
		and main_menu != null
		and game_ui != null
		and runtime != null,
		"production game mounts settings, save, UI and bounded autosave runtime"
	)
	if hub == null or save == null or main_menu == null or game_ui == null or runtime == null:
		await _finish(game, hub, save, {}, runtime)
		return
	var original_settings: Dictionary = hub.current_settings.duplicate(true)

	var settings_panel := main_menu.get("_settings_panel") as Control
	var autosave_option := settings_panel.get("_autosave_interval") as OptionButton if settings_panel != null else null
	main_menu.call("_show_panel", settings_panel)
	await process_frame
	var option_ids := _option_ids(autosave_option)
	_check(
		settings_panel != null
		and settings_panel.visible
		and option_ids == [0, 2, 5, 10, 15],
		"real settings page exposes exactly the bounded autosave choices"
	)
	_check(
		settings_panel != null
		and _rect_inside(Rect2(Vector2.ZERO, Vector2(root.size)), settings_panel.get_global_rect()),
		"autosave settings remain inside the 1280x720 production viewport"
	)
	_check(
		await _capture(_settings_capture_path),
		"real autosave settings screenshot is saved"
	)
	main_menu.call("show_main")
	hub.main_menu.settings_changed.emit({"autosave_minutes":2})
	var configured: Dictionary = runtime.call("get_snapshot")
	_check(
		is_equal_approx(float(configured.get("interval_minutes", 0.0)), 2.0),
		"settings selection reaches the live production autosave runtime"
	)

	var state: Dictionary = save.call(
		"create_world",
		"Desktop-Autosave-%d" % Time.get_ticks_msec(),
		"star_continent",
		2672026
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop journey creates a temporary world")
	if _world_id.is_empty():
		await _finish(game, hub, save, original_settings, runtime)
		return
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a playable state"
	)
	if str(hub.get("current_world_id")) != _world_id:
		await _finish(game, hub, save, original_settings, runtime)
		return

	runtime.set_process(false)
	runtime.call("configure_interval_minutes", 0.02)
	var before_pause: Dictionary = runtime.call("get_snapshot")
	game_ui.call("toggle_pause")
	await process_frame
	_check(
		bool(hub.simulation_pause.call("is_paused")) and paused,
		"real pause overlay owns the SceneTree pause state"
	)
	_check(
		not bool(runtime.call("advance_active_time", 30.0)),
		"paused desktop time cannot schedule an automatic save"
	)
	var during_pause: Dictionary = runtime.call("get_snapshot")
	_check(
		is_equal_approx(
			float(during_pause.get("elapsed_active_seconds", -1.0)),
			float(before_pause.get("elapsed_active_seconds", 0.0))
		),
		"paused desktop time leaves the active countdown unchanged"
	)
	game_ui.call("toggle_pause")
	await process_frame
	_check(
		not bool(hub.simulation_pause.call("is_paused")) and not paused,
		"closing the real pause overlay resumes autosave eligibility"
	)

	var feedback: Node = hub.player_experience.call("get_feedback") as Node
	if feedback != null:
		feedback.call("clear")
	var apples_before := int(hub.inventory.call("count_item", "apple"))
	hub.inventory.call("add_item", "apple", 7)
	var completions: Array[Dictionary] = []
	runtime.connect(
		"autosave_completed",
		func(success: bool, snapshot: Dictionary) -> void:
			var evidence := snapshot.duplicate(true)
			evidence["signal_success"] = success
			completions.append(evidence)
	)
	_check(
		bool(runtime.call("advance_active_time", 1.21)),
		"unpaused active time schedules the production autosave"
	)
	for _frame in 4:
		await process_frame
	var final_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		completions.size() == 1
		and bool(completions[0].get("signal_success", false))
		and int(final_snapshot.get("success_count", 0)) >= 1,
		"one due desktop interval completes exactly one real save"
	)
	var loaded: Dictionary = save.call("load_world", _world_id)
	_check(
		_count_inventory_item(loaded.get("inventory", {}), "apple") == apples_before + 7,
		"real autosave persists the unsaved production inventory mutation"
	)
	_check(
		not loaded.has("autosave"),
		"real autosave leaves scheduling counters outside world.json"
	)
	var guidance := game_ui.call("get_guidance_overlay") as Node
	var toast_panel := guidance.get("_toast_panel") as Control if guidance != null else null
	var toast_label := guidance.get("_toast_label") as Label if guidance != null else null
	_check(
		toast_panel != null
		and toast_panel.visible
		and toast_label != null
		and toast_label.text == "世界已自动保存",
		"successful automatic checkpoint is visible in the real gameplay HUD"
	)
	_check(
		await _capture(_capture_path),
		"real gameplay autosave confirmation screenshot is saved"
	)

	_report = {
		"schema_version":1,
		"world_id":_world_id,
		"settings_option_ids":option_ids,
		"configured_snapshot":configured,
		"before_pause":before_pause,
		"during_pause":during_pause,
		"final_snapshot":final_snapshot,
		"completion_count":completions.size(),
		"persisted_apple_count":_count_inventory_item(
			loaded.get("inventory", {}), "apple"
		),
		"toast_text":toast_label.text if toast_label != null else "",
		"capture_path":_capture_path,
		"settings_capture_path":_settings_capture_path,
	}
	_write_report()
	await _finish(game, hub, save, original_settings, runtime)


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		if (
			world != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _option_ids(option: OptionButton) -> Array[int]:
	var ids: Array[int] = []
	if option == null:
		return ids
	for index in option.item_count:
		ids.append(option.get_item_id(index))
	return ids


func _count_inventory_item(serialized: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized.get("slots", [])
	if raw_slots is not Array:
		return 0
	for raw_slot: Variant in raw_slots:
		if raw_slot is Dictionary and str(raw_slot.get("item_id", "")) == item_id:
			total += maxi(0, int(raw_slot.get("count", 0)))
	return total


func _capture(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return image.save_png(path) == OK and FileAccess.file_exists(path)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "bounded autosave JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "bounded autosave JSON report is saved")


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


func _finish(
	game: Node,
	hub: Node,
	save: Node,
	original_settings: Dictionary,
	runtime: Node
) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if hub.get("simulation_pause") != null:
			hub.simulation_pause.call("reset")
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
		if not original_settings.is_empty():
			hub.main_menu.settings_changed.emit(original_settings)
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if save != null and is_instance_valid(save) and not _world_id.is_empty():
		if bool(save.call("world_exists", _world_id)):
			save.call("delete_world", _world_id)
	if runtime != null and is_instance_valid(runtime):
		runtime.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA BOUNDED AUTOSAVE DESKTOP PASS | checks=%d | world=%s | capture=%s"
			% [checks, _world_id, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED AUTOSAVE DESKTOP FAILURE: %s" % failure)
		print(
			"QA BOUNDED AUTOSAVE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
