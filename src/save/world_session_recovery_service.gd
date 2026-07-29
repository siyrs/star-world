class_name WorldSessionRecoveryService
extends Node

signal candidate_changed(candidate: Dictionary)
signal marker_write_failed(reason: String)

const MARKER_PATH := "user://session_recovery.json"
const Policy = preload("res://src/save/world_session_recovery_policy.gd")
const AtomicJsonStoreScript = preload("res://src/save/atomic_json_store.gd")
const MARKER_SUFFIXES := ["", ".tmp", ".bak", ".recover", ".corrupt"]

var save_service: Node
var _store = AtomicJsonStoreScript.new()
var _marker: Dictionary = {}
var _installed := false
var _shutdown := false
var _begin_count := 0
var _active_count := 0
var _checkpoint_count := 0
var _clean_end_count := 0
var _dismiss_count := 0
var _stale_clear_count := 0
var _write_failure_count := 0
var _non_primary_rejection_count := 0
var _last_source := "missing"


func setup(p_save_service: Node) -> bool:
	if _installed or p_save_service == null or not is_instance_valid(p_save_service):
		return false
	save_service = p_save_service
	_connect_save_signals()
	_installed = true
	_shutdown = false
	_marker = _read_primary_marker()
	candidate_changed.emit(get_recovery_candidate())
	return true


func begin_world(world_state: Dictionary) -> bool:
	if not _installed or _shutdown:
		return false
	var marker := Policy.create_marker(
		world_state, int(Time.get_unix_time_from_system())
	)
	if marker.is_empty():
		return false
	if not _write_marker(marker):
		return false
	_begin_count += 1
	return true


func mark_active(world_id: String) -> bool:
	if not _installed or _shutdown:
		return false
	var marker := Policy.mark_active(
		_marker,
		world_id,
		int(Time.get_unix_time_from_system())
	)
	if marker.is_empty() or not _write_marker(marker):
		return false
	_active_count += 1
	return true


func end_world(world_id: String) -> bool:
	var candidate := Policy.candidate(_marker)
	if candidate.is_empty() or str(candidate.get("world_id", "")) != world_id:
		return false
	var cleared := _clear_marker_files()
	if cleared:
		_clean_end_count += 1
	return cleared


func abort_world(world_id: String) -> bool:
	return end_world(world_id)


func dismiss_candidate() -> bool:
	var had_candidate := not Policy.candidate(_marker).is_empty() or _marker_files_exist()
	var cleared := _clear_marker_files()
	if cleared and had_candidate:
		_dismiss_count += 1
	return cleared


func get_recovery_candidate() -> Dictionary:
	if not _installed or _shutdown:
		return {}
	if _marker.is_empty():
		_marker = _read_primary_marker()
	var candidate := Policy.candidate(_marker)
	if candidate.is_empty():
		return {}
	var world_id := str(candidate.get("world_id", ""))
	if (
		save_service == null
		or not is_instance_valid(save_service)
		or not save_service.has_method("world_exists")
		or not bool(save_service.call("world_exists", world_id))
	):
		_stale_clear_count += 1
		_clear_marker_files()
		return {}
	return candidate.duplicate(true)


func get_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"shutdown": _shutdown,
		"marker_path": MARKER_PATH,
		"candidate": get_recovery_candidate(),
		"begin_count": _begin_count,
		"active_count": _active_count,
		"checkpoint_count": _checkpoint_count,
		"clean_end_count": _clean_end_count,
		"dismiss_count": _dismiss_count,
		"stale_clear_count": _stale_clear_count,
		"write_failure_count": _write_failure_count,
		"non_primary_rejection_count": _non_primary_rejection_count,
		"last_source": _last_source,
	}


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	_disconnect_save_signals()
	save_service = null
	# The marker is intentionally not cleared here. A process or device failure can
	# bypass orderly world release, and the persisted marker is the evidence used by
	# the next application start.


func _on_world_saved(world_id: String) -> void:
	if _shutdown:
		return
	var marker := Policy.record_checkpoint(
		_marker,
		world_id,
		int(Time.get_unix_time_from_system())
	)
	if marker.is_empty():
		return
	if _write_marker(marker):
		_checkpoint_count += 1


func _on_world_deleted(world_id: String) -> void:
	var candidate := Policy.candidate(_marker)
	if not candidate.is_empty() and str(candidate.get("world_id", "")) == world_id:
		_stale_clear_count += 1
		_clear_marker_files()


func _write_marker(marker: Dictionary) -> bool:
	var normalized := Policy.normalize(marker)
	if normalized.is_empty():
		return false
	if not _store.write_dictionary(MARKER_PATH, normalized):
		_write_failure_count += 1
		marker_write_failed.emit("write_failed")
		return false
	_marker = normalized
	_last_source = "primary"
	candidate_changed.emit(Policy.candidate(_marker))
	return true


func _read_primary_marker() -> Dictionary:
	var result := _store.read_dictionary_validated(
		MARKER_PATH,
		Callable(self, "_validate_marker"),
		false
	)
	if not bool(result.get("ok", false)):
		_last_source = str(result.get("source", "missing_or_invalid"))
		return {}
	var source := str(result.get("source", ""))
	_last_source = source
	# Session recovery is advisory. A stale backup from a previous world must never
	# be promoted into a false recovery prompt, so only the current primary is trusted.
	if source != "primary":
		_non_primary_rejection_count += 1
		_clear_marker_files()
		return {}
	return Policy.normalize(result.get("data", {}))


func _validate_marker(payload: Dictionary) -> bool:
	return Policy.is_valid(payload)


func _clear_marker_files() -> bool:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	var success := true
	for suffix: String in MARKER_SUFFIXES:
		var candidate_path := "%s%s" % [absolute_path, suffix]
		if not FileAccess.file_exists(candidate_path):
			continue
		if DirAccess.remove_absolute(candidate_path) != OK:
			success = false
	if success:
		_marker.clear()
		_last_source = "missing"
		candidate_changed.emit({})
	return success


func _marker_files_exist() -> bool:
	var absolute_path := ProjectSettings.globalize_path(MARKER_PATH)
	for suffix: String in MARKER_SUFFIXES:
		if FileAccess.file_exists("%s%s" % [absolute_path, suffix]):
			return true
	return false


func _connect_save_signals() -> void:
	if save_service == null or not is_instance_valid(save_service):
		return
	var saved_callback := Callable(self, "_on_world_saved")
	if save_service.has_signal("world_saved") and not save_service.is_connected(
		"world_saved", saved_callback
	):
		save_service.connect("world_saved", saved_callback)
	var deleted_callback := Callable(self, "_on_world_deleted")
	if save_service.has_signal("world_deleted") and not save_service.is_connected(
		"world_deleted", deleted_callback
	):
		save_service.connect("world_deleted", deleted_callback)


func _disconnect_save_signals() -> void:
	if save_service == null or not is_instance_valid(save_service):
		return
	var saved_callback := Callable(self, "_on_world_saved")
	if save_service.has_signal("world_saved") and save_service.is_connected(
		"world_saved", saved_callback
	):
		save_service.disconnect("world_saved", saved_callback)
	var deleted_callback := Callable(self, "_on_world_deleted")
	if save_service.has_signal("world_deleted") and save_service.is_connected(
		"world_deleted", deleted_callback
	):
		save_service.disconnect("world_deleted", deleted_callback)


func _exit_tree() -> void:
	shutdown()
