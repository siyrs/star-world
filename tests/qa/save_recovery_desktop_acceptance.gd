extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const AtomicStoreScript = preload("res://src/save/atomic_json_store.gd")

const OUTPUT_PATH := "user://save-recovery-desktop.png"
const OVERRIDE_COUNT := 256
const READY_FRAMES := 600
const SETTLE_FRAMES := 24
const CLEANUP_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _health_capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_health_capture_path = _capture_path.get_basename() + "-health.png"
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 6:
		await process_frame
	var hub := game.get("service_hub") as Node
	var main_menu := hub.get("main_menu") as Control if hub != null else null
	var save := hub.get("save_service") as Node if hub != null else null
	var diagnostics := game.get("runtime_diagnostics") as Node
	var report_service := (
		hub.get("runtime_health_report_service") as Node if hub != null else null
	)
	_check(
		hub != null
		and main_menu != null
		and save != null
		and diagnostics != null
		and report_service != null,
		"production game mounts menu, save, diagnostics and runtime health services",
	)
	if hub == null or main_menu == null or save == null or diagnostics == null:
		await _finish(game, hub, save)
		return

	var state: Dictionary = save.call(
		"create_world",
		"Recovery-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		770033,
	)
	_check(not state.is_empty(), "desktop recovery journey creates a real world")
	if state.is_empty():
		await _finish(game, hub, save)
		return
	var metadata: Dictionary = state.get("metadata", {})
	_world_id = str(metadata.get("id", ""))
	var backup_overrides := _block_overrides(OVERRIDE_COUNT)
	metadata["recovery_marker"] = "backup-ready"
	state["metadata"] = metadata
	state["world"] = {"block_overrides": backup_overrides.duplicate(true)}
	_check(
		bool(save.call("save_world", _world_id, state)),
		"desktop journey persists the backup-ready world generation",
	)
	metadata["recovery_marker"] = "newer-primary"
	state["metadata"] = metadata
	var newer_overrides := backup_overrides.duplicate(true)
	newer_overrides["999,12,999"] = "glass_pane"
	state["world"] = {"block_overrides": newer_overrides}
	_check(
		bool(save.call("save_world", _world_id, state)),
		"desktop journey rotates the backup-ready generation into .bak",
	)

	var world_path := _world_path(_world_id)
	var catalog_path := _catalog_path(_world_id)
	_remove_file(catalog_path)
	_check(
		_write_dictionary(world_path, {
			"save_version": 2,
			"metadata": {"id": _world_id, "name": "Parseable corruption"},
			"player": "invalid-player-domain",
			"world": {"block_overrides": "invalid-world-domain"},
		}),
		"desktop journey replaces world.json with parseable structural corruption",
	)
	save.call("reset_recovery_diagnostics")
	save.call("reset_catalog_diagnostics")

	var save_panel := main_menu.get("_save_panel") as Control
	_check(save_panel != null, "production main menu exposes the save browser")
	if save_panel == null:
		await _finish(game, hub, save)
		return
	save_panel.call("refresh")
	main_menu.call("_show_panel", save_panel)
	for _frame in SETTLE_FRAMES:
		await process_frame

	var recovery: Dictionary = save.call("get_recovery_diagnostics")
	var catalog: Dictionary = save.call("get_catalog_diagnostics")
	var status_label := save_panel.get("_status") as Label
	_check(
		status_label != null
		and status_label.text.contains("已自愈 1 个存档")
		and status_label.text.contains("已修复 1 个旧目录"),
		"save browser visibly reports authoritative and catalog self-healing",
	)
	_check(
		int(recovery.get("recovery_count", 0)) == 1
		and int(recovery.get("repair_success_count", 0)) == 1
		and int(recovery.get("repair_failure_count", 0)) == 0,
		"desktop recovery records one successful primary repair",
	)
	_check(
		str(recovery.get("last_source", "")) == "backup"
		and bool(recovery.get("last_repaired", false))
		and int(recovery.get("primary_rejection_count", 0)) == 1,
		"desktop recovery identifies the backup and rejected primary",
	)
	_check(
		int(catalog.get("last_fallback_count", 0)) == 1
		and int(catalog.get("last_repair_count", 0)) == 1,
		"desktop recovery rebuilds exactly one missing catalog after promotion",
	)

	var repaired_primary := _read_dictionary(world_path)
	var repaired_metadata: Dictionary = repaired_primary.get("metadata", {})
	var repaired_world: Dictionary = repaired_primary.get("world", {})
	_check(
		str(repaired_metadata.get("recovery_marker", "")) == "backup-ready",
		"desktop primary is repaired to the expected backup generation",
	)
	_check(
		(repaired_world.get("block_overrides", {}) as Dictionary).size() == OVERRIDE_COUNT,
		"desktop primary restores the exact sparse world payload",
	)
	_check(
		str(_read_dictionary("%s%s" % [world_path, AtomicStoreScript.BACKUP_SUFFIX]).get("metadata", {}).get("recovery_marker", ""))
		== "backup-ready",
		"desktop repair preserves the valid backup file",
	)
	var catalog_payload := _read_dictionary(catalog_path)
	_check(
		int(catalog_payload.get("save_bytes", 0)) == _file_length(world_path),
		"desktop catalog binds to the repaired world.json byte length",
	)
	_check(_recovery_artifacts_absent(world_path), "desktop repair leaves no stale tmp, recover or corrupt files")

	var list_node := save_panel.get("_list") as VBoxContainer
	var load_button: Button = null
	var row_has_size := false
	if list_node != null:
		for row: Node in list_node.get_children():
			if row.get_child_count() < 2:
				continue
			var select_button := row.get_child(0) as Button
			var candidate_load := row.get_child(1) as Button
			if select_button == null or candidate_load == null:
				continue
			if select_button.text.contains("Recovery-Desktop"):
				load_button = candidate_load
				row_has_size = select_button.text.contains("存档")
				break
	_check(load_button != null, "desktop journey locates the recovered world's real continue button")
	_check(row_has_size, "recovered save row retains a human-readable authoritative file size")

	var warning_snapshot: Dictionary = diagnostics.call("sample_now")
	var operations: Dictionary = warning_snapshot.get("operations", {})
	var save_health: Dictionary = operations.get("save", {})
	_check(
		int(save_health.get("recovery_count", 0)) == 1
		and int(save_health.get("repair_success_count", 0)) == 1
		and int(save_health.get("repair_failure_count", 0)) == 0,
		"unified telemetry carries bounded recovery and primary repair evidence",
	)
	_check(
		str(operations.get("status", "")) in ["warning", "critical"],
		"self-healing remains visible as operational health evidence",
	)
	_check(
		await _capture(_capture_path),
		"desktop save browser recovery screenshot is saved",
	)

	var overlay := diagnostics.get("overlay") as CanvasLayer
	_check(overlay != null, "production diagnostics exposes the F3 overlay")
	await _press_f3()
	_check(
		overlay != null and bool(overlay.call("is_overlay_visible")),
		"real F3 input opens recovery health visualization",
	)
	var display := str(overlay.call("get_display_text")) if overlay != null else ""
	_check(
		display.contains("主文件修复 1 / 失败 0")
		and display.contains("恢复 1"),
		"F3 visibly reports successful authoritative save repair",
	)
	_check(
		await _capture(_health_capture_path),
		"desktop F3 recovery health screenshot is saved",
	)
	await _press_f3()

	if load_button != null:
		load_button.pressed.emit()
		_check(
			await _wait_for_world_ready(game, hub, _world_id),
			"continue button starts the recovered production world",
		)
		var loaded: Dictionary = save.call("load_world", _world_id)
		var loaded_world: Dictionary = loaded.get("world", {})
		_check(
			str(loaded.get("metadata", {}).get("recovery_marker", "")) == "backup-ready",
			"full load uses the repaired primary generation",
		)
		_check(
			(loaded_world.get("block_overrides", {}) as Dictionary).size() == OVERRIDE_COUNT,
			"full load restores every recovered world override",
		)
		_check(
			int(save.call("get_recovery_diagnostics").get("recovery_count", 0)) == 1,
			"continue does not repeat recovery after authoritative repair",
		)

	save.call("reset_catalog_diagnostics")
	var steady_worlds: Array = save.call("list_worlds")
	var steady_catalog: Dictionary = save.call("get_catalog_diagnostics")
	_check(_contains_world(steady_worlds, _world_id), "steady catalog keeps the recovered world visible")
	_check(
		int(steady_catalog.get("last_hit_count", 0)) >= 1
		and int(steady_catalog.get("last_fallback_count", 0)) == 0,
		"next catalog scan is a pure sidecar hit",
	)

	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"override_count": OVERRIDE_COUNT,
		"recovery": recovery,
		"catalog_repair": catalog,
		"steady_catalog": steady_catalog,
		"operations": operations,
		"primary_bytes": _file_length(world_path),
		"backup_bytes": _file_length("%s%s" % [world_path, AtomicStoreScript.BACKUP_SUFFIX]),
		"save_browser_status": status_label.text if status_label != null else "",
		"save_browser_capture": _capture_path,
		"health_capture": _health_capture_path,
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


func _capture(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != root.size:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return image.save_png(path) == OK and FileAccess.file_exists(path)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "save recovery JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "save recovery JSON report is saved")


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
			"QA SAVE RECOVERY DESKTOP PASS | checks=%d | world=%s | capture=%s | health=%s"
			% [checks, _world_id, _capture_path, _health_capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE RECOVERY DESKTOP FAILURE: %s" % failure)
		print(
			"QA SAVE RECOVERY DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _block_overrides(count: int) -> Dictionary:
	var result: Dictionary = {}
	for index in count:
		result["%d,%d,%d" % [index % 32, 12 + int(index / 128), int(index / 32)]] = (
			"stone_bricks" if index % 3 != 0 else "glass_pane"
		)
	return result


func _contains_world(worlds: Array, world_id: String) -> bool:
	for raw_metadata: Variant in worlds:
		if raw_metadata is Dictionary and str(raw_metadata.get("id", "")) == world_id:
			return true
	return false


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _write_dictionary(path: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or parser.data is not Dictionary:
		return {}
	return parser.data


func _file_length(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return length


func _recovery_artifacts_absent(path: String) -> bool:
	return (
		not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.TEMP_SUFFIX])
		and not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.RECOVERY_SUFFIX])
		and not FileAccess.file_exists("%s%s" % [path, AtomicStoreScript.DISPLACED_SUFFIX])
	)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
