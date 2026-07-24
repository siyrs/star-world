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
const WORLD_FILE_NAME := "world.json"
const CATALOG_FILE_NAME := "catalog.json"
const MAX_PRIMARY_REPAIRS_PER_LIST := 8
const MAX_CATALOG_REBUILDS_PER_LIST := 16
const MAX_AUTHORITATIVE_READS_PER_LIST := 32
const AtomicJsonStoreScript = preload("res://src/save/atomic_json_store.gd")
const WorldCatalogPolicyScript = preload("res://src/save/world_catalog_policy.gd")

var _store = AtomicJsonStoreScript.new()
var _catalog_list_count := 0
var _catalog_hit_count := 0
var _catalog_fallback_count := 0
var _catalog_repair_count := 0
var _catalog_write_failure_count := 0
var _last_catalog_world_count := 0
var _last_catalog_hit_count := 0
var _last_catalog_fallback_count := 0
var _last_catalog_repair_count := 0
var _last_catalog_avoided_world_bytes := 0
var _last_catalog_elapsed_usec := 0
var _catalog_deferred_recovery_count := 0
var _last_catalog_deferred_recovery_count := 0
var _last_catalog_repair_budget_used := 0
var _catalog_deferred_rebuild_count := 0
var _last_catalog_deferred_rebuild_count := 0
var _last_catalog_rebuild_budget_used := 0
var _catalog_deferred_authoritative_read_count := 0
var _last_catalog_deferred_authoritative_read_count := 0
var _last_catalog_authoritative_read_budget_used := 0
var _recovery_count := 0
var _recovery_repair_attempt_count := 0
var _recovery_repair_success_count := 0
var _recovery_repair_failure_count := 0
var _recovery_primary_rejection_count := 0
var _last_recovery_world_id := ""
var _last_recovery_source := ""
var _last_recovery_repaired := false
var _last_recovery_candidate_bytes := 0
var _last_recovery_primary_bytes := 0
var _last_recovery_elapsed_usec := 0
var _last_recovery_rejected_sources: Array[String] = []


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
		"agriculture": {
			"version": 2,
			"saved_at_unix": timestamp,
			"crops": {},
			"soil_moisture": {"version": 1, "soils": {}},
		},
		"husbandry": {
			"version": 1,
			"saved_at_unix": timestamp,
			"animals": {},
		},
		"containers": {"version": 1, "containers": {}},
		"machines": {"version": 1, "saved_at_unix": timestamp, "furnaces": {}},
		"world": {"block_overrides": {}},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 8.0, "day": 1},
		"rest": {
			"version": 1,
			"has_custom_spawn": false,
			"bed_position": [],
			"respawn_position": [],
		},
		"experience": {"version": 1, "onboarding": {}},
		"exploration": {"version": 3, "records": [], "last_result": {}},
		"exploration_rewards": {"version": 1, "claimed": []},
	}
	if save_world(world_id, state):
		return state
	return {}


func save_world(world_id: String, state: Dictionary) -> bool:
	if not _is_safe_id(world_id):
		save_failed.emit(world_id, "invalid_world_id")
		return false
	var world_dir := _world_directory(world_id)
	_ensure_directory(world_dir)
	var payload := state.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	var raw_metadata: Variant = payload.get("metadata", {})
	var metadata: Dictionary = {}
	if raw_metadata is Dictionary:
		metadata = raw_metadata.duplicate(true)
	metadata["id"] = world_id
	metadata["updated_at"] = Time.get_datetime_string_from_system()
	payload["metadata"] = metadata
	_strip_transient_world_state(payload)
	var world_path := _world_path(world_id)
	if not _store.write_dictionary(world_path, payload):
		save_failed.emit(world_id, "write_failed")
		return false
	var save_bytes := _file_size(world_path)
	if not _write_catalog_entry(world_id, payload, save_bytes):
		# The catalog is derived and self-healing. A catalog failure must never turn
		# a successful authoritative world write into a false save failure.
		_catalog_write_failure_count += 1
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
	var started_at := Time.get_ticks_usec()
	var result: Array = []
	var hit_count := 0
	var fallback_count := 0
	var repair_count := 0
	var deferred_recovery_count := 0
	var repair_budget_used := 0
	var deferred_catalog_rebuild_count := 0
	var catalog_rebuild_budget_used := 0
	var deferred_authoritative_read_count := 0
	var authoritative_read_budget_used := 0
	var avoided_world_bytes := 0
	var directory := DirAccess.open(WORLDS_DIR)
	if directory == null:
		_record_catalog_list(
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			Time.get_ticks_usec() - started_at
		)
		return result
	var world_ids: PackedStringArray = directory.get_directories()
	world_ids.sort()
	for raw_world_id: String in world_ids:
		var world_id := str(raw_world_id)
		var metadata: Dictionary = {}
		var catalog_read: Dictionary = _read_catalog_entry(world_id)
		if not catalog_read.is_empty():
			var entry: Dictionary = catalog_read.get("entry", {})
			metadata = WorldCatalogPolicyScript.metadata_for_list(entry, "catalog")
			hit_count += 1
			avoided_world_bytes += int(catalog_read.get("world_bytes", 0))
		else:
			fallback_count += 1
			var allow_authoritative_read := (
				authoritative_read_budget_used
				< MAX_AUTHORITATIVE_READS_PER_LIST
			)
			if not allow_authoritative_read:
				deferred_authoritative_read_count += 1
				deferred_catalog_rebuild_count += 1
				metadata = _deferred_world_metadata(world_id)
				if not metadata.is_empty():
					result.append(metadata)
				continue
			authoritative_read_budget_used += 1
			var allow_primary_repair := (
				repair_budget_used < MAX_PRIMARY_REPAIRS_PER_LIST
			)
			var world_read := _read_world_result(
				world_id, false, allow_primary_repair
			)
			if bool(world_read.get("repair_attempted", false)):
				repair_budget_used += 1
			var source := str(world_read.get("source", "primary"))
			var primary_ready := bool(world_read.get("primary_ready", false))
			if source != "primary" and not primary_ready:
				deferred_recovery_count += 1
			var payload: Dictionary = world_read.get("payload", {})
			if payload.is_empty():
				continue
			var world_bytes := maxi(
				0, int(world_read.get("authoritative_bytes", 0))
			)
			if world_bytes <= 0:
				world_bytes = maxi(
					0, int(world_read.get("candidate_bytes", 0))
				)
			var entry := WorldCatalogPolicyScript.build_entry(
				world_id, payload, world_bytes
			)
			metadata = WorldCatalogPolicyScript.metadata_for_list(
				entry, "world_fallback"
			)
			metadata["recovery_deferred"] = source != "primary" and not primary_ready
			var allow_catalog_rebuild := (
				catalog_rebuild_budget_used < MAX_CATALOG_REBUILDS_PER_LIST
			)
			metadata["catalog_rebuild_deferred"] = (
				primary_ready and not allow_catalog_rebuild
			)
			if primary_ready:
				if allow_catalog_rebuild:
					catalog_rebuild_budget_used += 1
					if _write_catalog_entry(world_id, payload, world_bytes):
						repair_count += 1
					else:
						_catalog_write_failure_count += 1
				else:
					deferred_catalog_rebuild_count += 1
		if not metadata.is_empty():
			result.append(metadata)
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("updated_at", "")) > str(b.get("updated_at", ""))
	)
	_record_catalog_list(
		result.size(),
		hit_count,
		fallback_count,
		repair_count,
		deferred_recovery_count,
		repair_budget_used,
		deferred_catalog_rebuild_count,
		catalog_rebuild_budget_used,
		deferred_authoritative_read_count,
		authoritative_read_budget_used,
		avoided_world_bytes,
		Time.get_ticks_usec() - started_at
	)
	return result


func get_catalog_diagnostics() -> Dictionary:
	var hit_ratio := 0.0
	if _last_catalog_world_count > 0:
		hit_ratio = (
			float(_last_catalog_hit_count) / float(_last_catalog_world_count)
		)
	return {
		"catalog_version": WorldCatalogPolicyScript.CATALOG_VERSION,
		"list_count": _catalog_list_count,
		"hit_count": _catalog_hit_count,
		"fallback_count": _catalog_fallback_count,
		"repair_count": _catalog_repair_count,
		"write_failure_count": _catalog_write_failure_count,
		"last_world_count": _last_catalog_world_count,
		"last_hit_count": _last_catalog_hit_count,
		"last_fallback_count": _last_catalog_fallback_count,
		"last_repair_count": _last_catalog_repair_count,
		"last_avoided_world_bytes": _last_catalog_avoided_world_bytes,
		"last_elapsed_usec": _last_catalog_elapsed_usec,
		"last_elapsed_milliseconds": (
			float(_last_catalog_elapsed_usec) / 1000.0
		),
		"last_hit_ratio": hit_ratio,
		"primary_repair_budget": MAX_PRIMARY_REPAIRS_PER_LIST,
		"deferred_recovery_count": _catalog_deferred_recovery_count,
		"last_deferred_recovery_count": (
			_last_catalog_deferred_recovery_count
		),
		"last_repair_budget_used": _last_catalog_repair_budget_used,
		"catalog_rebuild_budget": MAX_CATALOG_REBUILDS_PER_LIST,
		"deferred_catalog_rebuild_count": (
			_catalog_deferred_rebuild_count
		),
		"last_deferred_catalog_rebuild_count": (
			_last_catalog_deferred_rebuild_count
		),
		"last_catalog_rebuild_budget_used": (
			_last_catalog_rebuild_budget_used
		),
		"authoritative_read_budget": MAX_AUTHORITATIVE_READS_PER_LIST,
		"deferred_authoritative_read_count": (
			_catalog_deferred_authoritative_read_count
		),
		"last_deferred_authoritative_read_count": (
			_last_catalog_deferred_authoritative_read_count
		),
		"last_authoritative_read_budget_used": (
			_last_catalog_authoritative_read_budget_used
		),
	}


func reset_catalog_diagnostics() -> void:
	_catalog_list_count = 0
	_catalog_hit_count = 0
	_catalog_fallback_count = 0
	_catalog_repair_count = 0
	_catalog_write_failure_count = 0
	_last_catalog_world_count = 0
	_last_catalog_hit_count = 0
	_last_catalog_fallback_count = 0
	_last_catalog_repair_count = 0
	_last_catalog_avoided_world_bytes = 0
	_last_catalog_elapsed_usec = 0
	_catalog_deferred_recovery_count = 0
	_last_catalog_deferred_recovery_count = 0
	_last_catalog_repair_budget_used = 0
	_catalog_deferred_rebuild_count = 0
	_last_catalog_deferred_rebuild_count = 0
	_last_catalog_rebuild_budget_used = 0
	_catalog_deferred_authoritative_read_count = 0
	_last_catalog_deferred_authoritative_read_count = 0
	_last_catalog_authoritative_read_budget_used = 0


func get_recovery_diagnostics() -> Dictionary:
	return {
		"recovery_count": _recovery_count,
		"repair_attempt_count": _recovery_repair_attempt_count,
		"repair_success_count": _recovery_repair_success_count,
		"repair_failure_count": _recovery_repair_failure_count,
		"primary_rejection_count": _recovery_primary_rejection_count,
		"last_world_id": _last_recovery_world_id,
		"last_source": _last_recovery_source,
		"last_repaired": _last_recovery_repaired,
		"last_candidate_bytes": _last_recovery_candidate_bytes,
		"last_primary_bytes": _last_recovery_primary_bytes,
		"last_elapsed_usec": _last_recovery_elapsed_usec,
		"last_elapsed_milliseconds": float(_last_recovery_elapsed_usec) / 1000.0,
		"last_rejected_sources": _last_recovery_rejected_sources.duplicate(),
	}


func reset_recovery_diagnostics() -> void:
	_recovery_count = 0
	_recovery_repair_attempt_count = 0
	_recovery_repair_success_count = 0
	_recovery_repair_failure_count = 0
	_recovery_primary_rejection_count = 0
	_last_recovery_world_id = ""
	_last_recovery_source = ""
	_last_recovery_repaired = false
	_last_recovery_candidate_bytes = 0
	_last_recovery_primary_bytes = 0
	_last_recovery_elapsed_usec = 0
	_last_recovery_rejected_sources.clear()


func delete_world(world_id: String) -> bool:
	if not _is_safe_id(world_id) or not world_exists(world_id):
		return false
	var absolute_dir := ProjectSettings.globalize_path(_world_directory(world_id))
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
	if not _is_safe_id(world_id):
		return false
	var world_path := _world_path(world_id)
	return (
		FileAccess.file_exists(world_path)
		or FileAccess.file_exists("%s.tmp" % world_path)
		or FileAccess.file_exists("%s.bak" % world_path)
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
	return _read_world_result(world_id, emit_recovery).get("payload", {})


func _read_world_result(
	world_id: String, emit_recovery: bool, repair_primary: bool = true
) -> Dictionary:
	if not _is_safe_id(world_id):
		return {"payload": {}, "source": "invalid_world_id", "primary_ready": false, "candidate_bytes": 0, "authoritative_bytes": 0, "repair_attempted": false}
	var world_path := _world_path(world_id)
	var result := _store.read_dictionary_validated(world_path, Callable(self, "_is_valid_world_payload").bind(world_id), repair_primary)
	if not bool(result.get("ok", false)):
		return {"payload": {}, "source": str(result.get("source", "missing_or_invalid")), "primary_ready": false, "candidate_bytes": 0, "authoritative_bytes": 0, "repair_attempted": false}
	var source := str(result.get("source", "primary"))
	var primary_ready := source == "primary" or bool(result.get("repair_success", false))
	if source != "primary":
		_record_recovery_result(world_id, source, result, world_path)
		if emit_recovery:
			save_recovered.emit(world_id, source)
	var raw_payload: Variant = result.get("data", {})
	var payload: Dictionary = raw_payload.duplicate(true) if raw_payload is Dictionary else {}
	return {
		"payload": _migrate(payload),
		"source": source,
		"primary_ready": primary_ready,
		"candidate_bytes": maxi(0, int(result.get("candidate_bytes", 0))),
		"authoritative_bytes": _file_size(world_path) if primary_ready else 0,
		"repair_attempted": bool(result.get("repair_attempted", false)),
		"repair_success": bool(result.get("repair_success", false)),
	}


func _is_valid_world_payload(payload: Dictionary, expected_world_id: String) -> bool:
	var raw_metadata: Variant = payload.get("metadata", null)
	var raw_player: Variant = payload.get("player", null)
	var raw_world: Variant = payload.get("world", null)
	if (
		raw_metadata is not Dictionary
		or raw_player is not Dictionary
		or raw_world is not Dictionary
	):
		return false
	var metadata: Dictionary = raw_metadata
	var stored_world_id := str(metadata.get("id", ""))
	if not stored_world_id.is_empty() and stored_world_id != expected_world_id:
		return false
	var world: Dictionary = raw_world
	return world.get("block_overrides", {}) is Dictionary


func _record_recovery_result(
	world_id: String,
	source: String,
	result: Dictionary,
	world_path: String
) -> void:
	_recovery_count += 1
	var repair_attempted := bool(result.get("repair_attempted", false))
	var repair_success := bool(result.get("repair_success", false))
	if repair_attempted:
		_recovery_repair_attempt_count += 1
		if repair_success:
			_recovery_repair_success_count += 1
		else:
			_recovery_repair_failure_count += 1
	_last_recovery_rejected_sources.clear()
	var raw_rejected: Variant = result.get("rejected_sources", [])
	if raw_rejected is Array:
		for raw_source: Variant in raw_rejected:
			if _last_recovery_rejected_sources.size() >= 3:
				break
			_last_recovery_rejected_sources.append(str(raw_source))
	if _last_recovery_rejected_sources.has("primary"):
		_recovery_primary_rejection_count += 1
	_last_recovery_world_id = world_id.left(128)
	_last_recovery_source = source.left(32)
	_last_recovery_repaired = repair_success
	_last_recovery_candidate_bytes = maxi(0, int(result.get("candidate_bytes", 0)))
	_last_recovery_primary_bytes = _file_size(world_path) if repair_success else 0
	_last_recovery_elapsed_usec = maxi(0, int(result.get("repair_elapsed_usec", 0)))


func _read_catalog_entry(world_id: String) -> Dictionary:
	if not _is_safe_id(world_id):
		return {}
	var world_bytes := _file_size(_world_path(world_id))
	if world_bytes <= 0:
		return {}
	var result := _store.read_dictionary(_catalog_path(world_id))
	if (
		not bool(result.get("ok", false))
		or str(result.get("source", "")) != "primary"
	):
		return {}
	var entry := WorldCatalogPolicyScript.normalize_entry(
		result.get("data", {}),
		world_id,
		world_bytes
	)
	if entry.is_empty():
		return {}
	return {
		"entry": entry,
		"world_bytes": world_bytes,
	}


func _write_catalog_entry(
	world_id: String,
	payload: Dictionary,
	save_bytes: int
) -> bool:
	if not _is_safe_id(world_id):
		return false
	var safe_bytes := save_bytes
	if safe_bytes <= 0:
		safe_bytes = _file_size(_world_path(world_id))
	if safe_bytes <= 0:
		return false
	var entry := WorldCatalogPolicyScript.build_entry(world_id, payload, safe_bytes)
	return _store.write_dictionary(_catalog_path(world_id), entry)


func _record_catalog_list(
	world_count: int,
	hit_count: int,
	fallback_count: int,
	repair_count: int,
	deferred_recovery_count: int,
	repair_budget_used: int,
	deferred_catalog_rebuild_count: int,
	catalog_rebuild_budget_used: int,
	deferred_authoritative_read_count: int,
	authoritative_read_budget_used: int,
	avoided_world_bytes: int,
	elapsed_usec: int
) -> void:
	_catalog_list_count += 1
	_catalog_hit_count += hit_count
	_catalog_fallback_count += fallback_count
	_catalog_repair_count += repair_count
	_catalog_deferred_recovery_count += deferred_recovery_count
	_catalog_deferred_rebuild_count += deferred_catalog_rebuild_count
	_catalog_deferred_authoritative_read_count += (
		deferred_authoritative_read_count
	)
	_last_catalog_world_count = world_count
	_last_catalog_hit_count = hit_count
	_last_catalog_fallback_count = fallback_count
	_last_catalog_repair_count = repair_count
	_last_catalog_deferred_recovery_count = maxi(
		0, deferred_recovery_count
	)
	_last_catalog_repair_budget_used = clampi(
		repair_budget_used, 0, MAX_PRIMARY_REPAIRS_PER_LIST
	)
	_last_catalog_deferred_rebuild_count = maxi(
		0, deferred_catalog_rebuild_count
	)
	_last_catalog_rebuild_budget_used = clampi(
		catalog_rebuild_budget_used, 0, MAX_CATALOG_REBUILDS_PER_LIST
	)
	_last_catalog_deferred_authoritative_read_count = maxi(
		0, deferred_authoritative_read_count
	)
	_last_catalog_authoritative_read_budget_used = clampi(
		authoritative_read_budget_used, 0, MAX_AUTHORITATIVE_READS_PER_LIST
	)
	_last_catalog_avoided_world_bytes = maxi(0, avoided_world_bytes)
	_last_catalog_elapsed_usec = maxi(0, elapsed_usec)


func _deferred_world_metadata(world_id: String) -> Dictionary:
	if not _is_safe_id(world_id):
		return {}
	var world_path := _world_path(world_id)
	var candidate_paths: Array[String] = [
		world_path,
		"%s.tmp" % world_path,
		"%s.bak" % world_path,
	]
	var save_bytes := 0
	var modified_unix := 0
	for candidate_path: String in candidate_paths:
		if not FileAccess.file_exists(candidate_path):
			continue
		save_bytes = maxi(save_bytes, _file_size(candidate_path))
		modified_unix = maxi(
			modified_unix, int(FileAccess.get_modified_time(candidate_path))
		)
	if save_bytes <= 0:
		return {}
	var updated_at := (
		Time.get_datetime_string_from_unix_time(modified_unix)
		if modified_unix > 0
		else ""
	)
	return {
		"id": world_id,
		"name": world_id.left(128),
		"map_id": "metadata_pending",
		"seed": 0,
		"created_at": "",
		"updated_at": updated_at,
		"play_seconds": 0,
		"save_bytes": save_bytes,
		"catalog_source": "authoritative_read_deferred",
		"authoritative_read_deferred": true,
		"catalog_rebuild_deferred": true,
	}


func _strip_transient_world_state(payload: Dictionary) -> void:
	var raw_world: Variant = payload.get("world", {})
	var world: Dictionary = {}
	if raw_world is Dictionary:
		world = raw_world.duplicate(true)
	world.erase("loaded_chunks")
	payload["world"] = world


func _world_directory(world_id: String) -> String:
	return "%s/%s" % [WORLDS_DIR, world_id]


func _world_path(world_id: String) -> String:
	return "%s/%s" % [_world_directory(world_id), WORLD_FILE_NAME]


func _catalog_path(world_id: String) -> String:
	return "%s/%s" % [_world_directory(world_id), CATALOG_FILE_NAME]


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return maxi(0, length)


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
	if not payload.has("agriculture") or payload["agriculture"] is not Dictionary:
		payload["agriculture"] = {
			"version": 2,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"crops": {},
			"soil_moisture": {"version": 1, "soils": {}},
		}
	else:
		var agriculture: Dictionary = payload["agriculture"]
		if not agriculture.has("soil_moisture") or agriculture["soil_moisture"] is not Dictionary:
			agriculture["soil_moisture"] = {"version": 1, "soils": {}}
		agriculture["version"] = maxi(2, int(agriculture.get("version", 1)))
		payload["agriculture"] = agriculture
	if not payload.has("husbandry") or payload["husbandry"] is not Dictionary:
		payload["husbandry"] = {
			"version": 1,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"animals": {},
		}
	else:
		var husbandry: Dictionary = payload["husbandry"]
		if not husbandry.has("animals") or husbandry["animals"] is not Dictionary:
			husbandry["animals"] = {}
		husbandry["version"] = maxi(1, int(husbandry.get("version", 1)))
		husbandry["saved_at_unix"] = int(
			husbandry.get("saved_at_unix", Time.get_unix_time_from_system())
		)
		payload["husbandry"] = husbandry
	if not payload.has("containers") or payload["containers"] is not Dictionary:
		payload["containers"] = {"version": 1, "containers": {}}
	if not payload.has("machines") or payload["machines"] is not Dictionary:
		payload["machines"] = {
			"version": 1,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"furnaces": {},
		}
	if not payload.has("rest") or payload["rest"] is not Dictionary:
		payload["rest"] = {
			"version": 1,
			"has_custom_spawn": false,
			"bed_position": [],
			"respawn_position": [],
		}
	if not payload.has("experience") or payload["experience"] is not Dictionary:
		payload["experience"] = {"version": 1, "onboarding": {}}
	if not payload.has("exploration") or payload["exploration"] is not Dictionary:
		payload["exploration"] = {"version": 3, "records": [], "last_result": {}}
	if not payload.has("exploration_rewards") or payload["exploration_rewards"] is not Dictionary:
		payload["exploration_rewards"] = {"version": 1, "claimed": []}
	_strip_transient_world_state(payload)
	return payload


func _ensure_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _sanitize_id(value: String) -> String:
	var result := value.strip_edges().to_lower()
	for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]:
		result = result.replace(invalid, "-")
	while "--" in result:
		result = result.replace("--", "-")
	return result.trim_prefix("-").trim_suffix("-")


func _is_safe_id(value: String) -> bool:
	return not value.is_empty() and value == _sanitize_id(value)
