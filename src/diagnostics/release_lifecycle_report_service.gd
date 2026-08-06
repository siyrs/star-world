class_name ReleaseLifecycleReportService
extends Node

signal report_persisted(path: String, report: Dictionary)
signal report_persist_failed(path: String)

const AtomicJsonStoreScript = preload("res://src/save/atomic_json_store.gd")
const SCHEMA_VERSION := 1
const DEFAULT_REPORT_PATH := "user://diagnostics/release-lifecycle-report.json"
const MAX_WORLD_ID_LENGTH := 128
const MAX_PROFILE_ID_LENGTH := 64
const MAX_SOURCE_LENGTH := 32

var _store = AtomicJsonStoreScript.new()
var _enabled := false
var _report_path := DEFAULT_REPORT_PATH
var _service_ready_usec := 0
var _scene_ready_usec := -1
var _first_world_playable_usec := -1
var _first_save_usec := -1
var _quit_requested_usec := -1
var _quit_completed_usec := -1
var _first_world: Dictionary = {}
var _first_save: Dictionary = {}
var _quit_source := ""
var _quit_prepared := false
var _quit_attempt_count := 0
var _quit_before_resources: Dictionary = {}
var _quit_after_resources: Dictionary = {}
var _runtime_health: Dictionary = {}
var _service_hub_quit: Dictionary = {}
var _game_quit: Dictionary = {}
var _termination_reason := "running"
var _successful_quit_finalized := false
var _persist_count := 0
var _persist_failure_count := 0
var _last_write_ok := false


func _init() -> void:
	_service_ready_usec = Time.get_ticks_usec()


func configure(force_enabled: bool = false, report_path: String = "") -> void:
	_enabled = (
		force_enabled
		or not OS.has_feature("editor")
		or OS.get_cmdline_user_args().has("--release-lifecycle-report")
	)
	_report_path = (
		report_path.strip_edges()
		if not report_path.strip_edges().is_empty()
		else DEFAULT_REPORT_PATH
	)


func is_enabled() -> bool:
	return _enabled


func get_report_path() -> String:
	return _report_path


func mark_scene_ready() -> void:
	if not _enabled or _scene_ready_usec >= 0:
		return
	_scene_ready_usec = Time.get_ticks_usec()


func mark_first_world_playable(profile_id: String, seed: int, world_id: String) -> void:
	if not _enabled or not _first_world.is_empty():
		return
	_first_world_playable_usec = Time.get_ticks_usec()
	_first_world = {
		"profile_id": profile_id.strip_edges().left(MAX_PROFILE_ID_LENGTH),
		"seed": seed,
		"world_id": world_id.strip_edges().left(MAX_WORLD_ID_LENGTH),
	}


func mark_first_save(event: Dictionary, _timeline: Dictionary = {}) -> void:
	if not _enabled or not _first_save.is_empty() or not bool(event.get("success", false)):
		return
	_first_save_usec = Time.get_ticks_usec()
	_first_save = {
		"success": true,
		"reason": str(event.get("reason", "manual")).left(MAX_SOURCE_LENGTH),
		"world_id": str(event.get("world_id", "")).left(MAX_WORLD_ID_LENGTH),
		"bytes": maxi(0, int(event.get("bytes", 0))),
		"elapsed_usec": maxi(0, int(event.get("elapsed_usec", 0))),
		"elapsed_milliseconds": maxf(
			0.0, float(event.get("elapsed_usec", 0)) / 1000.0
		),
		"sequence": maxi(0, int(event.get("sequence", 0))),
	}


func begin_quit(source: StringName) -> void:
	if not _enabled or _successful_quit_finalized:
		return
	_quit_attempt_count += 1
	_quit_source = str(source).left(MAX_SOURCE_LENGTH)
	_quit_requested_usec = Time.get_ticks_usec()
	_quit_completed_usec = -1
	_quit_prepared = false
	_quit_before_resources = _capture_resource_snapshot()
	_quit_after_resources.clear()
	_runtime_health.clear()
	_service_hub_quit.clear()
	_game_quit.clear()
	_termination_reason = "quit_in_progress"


func complete_quit(
	prepared: bool,
	runtime_health: Dictionary = {},
	service_hub_quit: Dictionary = {},
	game_quit: Dictionary = {}
) -> bool:
	if not _enabled:
		return false
	_quit_completed_usec = Time.get_ticks_usec()
	_quit_prepared = prepared
	_quit_after_resources = _capture_resource_snapshot()
	_runtime_health = _project_runtime_health(runtime_health)
	_service_hub_quit = _project_quit_snapshot(service_hub_quit)
	_game_quit = _project_quit_snapshot(game_quit)
	_termination_reason = "prepared_quit" if prepared else "blocked_quit"
	_successful_quit_finalized = prepared
	return persist_report()


func finalize_scene_exit() -> bool:
	if not _enabled or _successful_quit_finalized:
		return false
	if _quit_requested_usec < 0:
		_quit_requested_usec = Time.get_ticks_usec()
		_quit_before_resources = _capture_resource_snapshot()
	_quit_completed_usec = Time.get_ticks_usec()
	_quit_after_resources = _capture_resource_snapshot()
	_termination_reason = "scene_exit_without_prepared_quit"
	return persist_report()


func persist_report() -> bool:
	if not _enabled:
		return false
	var report := _build_report()
	_last_write_ok = _store.write_dictionary(_report_path, report)
	if _last_write_ok:
		_persist_count += 1
		report_persisted.emit(_report_path, report.duplicate(true))
	else:
		_persist_failure_count += 1
		report_persist_failed.emit(_report_path)
	return _last_write_ok


func get_snapshot() -> Dictionary:
	var report := _build_report()
	report["enabled"] = _enabled
	report["report_path"] = _report_path
	report["persist_count"] = _persist_count
	report["persist_failure_count"] = _persist_failure_count
	report["last_write_ok"] = _last_write_ok
	return report


func _build_report() -> Dictionary:
	var before := _quit_before_resources.duplicate(true)
	var after := _quit_after_resources.duplicate(true)
	return {
		"schema_version": SCHEMA_VERSION,
		"captured_at": Time.get_datetime_string_from_system(),
		"captured_unix": int(Time.get_unix_time_from_system()),
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"release_build": not OS.has_feature("editor"),
		"clock": "engine_monotonic_uptime",
		"timings": {
			"service_ready_milliseconds": _to_milliseconds(_service_ready_usec),
			"scene_ready_milliseconds": _to_milliseconds(_scene_ready_usec),
			"first_world_playable_milliseconds": _to_milliseconds(
				_first_world_playable_usec
			),
			"first_save_milliseconds": _to_milliseconds(_first_save_usec),
			"quit_requested_milliseconds": _to_milliseconds(_quit_requested_usec),
			"quit_completed_milliseconds": _to_milliseconds(_quit_completed_usec),
		},
		"first_world": _first_world.duplicate(true),
		"first_save": _first_save.duplicate(true),
		"quit": {
			"attempt_count": _quit_attempt_count,
			"source": _quit_source,
			"prepared": _quit_prepared,
			"termination_reason": _termination_reason,
			"before_resources": before,
			"after_resources": after,
			"resource_delta": _resource_delta(before, after),
			"runtime_health": _runtime_health.duplicate(true),
			"service_hub": _service_hub_quit.duplicate(true),
			"game": _game_quit.duplicate(true),
		},
	}


func _capture_resource_snapshot() -> Dictionary:
	return {
		"node_count": maxi(
			0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		),
		"resource_count": maxi(
			0, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		),
		"orphan_node_count": maxi(
			0, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		),
		"static_memory_bytes": maxi(
			0, int(Performance.get_monitor(Performance.MEMORY_STATIC))
		),
	}


func _resource_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in [
		"node_count", "resource_count", "orphan_node_count", "static_memory_bytes"
	]:
		result[key] = int(after.get(key, 0)) - int(before.get(key, 0))
	return result


func _project_runtime_health(snapshot: Dictionary) -> Dictionary:
	var save: Dictionary = (
		snapshot.get("save", {})
		if snapshot.get("save", {}) is Dictionary
		else {}
	)
	return {
		"status": str(snapshot.get("status", "unknown")).left(32),
		"issue_count": maxi(0, int(snapshot.get("issue_count", 0))),
		"warning_count": maxi(0, int(snapshot.get("warning_count", 0))),
		"source_count": maxi(0, int(snapshot.get("source_count", 0))),
		"fallback_source_count": maxi(
			0, int(snapshot.get("fallback_source_count", 0))
		),
		"unavailable_source_count": maxi(
			0, int(snapshot.get("unavailable_source_count", 0))
		),
		"world_attached": bool(snapshot.get("world_attached", false)),
		"save_attempt_count": maxi(0, int(save.get("attempt_count", 0))),
		"save_success_count": maxi(0, int(save.get("success_count", 0))),
		"save_failure_count": maxi(0, int(save.get("failure_count", 0))),
	}


func _project_quit_snapshot(snapshot: Dictionary) -> Dictionary:
	return {
		"request_count": maxi(0, int(snapshot.get("request_count", 0))),
		"success_count": maxi(0, int(snapshot.get("success_count", 0))),
		"failure_count": maxi(0, int(snapshot.get("failure_count", 0))),
		"duplicate_request_count": maxi(
			0, int(snapshot.get("duplicate_request_count", 0))
		),
		"last_source": str(snapshot.get("last_source", "")).left(MAX_SOURCE_LENGTH),
		"world_active": bool(snapshot.get("world_active", false)),
		"in_flight": bool(snapshot.get("in_flight", false)),
	}


func _to_milliseconds(usec: int) -> float:
	return -1.0 if usec < 0 else float(usec) / 1000.0
