extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://runtime-health-report-desktop.png"
const READY_FRAMES := 600
const SETTLE_FRAMES := 180
const CLEANUP_FRAMES := 30

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
	for _frame in 6:
		await process_frame
	var hub := game.get("service_hub") as Node
	var save := hub.get("save_service") as Node if hub != null else null
	var diagnostics := game.get("runtime_diagnostics") as Node
	var report_service := hub.get("runtime_health_report_service") as Node if hub != null else null
	_check(
		hub != null and save != null and diagnostics != null and report_service != null,
		"production game mounts save, diagnostics and the stable runtime health service",
	)
	_check(
		hub != null and hub.get_node_or_null("RuntimeHealthReport") == report_service,
		"final service hub exposes the stable RuntimeHealthReport node",
	)
	if hub == null or save == null or diagnostics == null or report_service == null:
		await _finish(game, hub, save)
		return

	var state: Dictionary = save.call(
		"create_world",
		"Runtime-Health-%d" % Time.get_ticks_msec(),
		"star_continent",
		93172026,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop health journey creates a temporary world")
	game.call("begin_world_state", state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a playable state",
	)
	if str(hub.get("current_world_id")) != _world_id:
		await _finish(game, hub, save)
		return
	for _frame in SETTLE_FRAMES:
		await process_frame

	var saved := bool(hub.call("save_current"))
	_check(saved, "real service-hub save transaction succeeds")
	var save_snapshot: Dictionary = report_service.call("get_save_snapshot")
	_check(
		int(save_snapshot.get("attempt_count", 0)) >= 1
		and int(save_snapshot.get("success_count", 0)) >= 1
		and bool(save_snapshot.get("last_success", false)),
		"health service records a successful real save attempt",
	)
	_check(
		int(save_snapshot.get("last_bytes", 0)) > 0
		and float(save_snapshot.get("last_elapsed_milliseconds", 0.0)) > 0.0,
		"health service records measurable save bytes and duration",
	)

	var catalog_path := "user://worlds/%s/catalog.json" % _world_id
	_check(FileAccess.file_exists(catalog_path), "real save creates the derived catalog sidecar")
	_remove_file(catalog_path)
	_check(not FileAccess.file_exists(catalog_path), "desktop journey removes one catalog sidecar")
	save.call("reset_catalog_diagnostics")
	var listed: Array = save.call("list_worlds")
	var catalog_warning: Dictionary = save.call("get_catalog_diagnostics")
	_check(_contains_world(listed, _world_id), "authoritative fallback keeps the world visible")
	_check(
		int(catalog_warning.get("last_fallback_count", 0)) >= 1
		and int(catalog_warning.get("last_repair_count", 0)) >= 1,
		"missing sidecar triggers real fallback and self-healing repair",
	)
	_check(FileAccess.file_exists(catalog_path), "catalog self-healing recreates the sidecar")

	var warning_snapshot: Dictionary = diagnostics.call("sample_now")
	var operations: Dictionary = warning_snapshot.get("operations", {})
	_check(
		operations is Dictionary and str(operations.get("status", "")) in ["warning", "critical"],
		"telemetry raises operational health for the real catalog fallback",
	)
	_check(
		int(operations.get("save", {}).get("last_bytes", 0)) > 0
		and int(operations.get("catalog", {}).get("last_repair_count", 0)) >= 1,
		"one bounded telemetry snapshot combines save and catalog repair evidence",
	)
	var primary: Dictionary = operations.get("primary_bottleneck", {})
	_check(
		str(primary.get("id", "")) == "catalog",
		"catalog self-healing becomes the deterministic primary operational bottleneck",
	)
	var serialized := JSON.stringify(operations)
	for forbidden: String in [
		"block_overrides",
		"crop_counts",
		"species_counts",
		"participant_dependencies",
		"domain_summaries",
	]:
		_check(not serialized.contains(forbidden), "desktop projection excludes %s" % forbidden)

	var overlay := diagnostics.get("overlay") as CanvasLayer
	_check(overlay != null, "production diagnostics coordinator exposes the F3 overlay")
	await _press_f3()
	_check(overlay != null and bool(overlay.call("is_overlay_visible")), "real F3 input opens the unified health report")
	var display := str(overlay.call("get_display_text")) if overlay != null else ""
	for phrase: String in [
		"F3 运行诊断",
		"F3 运行与保存健康",
		"主要压力",
		"世界目录",
		"保存会话",
		"目录累计",
	]:
		_check(display.contains(phrase), "real F3 surface renders %s" % phrase)
	var panel_rect: Rect2 = overlay.call("get_panel_rect") if overlay != null else Rect2()
	_check(
		_rect_inside(Rect2(Vector2.ZERO, Vector2(root.size)), panel_rect),
		"two-column F3 panel remains inside the 1280x720 viewport",
	)
	_check(_all_controls_are_passthrough(overlay), "real F3 health surface cannot intercept mouse input")

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the unified health surface")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "runtime health evidence uses 1280x720 resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var image_error := image.save_png(_capture_path)
		_check(
			image_error == OK and FileAccess.file_exists(_capture_path),
			"runtime health screenshot is saved",
		)

	save.call("reset_catalog_diagnostics")
	save.call("list_worlds")
	var steady_snapshot: Dictionary = diagnostics.call("sample_now")
	var steady_operations: Dictionary = steady_snapshot.get("operations", {})
	_check(
		int(steady_operations.get("catalog", {}).get("last_fallback_count", -1)) == 0
		and int(steady_operations.get("catalog", {}).get("last_hit_count", 0)) >= 1,
		"next catalog scan returns to steady sidecar hits without another fallback",
	)

	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"save": save_snapshot,
		"catalog_warning": catalog_warning,
		"warning_operations": operations,
		"steady_operations": steady_operations,
		"panel_rect": {
			"x": panel_rect.position.x,
			"y": panel_rect.position.y,
			"width": panel_rect.size.x,
			"height": panel_rect.size.y,
		},
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


func _press_f3() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_F3
	press.physical_keycode = KEY_F3
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = KEY_F3
	release.physical_keycode = KEY_F3
	release.pressed = false
	root.push_input(release)
	await process_frame


func _contains_world(worlds: Array, world_id: String) -> bool:
	for raw_metadata: Variant in worlds:
		if raw_metadata is Dictionary and str(raw_metadata.get("id", "")) == world_id:
			return true
	return false


func _remove_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rect_inside(container_rect: Rect2, candidate: Rect2) -> bool:
	return (
		candidate.size.x > 0.0
		and candidate.size.y > 0.0
		and candidate.position.x >= container_rect.position.x
		and candidate.position.y >= container_rect.position.y
		and candidate.end.x <= container_rect.end.x
		and candidate.end.y <= container_rect.end.y
	)


func _all_controls_are_passthrough(node: Node) -> bool:
	if node == null:
		return false
	if node is Control:
		if node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE:
			return false
	for child: Node in node.get_children():
		if not _all_controls_are_passthrough(child):
			return false
	return true


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "runtime health JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "runtime health JSON report is saved")


func _finish(game: Node, hub: Node, save: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if save != null and is_instance_valid(save) and not _world_id.is_empty():
		save.call("delete_world", _world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA RUNTIME HEALTH DESKTOP PASS | checks=%d | world=%s | capture=%s"
			% [checks, _world_id, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RUNTIME HEALTH DESKTOP FAILURE: %s" % failure)
		print(
			"QA RUNTIME HEALTH DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
