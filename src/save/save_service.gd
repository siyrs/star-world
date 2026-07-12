class_name SaveService
extends Node

signal world_saved(world_id: String)
signal world_loaded(world_id: String, state: Dictionary)
signal world_deleted(world_id: String)
signal save_failed(world_id: String, reason: String)

const SAVE_VERSION := 2
const WORLDS_DIR := "user://worlds"
const SETTINGS_PATH := "user://settings.json"


func _ready() -> void:
	_ensure_directory(WORLDS_DIR)


func create_world(display_name: String, map_id: String, seed_value: int, extra: Dictionary = {}) -> Dictionary:
	_ensure_directory(WORLDS_DIR)
	var timestamp := int(Time.get_unix_time_from_system())
	var base_id := _sanitize_id(display_name)
	if base_id.is_empty():
		base_id = map_id
	var world_id := "%s-%s" % [base_id, timestamp]
	var suffix := 2
	while world_exists(world_id):
		world_id = "%s-%s-%s" % [base_id, timestamp, suffix]
		suffix += 1
	var now := Time.get_datetime_string_from_system()
	var metadata := {
		"id": world_id,
		"name": display_name if not display_name.strip_edges().is_empty() else "新世界",
		"map_id": map_id,
		"seed": seed_value,
		"created_at": now,
		"updated_at": now,
		"play_seconds": 0
	}
	metadata.merge(extra, true)
	var state := {
		"save_version": SAVE_VERSION,
		"metadata": metadata,
		"player": {"position":[0.0, 48.0, 0.0], "rotation":[0.0, 0.0, 0.0]},
		"inventory": {},
		"world": {"block_overrides":{}, "loaded_chunks":[]},
		"survival": {"health":20.0, "hunger":20.0},
		"day_night": {"time_of_day":8.0, "day":1}
	}
	if save_world(world_id, state):
		return state
	return {}


func save_world(world_id: String, state: Dictionary) -> bool:
	if not _is_safe_id(world_id):
		save_failed.emit(world_id, "invalid_world_id")
		return false
	var world_dir := "%s/%s" % [WORLDS_DIR, world_id]
	_ensure_directory(world_dir)
	var payload := state.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	var metadata: Dictionary = payload.get("metadata", {})
	metadata["id"] = world_id
	metadata["updated_at"] = Time.get_datetime_string_from_system()
	payload["metadata"] = metadata
	var json_text := JSON.stringify(payload, "\t", false)
	if not _atomic_write("%s/world.json" % world_dir, json_text):
		save_failed.emit(world_id, "write_failed")
		return false
	world_saved.emit(world_id)
	return true


func load_world(world_id: String) -> Dictionary:
	if not _is_safe_id(world_id):
		return {}
	var path := "%s/%s/world.json" % [WORLDS_DIR, world_id]
	var payload := _read_json(path)
	if payload.is_empty():
		return {}
	payload = _migrate(payload)
	world_loaded.emit(world_id, payload.duplicate(true))
	return payload


func list_worlds() -> Array:
	_ensure_directory(WORLDS_DIR)
	var result: Array = []
	var directory := DirAccess.open(WORLDS_DIR)
	if directory == null:
		return result
	for world_id in directory.get_directories():
		var payload := load_world(world_id)
		if not payload.is_empty():
			result.append(payload.get("metadata", {}).duplicate(true))
	result.sort_custom(func(a, b): return str(a.get("updated_at", "")) > str(b.get("updated_at", "")))
	return result


func delete_world(world_id: String) -> bool:
	if not _is_safe_id(world_id) or not world_exists(world_id):
		return false
	var absolute_dir := ProjectSettings.globalize_path("%s/%s" % [WORLDS_DIR, world_id])
	var directory := DirAccess.open(absolute_dir)
	if directory == null:
		return false
	for file_name in directory.get_files():
		DirAccess.remove_absolute(absolute_dir.path_join(file_name))
	var error := DirAccess.remove_absolute(absolute_dir)
	if error == OK:
		world_deleted.emit(world_id)
		return true
	return false


func world_exists(world_id: String) -> bool:
	return _is_safe_id(world_id) and FileAccess.file_exists("%s/%s/world.json" % [WORLDS_DIR, world_id])


func save_settings(settings: Dictionary) -> bool:
	return _atomic_write(SETTINGS_PATH, JSON.stringify({"version":1, "settings":settings}, "\t", false))


func load_settings(defaults: Dictionary = {}) -> Dictionary:
	var payload := _read_json(SETTINGS_PATH)
	if payload.is_empty():
		return defaults.duplicate(true)
	var settings: Dictionary = payload.get("settings", {})
	for key in defaults:
		if not settings.has(key):
			settings[key] = defaults[key]
	return settings


func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("save_version", 1))
	if version < 2:
		if not payload.has("day_night"):
			payload["day_night"] = {"time_of_day":8.0, "day":1}
		if not payload.has("survival"):
			payload["survival"] = {"health":20.0, "hunger":20.0}
		payload["save_version"] = 2
	return payload


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _atomic_write(path: String, content: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	_ensure_directory(path.get_base_dir())
	var temporary_path := "%s.tmp" % absolute_path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	return DirAccess.rename_absolute(temporary_path, absolute_path) == OK


func _ensure_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _sanitize_id(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int() or character in ["-", "_"]:
			result += character
		elif character == " ":
			result += "-"
	return result.left(40).strip_edges()


func _is_safe_id(world_id: String) -> bool:
	return not world_id.is_empty() and world_id == world_id.get_file() and ".." not in world_id and "/" not in world_id and "\\" not in world_id
