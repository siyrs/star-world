extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const OUTPUT_PATH := "user://bounded-trash-manager-desktop.png"
const WORLD_COUNT := 33
const TRASH_CAPACITY := 32
const ROW_POOL_LIMIT := 24
const OVERRIDES := 16
const CLEANUP_FRAMES := 30

var checks := 0
var failures: Array[String] = []
var world_ids: Array[String] = []
var trash_id_by_world: Dictionary = {}
var test_prefix := "Trash-Manager-Desktop-%d-%d" % [
	int(Time.get_unix_time_from_system()), Time.get_ticks_msec()
]
var target_world_id := ""
var target_trash_id := ""
var invalid_trash_id := ""
var overflow_world_id := ""
var target_primary := ""
var target_catalog := ""
var target_backup := ""
var capture_path := ""
var purge_confirm_path := ""
var after_path := ""
var report_path := ""
var report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	purge_confirm_path = capture_path.get_basename() + "-purge-confirm.png"
	after_path = capture_path.get_basename() + "-after.png"
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
	var save_panel: Control = main_menu.get("_save_panel") if main_menu != null else null
	var trash_service: Node = save_panel.get("_trash_service") if save_panel != null else null
	var manager: Control = save_panel.get("_trash_manager") if save_panel != null else null
	_check(
		save != null
		and main_menu != null
		and save_panel != null
		and trash_service != null
		and manager != null,
		"production game exposes save browser, protected trash service and manager"
	)
	if save == null or save_panel == null or trash_service == null or manager == null:
		await _finish(game, save, trash_service)
		return
	var hidden_manager_snapshot: Dictionary = manager.call("get_management_snapshot")
	_check(
		int(hidden_manager_snapshot.get("service_list_count", -1)) == 0,
		"hidden manager performs zero directory lists before the player opens it"
	)
	_cleanup_fixture(save, trash_service)
	await _create_fixture(save, trash_service)
	await _exercise_full_manager(save, main_menu, save_panel, trash_service, manager)
	await _finish(game, save, trash_service)


func _create_fixture(save: Node, trash_service: Node) -> void:
	for index in WORLD_COUNT:
		var display_name := "%s-%02d" % [test_prefix, index]
		var state: Dictionary = save.call(
			"create_world",
			display_name,
			"star_continent",
			2000000 + index
		)
		_check(not state.is_empty(), "desktop fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		if index == 5:
			target_world_id = world_id
			var overrides: Dictionary = {}
			for offset in OVERRIDES:
				overrides["%d,28,%d" % [offset, offset % 4]] = "stone_bricks"
			state["world"] = {"block_overrides": overrides}
			_check(
				bool(save.call("save_world", world_id, state)),
				"restore target writes first authoritative generation"
			)
			state["metadata"]["generation"] = "second"
			_check(
				bool(save.call("save_world", world_id, state)),
				"restore target rotates a real backup"
			)
			target_primary = _read_text(_world_path(world_id))
			target_catalog = _read_text(_catalog_path(world_id))
			target_backup = _read_text("%s.bak" % _world_path(world_id))
		if index < TRASH_CAPACITY:
			var result: Dictionary = trash_service.call("trash_world", world_id)
			var trash_id := str(result.get("trash_id", ""))
			_check(
				bool(result.get("ok", false)) and not trash_id.is_empty(),
				"desktop fixture fills trash slot %02d" % index
			)
			trash_id_by_world[world_id] = trash_id
			if index == 5:
				target_trash_id = trash_id
			elif index == 7:
				invalid_trash_id = trash_id
		else:
			overflow_world_id = world_id
	var manifest := FileAccess.open(_trash_manifest_path(invalid_trash_id), FileAccess.WRITE)
	_check(manifest != null, "desktop fixture opens one manifest for corruption")
	if manifest != null:
		manifest.store_string("{broken-desktop-manifest")
		manifest.close()
	trash_service.call("list_trash_slots", TRASH_CAPACITY)
	var overflow_attempt: Dictionary = trash_service.call("trash_world", overflow_world_id)
	_check(
		not bool(overflow_attempt.get("ok", true))
		and str(overflow_attempt.get("reason", "")) == "trash_full"
		and bool(save.call("world_exists", overflow_world_id)),
		"full physical trash rejects the thirty-third world without moving it"
	)


func _exercise_full_manager(
	save: Node,
	main_menu: Control,
	save_panel: Control,
	trash_service: Node,
	manager: Control
) -> void:
	save_panel.call("refresh")
	main_menu.call("_show_panel", save_panel)
	await process_frame
	save_panel.call("_show_trash_manager")
	await process_frame
	var full_snapshot: Dictionary = manager.call("get_management_snapshot")
	var browser_open_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		bool(browser_open_snapshot.get("trash_manager_visible", false)),
		"production save browser opens the dedicated trash manager"
	)
	_check(
		int(full_snapshot.get("row_pool_size", -1)) == ROW_POOL_LIMIT
		and int(full_snapshot.get("row_create_count", -1)) == ROW_POOL_LIMIT,
		"real manager owns exactly twenty-four reusable rows"
	)
	_check(
		int(full_snapshot.get("total_slot_count", -1)) == TRASH_CAPACITY
		and int(full_snapshot.get("page_count", -1)) == 2
		and int(full_snapshot.get("valid_slot_count", -1)) == 31
		and int(full_snapshot.get("invalid_slot_count", -1)) == 1,
		"real full trash exposes thirty-two slots across two pages including damage"
	)
	_check(
		int(full_snapshot.get("physical_entry_count", -1)) == TRASH_CAPACITY
		and int(full_snapshot.get("trash_capacity", -1)) == TRASH_CAPACITY,
		"real manager reports the exact thirty-two-slot physical capacity"
	)
	_check(
		_count_active_fixture_worlds(save) == 1,
		"only the blocked overflow world remains active while trash is full"
	)
	await _capture(capture_path, "full bounded trash manager screenshot is saved")

	var target_position := _manager_position(manager, target_trash_id)
	_check(target_position.x >= 0, "older restore target is present in the manager index")
	if target_position.x >= 0:
		manager.call("show_page", int(target_position.x))
		await process_frame
		var rows: Array = manager.get("_row_slots")
		var restore_button := rows[int(target_position.y)].get("restore") as Button
		_check(
			restore_button != null and not restore_button.disabled,
			"older valid target exposes an enabled row restore action"
		)
		if restore_button != null:
			restore_button.emit_signal("pressed")
		await process_frame
	_check(
		bool(save.call("world_exists", target_world_id))
		and _count_active_fixture_worlds(save) == 2,
		"selected older entry restores without consuming the latest trash item"
	)
	_check(
		_read_text(_world_path(target_world_id)) == target_primary
		and _read_text(_catalog_path(target_world_id)) == target_catalog
		and _read_text("%s.bak" % _world_path(target_world_id)) == target_backup,
		"real selected restore preserves primary, sidecar and backup bytes"
	)
	var loaded: Dictionary = save.call("load_world", target_world_id)
	_check(
		(loaded.get("world", {}).get("block_overrides", {}) as Dictionary).size()
		== OVERRIDES,
		"real selected restore reloads all sparse modifications"
	)
	var after_restore: Dictionary = manager.call("get_management_snapshot")
	_check(
		int(after_restore.get("total_slot_count", -1)) == 31
		and int(after_restore.get("physical_entry_count", -1)) == 31,
		"selected restore frees exactly one physical capacity unit"
	)

	var invalid_position := _manager_position(manager, invalid_trash_id)
	_check(invalid_position.x >= 0, "damaged slot remains visible after selected restore")
	if invalid_position.x >= 0:
		manager.call("show_page", int(invalid_position.x))
		await process_frame
		manager.call("_select_slot", int(invalid_position.y))
	var purge_button := manager.get("_purge_button") as Button
	_check(purge_button != null, "manager exposes permanent clean only inside trash view")
	if purge_button != null:
		purge_button.emit_signal("pressed")
	await process_frame
	var purge_armed: Dictionary = manager.call("get_management_snapshot")
	_check(
		bool(purge_armed.get("purge_confirmation_armed", false))
		and str(purge_armed.get("pending_purge_trash_id", "")) == invalid_trash_id
		and DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_trash_directory(invalid_trash_id))
		),
		"first permanent-clean click arms the damaged slot without removing files"
	)
	await _capture(
		purge_confirm_path,
		"damaged-slot permanent-clean confirmation screenshot is saved"
	)
	if purge_button != null:
		purge_button.emit_signal("pressed")
	await process_frame
	var after_purge: Dictionary = manager.call("get_management_snapshot")
	_check(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_trash_directory(invalid_trash_id))
		)
		and int(after_purge.get("total_slot_count", -1)) == 30
		and int(after_purge.get("invalid_slot_count", -1)) == 0,
		"second click permanently cleans only the damaged slot and frees capacity"
	)

	var accepted: Dictionary = trash_service.call("trash_world", overflow_world_id)
	_check(
		bool(accepted.get("ok", false))
		and not bool(save.call("world_exists", overflow_world_id)),
		"capacity released by management accepts the previously blocked world"
	)
	manager.call("refresh")
	var final_snapshot: Dictionary = manager.call("get_management_snapshot")
	_check(
		int(final_snapshot.get("physical_entry_count", -1)) == 31
		and int(final_snapshot.get("valid_slot_count", -1)) == 31
		and int(final_snapshot.get("invalid_slot_count", -1)) == 0,
		"final manager state contains thirty-one valid bounded slots"
	)
	_check(
		_count_active_fixture_worlds(save) == 1
		and bool(save.call("world_exists", target_world_id)),
		"restored target remains the only active fixture world"
	)
	await _capture(after_path, "post-management trash screenshot is saved")

	var back_button := _find_button(manager, "返回存档")
	_check(back_button != null, "real manager exposes return-to-save-browser control")
	if back_button != null:
		back_button.emit_signal("pressed")
	await process_frame
	var browser_snapshot: Dictionary = save_panel.call("get_virtualization_snapshot")
	_check(
		not bool(browser_snapshot.get("trash_manager_visible", true)),
		"return control restores the normal indexed save browser"
	)
	save_panel.call("apply_query", target_world_id, "name_asc")
	_check(
		save_panel.call("get_visible_world_ids") == [target_world_id],
		"restored target is immediately searchable in the active browser"
	)

	report = {
		"schema_version": 1,
		"world_count": WORLD_COUNT,
		"trash_capacity": TRASH_CAPACITY,
		"row_pool_limit": ROW_POOL_LIMIT,
		"target_world_id": target_world_id,
		"target_trash_id": target_trash_id,
		"invalid_trash_id": invalid_trash_id,
		"overflow_world_id": overflow_world_id,
		"full": full_snapshot,
		"after_restore": after_restore,
		"purge_armed": purge_armed,
		"after_purge": after_purge,
		"final": final_snapshot,
		"browser": browser_snapshot,
		"trash_diagnostics": trash_service.call("get_trash_diagnostics"),
	}
	_write_report()


func _manager_position(manager: Control, trash_id: String) -> Vector2i:
	var ids: Array = manager.get("_slot_ids")
	var index := ids.find(trash_id)
	if index < 0:
		return Vector2i(-1, -1)
	return Vector2i(floori(float(index) / float(ROW_POOL_LIMIT)), index % ROW_POOL_LIMIT)


func _count_active_fixture_worlds(save: Node) -> int:
	var count := 0
	var worlds: Array = save.call("list_worlds")
	for raw_metadata: Variant in worlds:
		if raw_metadata is Dictionary and str(raw_metadata.get("name", "")).begins_with(test_prefix):
			count += 1
	return count


func _cleanup_fixture(save: Node, trash_service: Node) -> void:
	if trash_service != null and trash_service.has_method("list_trash_slots"):
		var slots: Array = trash_service.call("list_trash_slots", TRASH_CAPACITY)
		for raw_entry: Variant in slots:
			if raw_entry is not Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var world_id := str(entry.get("world_id", ""))
			var trash_id := str(entry.get("trash_id", ""))
			if world_id.begins_with(_safe_prefix()) or trash_id.contains(_safe_prefix()):
				trash_service.call("purge_trash_slot", trash_id)
	if save != null:
		for world_id: String in world_ids:
			if bool(save.call("world_exists", world_id)):
				save.call("delete_world", world_id)


func _safe_prefix() -> String:
	return test_prefix.to_lower().replace("_", "-")


func _capture(path: String, description: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "%s produces an image" % description)
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image.save_png(path) == OK and FileAccess.file_exists(path), description)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "bounded trash manager JSON report opens")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check(FileAccess.file_exists(report_path), "bounded trash manager JSON report is saved")


func _finish(game: Node, save: Node, trash_service: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cleanup_fixture(save, trash_service)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA BOUNDED TRASH MANAGER DESKTOP PASS | checks=%d | worlds=%d | slots=%d"
			% [checks, WORLD_COUNT, TRASH_CAPACITY]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BOUNDED TRASH MANAGER DESKTOP FAILURE: %s" % failure)
		print(
			"QA BOUNDED TRASH MANAGER DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


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


func _trash_directory(trash_id: String) -> String:
	return "user://world_trash/%s" % trash_id


func _trash_manifest_path(trash_id: String) -> String:
	return "%s/trash.json" % _trash_directory(trash_id)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
