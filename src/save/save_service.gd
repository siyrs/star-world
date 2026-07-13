class_name SaveService
extends Node

signal world_saved(world_id: String)
signal world_loaded(world_id: String, state: Dictionary)
signal world_deleted(world_id: String)
signal save_failed(world_id: String, reason: String)
signal save_recovered(world_id: String, source: String)
signal settings_saved
signal settings_save_failed(reason: String)
signal settings_recovered(source: String)

const SAVE_VERSION := 2
const WORLDS_DIR := "user://worlds"
const SETTINGS_PATH := "user://settings.json"
const AtomicJsonStoreScript = preload("res://src/save/atomic_json_store.gd")

var _store = AtomicJsonStoreScript.new()


func _ready() -> void:
	_ensure_directory(WORLDS_DIR)


func create_world(
	display_name: String, map_id: String, seed_value: int, extra: Dictionary = {}
) -> Dictionary:
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
		"play_seconds": 0,
	}
	metadata.merge(extra, true)
	var state := {
		"save_version": SAVE_VERSION,
		"metadata": metadata,
		# Empty means the generator owns first spawn selection. The old fixed Y=48
		# placeholder could leave the camera high above terrain on a sky-only view.
		"player": {"position": [], "rotation": [0.0, 0.0, 0.0], "look_pitch": 0.0},
		"inventory": {},
		"equipment": {"version": 2, "slots": {}},
		"attributes": {"version": 1, "base": {}, "sources": {}},
		"containers": {"version": 1, "containers": {}},
		"machines": {"version": 1, "saved_at_unix": timestamp, "furnaces": {}},
		"world": {"block_overrides": {}, "loaded_chunks": []},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 8.0, "day": 1},
		"experience": {"version": 1, "onboarding": {}},
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
	if not _store.write_dictionary("%s/world.json" % world_dir, payload):
		save_failed.emit(world_id, "write_failed")
		return false
	world_saved.emit(world_id)
	return true


func load_world(world_id: String) -> Dictionary:
	var payload := _read_world_payload(world_id, true)
	if payload.is_empty():
		return {}
	world_loaded.emit(world_id, payload.duplicate(true))
	return payload


func list_worlds() -> Array:
	_ensure_directory(WORLDS_DIR)
	var result: Array = []
	var directory := DirAccess.open(WORLDS_DIR)
	if directory == null:
		return result
	for world_id in directory.get_directories():
		var payload := _read_world_payload(world_id, false)
		if not payload.is_empty():
			result.append(payload.get("metadata", {}).duplicate(true))
	result.sort_custom(
		func(a, b): return str(a.get("updated_at", "")) > str(b.get("updated_at", ""))
	)
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
	return (
		_is_safe_id(world_id)
		and (
			FileAccess.file_exists("%s/%s/world.json" % [WORLDS_DIR, world_id])
			or FileAccess.file_exists("%s/%s/world.json.tmp" % [WORLDS_DIR, world_id])
			or FileAccess.file_exists("%s/%s/world.json.bak" % [WORLDS_DIR, world_id])
		)
	)


func save_settings(settings: Dictionary) -> bool:
	var saved := _store.write_dictionary(
		SETTINGS_PATH, {"version": 1, "settings": settings.duplicate(true)}
	)
	if saved:
		settings_saved.emit()
	else:
		settings_save_failed.emit("write_failed")
	return saved


func load_settings(defaults: Dictionary = {}) -> Dictionary:
	var result := _store.read_dictionary(SETTINGS_PATH)
	if not bool(result.get("ok", false)):
		return defaults.duplicate(true)
	var source := str(result.get("source", "primary"))
	if source != "primary":
		settings_recovered.emit(source)
	var payload: Dictionary = result.get("data", {})
	var settings: Dictionary = payload.get("settings", {}).duplicate(true)
	for key in defaults:
		if not settings.has(key):
			settings[key] = defaults[key]
	return settings


func _read_world_payload(world_id: String, emit_recovery: bool) -> Dictionary:
	if not _is_safe_id(world_id):
		return {}
	var path := "%s/%s/world.json" % [WORLDS_DIR, world_id]
	var result := _store.read_dictionary(path)
	if not bool(result.get("ok", false)):
		return {}
	var source := str(result.get("source", "primary"))
	if emit_recovery and source != "primary":
		save_recovered.emit(world_id, source)
	var payload: Dictionary = result.get("data", {}).duplicate(true)
	return _migrate(payload)


func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("save_version", 1))
	if version < 2:
		if not payload.has("day_night"):
			payload["day_night"] = {"time_of_day": 8.0, "day": 1}
		if not payload.has("survival"):
			payload["survival"] = {"health": 20.0, "hunger": 20.0}
		payload["save_version"] = 2
	if not payload.has("equipment") or payload["equipment"] is not Dictionary:
		payload["equipment"] = {"version": 2, "slots": {}}
	if not payload.has("attributes") or payload["attributes"] is not Dictionary:
		payload["attributes"] = {"version": 1, "base": {}, "sources": {}}
	if not payload.has("containers") or payload["containers"] is not Dictionary:
		payload["containers"] = {"version": 1, "containers": {}}
	if not payload.has("machines") or payload["machines"] is not Dictionary:
		payload["machines"] = {
			"version": 1,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"furnaces": {},
		}
	if not payload.has("experience") or payload["experience"] is not Dictionary:
		payload["experience"] = {"version": 1, "onboarding": {}}
	return payload


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
	return (
		not world_id.is_empty()
		and world_id == world_id.get_file()
		and ".." not in world_id
		and "/" not in world_id
		and "\\" not in world_id
	)
