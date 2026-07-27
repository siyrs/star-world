extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://save-checkpoint-timeline-desktop.png"
const READY_FRAMES := 720
const CLEANUP_FRAMES := 36

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
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
		"production game mounts save, autosave, timeline and F3 services"
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
	var state: Dictionary = save.call(
		"create_world",
		"Checkpoint-Timeline-%d" % Time.get_ticks_msec(),
		"star_continent",
		260743
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop timeline journey creates a temporary world")
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a playable state"
	)
	if str(hub.get("current_world_id")) != _world_id:
		await _finish(game, hub, save)
		return

	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == 5
		and bool(hub.simulation_pause.call("is_paused")),
		"real Escape input opens the pause overlay and pauses simulation"
	)
	var save_button := _find_button(game_ui, "保存世界")
	_check(save_button != null, "pause overlay exposes the real manual save button")
	if save_button != null:
		await _click_control(save_button)
	for _frame in 3:
		await process_frame
	var manual_timeline: Dictionary = report.call("get_save_timeline_snapshot")
	_check(
		int(manual_timeline.get("reason_counts", {}).get("manual", 0)) == 1
		and str(manual_timeline.get("last_event", {}).get("reason", "")) == "manual",
		"real pause save is classified as one manual checkpoint"
	)
	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == 0
		and not bool(hub.simulation_pause.call("is_paused")),
		"second Escape resumes gameplay before automatic checkpointing"
	)

	autosave.set_process(false)
	autosave.call("configure_interval_minutes", 0.02)
	var apples_before := int(hub.inventory.call("count_item", "apple"))
	hub.inventory.call("add_item", "apple", 5)
	_check(
		bool(autosave.call("advance_active_time", 1.21)),
		"unpaused active time schedules the real autosave transaction"
	)
	for _frame in 5:
		await process_frame
	var timeline: Dictionary = report.call("get_save_timeline_snapshot")
	var counts: Dictionary = timeline.get("reason_counts", {})
	_check(
		int(counts.get("manual", 0)) == 1
		and int(counts.get("autosave", 0)) == 1
		and int(timeline.get("history_count", 0)) == 2,
		"timeline correlates one real manual and one real automatic checkpoint"
	)
	_check(
		str(timeline.get("last_current_world_event", {}).get("reason", "")) == "autosave"
		and bool(timeline.get("last_current_world_event", {}).get("success", false)),
		"latest current-world checkpoint is the successful automatic save"
	)
	var loaded: Dictionary = save.call("load_world", _world_id)
	_check(
		_count_inventory_item(loaded.get("inventory", {}), "apple") == apples_before + 5,
		"automatic checkpoint persists the unsaved production inventory mutation"
	)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("save_timeline")
		and not serialized.contains("checkpoint_history")
		and not serialized.contains("save_checkpoint"),
		"real world payload excludes all transient checkpoint history"
	)

	var overlay := diagnostics.get("overlay") as CanvasLayer
	await _tap_key(KEY_F3)
	_check(
		overlay != null and bool(overlay.call("is_overlay_visible")),
		"real F3 input opens the checkpoint-aware health surface"
	)
	var display := str(overlay.call("get_display_text")) if overlay != null else ""
	for phrase: String in [
		"保存来源",
		"手动 1",
		"自动 1",
		"检查点历史",
		"最近检查点：自动保存成功",
		"自动保存：",
	]:
		_check(display.contains(phrase), "real F3 timeline renders %s" % phrase)
	var panel_rect: Rect2 = overlay.call("get_panel_rect") if overlay != null else Rect2()
	_check(
		_rect_inside(Rect2(Vector2.ZERO, Vector2(root.size)), panel_rect),
		"checkpoint-aware F3 panel remains inside the 1280x720 viewport"
	)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the save timeline")
	if image != null and not image.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		_check(
			image.save_png(_capture_path) == OK and FileAccess.file_exists(_capture_path),
			"save checkpoint timeline screenshot is saved"
		)

	_report = {
		"schema_version":1,
		"world_id":_world_id,
		"timeline":timeline,
		"persisted_apple_count":_count_inventory_item(
			loaded.get("inventory", {}), "apple"
		),
		"f3_text":display,
		"panel_rect":{
			"x":panel_rect.position.x,
			"y":panel_rect.position.y,
			"width":panel_rect.size.x,
			"height":panel_rect.size.y,
		},
		"capture_path":_capture_path,
	}
	_write_report()
	await _finish(game, hub, save)


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


func _count_inventory_item(serialized_inventory: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized_inventory.get("slots", [])
	if raw_slots is not Array:
		return total
	for raw_slot: Variant in raw_slots:
		if raw_slot is Dictionary and str(raw_slot.get("item_id", "")) == item_id:
			total += maxi(0, int(raw_slot.get("count", 0)))
	return total


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "save checkpoint JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "save checkpoint JSON report is saved")


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
	if save != null and is_instance_valid(save) and not _world_id.is_empty():
		if bool(save.call("world_exists", _world_id)):
			save.call("delete_world", _world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA SAVE CHECKPOINT TIMELINE DESKTOP PASS | checks=%d | world=%s | capture=%s"
			% [checks, _world_id, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE CHECKPOINT TIMELINE DESKTOP FAILURE: %s" % failure)
		print(
			"QA SAVE CHECKPOINT TIMELINE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
