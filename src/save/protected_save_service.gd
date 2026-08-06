class_name ProtectedSaveService
extends "res://src/save/save_service.gd"

signal world_trashed(world_id: String, trash_id: String)
signal world_restored(world_id: String, trash_id: String)
signal trash_slot_purged(trash_id: String, world_id: String, was_valid: bool)
signal trash_operation_failed(operation: String, target_id: String, reason: String)

const TRASH_DIR := "user://world_trash"
const TRASH_FILE_NAME := "trash.json"
const TRASH_VERSION := 1
const MAX_TRASH_ENTRIES := 32
const MAX_TRASH_SCAN_ENTRIES := 64
const CatalogPolicy = preload("res://src/save/world_catalog_policy.gd")

var _trash_entry_count := 0
var _trash_valid_entry_count := 0
var _trash_invalid_entry_count := 0
var _trash_overflow_entry_count := 0
var _trash_scan_count := 0
var _trash_success_count := 0
var _trash_restore_count := 0
var _trash_purge_count := 0
var _trash_failure_count := 0
var _latest_trash_deleted_usec := 0
var _last_trash_operation := ""
var _last_trash_reason := ""
var _last_trash_world_id := ""
var _last_trash_id := ""
var _last_trash_entry: Dictionary = {}
var _restore_integrity_check_count := 0
var _restore_integrity_failure_count := 0
var _restore_repair_attempt_count := 0
var _restore_repair_success_count := 0
var _restore_repair_failure_count := 0
var _last_restore_source := ""
var _last_restore_integrity_reason := ""


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
		var rollback_error := DirAccess.rename_absolute(trash_absolute, source_absolute)
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
	if not bool(entry.get("valid", false)):
		_restore_integrity_check_count += 1
		_restore_integrity_failure_count += 1
		_last_restore_source = str(
			entry.get("integrity_source", "missing_or_invalid")
		).left(32)
		_last_restore_integrity_reason = str(
			entry.get("reason", "world_payload_unrecoverable")
		).left(64)
		return _trash_failure(
			"restore", trash_id, str(entry.get("reason", "trash_missing_or_invalid"))
		)
	var world_id := str(entry.get("world_id", ""))
	if not _is_safe_id(world_id):
		return _trash_failure("restore", trash_id, "invalid_world_id")
	if world_exists(world_id) or DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(_world_directory(world_id))
	):
		return _trash_failure("restore", trash_id, "world_exists")
	var prepared := _prepare_trash_restore(trash_id, world_id)
	if not bool(prepared.get("ok", false)):
		return _trash_failure(
			"restore", trash_id, str(prepared.get("reason", "world_payload_unrecoverable"))
		)
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
		"recovery_source": str(prepared.get("source", "primary")),
		"repaired_primary": bool(prepared.get("repaired_primary", false)),
		"entry": entry.duplicate(true),
	}


func purge_trashed_world(trash_id: String) -> bool:
	if not _is_safe_id(trash_id):
		_trash_failure("purge", trash_id, "invalid_trash_id")
		return false
	var entry := _read_trash_entry(trash_id)
	if entry.is_empty() or not bool(entry.get("valid", false)):
		_trash_failure("purge", trash_id, "trash_missing_or_invalid")
		return false
	return purge_trash_slot(trash_id)


func purge_trash_slot(trash_id: String) -> bool:
	if not _is_safe_id(trash_id):
		_trash_failure("purge_slot", trash_id, "invalid_trash_id")
		return false
	var trash_absolute := ProjectSettings.globalize_path(_trash_directory(trash_id))
	if not DirAccess.dir_exists_absolute(trash_absolute):
		_trash_failure("purge_slot", trash_id, "trash_missing")
		return false
	var entry := _read_trash_entry(trash_id)
	var was_valid := not entry.is_empty() and bool(entry.get("valid", false))
	var world_id := str(entry.get("world_id", "")) if was_valid else ""
	if not _remove_directory_recursive(trash_absolute):
		_trash_failure("purge_slot", trash_id, "remove_failed")
		return false
	_trash_purge_count += 1
	_record_trash_operation("purge_slot", world_id, trash_id, "ok")
	_rebuild_trash_state()
	trash_slot_purged.emit(trash_id, world_id, was_valid)
	return true


func list_trash_slots(limit: int = MAX_TRASH_ENTRIES) -> Array:
	_ensure_directory(TRASH_DIR)
	var directory := DirAccess.open(TRASH_DIR)
	var result: Array = []
	if directory == null:
		_record_trash_scan(0, 0, 0, 0, 0)
		return result
	var trash_ids: PackedStringArray = directory.get_directories()
	trash_ids.sort()
	var physical_count := trash_ids.size()
	var scan_limit := mini(physical_count, MAX_TRASH_SCAN_ENTRIES)
	var valid_count := 0
	var invalid_count := 0
	var latest_deleted_usec := 0
	for index in scan_limit:
		var trash_id := str(trash_ids[index])
		var entry := _read_trash_entry(trash_id)
		if entry.is_empty():
			entry = _invalid_trash_slot(trash_id)
		if bool(entry.get("valid", false)):
			valid_count += 1
			latest_deleted_usec = maxi(
				latest_deleted_usec,
				int(entry.get("deleted_unix_usec", 0))
			)
		else:
			invalid_count += 1
		result.append(entry)
	result.sort_custom(Callable(self, "_sort_trash_slots"))
	_record_trash_scan(
		physical_count,
		valid_count,
		invalid_count,
		maxi(0, physical_count - scan_limit),
		latest_deleted_usec
	)
	var safe_limit := clampi(limit, 0, MAX_TRASH_ENTRIES)
	if result.size() > safe_limit:
		result.resize(safe_limit)
	return result


func list_trashed_worlds(limit: int = MAX_TRASH_ENTRIES) -> Array:
	var result: Array = []
	for raw_entry: Variant in list_trash_slots(MAX_TRASH_ENTRIES):
		if raw_entry is Dictionary and bool(raw_entry.get("valid", false)):
			result.append(raw_entry)
	var safe_limit := clampi(limit, 0, MAX_TRASH_ENTRIES)
	if result.size() > safe_limit:
		result.resize(safe_limit)
	return result


func get_last_trashed_world() -> Dictionary:
	return _last_trash_entry.duplicate(true)


func get_trash_diagnostics() -> Dictionary:
	return {
		"trash_capacity": MAX_TRASH_ENTRIES,
		"trash_scan_capacity": MAX_TRASH_SCAN_ENTRIES,
		"trash_entry_count": _trash_entry_count,
		"valid_entry_count": _trash_valid_entry_count,
		"invalid_entry_count": _trash_invalid_entry_count,
		"overflow_entry_count": _trash_overflow_entry_count,
		"scan_count": _trash_scan_count,
		"trash_success_count": _trash_success_count,
		"restore_success_count": _trash_restore_count,
		"restore_integrity_check_count": _restore_integrity_check_count,
		"restore_integrity_failure_count": _restore_integrity_failure_count,
		"restore_repair_attempt_count": _restore_repair_attempt_count,
		"restore_repair_success_count": _restore_repair_success_count,
		"restore_repair_failure_count": _restore_repair_failure_count,
		"last_restore_source": _last_restore_source,
		"last_restore_integrity_reason": _last_restore_integrity_reason,
		"purge_success_count": _trash_purge_count,
		"failure_count": _trash_failure_count,
		"last_operation": _last_trash_operation,
		"last_reason": _last_trash_reason,
		"last_world_id": _last_trash_world_id,
		"last_trash_id": _last_trash_id,
		"latest_deleted_unix_usec": _latest_trash_deleted_usec,
		"undo_available": not _last_trash_entry.is_empty(),
	}


func reset_trash_diagnostics() -> void:
	_trash_success_count = 0
	_trash_restore_count = 0
	_trash_purge_count = 0
	_trash_failure_count = 0
	_restore_integrity_check_count = 0
	_restore_integrity_failure_count = 0
	_restore_repair_attempt_count = 0
	_restore_repair_success_count = 0
	_restore_repair_failure_count = 0
	_last_restore_source = ""
	_last_restore_integrity_reason = ""
	_last_trash_operation = ""
	_last_trash_reason = ""


func _build_trash_entry(world_id: String, trash_id: String) -> Dictionary:
	var metadata := _deferred_world_metadata(world_id)
	var catalog_read: Dictionary = _read_catalog_entry(world_id)
	if not catalog_read.is_empty():
		metadata = CatalogPolicy.metadata_for_list(
			catalog_read.get("entry", {}), "catalog"
		)
	var world_bytes := maxi(
		_file_size(_world_path(world_id)),
		maxi(0, int(metadata.get("save_bytes", 0)))
	)
	if metadata.is_empty() or world_bytes <= 0:
		return {}
	var deleted_unix_value := Time.get_unix_time_from_system()
	var deleted_unix_usec := int(deleted_unix_value * 1000000.0)
	deleted_unix_usec = maxi(deleted_unix_usec, _latest_trash_deleted_usec + 1)
	var deleted_unix := int(deleted_unix_usec / 1000000)
	return {
		"version": TRASH_VERSION,
		"trash_id": trash_id,
		"world_id": world_id,
		"name": str(metadata.get("name", world_id)).left(128),
		"map_id": str(metadata.get("map_id", "")).left(64),
		"seed": int(metadata.get("seed", 0)),
		"save_bytes": world_bytes,
		"deleted_unix": deleted_unix,
		"deleted_unix_usec": deleted_unix_usec,
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
	var deleted_unix := maxi(0, int(entry.get("deleted_unix", 0)))
	var deleted_unix_usec := maxi(
		deleted_unix * 1000000,
		int(entry.get("deleted_unix_usec", 0))
	)
	var integrity := _read_trash_world_integrity(trash_id, world_id)
	var projected := {
		"version": TRASH_VERSION,
		"trash_id": trash_id,
		"world_id": world_id,
		"name": str(entry.get("name", world_id)).left(128),
		"map_id": str(entry.get("map_id", "")).left(64),
		"seed": int(entry.get("seed", 0)),
		"save_bytes": maxi(
			maxi(0, int(entry.get("save_bytes", 0))),
			maxi(0, int(integrity.get("candidate_bytes", 0)))
		),
		"deleted_unix": deleted_unix,
		"deleted_unix_usec": deleted_unix_usec,
		"deleted_at": str(entry.get("deleted_at", "")).left(64),
		"valid": bool(integrity.get("ok", false)),
		"restorable": bool(integrity.get("ok", false)),
		"purgeable": true,
		"reason": str(integrity.get("reason", "world_payload_unrecoverable")),
		"integrity_source": str(integrity.get("source", "missing_or_invalid")),
		"requires_primary_repair": (
			bool(integrity.get("ok", false))
			and str(integrity.get("source", "")) != "primary"
		),
		"rejected_sources": integrity.get("rejected_sources", []).duplicate(),
	}
	if bool(projected.get("valid", false)):
		projected["reason"] = "ok"
	return projected


func _read_trash_world_integrity(trash_id: String, world_id: String) -> Dictionary:
	var world_path := "%s/%s" % [_trash_directory(trash_id), WORLD_FILE_NAME]
	var validator := func(payload: Dictionary) -> bool:
		return _is_valid_world_payload(payload, world_id)
	var result: Dictionary = _store.read_dictionary_validated(
		world_path, validator, false
	)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"reason": "world_payload_unrecoverable",
			"source": str(result.get("source", "missing_or_invalid")),
			"candidate_bytes": maxi(0, int(result.get("candidate_bytes", 0))),
			"rejected_sources": result.get("rejected_sources", []).duplicate(),
			"payload": {},
		}
	return {
		"ok": true,
		"reason": "ok",
		"source": str(result.get("source", "primary")),
		"candidate_bytes": maxi(0, int(result.get("candidate_bytes", 0))),
		"rejected_sources": result.get("rejected_sources", []).duplicate(),
		"payload": (result.get("data", {}) as Dictionary).duplicate(true),
	}


func _prepare_trash_restore(trash_id: String, world_id: String) -> Dictionary:
	_restore_integrity_check_count += 1
	var integrity := _read_trash_world_integrity(trash_id, world_id)
	_last_restore_source = str(integrity.get("source", "missing_or_invalid")).left(32)
	if not bool(integrity.get("ok", false)):
		_restore_integrity_failure_count += 1
		_last_restore_integrity_reason = str(
			integrity.get("reason", "world_payload_unrecoverable")
		).left(64)
		return integrity
	if _last_restore_source == "primary":
		_last_restore_integrity_reason = "ok"
		return {
			"ok": true,
			"reason": "ok",
			"source": "primary",
			"repaired_primary": false,
		}
	_restore_repair_attempt_count += 1
	var world_path := "%s/%s" % [_trash_directory(trash_id), WORLD_FILE_NAME]
	var repair: Dictionary = _store.repair_dictionary(
		world_path, integrity.get("payload", {})
	)
	if not bool(repair.get("ok", false)):
		_restore_integrity_failure_count += 1
		_restore_repair_failure_count += 1
		_last_restore_integrity_reason = str(
			repair.get("reason", "primary_repair_failed")
		).left(64)
		return {
			"ok": false,
			"reason": "primary_repair_failed",
			"source": _last_restore_source,
			"repaired_primary": false,
		}
	var verified := _read_trash_world_integrity(trash_id, world_id)
	if (
		not bool(verified.get("ok", false))
		or str(verified.get("source", "")) != "primary"
	):
		_restore_integrity_failure_count += 1
		_restore_repair_failure_count += 1
		_last_restore_integrity_reason = "primary_repair_verification_failed"
		return {
			"ok": false,
			"reason": "primary_repair_verification_failed",
			"source": _last_restore_source,
			"repaired_primary": false,
		}
	_restore_repair_success_count += 1
	_last_restore_integrity_reason = "ok"
	_remove_trash_catalog_artifacts(trash_id)
	return {
		"ok": true,
		"reason": "ok",
		"source": _last_restore_source,
		"repaired_primary": true,
	}


func _remove_trash_catalog_artifacts(trash_id: String) -> void:
	var directory_path := _trash_directory(trash_id)
	for file_name: String in [CATALOG_FILE_NAME, CATALOG_PENDING_FILE_NAME]:
		for suffix: String in ["", ".tmp", ".bak", ".recover", ".corrupt"]:
			var path := "%s/%s%s" % [directory_path, file_name, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _invalid_trash_slot(trash_id: String) -> Dictionary:
	var safe_id := _is_safe_id(trash_id)
	if not safe_id:
		return {
			"version": TRASH_VERSION,
			"trash_id": trash_id.left(192),
			"world_id": "",
			"name": "不安全的回收站目录",
			"map_id": "unsafe_trash_id",
			"seed": 0,
			"save_bytes": 0,
			"deleted_unix": 0,
			"deleted_unix_usec": 0,
			"deleted_at": "",
			"valid": false,
			"restorable": false,
			"purgeable": false,
			"reason": "unsafe_trash_id",
		}
	var world_path := "%s/%s" % [_trash_directory(trash_id), WORLD_FILE_NAME]
	var catalog_path := "%s/%s" % [_trash_directory(trash_id), CATALOG_FILE_NAME]
	var candidates: Array[String] = [
		world_path,
		"%s.tmp" % world_path,
		"%s.bak" % world_path,
		catalog_path,
		_trash_manifest_path(trash_id),
	]
	var save_bytes := 0
	var modified_unix := 0
	for path: String in candidates:
		if not FileAccess.file_exists(path):
			continue
		save_bytes = maxi(save_bytes, _file_size(path))
		modified_unix = maxi(modified_unix, int(FileAccess.get_modified_time(path)))
	return {
		"version": TRASH_VERSION,
		"trash_id": trash_id.left(192),
		"world_id": "",
		"name": "损坏的回收站条目",
		"map_id": "invalid_manifest",
		"seed": 0,
		"save_bytes": save_bytes,
		"deleted_unix": modified_unix,
		"deleted_unix_usec": modified_unix * 1000000,
		"deleted_at": (
			Time.get_datetime_string_from_unix_time(modified_unix)
			if modified_unix > 0
			else ""
		),
		"valid": false,
		"restorable": false,
		"purgeable": true,
		"reason": "manifest_missing_or_invalid",
	}


func _sort_trash_slots(left: Dictionary, right: Dictionary) -> bool:
	var left_deleted := int(left.get("deleted_unix_usec", 0))
	var right_deleted := int(right.get("deleted_unix_usec", 0))
	if left_deleted != right_deleted:
		return left_deleted > right_deleted
	return str(left.get("trash_id", "")).naturalnocasecmp_to(
		str(right.get("trash_id", ""))
	) > 0


func _record_trash_scan(
	physical_count: int,
	valid_count: int,
	invalid_count: int,
	overflow_count: int,
	latest_deleted_usec: int
) -> void:
	_trash_scan_count += 1
	_trash_entry_count = maxi(0, physical_count)
	_trash_valid_entry_count = maxi(0, valid_count)
	_trash_invalid_entry_count = maxi(0, invalid_count)
	_trash_overflow_entry_count = maxi(0, overflow_count)
	_latest_trash_deleted_usec = maxi(0, latest_deleted_usec)


func _rebuild_trash_state() -> void:
	var slots := list_trash_slots(MAX_TRASH_ENTRIES)
	_last_trash_entry.clear()
	_last_trash_id = ""
	for raw_entry: Variant in slots:
		if raw_entry is not Dictionary or not bool(raw_entry.get("valid", false)):
			continue
		_last_trash_entry = (raw_entry as Dictionary).duplicate(true)
		_last_trash_id = str(_last_trash_entry.get("trash_id", ""))
		break


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
