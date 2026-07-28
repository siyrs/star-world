extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://save-checkpoint-session-isolation.png"
const READY_FRAMES := 720
const MENU_FRAMES := 240
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _first_capture_path := ""
var _reentry_capture_path := ""
var _report_path := ""
var _world_ids: Array[String] = []
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_first_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_reentry_capture_path = _first_capture_path.get_base_dir().path_join(
		"save-checkpoint-same-world-reentry.png"
	)
	_report_path = _first_capture_path.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	var autosave := hub.get("autosave_runtime_participant") as Node if hub != null else null
	var report := hub.get("runtime_health_report_service") as Node if hub != null else null
	var diagnostics := game.get("runtime_diagnostics") as Node
	_check(
		hub != null
		and save != null
		and game_ui != null
		and autosave != null
		and report != null
		and diagnostics != null,
		"production game mounts the session-scoped save and F3 composition"
	)
	if (
		hub == null
		or save == null
		or game_ui == null
		or autosave == null
		or report == null
		or diagnostics == null
	):
		await _finish(game, hub, save)
		return
	autosave.set_process(false)

	var state_a: Dictionary = save.call(
		"create_world",
		"Checkpoint-Session-A-%d" % Time.get_ticks_msec(),
		"star_continent",
		490731
	)
	var state_b: Dictionary = save.call(
		"create_world",
		"Checkpoint-Session-B-%d" % Time.get_ticks_msec(),
		"desert_ruins",
		490732
	)
	var world_a := str(state_a.get("metadata", {}).get("id", ""))
	var world_b := str(state_b.get("metadata", {}).get("id", ""))
	for world_id: String in [world_a, world_b]:
		if not world_id.is_empty():
			_world_ids.append(world_id)
	_check(
		not world_a.is_empty() and not world_b.is_empty() and world_a != world_b,
		"desktop session journey creates two independent production worlds"
	)
	if world_a.is_empty() or world_b.is_empty():
		await _finish(game, hub, save)
		return

	game.call("begin_world_state", state_a)
	_check(
		await _wait_for_world_ready(game, hub, world_a),
		"world A reaches a playable first entry"
	)
	await _open_pause_and_save(game_ui, hub)
	var first_a_timeline: Dictionary = report.call("get_save_timeline_snapshot")
	_check(
		int(first_a_timeline.get("current_session_history_count", 0)) == 1
		and str(first_a_timeline.get("last_current_session_event", {}).get("reason", "")) == "manual",
		"real pause save belongs to world A first entry"
	)
	await _tap_key(KEY_ESCAPE)
	_check(int(game_ui.call("get_active_overlay")) == 0, "world A resumes before leaving")
	hub.call("return_to_menu")
	_check(
		await _wait_for_menu(hub),
		"world A final save completes before the next world entry"
	)

	game.call("begin_world_state", state_b)
	_check(
		await _wait_for_world_ready(game, hub, world_b),
		"world B reaches a playable first entry"
	)
	var world_b_empty: Dictionary = report.call("get_save_timeline_snapshot")
	_check(
		int(world_b_empty.get("history_count", 0)) >= 2
		and int(world_b_empty.get("current_session_history_count", -1)) == 0
		and int(world_b_empty.get("current_world_session_sequence", 0)) == 2,
		"world B keeps global A evidence but starts with no current-entry checkpoint"
	)
	var overlay := diagnostics.get("overlay") as CanvasLayer
	await _tap_key(KEY_F3)
	var world_b_display := str(overlay.call("get_display_text")) if overlay != null else ""
	_check(
		overlay != null and bool(overlay.call("is_overlay_visible")),
		"real F3 input opens on world B before its first save"
	)
	_check(
		world_b_display.contains("检查点历史：本次 0")
		and world_b_display.contains("当前世界本次进入尚无保存记录")
		and not world_b_display.contains("最近检查点：手动保存成功")
		and not world_b_display.contains("最近检查点：返回主菜单保存成功"),
		"world B F3 never falls back to world A checkpoints"
	)
	await _capture(_first_capture_path, "cross-world checkpoint isolation screenshot is saved")
	await _tap_key(KEY_F3)
	hub.call("return_to_menu")
	_check(
		await _wait_for_menu(hub),
		"world B final save completes before same-world re-entry"
	)

	var reloaded_a: Dictionary = save.call("load_world", world_a)
	_check(not reloaded_a.is_empty(), "world A reloads from its authoritative save")
	game.call("begin_world_state", reloaded_a)
	_check(
		await _wait_for_world_ready(game, hub, world_a),
		"world A reaches a playable second entry"
	)
	var world_a_reentry: Dictionary = report.call("get_save_timeline_snapshot")
	_check(
		int(world_a_reentry.get("history_count", 0)) >= 3
		and int(world_a_reentry.get("current_session_history_count", -1)) == 0
		and int(world_a_reentry.get("current_world_session_sequence", 0)) == 3,
		"same world ID re-entry excludes checkpoints from world A first entry"
	)
	await _tap_key(KEY_F3)
	var world_a_reentry_display := str(overlay.call("get_display_text")) if overlay != null else ""
	_check(
		world_a_reentry_display.contains("检查点历史：本次 0")
		and world_a_reentry_display.contains("当前世界本次进入尚无保存记录"),
		"same-world re-entry F3 visibly starts from an empty checkpoint scope"
	)
	await _capture(
		_reentry_capture_path,
		"same-world re-entry checkpoint isolation screenshot is saved"
	)
	await _tap_key(KEY_F3)
	await _open_pause_and_save(game_ui, hub)
	var final_timeline: Dictionary = report.call("get_save_timeline_snapshot")
	var current_history: Array = final_timeline.get("current_session_history", [])
	_check(
		current_history.size() == 1
		and str(final_timeline.get("last_current_session_event", {}).get("reason", "")) == "manual"
		and int(final_timeline.get("last_current_session_event", {}).get("sequence", 0))
		> int(final_timeline.get("current_world_session_started_after_sequence", 0)),
		"world A second entry accepts exactly its new real manual checkpoint"
	)

	_report = {
		"schema_version":1,
		"world_a":world_a,
		"world_b":world_b,
		"world_b_empty_timeline":world_b_empty,
		"world_a_reentry_timeline":world_a_reentry,
		"final_timeline":final_timeline,
		"world_b_f3_text":world_b_display,
		"world_a_reentry_f3_text":world_a_reentry_display,
		"cross_world_capture":_first_capture_path,
		"same_world_reentry_capture":_reentry_capture_path,
	}
	_write_report()
	await _finish(game, hub, save)


func _open_pause_and_save(game_ui: Node, hub: Node) -> void:
	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == 5
		and bool(hub.simulation_pause.call("is_paused")),
		"real Escape opens the pause overlay for authoritative manual save"
	)
	var save_button := _find_button(game_ui, "保存世界")
	_check(save_button != null, "pause overlay exposes the production save command")
	if save_button != null:
		await _click_control(save_button)
	for _frame in 3:
		await process_frame


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


func _wait_for_menu(hub: Node) -> bool:
	for _frame in MENU_FRAMES:
		await process_frame
		if hub == null or not is_instance_valid(hub):
			return false
		var main_menu := hub.get("main_menu") as Control
		if str(hub.get("current_world_id")).is_empty() and main_menu != null and main_menu.visible:
			return true
	return false


func _tap_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _find_button(node: Node, label: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and child.text == label:
			return child
		var nested := _find_button(child, label)
		if nested != null:
			return nested
	return null


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


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s renders a non-empty viewport" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image.save_png(path) == OK and FileAccess.file_exists(path), description)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "world-scoped checkpoint JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "world-scoped checkpoint JSON report is saved")


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if hub.get("simulation_pause") != null:
			hub.simulation_pause.call("reset")
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if save != null and is_instance_valid(save):
		for world_id: String in _world_ids:
			if bool(save.call("world_exists", world_id)):
				save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA WORLD-SCOPED SAVE CHECKPOINT SESSION DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _first_capture_path]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA WORLD-SCOPED SAVE CHECKPOINT SESSION DESKTOP FAILURE: %s" % failure)
	print(
		"QA WORLD-SCOPED SAVE CHECKPOINT SESSION DESKTOP FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
