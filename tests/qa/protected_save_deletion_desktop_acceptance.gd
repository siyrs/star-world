extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://protected-save-deletion-desktop.png"
const WORLD_COUNT := 12
const OVERRIDES_PER_WORLD := 16
const CLEANUP_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var primary_before := ""
var catalog_before := ""
var backup_before := ""
var target_world_id := ""
var target_name := ""
var test_prefix := "Protected-Desktop-%d" % Time.get_ticks_msec()
var capture_path := ""
var confirm_capture_path := ""
var restored_capture_path := ""
var report_path := ""
var report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	confirm_capture_path = capture_path.get_basename() + "-confirm.png"
	restored_capture_path = capture_path.get_basename() + "-restored.png"
	report_path = capture_path.get_basename() + ".json"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 8:
		await process_frame
	var hub: Node = game.get("service_hub")
	var save: Node = hub.get("save_service") if hub != null else null
	var main_menu: Control = hub.get("main_menu") if hub != null else null
	_check(
		save != null and main_menu != null,
		"production game exposes authoritative save service and main menu"
	)
	if save == null or main_menu == null:
		await _finish(game, save, null)
		return
	await _create_fixture(save)
	var save_panel: Control = main_menu.get("_save_panel")
	var trash_service: Node = save_panel.get("_trash_service") if save_panel != null else null
	var delete_button := save_panel.get("_delete_button") as Button if save_panel != null else null
	var undo_button := save_panel.get("_undo_delete_button") as Button if save_panel != null else null
	var status_label := save_panel.get("_status") as Label if save_panel != null else null
	_check(
		save_panel != null
		and trash_service != null
		and delete_button != null
		and undo_button != null
		and status_label != null,
		"production menu installs protected save browser and independent trash service"
	)
	if (
		save_panel == null
		or trash_service == null
		or delete_button == null
		or undo_button == null
	):
		await _finish(game, save, trash_service)
		return

	_cleanup_test_trash(trash_service)
	var trash_before: Dictionary = trash_service.call("get_trash_diagnostics")
	var trash_count_before := int(trash_before.get("trash_entry_count", 0))
	save_panel.call("refresh")
	main_menu.call("_show_panel", save_panel)
	await process_frame
	save_panel.call("apply_query", target_name, "name_asc")
	await process_frame
	_check(
		save_panel.call("get_visible_world_ids") == [target_world_id],
		"real name search isolates the protected deletion target"
	)
	save_panel.call("_select_slot", 0)
	var selected_snapshot: Dictionary = save_panel.call(
		"get_virtualization_snapshot"
	)
	_check(
		str(save_panel.get("_selected_world_id")) == target_world_id
		and not bool(selected_snapshot.get("delete_confirmation_armed", true)),
		"real target selection starts with no destructive action armed"
	)

	delete_button.emit_signal("pressed")
	await process_frame
	var confirmation: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		bool(confirmation.get("delete_confirmation_armed", false))
		and str(confirmation.get("pending_delete_world_id", ""))
		== target_world_id,
		"first real delete click only arms the exact selected world"
	)
	_check(
		bool(save.call("world_exists", target_world_id))
		and FileAccess.file_exists(_world_path(target_world_id))
		and delete_button.text == "确认移到回收站",
		"confirmation state leaves authoritative files untouched"
	)
	_check(
		status_label.text.contains("再次点击确认")
		and status_label.text.contains("可撤销"),
		"confirmation message clearly explains the reversible action"
	)
	await _capture(
		confirm_capture_path,
		"protected deletion confirmation screenshot is saved"
	)

	delete_button.emit_signal("pressed")
	await process_frame
	var trashed_snapshot: Dictionary = save_panel.call(
		"get_virtualization_snapshot"
	)
	var trashed_diagnostics: Dictionary = trash_service.call(
		"get_trash_diagnostics"
	)
	var trash_id := str(trashed_snapshot.get("last_trash_id", ""))
	_check(
		not bool(save.call("world_exists", target_world_id))
		and not FileAccess.file_exists(_world_path(target_world_id)),
		"confirmed deletion removes the world only from the active directory"
	)
	_check(
		int(trashed_diagnostics.get("trash_entry_count", -1))
		== trash_count_before + 1
		and int(trashed_diagnostics.get("trash_success_count", -1)) == 1
		and bool(trashed_diagnostics.get("undo_available", false)),
		"real trash diagnostics record one reversible deletion"
	)
	_check(
		not trash_id.is_empty()
		and FileAccess.file_exists(_trash_world_path(trash_id))
		and FileAccess.file_exists(_trash_catalog_path(trash_id))
		and FileAccess.file_exists("%s.bak" % _trash_world_path(trash_id)),
		"real trash directory retains primary, sidecar and backup"
	)
	_check(
		bool(trashed_snapshot.get("undo_available", false))
		and not undo_button.disabled
		and status_label.text.contains("撤销删除"),
		"successful trash exposes a visible undo action"
	)
	_check(
		(save.call("load_world", target_world_id) as Dictionary).is_empty(),
		"trashed world cannot be continued until restored"
	)
	_check(
		(save.call("list_worlds") as Array).size() == WORLD_COUNT - 1,
		"authoritative world list excludes the trashed entry"
	)
	await _capture(capture_path, "protected trash screenshot is saved")

	undo_button.emit_signal("pressed")
	await process_frame
	var restored_snapshot: Dictionary = save_panel.call(
		"get_virtualization_snapshot"
	)
	var restored_diagnostics: Dictionary = trash_service.call(
		"get_trash_diagnostics"
	)
	_check(
		bool(save.call("world_exists", target_world_id))
		and FileAccess.file_exists(_world_path(target_world_id)),
		"real undo atomically restores the original world directory"
	)
	_check(
		_read_text(_world_path(target_world_id)) == primary_before
		and _read_text(_catalog_path(target_world_id)) == catalog_before
		and _read_text("%s.bak" % _world_path(target_world_id)) == backup_before,
		"real undo preserves primary, sidecar and backup bytes exactly"
	)
	_check(
		int(restored_diagnostics.get("restore_success_count", -1)) == 1
		and int(restored_diagnostics.get("trash_entry_count", -1))
		== trash_count_before,
		"real undo consumes only the matching trash entry"
	)
	_check(
		not bool(restored_snapshot.get("delete_confirmation_armed", true))
		and str(restored_snapshot.get("applied_query", "not-empty")).is_empty(),
		"undo clears destructive and filter state so the restored world is visible"
	)
	var loaded: Dictionary = save.call("load_world", target_world_id)
	_check(
		(loaded.get("world", {}).get("block_overrides", {}) as Dictionary).size()
		== OVERRIDES_PER_WORLD,
		"restored world fully loads all real sparse modifications"
	)
	_check(
		(save.call("list_worlds") as Array).size() == WORLD_COUNT,
		"authoritative world list returns to the full fixture size"
	)
	await _capture(
		restored_capture_path,
		"protected deletion restored screenshot is saved"
	)

	save_panel.call("apply_query", target_name, "name_asc")
	save_panel.call("_select_slot", 0)
	delete_button.emit_signal("pressed")
	save_panel.call("apply_query", "%s-Other-00" % test_prefix, "name_asc")
	var hidden_selection: Dictionary = save_panel.call(
		"get_virtualization_snapshot"
	)
	_check(
		not bool(hidden_selection.get("delete_confirmation_armed", true))
		and str(save_panel.get("_selected_world_id")).is_empty()
		and bool(save.call("world_exists", target_world_id)),
		"real filtering clears an armed hidden deletion without moving the world"
	)

	report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"target_world_id": target_world_id,
		"trash_capacity": int(
			trashed_diagnostics.get("trash_capacity", -1)
		),
		"confirmation": confirmation,
		"trashed": trashed_snapshot,
		"trashed_diagnostics": trashed_diagnostics,
		"restored": restored_snapshot,
		"restored_diagnostics": restored_diagnostics,
		"hidden_selection": hidden_selection,
	}
	_write_report()
	await _finish(game, save, trash_service)


func _create_fixture(save: Node) -> void:
	for index in WORLD_COUNT:
		var display_name := (
			"%s-Target" % test_prefix
			if index == 5
			else "%s-Other-%02d" % [test_prefix, index]
		)
		var state: Dictionary = save.call(
			"create_world",
			display_name,
			"star_continent",
			1700000 + index
		)
		_check(
			not state.is_empty(),
			"desktop fixture creates world %02d" % index
		)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		if index != 5:
			continue
		target_world_id = world_id
		target_name = display_name
		var overrides: Dictionary = {}
		for offset in OVERRIDES_PER_WORLD:
			overrides["%d,20,%d" % [offset, offset % 4]] = "stone_bricks"
		state["world"] = {"block_overrides": overrides}
		_check(
			bool(save.call("save_world", world_id, state)),
			"target writes the first authoritative generation"
		)
		state["metadata"]["generation"] = "second"
		_check(
			bool(save.call("save_world", world_id, state)),
			"target rotates an authoritative backup"
		)
		primary_before = _read_text(_world_path(world_id))
		catalog_before = _read_text(_catalog_path(world_id))
		backup_before = _read_text("%s.bak" % _world_path(world_id))
	await process_frame


func _cleanup_test_trash(trash_service: Node) -> void:
	if trash_service == null:
		return
	var entries: Array = trash_service.call("list_trashed_worlds", 32)
	for raw_entry: Variant in entries:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if str(entry.get("name", "")).begins_with(test_prefix):
			trash_service.call(
				"purge_trashed_world", str(entry.get("trash_id", ""))
			)


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s produces an image" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(
		image.save_png(path) == OK and FileAccess.file_exists(path),
		description
	)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "protected deletion JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(
		FileAccess.file_exists(report_path),
		"protected deletion JSON report is saved"
	)


func _finish(game: Node, save: Node, trash_service: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cleanup_test_trash(trash_service)
	for world_id: String in world_ids:
		if save != null and is_instance_valid(save):
			if bool(save.call("world_exists", world_id)):
				save.call("delete_world", world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA PROTECTED SAVE DELETION DESKTOP PASS | checks=%d | worlds=%d"
			% [checks, WORLD_COUNT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROTECTED SAVE DELETION DESKTOP FAILURE: %s" % failure)
		print(
			"QA PROTECTED SAVE DELETION DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _world_path(world_id: String) -> String:
	return "user://worlds/%s/world.json" % world_id


func _catalog_path(world_id: String) -> String:
	return "user://worlds/%s/catalog.json" % world_id


func _trash_world_path(trash_id: String) -> String:
	return "user://world_trash/%s/world.json" % trash_id


func _trash_catalog_path(trash_id: String) -> String:
	return "user://world_trash/%s/catalog.json" % trash_id


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
