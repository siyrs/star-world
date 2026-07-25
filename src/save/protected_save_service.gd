class_name ProtectedSaveService
extends "res://src/save/save_service.gd"

signal world_trashed(world_id: String, trash_id: String)
signal world_restored(world_id: String, trash_id: String)
signal trash_operation_failed(operation: String, target_id: String, reason: String)

const TRASH_DIR := "user://world_trash"
const TRASH_FILE_NAME := "trash.json"
const TRASH_VERSION := 1
const MAX_TRASH_ENTRIES := 32
const CatalogPolicy = preload("res://src/save/world_catalog_policy.gd")

var _trash_entry_count := 0
var _trash_success_count := 0
var _trash_restore_count := 0
var _trash_purge_count := 0
var _trash_failure_count := 0
var _last_trash_operation := ""
var _last_trash_reason := ""
var _last_trash_world_id := ""
var _last_trash_id := ""
var _last_trash_entry: Dictionary = {}


func _ready() -> void:
	super._ready()
	_ensure_directory(TRASH_DIR)
	_rebuild_trash_state()


func trash_world(world_id: String) -> Dictionary:
	if not _is_safe_id(world_id):
		return _trash_failure("trash", world_id, "invalid_world_id")
	if not world_exists(world_id):
		return _trash_failure("trash", world_id, "world_missing")
	_rebuild_trash_state()
	if _trash_entry_count >= MAX_TRASH_ENTRIES:
		return _trash_failure("trash", world_id, "trash_full")
	var trash_id := _next_trash_id(world_id)
	var entry := _build_trash_entry(world_id, trash_id)
	if entry.is_empty():
		return _trash_failure("trash", world_id, "metadata_unavailable")
	_ensure_directory(TRASH_DIR)
	var source_absolute := ProjectSettings.globalize_path(_world_directory(world_id))
	var trash_absolute := ProjectSettings.globalize_path(_trash_directory(trash_id))
	var rename_error := DirAccess.rename_absolute(source_absolute, trash_absolute)
	if rename_error != OK:
		return _trash_failure(
			"trash", world_id, "rename_failed_%d" % int(rename_error)
		)
	if not _store.write_dictionary(_trash_manifest_path(trash_id), entry):
		var rollback_error := DirAccess.rename_absolute(
			trash_absolute, source_absolute
		)
		if rollback_error == OK:
			_remove_trash_manifest_files(_world_directory(world_id))
			return _trash_failure("trash", world_id, "manifest_write_failed")
		_rebuild_trash_state()
		return _trash_failure(
			"trash",
			world_id,
			"manifest_write_failed_rollback_failed_%d" % int(rollback_error)
		)
	_staged_catalog_entries.erase(world_id)
	_trash_success_count += 1
	_record_trash_operation("trash", world_id, trash_id, "ok")
	_rebuild_trash_state()
	world_deleted.emit(world_id)
	world_trashed.emit(world_id, trash_id)
	return {
		"ok": true,
		"reason": "ok",
		"world_id": world_id,
		"trash_id": trash_id,
		"entry": entry.duplicate(true),
	}


func restore_trashed_world(trash_id: String) -> Dictionary:
	if not _is_safe_id(trash_id):
		return _trash_failure("restore", trash_id, "invalid_trash_id")
	var entry := _read_trash_entry(trash_id)
	if entry.is_empty():
		return _trash_failure("restore", trash_id, "trash_missing_or_invalid")
	var world_id := str(entry.get("world_id", ""))
	if not _is_safe_id(world_id):
		return _trash_failure("restore", trash_id, "invalid_world_id")
	if world_exists(world_id) or DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(_world_directory(world_id))
	):
		return _trash_failure("restore", trash_id, "world_exists")
	_ensure_directory(WORLDS_DIR)
	var trash_absolute := ProjectSettings.globalize_path(_trash_directory(trash_id))
	var world_absolute := ProjectSettings.globalize_path(_world_directory(world_id))
	var rename_error := DirAccess.rename_absolute(trash_absolute, world_absolute)
	if rename_error != OK:
		return _trash_failure(
			"restore", trash_id, "rename_failed_%d" % int(rename_error)
		)
	_remove_trash_manifest_files(_world_directory(world_id))
	_staged_catalog_entries.erase(world_id)
	_trash_restore_count += 1
	_record_trash_operation("restore", world_id, trash_id, "ok")
	_rebuild_trash_state()
	world_restored.emit(world_id, trash_id)
	return {
		"ok": true,
		"reason": "ok",
		"world_id": world_id,
		"trash_id": trash_id,
		"entry": entry.duplicate(true),
	}


func purge_trashed_world(trash_id: String) -> bool:
	if not _is_safe_id(trash_id):
		_trash_failure("purge", trash_id, "invalid_trash_id")
		return false
	var entry := _read_trash_entry(trash_id)
	if entry.is_empty():
		_trash_failure("purge", trash_id, "trash_missing_or_invalid")
		return false
	if not _remove_directory_recursive(
		ProjectSettings.globalize_path(_trash_directory(trash_id))
	):
		_trash_failure("purge", trash_id, "remove_failed")
		return false
	_trash_purge_count += 1
	_record_trash_operation(
		"purge", str(entry.get("world_id", "")), trash_id, "ok"
	)
	_rebuild_trash_state()
	return true


func list_trashed_worlds(limit: int = MAX_TRASH_ENTRIES) -> Array:
	_ensure_directory(TRASH_DIR)
	var directory := DirAccess.open(TRASH_DIR)
	var result: Array = []
	if directory == null:
		return result
	var trash_ids: PackedStringArray = directory.get_directories()
	trash_ids.sort()
	for raw_trash_id: String in trash_ids:
		var entry := _read_trash_entry(str(raw_trash_id))
		if not entry.is_empty():
			result.append(entry)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_deleted := int(left.get("deleted_unix", 0))
			var right_deleted := int(right.get("deleted_unix", 0))
			if left_deleted != right_deleted:
				return left_deleted > right_deleted
			return str(left.get("trash_id", "")) > str(
				right.get("trash_id", "")
			)
	)
	var safe_limit := clampi(limit, 0, MAX_TRASH_ENTRIES)
	if result.size() > safe_limit:
		result.resize(safe_limit)
	return result


func get_last_trashed_world() -> Dictionary:
	return _last_trash_entry.duplicate(true)


func get_trash_diagnostics() -> Dictionary:
	return {
		"trash_capacity": MAX_TRASH_ENTRIES,
		"trash_entry_count": _trash_entry_count,
		"trash_success_count": _trash_success_count,
		"restore_success_count": _trash_restore_count,
		"purge_success_count": _trash_purge_count,
		"failure_count": _trash_failure_count,
		"last_operation": _last_trash_operation,
		"last_reason": _last_trash_reason,
		"last_world_id": _last_trash_world_id,
		"last_trash_id": _last_trash_id,
		"undo_available": not _last_trash_entry.is_empty(),
	}


func reset_trash_diagnostics() -> void:
	_trash_success_count = 0
	_trash_restore_count = 0
	_trash_purge_count = 0
	_trash_failure_count = 0
	_last_trash_operation = ""
	_last_trash_reason = ""


func _build_trash_entry(world_id: String, trash_id: String) -> Dictionary:
	var metadata := _deferred_world_metadata(world_id)
	var catalog_read: Dictionary = _read_catalog_entry(world_id)
	if not catalog_read.is_empty():
		metadata = CatalogPolicy.metadata_for_list(
			catalog_read.get("entry", {}), "catalog"
		)
	var world_bytes := _file_size(_world_path(world_id))
	if metadata.is_empty() or world_bytes <= 0:
		return {}
	var deleted_unix := int(Time.get_unix_time_from_system())
	return {
		"version": TRASH_VERSION,
		"trash_id": trash_id,
		"world_id": world_id,
		"name": str(metadata.get("name", world_id)).left(128),
		"map_id": str(metadata.get("map_id", "")).left(64),
		"seed": int(metadata.get("seed", 0)),
		"save_bytes": world_bytes,
		"deleted_unix": deleted_unix,
		"deleted_at": Time.get_datetime_string_from_unix_time(deleted_unix),
	}


func _read_trash_entry(trash_id: String) -> Dictionary:
	if not _is_safe_id(trash_id):
		return {}
	var result := _store.read_dictionary(_trash_manifest_path(trash_id))
	if not bool(result.get("ok", false)):
		return {}
	var raw_entry: Variant = result.get("data", {})
	if raw_entry is not Dictionary:
		return {}
	var entry: Dictionary = raw_entry
	var world_id := str(entry.get("world_id", ""))
	if (
		int(entry.get("version", 0)) != TRASH_VERSION
		or str(entry.get("trash_id", "")) != trash_id
		or not _is_safe_id(world_id)
	):
		return {}
	return {
		"version": TRASH_VERSION,
		"trash_id": trash_id,
		"world_id": world_id,
		"name": str(entry.get("name", world_id)).left(128),
		"map_id": str(entry.get("map_id", "")).left(64),
		"seed": int(entry.get("seed", 0)),
		"save_bytes": maxi(0, int(entry.get("save_bytes", 0))),
		"deleted_unix": maxi(0, int(entry.get("deleted_unix", 0))),
		"deleted_at": str(entry.get("deleted_at", "")).left(64),
	}


func _rebuild_trash_state() -> void:
	var entries := list_trashed_worlds(MAX_TRASH_ENTRIES)
	_trash_entry_count = entries.size()
	if entries.is_empty():
		_last_trash_entry.clear()
		_last_trash_id = ""
		return
	_last_trash_entry = (entries[0] as Dictionary).duplicate(true)
	_last_trash_id = str(_last_trash_entry.get("trash_id", ""))


func _next_trash_id(world_id: String) -> String:
	var timestamp := int(Time.get_unix_time_from_system())
	var base_id := _sanitize_id("%s-trashed-%d" % [world_id, timestamp])
	var trash_id := base_id
	var suffix := 2
	while DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(_trash_directory(trash_id))
	):
		trash_id = "%s-%d" % [base_id, suffix]
		suffix += 1
	return trash_id


func _record_trash_operation(
	operation: String,
	world_id: String,
	trash_id: String,
	reason: String
) -> void:
	_last_trash_operation = operation.left(32)
	_last_trash_reason = reason.left(64)
	_last_trash_world_id = world_id.left(128)
	_last_trash_id = trash_id.left(192)


func _trash_failure(
	operation: String,
	target_id: String,
	reason: String
) -> Dictionary:
	_trash_failure_count += 1
	_record_trash_operation(operation, target_id, "", reason)
	trash_operation_failed.emit(operation, target_id, reason)
	return {
		"ok": false,
		"reason": reason,
		"world_id": target_id if operation == "trash" else "",
		"trash_id": target_id if operation != "trash" else "",
	}


func _remove_trash_manifest_files(directory_path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".recover", ".corrupt"]:
		var path := "%s/%s%s" % [directory_path, TRASH_FILE_NAME, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_directory_recursive(absolute_path: String) -> bool:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if DirAccess.remove_absolute(absolute_path.path_join(file_name)) != OK:
			return false
	for child_name: String in directory.get_directories():
		if not _remove_directory_recursive(absolute_path.path_join(child_name)):
			return false
	return DirAccess.remove_absolute(absolute_path) == OK


func _trash_directory(trash_id: String) -> String:
	return "%s/%s" % [TRASH_DIR, trash_id]


func _trash_manifest_path(trash_id: String) -> String:
	return "%s/%s" % [_trash_directory(trash_id), TRASH_FILE_NAME]
