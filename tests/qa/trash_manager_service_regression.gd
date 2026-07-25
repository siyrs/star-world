extends SceneTree

const ProtectedSaveServiceScript = preload(
	"res://src/save/protected_save_service.gd"
)
const WORLD_COUNT := 4
const OVERRIDES := 48

var checks := 0
var failures: Array[String] = []
var service: Node
var world_ids: Array[String] = []
var trash_ids: Dictionary = {}
var test_prefix := "qa-trash-manager-%d-%d" % [
	int(Time.get_unix_time_from_system()), Time.get_ticks_msec()
]
var target_world_id := ""
var target_primary := ""
var target_catalog := ""
var target_backup := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = ProtectedSaveServiceScript.new()
	root.add_child(service)
	await process_frame
	_cleanup_fixture()
	await _create_and_trash_worlds()
	await _restart_service()
	_exercise_cross_session_management()
	_cleanup_fixture()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA TRASH MANAGER SERVICE PASS | checks=%d | worlds=%d"
			% [checks, WORLD_COUNT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA TRASH MANAGER SERVICE FAILURE: %s" % failure)
		print(
			"QA TRASH MANAGER SERVICE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _create_and_trash_worlds() -> void:
	for index in WORLD_COUNT:
		var state: Dictionary = service.call(
			"create_world",
			"%s-%02d" % [test_prefix, index],
			"star_continent",
			1800000 + index
		)
		_check(not state.is_empty(), "fixture creates world %02d" % index)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		world_ids.append(world_id)
		if index == 1:
			target_world_id = world_id
			var overrides: Dictionary = {}
			for offset in OVERRIDES:
				overrides["%d,24,%d" % [offset, offset % 6]] = "stone_bricks"
			state["world"] = {"block_overrides": overrides}
			_check(
				bool(service.call("save_world", world_id, state)),
				"target writes first authoritative generation"
			)
			state["metadata"]["generation"] = "second"
			_check(
				bool(service.call("save_world", world_id, state)),
				"target rotates a real backup"
			)
			target_primary = _read_text(_world_path(world_id))
			target_catalog = _read_text(_catalog_path(world_id))
			target_backup = _read_text("%s.bak" % _world_path(world_id))
		var result: Dictionary = service.call("trash_world", world_id)
		var trash_id := str(result.get("trash_id", ""))
		_check(
			bool(result.get("ok", false)) and not trash_id.is_empty(),
			"fixture trashes world %02d" % index
		)
		trash_ids[world_id] = trash_id
	var slots: Array = service.call("list_trash_slots", 32)
	_check(
		slots.size() == WORLD_COUNT,
		"slot listing exposes every physical trash directory"
	)
	var last_entry: Dictionary = service.call("get_last_trashed_world")
	_check(
		str(last_entry.get("world_id", "")) == world_ids[WORLD_COUNT - 1],
		"monotonic epoch-microsecond order identifies the latest rapid deletion"
	)
	var previous_usec := 9223372036854775807
	for raw_entry: Variant in slots:
		var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
		var deleted_usec := int(entry.get("deleted_unix_usec", 0))
		_check(
			deleted_usec > 0 and deleted_usec <= previous_usec,
			"trash slots remain newest-first with a persistent timestamp"
		)
		previous_usec = deleted_usec
	var oldest_trash_id := str(trash_ids.get(world_ids[0], ""))
	var manifest := FileAccess.open(_trash_manifest_path(oldest_trash_id), FileAccess.WRITE)
	_check(manifest != null, "corruption fixture opens the oldest manifest")
	if manifest != null:
		manifest.store_string("{broken-manifest")
		manifest.close()


func _restart_service() -> void:
	service.queue_free()
	await process_frame
	await process_frame
	service = ProtectedSaveServiceScript.new()
	root.add_child(service)
	await process_frame


func _exercise_cross_session_management() -> void:
	var diagnostics: Dictionary = service.call("get_trash_diagnostics")
	_check(
		int(diagnostics.get("trash_entry_count", -1)) == WORLD_COUNT
		and int(diagnostics.get("valid_entry_count", -1)) == WORLD_COUNT - 1
		and int(diagnostics.get("invalid_entry_count", -1)) == 1,
		"restart counts valid and damaged physical slots without losing capacity"
	)
	var last_entry: Dictionary = service.call("get_last_trashed_world")
	_check(
		str(last_entry.get("world_id", "")) == world_ids[WORLD_COUNT - 1],
		"restart preserves the true latest valid undo target"
	)
	var slots: Array = service.call("list_trash_slots", 32)
	var invalid_trash_id := str(trash_ids.get(world_ids[0], ""))
	var invalid_entry := _find_slot(slots, invalid_trash_id)
	_check(
		not invalid_entry.is_empty()
		and not bool(invalid_entry.get("valid", true))
		and bool(invalid_entry.get("purgeable", false))
		and str(invalid_entry.get("reason", "")) == "manifest_missing_or_invalid",
		"manager projection exposes the damaged slot as purgeable but not restorable"
	)
	var invalid_restore: Dictionary = service.call(
		"restore_trashed_world", invalid_trash_id
	)
	_check(
		not bool(invalid_restore.get("ok", true))
		and str(invalid_restore.get("reason", "")) == "trash_missing_or_invalid",
		"damaged slot cannot be restored through the authoritative path"
	)

	var target_trash_id := str(trash_ids.get(target_world_id, ""))
	var restored: Dictionary = service.call("restore_trashed_world", target_trash_id)
	_check(
		bool(restored.get("ok", false))
		and str(restored.get("world_id", "")) == target_world_id,
		"manager can restore an explicitly selected older valid entry"
	)
	_check(
		_read_text(_world_path(target_world_id)) == target_primary
		and _read_text(_catalog_path(target_world_id)) == target_catalog
		and _read_text("%s.bak" % _world_path(target_world_id)) == target_backup,
		"selected restore preserves primary, sidecar and backup bytes exactly"
	)
	var loaded: Dictionary = service.call("load_world", target_world_id)
	_check(
		(loaded.get("world", {}).get("block_overrides", {}) as Dictionary).size()
		== OVERRIDES,
		"selected restore fully reloads every sparse modification"
	)
	_check(
		bool(service.call("purge_trash_slot", invalid_trash_id)),
		"explicit slot purge removes a damaged manifest directory"
	)
	diagnostics = service.call("get_trash_diagnostics")
	_check(
		int(diagnostics.get("trash_entry_count", -1)) == 2
		and int(diagnostics.get("valid_entry_count", -1)) == 2
		and int(diagnostics.get("invalid_entry_count", -1)) == 0
		and int(diagnostics.get("purge_success_count", -1)) == 1,
		"purging one damaged slot frees exactly one capacity unit"
	)
	_check(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_trash_directory(invalid_trash_id))
		),
		"damaged physical directory is actually removed"
	)


func _find_slot(slots: Array, trash_id: String) -> Dictionary:
	for raw_entry: Variant in slots:
		if raw_entry is Dictionary and str(raw_entry.get("trash_id", "")) == trash_id:
			return raw_entry
	return {}


func _cleanup_fixture() -> void:
	if service == null:
		return
	if service.has_method("list_trash_slots"):
		var slots: Array = service.call("list_trash_slots", 32)
		for raw_entry: Variant in slots:
			if raw_entry is not Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var trash_id := str(entry.get("trash_id", ""))
			var world_id := str(entry.get("world_id", ""))
			if world_id.begins_with(test_prefix) or trash_id.contains(_safe_prefix()):
				service.call("purge_trash_slot", trash_id)
	for world_id: String in world_ids:
		if bool(service.call("world_exists", world_id)):
			service.call("delete_world", world_id)


func _safe_prefix() -> String:
	return test_prefix.to_lower().replace("_", "-")


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
