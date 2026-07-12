class_name AtomicJsonStore
extends RefCounted

const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


func write_dictionary(path: String, payload: Dictionary) -> bool:
	return write_text(path, JSON.stringify(payload, "\t", false))


func read_dictionary(path: String) -> Dictionary:
	var candidates := [
		{"path": path, "source": "primary"},
		{"path": "%s%s" % [path, TEMP_SUFFIX], "source": "temporary"},
		{"path": "%s%s" % [path, BACKUP_SUFFIX], "source": "backup"},
	]
	for candidate in candidates:
		var parsed := _read_candidate(str(candidate["path"]))
		if bool(parsed.get("ok", false)):
			return {
				"ok": true,
				"data": parsed.get("data", {}).duplicate(true),
				"source": str(candidate["source"]),
			}
	return {"ok": false, "data": {}, "source": "missing_or_invalid"}


func write_text(path: String, content: String) -> bool:
	_ensure_directory(path.get_base_dir())
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := "%s%s" % [absolute_path, TEMP_SUFFIX]
	var backup_path := "%s%s" % [absolute_path, BACKUP_SUFFIX]
	_remove_if_exists(temporary_path)

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
		return true

	_remove_if_exists(temporary_path)
	if had_primary and FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, absolute_path)
	return false


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or parser.data is not Dictionary:
		return {"ok": false}
	return {"ok": true, "data": parser.data}


func _ensure_directory(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _remove_if_exists(absolute_path: String) -> void:
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
