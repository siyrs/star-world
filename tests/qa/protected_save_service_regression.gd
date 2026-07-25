extends SceneTree

const ProtectedSaveServiceScript = preload(
	"res://src/save/protected_save_service.gd"
)
const TRASH_CAPACITY := 32
const CAPACITY_WORLD_COUNT := 33

var checks := 0
var failures: Array[String] = []
var service: Node
var cleanup_world_ids: Array[String] = []
var cleanup_trash_ids: Array[String] = []
var test_prefix := "qa-protected-delete-%d" % Time.get_ticks_msec()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = ProtectedSaveServiceScript.new()
	root.add_child(service)
	await process_frame
	await _exercise_atomic_round_trip()
	await _exercise_bounded_capacity()
	_cleanup()
	service.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print(
			"QA PROTECTED SAVE SERVICE PASS | checks=%d | capacity=%d"
			% [checks, TRASH_CAPACITY]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROTECTED SAVE SERVICE FAILURE: %s" % failure)
		print(
			"QA PROTECTED SAVE SERVICE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _exercise_atomic_round_trip() -> void:
	service.call("reset_trash_diagnostics")
	var state: Dictionary = service.call(
		"create_world",
		"%s-roundtrip" % test_prefix,
		"star_continent",
		1400001
	)
	_check(not state.is_empty(), "round-trip fixture creates a real world")
	if state.is_empty():
		return
	var world_id := str(state.get("metadata", {}).get("id", ""))
	cleanup_world_ids.append(world_id)
	var overrides: Dictionary = {}
	for index in 64:
		overrides["%d,12,%d" % [index, index % 8]] = "stone_bricks"
	state["world"] = {"block_overrides": overrides}
	_check(
		bool(service.call("save_world", world_id, state)),
		"round-trip fixture writes the first authoritative generation"
	)
	state["metadata"]["generation"] = "second"
	_check(
		bool(service.call("save_world", world_id, state)),
		"round-trip fixture rotates a real authoritative backup"
	)
	var world_before := _read_text(_world_path(world_id))
	var catalog_before := _read_text(_catalog_path(world_id))
	var backup_before := _read_text("%s.bak" % _world_path(world_id))
	_check(
		not world_before.is_empty()
		and not catalog_before.is_empty()
		and not backup_before.is_empty(),
		"round-trip fixture captures primary, sidecar and backup bytes"
	)

	var trashed: Dictionary = service.call("trash_world", world_id)
	var trash_id := str(trashed.get("trash_id", ""))
	cleanup_trash_ids.append(trash_id)
	_check(
		bool(trashed.get("ok", false)) and not trash_id.is_empty(),
		"trash operation atomically returns a stable trash id"
	)
	_check(
		not bool(service.call("world_exists", world_id))
		and not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_world_directory(world_id))
		),
		"trashed world immediately leaves the authoritative directory"
	)
	_check(
		FileAccess.file_exists(_trash_world_path(trash_id))
		and FileAccess.file_exists(_trash_catalog_path(trash_id))
		and FileAccess.file_exists("%s.bak" % _trash_world_path(trash_id))
		and FileAccess.file_exists(_trash_manifest_path(trash_id)),
		"trash keeps primary, sidecar, backup and a bounded manifest together"
	)
	_check(
		not _list_contains_world(service.call("list_worlds"), world_id)
		and (service.call("load_world", world_id) as Dictionary).is_empty(),
		"trashed world cannot be listed or loaded as active"
	)
	var trash_diagnostics: Dictionary = service.call("get_trash_diagnostics")
	_check(
		int(trash_diagnostics.get("trash_entry_count", -1)) == 1
		and int(trash_diagnostics.get("trash_success_count", -1)) == 1
		and bool(trash_diagnostics.get("undo_available", false)),
		"trash diagnostics expose one reversible deletion"
	)

	var conflict_state := state.duplicate(true)
	_check(
		bool(service.call("save_world", world_id, conflict_state)),
		"restore conflict fixture recreates the original world id"
	)
	var conflict_restore: Dictionary = service.call(
		"restore_trashed_world", trash_id
	)
	_check(
		not bool(conflict_restore.get("ok", true))
		and str(conflict_restore.get("reason", "")) == "world_exists"
		and FileAccess.file_exists(_trash_manifest_path(trash_id)),
		"restore refuses an occupied id without consuming the trash entry"
	)
	_check(
		bool(service.call("delete_world", world_id)),
		"test cleanup permanently removes only the explicit conflict"
	)

	var restored: Dictionary = service.call("restore_trashed_world", trash_id)
	_check(
		bool(restored.get("ok", false))
		and str(restored.get("world_id", "")) == world_id,
		"restore atomically returns the world to its original id"
	)
	cleanup_trash_ids.erase(trash_id)
	_check(
		_read_text(_world_path(world_id)) == world_before
		and _read_text(_catalog_path(world_id)) == catalog_before
		and _read_text("%s.bak" % _world_path(world_id)) == backup_before,
		"restore preserves primary, sidecar and backup bytes exactly"
	)
	_check(
		not FileAccess.file_exists(
			"%s/%s" % [_world_directory(world_id), "trash.json"]
		),
		"restore removes the internal trash manifest from the active world"
	)
	var loaded: Dictionary = service.call("load_world", world_id)
	_check(
		(loaded.get("world", {}).get("block_overrides", {}) as Dictionary).size()
		== overrides.size(),
		"restored world fully loads all sparse overrides"
	)
	var duplicate_restore: Dictionary = service.call(
		"restore_trashed_world", trash_id
	)
	_check(
		not bool(duplicate_restore.get("ok", true))
		and str(duplicate_restore.get("reason", ""))
		== "trash_missing_or_invalid",
		"a consumed trash entry cannot be restored twice"
	)


func _exercise_bounded_capacity() -> void:
	_cleanup_test_trash()
	var capacity_world_ids: Array[String] = []
	for index in CAPACITY_WORLD_COUNT:
		var state: Dictionary = service.call(
			"create_world",
			"%s-capacity-%02d" % [test_prefix, index],
			"star_continent",
			1500000 + index
		)
		_check(
			not state.is_empty(),
			"capacity fixture creates world %02d" % index
		)
		if state.is_empty():
			continue
		var world_id := str(state.get("metadata", {}).get("id", ""))
		capacity_world_ids.append(world_id)
		cleanup_world_ids.append(world_id)
		if index < TRASH_CAPACITY:
			var result: Dictionary = service.call("trash_world", world_id)
			var trash_id := str(result.get("trash_id", ""))
			_check(
				bool(result.get("ok", false)),
				"capacity trash accepts entry %02d" % index
			)
			if not trash_id.is_empty():
				cleanup_trash_ids.append(trash_id)
	var overflow_world_id := capacity_world_ids[TRASH_CAPACITY]
	var overflow: Dictionary = service.call("trash_world", overflow_world_id)
	_check(
		not bool(overflow.get("ok", true))
		and str(overflow.get("reason", "")) == "trash_full",
		"thirty-third deletion is rejected instead of purging older worlds"
	)
	_check(
		bool(service.call("world_exists", overflow_world_id))
		and (service.call("list_trashed_worlds", 99) as Array).size()
		== TRASH_CAPACITY,
		"full trash preserves the active overflow world and all thirty-two entries"
	)
	var newest: Dictionary = service.call("get_last_trashed_world")
	var newest_trash_id := str(newest.get("trash_id", ""))
	var restored: Dictionary = service.call(
		"restore_trashed_world", newest_trash_id
	)
	_check(
		bool(restored.get("ok", false)),
		"restoring one entry frees exactly one trash slot"
	)
	cleanup_trash_ids.erase(newest_trash_id)
	var restored_world_id := str(restored.get("world_id", ""))
	if not cleanup_world_ids.has(restored_world_id):
		cleanup_world_ids.append(restored_world_id)
	var accepted_after_restore: Dictionary = service.call(
		"trash_world", overflow_world_id
	)
	var accepted_trash_id := str(accepted_after_restore.get("trash_id", ""))
	_check(
		bool(accepted_after_restore.get("ok", false))
		and (service.call("list_trashed_worlds", 99) as Array).size()
		== TRASH_CAPACITY,
		"freed slot accepts the previously blocked world without exceeding capacity"
	)
	if not accepted_trash_id.is_empty():
		cleanup_trash_ids.append(accepted_trash_id)


func _cleanup_test_trash() -> void:
	var entries: Array = service.call("list_trashed_worlds", TRASH_CAPACITY)
	for raw_entry: Variant in entries:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var world_id := str(entry.get("world_id", ""))
		var trash_id := str(entry.get("trash_id", ""))
		if world_id.begins_with(test_prefix):
			service.call("purge_trashed_world", trash_id)
			cleanup_trash_ids.erase(trash_id)


func _cleanup() -> void:
	_cleanup_test_trash()
	for world_id: String in cleanup_world_ids:
		if bool(service.call("world_exists", world_id)):
			service.call("delete_world", world_id)


func _list_contains_world(worlds: Array, world_id: String) -> bool:
	for raw_metadata: Variant in worlds:
		if (
			raw_metadata is Dictionary
			and str(raw_metadata.get("id", "")) == world_id
		):
			return true
	return false


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _world_directory(world_id: String) -> String:
	return "user://worlds/%s" % world_id


func _world_path(world_id: String) -> String:
	return "%s/world.json" % _world_directory(world_id)


func _catalog_path(world_id: String) -> String:
	return "%s/catalog.json" % _world_directory(world_id)


func _trash_directory(trash_id: String) -> String:
	return "user://world_trash/%s" % trash_id


func _trash_world_path(trash_id: String) -> String:
	return "%s/world.json" % _trash_directory(trash_id)


func _trash_catalog_path(trash_id: String) -> String:
	return "%s/catalog.json" % _trash_directory(trash_id)


func _trash_manifest_path(trash_id: String) -> String:
	return "%s/trash.json" % _trash_directory(trash_id)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
