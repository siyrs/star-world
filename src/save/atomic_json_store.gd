class_name AtomicJsonStore
extends RefCounted

const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
const RECOVERY_SUFFIX := ".recover"
const DISPLACED_SUFFIX := ".corrupt"
const MAX_REJECTED_SOURCES := 3


func write_dictionary(path: String, payload: Dictionary) -> bool:
	return write_text(path, JSON.stringify(payload, "\t", false))


func read_dictionary(path: String) -> Dictionary:
	return read_dictionary_validated(path)


func read_dictionary_validated(
	path: String,
	validator: Callable = Callable(),
	repair_primary: bool = false
) -> Dictionary:
	var candidates: Array[Dictionary] = [
		{"path": path, "source": "primary"},
		{"path": "%s%s" % [path, TEMP_SUFFIX], "source": "temporary"},
		{"path": "%s%s" % [path, BACKUP_SUFFIX], "source": "backup"},
	]
	var rejected_sources: Array[String] = []
	for candidate: Dictionary in candidates:
		var candidate_path := str(candidate.get("path", ""))
		var source := str(candidate.get("source", ""))
		var parsed := _read_candidate(candidate_path)
		if not bool(parsed.get("ok", false)):
			continue
		var data: Dictionary = parsed.get("data", {})
		if validator.is_valid() and not bool(validator.call(data)):
			if rejected_sources.size() < MAX_REJECTED_SOURCES:
				rejected_sources.append(source)
			continue
		var repair := {
			"attempted": false,
			"ok": source == "primary",
			"bytes": int(parsed.get("bytes", 0)) if source == "primary" else 0,
			"elapsed_usec": 0,
			"elapsed_milliseconds": 0.0,
			"reason": "",
		}
		if repair_primary and source != "primary":
			repair = repair_dictionary(path, data)
		return {
			"ok": true,
			"data": data.duplicate(true),
			"source": source,
			"candidate_bytes": maxi(0, int(parsed.get("bytes", 0))),
			"rejected_sources": rejected_sources.duplicate(),
			"repair_attempted": bool(repair.get("attempted", false)),
			"repair_success": bool(repair.get("ok", false)),
			"repair_bytes": maxi(0, int(repair.get("bytes", 0))),
			"repair_elapsed_usec": maxi(0, int(repair.get("elapsed_usec", 0))),
			"repair_elapsed_milliseconds": maxf(
				0.0, float(repair.get("elapsed_milliseconds", 0.0))
			),
			"repair_reason": str(repair.get("reason", "")),
		}
	return {
		"ok": false,
		"data": {},
		"source": "missing_or_invalid",
		"candidate_bytes": 0,
		"rejected_sources": rejected_sources.duplicate(),
		"repair_attempted": false,
		"repair_success": false,
		"repair_bytes": 0,
		"repair_elapsed_usec": 0,
		"repair_elapsed_milliseconds": 0.0,
		"repair_reason": "no_valid_candidate",
	}


func repair_dictionary(path: String, payload: Dictionary) -> Dictionary:
	var started_at := Time.get_ticks_usec()
	var result := {
		"attempted": true,
		"ok": false,
		"bytes": 0,
		"reason": "invalid_path",
	}
	if not path.is_empty():
		result = _repair_text(path, JSON.stringify(payload, "\t", false))
		result["attempted"] = true
	var elapsed_usec := maxi(0, Time.get_ticks_usec() - started_at)
	result["elapsed_usec"] = elapsed_usec
	result["elapsed_milliseconds"] = float(elapsed_usec) / 1000.0
	return result


func write_text(path: String, content: String) -> bool:
	_ensure_directory(path.get_base_dir())
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := "%s%s" % [absolute_path, TEMP_SUFFIX]
	var backup_path := "%s%s" % [absolute_path, BACKUP_SUFFIX]
	var recovery_path := "%s%s" % [absolute_path, RECOVERY_SUFFIX]
	var displaced_path := "%s%s" % [absolute_path, DISPLACED_SUFFIX]
	_remove_if_exists(temporary_path)
	_remove_if_exists(recovery_path)

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(temporary_path)
		return false

	var had_primary := FileAccess.file_exists(absolute_path)
	if had_primary:
		_remove_if_exists(backup_path)
		if DirAccess.rename_absolute(absolute_path, backup_path) != OK:
			_remove_if_exists(temporary_path)
			return false

	if DirAccess.rename_absolute(temporary_path, absolute_path) == OK:
		_remove_if_exists(displaced_path)
		return true

	_remove_if_exists(temporary_path)
	if had_primary and FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, absolute_path)
	return false


func _repair_text(path: String, content: String) -> Dictionary:
	_ensure_directory(path.get_base_dir())
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := "%s%s" % [absolute_path, TEMP_SUFFIX]
	var recovery_path := "%s%s" % [absolute_path, RECOVERY_SUFFIX]
	var displaced_path := "%s%s" % [absolute_path, DISPLACED_SUFFIX]
	_remove_if_exists(recovery_path)

	var file := FileAccess.open(recovery_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "bytes": 0, "reason": "recovery_open_failed"}
	file.store_string(content)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(recovery_path)
		return {"ok": false, "bytes": 0, "reason": "recovery_write_failed"}

	var verification := _read_candidate(recovery_path)
	if not bool(verification.get("ok", false)):
		_remove_if_exists(recovery_path)
		return {"ok": false, "bytes": 0, "reason": "recovery_validation_failed"}

	var had_primary := FileAccess.file_exists(absolute_path)
	if had_primary:
		_remove_if_exists(displaced_path)
		if DirAccess.rename_absolute(absolute_path, displaced_path) != OK:
			_remove_if_exists(recovery_path)
			return {"ok": false, "bytes": 0, "reason": "primary_displace_failed"}

	if DirAccess.rename_absolute(recovery_path, absolute_path) != OK:
		_remove_if_exists(recovery_path)
		if had_primary and FileAccess.file_exists(displaced_path):
			DirAccess.rename_absolute(displaced_path, absolute_path)
		return {"ok": false, "bytes": 0, "reason": "primary_promote_failed"}

	# A successfully promoted primary is now authoritative. The validated backup is
	# deliberately preserved, while stale temporary and displaced files are bounded
	# to zero so future reads cannot repeat the same recovery.
	_remove_if_exists(temporary_path)
	_remove_if_exists(displaced_path)
	return {
		"ok": true,
		"bytes": maxi(0, int(verification.get("bytes", 0))),
		"reason": "",
	}


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "bytes": 0}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "bytes": 0}
	var bytes := int(file.get_length())
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or parser.data is not Dictionary:
		return {"ok": false, "bytes": bytes}
	return {"ok": true, "data": parser.data, "bytes": bytes}


func _ensure_directory(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _remove_if_exists(absolute_path: String) -> void:
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
