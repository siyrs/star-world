extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://session-recovery-candidate.png"
const READY_FRAMES := 720
const MENU_FRAMES := 240
const CLEANUP_FRAMES := 60
const MARKER_PATH := "user://session_recovery.json"
const MARKER_SUFFIXES := ["", ".tmp", ".bak", ".recover", ".corrupt"]

var checks := 0
var failures: Array[String] = []
var _candidate_capture_path := ""
var _safe_quit_capture_path := ""
var _clean_capture_path := ""
var _report_path := ""
var _world_id := ""
var _expected_apples := 0
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clear_marker_files()
	_candidate_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_safe_quit_capture_path = _candidate_capture_path.get_base_dir().path_join(
		"session-recovery-safe-quit.png"
	)
	_clean_capture_path = _candidate_capture_path.get_base_dir().path_join(
		"session-recovery-clean-exit.png"
	)
	_report_path = _candidate_capture_path.get_base_dir().path_join(
		"session-recovery-report.json"
	)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	var first_game = GameScene.instantiate()
	first_game.application_exit_enabled = false
	root.add_child(first_game)
	for _frame in 8:
		await process_frame
	var first_hub := first_game.get("service_hub") as Node
	var first_save := first_hub.get("save_service") as Node if first_hub != null else null
	var first_recovery := (
		first_hub.get("world_session_recovery_service") as Node
		if first_hub != null
		else null
	)
	_check(
		first_hub != null and first_save != null and first_recovery != null,
		"first production process mounts the recovery composition"
	)
	if first_hub == null or first_save == null or first_recovery == null:
		await _finish(first_game, null, null)
		return
	var state: Dictionary = first_save.create_world(
		"Desktop Recovery %d" % Time.get_ticks_msec(),
		"star_continent",
		530729
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop recovery journey creates a real world")
	if _world_id.is_empty():
		await _finish(first_game, first_save, null)
		return
	first_game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(first_game, first_hub, _world_id),
		"first process reaches a playable world"
	)
	var apples_before := int(first_hub.inventory.call("count_item", "apple"))
	first_hub.inventory.call("add_item", "apple", 4)
	_expected_apples = apples_before + 4
	_check(
		bool(first_hub.call("save_current")),
		"first process writes a real checkpoint before interruption"
	)
	var interrupted_candidate: Dictionary = first_recovery.call(
		"get_recovery_candidate"
	)
	_check(
		str(interrupted_candidate.get("world_id", "")) == _world_id
		and int(interrupted_candidate.get("checkpoint_count", 0)) == 1,
		"active marker records the latest authoritative checkpoint"
	)
	await _simulate_abrupt_process_end(first_game, first_hub)
	_check(_marker_files_exist(), "abrupt process end intentionally leaves recovery evidence")

	var game = GameScene.instantiate()
	game.application_exit_enabled = false
	root.add_child(game)
	for _frame in 12:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var recovery := hub.get("world_session_recovery_service") as Node if hub != null else null
	var main_menu := hub.get("main_menu") as Node if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	_check(
		hub != null
		and save != null
		and recovery != null
		and main_menu != null
		and game_ui != null,
		"restarted production process mounts recovery, menu and safe-quit UI"
	)
	if hub == null or save == null or recovery == null or main_menu == null or game_ui == null:
		await _finish(game, save, hub)
		return
	main_menu.call("show_main")
	for _frame in 4:
		await process_frame
	var menu_snapshot: Dictionary = main_menu.call("get_visual_snapshot")
	var recovery_visual: Dictionary = menu_snapshot.get("session_recovery", {})
	_check(
		bool(recovery_visual.get("visible", false))
		and str(recovery_visual.get("candidate", {}).get("world_id", "")) == _world_id
		and int(recovery_visual.get("candidate", {}).get("checkpoint_count", 0)) == 1,
		"restart exposes exactly the interrupted world and checkpoint count"
	)
	_check(
		_rect_inside(recovery_visual.get("card_rect", Rect2()), Vector2(1280, 720)),
		"recovery command card remains inside the 1280x720 viewport"
	)
	await _capture(
		_candidate_capture_path,
		"abnormal-session recovery command screenshot is saved"
	)

	var recover_button := _find_button(main_menu, "恢复上次世界")
	_check(recover_button != null, "main menu exposes the real recovery command")
	if recover_button != null:
		await _click_control(recover_button)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"real mouse recovery command reloads the interrupted world"
	)
	_check(
		int(hub.inventory.call("count_item", "apple")) == _expected_apples,
		"recovery resumes from the latest authoritative inventory checkpoint"
	)

	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == 5
		and bool(hub.simulation_pause.call("is_paused")),
		"real Escape opens the production pause overlay"
	)
	var safe_quit_button := _find_button(game_ui, "保存并退出游戏")
	_check(safe_quit_button != null, "pause overlay exposes the safe desktop exit command")
	var safe_quit_visual: Dictionary = game_ui.call("get_visual_snapshot").get(
		"safe_quit", {}
	)
	_check(
		_rect_inside(safe_quit_visual.get("rect", Rect2()), Vector2(1280, 720)),
		"safe quit command remains inside the 1280x720 viewport"
	)
	await _capture(
		_safe_quit_capture_path,
		"safe save-and-quit pause command screenshot is saved"
	)
	if safe_quit_button != null:
		await _click_control(safe_quit_button)
	_check(
		await _wait_for_menu(hub),
		"safe desktop exit completes final save and world release"
	)
	var final_candidate: Dictionary = recovery.call("get_recovery_candidate")
	var final_menu_snapshot: Dictionary = main_menu.call("get_visual_snapshot")
	var final_recovery_visual: Dictionary = final_menu_snapshot.get("session_recovery", {})
	var status_label := _find_label(main_menu, "MenuStatus")
	_check(
		final_candidate.is_empty()
		and not bool(final_recovery_visual.get("visible", true))
		and not _marker_files_exist(),
		"clean final save removes the recovery card and every marker candidate"
	)
	_check(
		status_label != null and status_label.text.contains("可以安全退出"),
		"main menu confirms the completed final-save boundary"
	)
	var reloaded: Dictionary = save.load_world(_world_id)
	_check(
		_count_inventory_item(reloaded.get("inventory", {}), "apple") == _expected_apples,
		"safe quit persists the recovered world without losing checkpoint data"
	)
	await _capture(
		_clean_capture_path,
		"clean session exit screenshot is saved"
	)

	_report = {
		"schema_version":1,
		"world_id":_world_id,
		"expected_apples":_expected_apples,
		"interrupted_candidate":interrupted_candidate,
		"restarted_candidate":recovery_visual.get("candidate", {}),
		"application_quit":game.call("get_application_quit_snapshot"),
		"hub_quit":hub.call("get_application_quit_snapshot"),
		"final_candidate":final_candidate,
		"candidate_capture":_candidate_capture_path,
		"safe_quit_capture":_safe_quit_capture_path,
		"clean_capture":_clean_capture_path,
		"recovery_card_rect":_rect_to_dictionary(
			recovery_visual.get("card_rect", Rect2())
		),
		"safe_quit_button_rect":_rect_to_dictionary(
			safe_quit_visual.get("rect", Rect2())
		),
		"final_status":status_label.text if status_label != null else "",
	}
	_write_report()
	await _finish(game, save, hub)


func _simulate_abrupt_process_end(game: Node, hub: Node) -> void:
	if hub != null and hub.get("simulation_pause") != null:
		hub.simulation_pause.call("reset")
	var audio := hub.get("audio_service") as Node if hub != null else null
	if audio != null and audio.has_method("dispose"):
		audio.call("dispose")
	elif audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	if game != null and is_instance_valid(game):
		var world := game.get("world") as Node
		if world != null and world.has_method("clear_world"):
			world.call("clear_world")
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
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
		var menu := hub.get("main_menu") as Control
		if str(hub.get("current_world_id")).is_empty() and menu != null and menu.visible:
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
	if node is Button and node.text == label:
		return node as Button
	for child: Node in node.get_children():
		var result := _find_button(child, label)
		if result != null:
			return result
	return null


func _find_label(node: Node, node_name: String) -> Label:
	if node is Label and node.name == node_name:
		return node as Label
	for child: Node in node.get_children():
		var result := _find_label(child, node_name)
		if result != null:
			return result
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
		_check(false, "session recovery JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "session recovery JSON report is saved")


func _finish(game: Node, save: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if hub.get("simulation_pause") != null:
			hub.simulation_pause.call("reset")
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if (
		save != null
		and is_instance_valid(save)
		and not _world_id.is_empty()
		and bool(save.call("world_exists", _world_id))
	):
		save.call("delete_world", _world_id)
	_clear_marker_files()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA WORLD SESSION RECOVERY DESKTOP PASS | checks=%d | world=%s | candidate=%s | safe_quit=%s | clean=%s"
			% [checks, _world_id, _candidate_capture_path, _safe_quit_capture_path, _clean_capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD SESSION RECOVERY DESKTOP FAILURE: %s" % failure)
		print(
			"QA WORLD SESSION RECOVERY DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _clear_marker_files() -> void:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	for suffix: String in MARKER_SUFFIXES:
		var path := "%s%s" % [absolute_path, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _marker_files_exist() -> bool:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	for suffix: String in MARKER_SUFFIXES:
		if FileAccess.file_exists("%s%s" % [absolute_path, suffix]):
			return true
	return false


func _count_inventory_item(serialized: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized.get("slots", [])
	if raw_slots is not Array:
		return 0
	for raw_slot: Variant in raw_slots:
		if raw_slot is Dictionary and str(raw_slot.get("item_id", "")) == item_id:
			total += maxi(0, int(raw_slot.get("count", 0)))
	return total


func _rect_inside(rect: Rect2, viewport_size: Vector2) -> bool:
	return (
		rect.size.x > 0.0
		and rect.size.y > 0.0
		and rect.position.x >= -0.5
		and rect.position.y >= -0.5
		and rect.end.x <= viewport_size.x + 0.5
		and rect.end.y <= viewport_size.y + 0.5
	)


func _rect_to_dictionary(rect: Rect2) -> Dictionary:
	return {
		"x":rect.position.x,
		"y":rect.position.y,
		"width":rect.size.x,
		"height":rect.size.y,
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
