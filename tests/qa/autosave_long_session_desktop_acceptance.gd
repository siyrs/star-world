extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://autosave-long-session-backoff.png"
const READY_FRAMES := 720
const CLEANUP_FRAMES := 48
const TEN_MINUTES_SECONDS := 600.0

var checks := 0
var failures: Array[String] = []
var _backoff_capture := ""
var _recovered_capture := ""
var _report_path := ""
var _world_id := ""
var _authoritative_save: Node
var _failing_save: Node
var _report: Dictionary = {}


class FailingSaveService:
	extends Node

	func save_world(_world_id: String, _state: Dictionary) -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backoff_capture = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_recovered_capture = _backoff_capture.get_base_dir().path_join(
		"autosave-long-session-recovered.png"
	)
	_report_path = _backoff_capture.get_base_dir().path_join(
		"autosave-long-session-report.json"
	)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub := game.get("service_hub") as Node
	_authoritative_save = hub.get("save_service") as Node if hub != null else null
	var game_ui := hub.get("game_ui") as Node if hub != null else null
	var runtime := hub.get("autosave_runtime_participant") as Node if hub != null else null
	var health_report := hub.get("runtime_health_report_service") as Node if hub != null else null
	var diagnostics := game.get("runtime_diagnostics") as Node
	var overlay := diagnostics.get("overlay") as CanvasLayer if diagnostics != null else null
	_check(
		hub != null
		and _authoritative_save != null
		and game_ui != null
		and runtime != null
		and health_report != null
		and diagnostics != null
		and overlay != null,
		"production game mounts authoritative save, autosave, health and F3 services"
	)
	if (
		hub == null
		or _authoritative_save == null
		or game_ui == null
		or runtime == null
		or health_report == null
		or diagnostics == null
		or overlay == null
	):
		await _finish(game, hub)
		return

	var state: Dictionary = _authoritative_save.call(
		"create_world",
		"Autosave-Long-Session-%d" % Time.get_ticks_msec(),
		"star_continent",
		500729
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop endurance journey creates a temporary world")
	if _world_id.is_empty():
		await _finish(game, hub)
		return
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a playable state before accelerated checkpointing"
	)
	if str(hub.get("current_world_id")) != _world_id:
		await _finish(game, hub)
		return

	runtime.set_process(false)
	runtime.call("configure_interval_minutes", 10.0)
	var apples_before := int(hub.inventory.call("count_item", "apple"))
	for checkpoint_index in 8:
		hub.inventory.call("add_item", "apple", 1)
		_check(
			bool(runtime.call("advance_active_time", TEN_MINUTES_SECONDS)),
			"real long-session interval %d schedules one automatic checkpoint"
			% (checkpoint_index + 1)
		)
		await _settle_autosave()
	var eight_checkpoint_snapshot: Dictionary = runtime.call("get_snapshot")
	_check(
		int(eight_checkpoint_snapshot.get("success_count", 0)) == 8
		and int(eight_checkpoint_snapshot.get("attempt_count", 0)) == 8,
		"real long-session journey produces eight successful automatic checkpoints before manual save"
	)

	hub.inventory.call("add_item", "apple", 1)
	await _tap_key(KEY_ESCAPE)
	var save_button := _find_button(game_ui, "保存世界")
	_check(
		save_button != null and int(game_ui.call("get_active_overlay")) == 5,
		"real pause overlay exposes the authoritative manual save action"
	)
	if save_button != null:
		await _click_control(save_button)
	for _frame in 4:
		await process_frame
	await _tap_key(KEY_ESCAPE)
	var after_manual: Dictionary = runtime.call("get_snapshot")
	_check(
		int(after_manual.get("manual_reset_count", 0)) >= 1
		and is_equal_approx(
			float(after_manual.get("next_in_seconds", 0.0)),
			TEN_MINUTES_SECONDS
		),
		"real pause button interleaves one manual checkpoint without duplicate autosave"
	)

	_failing_save = FailingSaveService.new()
	_failing_save.name = "DesktopLongSessionFailingSave"
	hub.add_child(_failing_save)
	hub.set("save_service", _failing_save)
	hub.inventory.call("add_item", "apple", 3)
	_check(
		bool(runtime.call("advance_active_time", TEN_MINUTES_SECONDS)),
		"post-manual interval reaches the real autosave failure path"
	)
	await _settle_autosave()
	for retry_delay: float in [15.0, 60.0]:
		_check(
			bool(runtime.call("advance_active_time", retry_delay)),
			"real failed autosave waits %.0f active seconds before retry" % retry_delay
		)
		await _settle_autosave()
	var failed_runtime: Dictionary = runtime.call("get_snapshot")
	_check(
		int(failed_runtime.get("consecutive_failure_count", 0)) == 3
		and is_equal_approx(
			float(failed_runtime.get("last_retry_delay_seconds", 0.0)),
			300.0
		),
		"three real autosave failures reach the bounded 300-second retry tier"
	)

	await _tap_key(KEY_F3)
	var backoff_text := str(overlay.call("get_display_text"))
	_check(
		backoff_text.contains("连续失败 3 次")
		and backoff_text.contains("5分00秒后重试"),
		"F3 exposes the active three-failure backoff without stale success text"
	)
	var backoff_rect: Rect2 = overlay.call("get_panel_rect")
	_check(
		_rect_inside(Rect2(Vector2.ZERO, Vector2(root.size)), backoff_rect),
		"backoff F3 panel remains inside the 1280x720 viewport"
	)
	await _capture(_backoff_capture, "autosave long-session backoff screenshot is saved")
	await _tap_key(KEY_F3)

	hub.set("save_service", _authoritative_save)
	_failing_save.queue_free()
	_failing_save = null
	await process_frame
	_check(
		bool(runtime.call("advance_active_time", 300.0)),
		"restored authoritative save schedules exactly one recovery checkpoint"
	)
	await _settle_autosave()
	var recovered_runtime: Dictionary = runtime.call("get_snapshot")
	var timeline: Dictionary = health_report.call("get_save_timeline_snapshot")
	var counts: Dictionary = timeline.get("reason_counts", {})
	_check(
		int(recovered_runtime.get("attempt_count", 0)) == 12
		and int(recovered_runtime.get("success_count", 0)) == 9
		and int(recovered_runtime.get("failure_count", 0)) == 3
		and int(recovered_runtime.get("consecutive_failure_count", -1)) == 0,
		"successful retry clears failure pressure with exact long-session counters"
	)
	_check(
		int(counts.get("manual", 0)) == 1
		and int(counts.get("autosave", 0)) == 12
		and int(timeline.get("history_count", 0)) == 12
		and int(timeline.get("history_dropped_count", 0)) == 1,
		"history rolls over to twelve with one exact dropped checkpoint"
	)
	var loaded: Dictionary = _authoritative_save.call("load_world", _world_id)
	var persisted_apples := _count_inventory_item(
		loaded.get("inventory", {}), "apple"
	)
	_check(
		persisted_apples == apples_before + 12,
		"successful retry clears failure pressure and persists all delayed mutations"
	)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("autosave_schedule")
		and not serialized.contains("carried_overshoot"),
		"desktop authoritative payload excludes all fixed-point schedule diagnostics"
	)

	await _tap_key(KEY_F3)
	var recovered_text := str(overlay.call("get_display_text"))
	_check(
		recovered_text.contains("最近检查点：自动保存成功")
		and recovered_text.contains("本次 12")
		and recovered_text.contains("已丢弃 1")
		and not recovered_text.contains("连续失败"),
		"recovered F3 shows the exact bounded history and latest successful autosave"
	)
	var recovered_rect: Rect2 = overlay.call("get_panel_rect")
	_check(
		_rect_inside(Rect2(Vector2.ZERO, Vector2(root.size)), recovered_rect),
		"recovered F3 panel remains inside the 1280x720 viewport"
	)
	await _capture(_recovered_capture, "autosave long-session recovery screenshot is saved")

	_report = {
		"schema_version":1,
		"world_id":_world_id,
		"apples_before":apples_before,
		"persisted_apples":persisted_apples,
		"backoff_runtime":failed_runtime,
		"recovered_runtime":recovered_runtime,
		"timeline":timeline,
		"backoff_f3_text":backoff_text,
		"recovered_f3_text":recovered_text,
		"backoff_panel_rect":_rect_to_dictionary(backoff_rect),
		"recovered_panel_rect":_rect_to_dictionary(recovered_rect),
		"backoff_capture":_backoff_capture,
		"recovered_capture":_recovered_capture,
	}
	_write_report()
	await _finish(game, hub)


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


func _settle_autosave() -> void:
	for _frame in 6:
		await process_frame


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
	_check(
		image != null and not image.is_empty(),
		"%s renders a non-empty viewport" % description
	)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(
		image.save_png(path) == OK and FileAccess.file_exists(path),
		description
	)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "autosave long-session JSON report opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(
		FileAccess.file_exists(_report_path),
		"autosave long-session JSON report is saved"
	)


func _count_inventory_item(serialized_inventory: Dictionary, item_id: String) -> int:
	var total := 0
	var raw_slots: Variant = serialized_inventory.get("slots", [])
	if raw_slots is not Array:
		return 0
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


func _rect_to_dictionary(rect: Rect2) -> Dictionary:
	return {
		"x":rect.position.x,
		"y":rect.position.y,
		"width":rect.size.x,
		"height":rect.size.y,
	}


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if _authoritative_save != null and is_instance_valid(_authoritative_save):
			hub.set("save_service", _authoritative_save)
		if _failing_save != null and is_instance_valid(_failing_save):
			_failing_save.queue_free()
			_failing_save = null
		var diagnostics := game.get("runtime_diagnostics") as Node if game != null else null
		var overlay := diagnostics.get("overlay") as CanvasLayer if diagnostics != null else null
		if (
			overlay != null
			and overlay.has_method("is_overlay_visible")
			and bool(overlay.call("is_overlay_visible"))
			and overlay.has_method("set_overlay_visible")
		):
			overlay.call("set_overlay_visible", false)
		var simulation_pause := hub.get("simulation_pause") as Node
		if simulation_pause != null:
			simulation_pause.call("reset")
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
	if (
		_authoritative_save != null
		and is_instance_valid(_authoritative_save)
		and not _world_id.is_empty()
		and bool(_authoritative_save.call("world_exists", _world_id))
	):
		_authoritative_save.call("delete_world", _world_id)
	if hub != null and is_instance_valid(hub):
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
		var accessibility := hub.get("ui_accessibility") as Node
		if accessibility != null and accessibility.has_method("dispose"):
			accessibility.call("dispose")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA AUTOSAVE LONG SESSION DESKTOP PASS | checks=%d | world=%s | backoff=%s | recovered=%s"
			% [checks, _world_id, _backoff_capture, _recovered_capture]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA AUTOSAVE LONG SESSION DESKTOP FAILURE: %s" % failure)
	print(
		"QA AUTOSAVE LONG SESSION DESKTOP FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
