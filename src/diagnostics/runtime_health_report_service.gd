class_name RuntimeHealthReportService
extends Node

const PolicyScript = preload("res://src/diagnostics/runtime_health_report_policy.gd")
const WORLD_FILE_NAME := "world.json"
const WORLDS_DIR := "user://worlds"

var hub: Node
var world: Node
var save_service: Node
var _current_world_id := ""
var _save_attempt_count := 0
var _save_success_count := 0
var _save_failure_count := 0
var _save_recovery_count := 0
var _last_save_success := false
var _last_save_world_id := ""
var _last_save_bytes := 0
var _last_save_elapsed_usec := 0
var _last_save_timestamp_msec := 0
var _last_source_count := 0
var _last_source_methods: Dictionary = {}
var _fallback_source_count := 0
var _unavailable_source_count := 0
var _shutdown := false


func setup(p_hub: Node) -> bool:
	_disconnect_save_signals()
	hub = p_hub
	world = null
	_current_world_id = ""
	_shutdown = false
	if hub == null or not is_instance_valid(hub):
		save_service = null
		return false
	save_service = hub.get("save_service") as Node
	_connect_save_signals()
	return save_service != null and is_instance_valid(save_service)


func begin_world(world_id: String) -> void:
	_current_world_id = world_id.strip_edges().left(128)


func attach_runtime(p_world: Node) -> void:
	world = p_world if p_world != null and is_instance_valid(p_world) else null


func detach_runtime() -> void:
	world = null


func record_save_result(
	world_id: String,
	success: bool,
	elapsed_usec: int,
	explicit_bytes: int = -1
) -> void:
	if _shutdown:
		return
	var normalized_id := world_id.strip_edges().left(128)
	_save_attempt_count += 1
	if success:
		_save_success_count += 1
	else:
		_save_failure_count += 1
	_last_save_success = success
	_last_save_world_id = normalized_id
	_last_save_elapsed_usec = maxi(0, elapsed_usec)
	_last_save_timestamp_msec = Time.get_ticks_msec()
	_last_save_bytes = (
		maxi(0, explicit_bytes)
		if explicit_bytes >= 0
		else _world_file_size(normalized_id)
	)


func get_snapshot() -> Dictionary:
	if _shutdown:
		return PolicyScript.build({})
	_last_source_methods.clear()
	_fallback_source_count = 0
	_unavailable_source_count = 0
	var sources := {
		"streaming": _snapshot_preferred(
			"streaming", world, ["get_streaming_stats"]
		),
		"machines": _snapshot_preferred(
			"machines",
			_hub_node("machine_runtime"),
			["get_health_snapshot", "get_snapshot"]
		),
		"agriculture": _snapshot_preferred(
			"agriculture",
			_hub_node("agriculture_service"),
			["get_health_snapshot", "get_runtime_snapshot"]
		),
		"husbandry": _snapshot_preferred(
			"husbandry", _hub_node("husbandry_service"), ["get_snapshot"]
		),
		"animal_attraction": _snapshot_preferred(
			"animal_attraction", _hub_node("animal_attraction_service"), ["get_snapshot"]
		),
		"animal_products": _snapshot_preferred(
			"animal_products", _hub_node("animal_product_service"), ["get_snapshot"]
		),
		"ecology": _snapshot_preferred(
			"ecology", _hub_node("creature_spawner"), ["get_ecology_snapshot"]
		),
		"pickups": _snapshot_preferred(
			"pickups", _hub_node("pickup_stack_coordinator"), ["get_snapshot"]
		),
		"structural_integrity": _snapshot_preferred(
			"structural_integrity",
			_hub_node("structural_integrity_service"),
			["get_snapshot"]
		),
		"catalog": _snapshot_preferred(
			"catalog", save_service, ["get_catalog_diagnostics"]
		),
		"save": _save_snapshot(),
	}
	_last_source_methods["save"] = "session_snapshot"
	_last_source_count = sources.size()
	var result: Dictionary = PolicyScript.build(sources)
	result["world_attached"] = world != null and is_instance_valid(world)
	result["current_world_id"] = _current_world_id
	result["source_count"] = _last_source_count
	result["source_limit"] = sources.size()
	result["source_methods"] = _last_source_methods.duplicate(true)
	result["fallback_source_count"] = _fallback_source_count
	result["unavailable_source_count"] = _unavailable_source_count
	result["preferred_source_count"] = maxi(
		0, _last_source_count - _fallback_source_count - _unavailable_source_count
	)
	return result


func get_save_snapshot() -> Dictionary:
	return _save_snapshot()


func get_source_contract_snapshot() -> Dictionary:
	return {
		"source_count": _last_source_count,
		"source_methods": _last_source_methods.duplicate(true),
		"fallback_source_count": _fallback_source_count,
		"unavailable_source_count": _unavailable_source_count,
	}


func clear_session_counters() -> void:
	_save_attempt_count = 0
	_save_success_count = 0
	_save_failure_count = 0
	_save_recovery_count = 0
	_last_save_success = false
	_last_save_world_id = ""
	_last_save_bytes = 0
	_last_save_elapsed_usec = 0
	_last_save_timestamp_msec = 0
	if save_service != null and is_instance_valid(save_service):
		if save_service.has_method("reset_recovery_diagnostics"):
			save_service.call("reset_recovery_diagnostics")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	_disconnect_save_signals()
	world = null
	save_service = null
	hub = null
	_current_world_id = ""
	_last_source_methods.clear()
	_fallback_source_count = 0
	_unavailable_source_count = 0


func _save_snapshot() -> Dictionary:
	var recovery: Dictionary = {}
	if (
		save_service != null
		and is_instance_valid(save_service)
		and save_service.has_method("get_recovery_diagnostics")
	):
		var raw_recovery: Variant = save_service.call("get_recovery_diagnostics")
		if raw_recovery is Dictionary:
			recovery = raw_recovery
	return {
		"attempt_count": _save_attempt_count,
		"success_count": _save_success_count,
		"failure_count": _save_failure_count,
		"recovery_count": maxi(
			_save_recovery_count, maxi(0, int(recovery.get("recovery_count", 0)))
		),
		"repair_attempt_count": maxi(0, int(recovery.get("repair_attempt_count", 0))),
		"repair_success_count": maxi(0, int(recovery.get("repair_success_count", 0))),
		"repair_failure_count": maxi(0, int(recovery.get("repair_failure_count", 0))),
		"primary_rejection_count": maxi(
			0, int(recovery.get("primary_rejection_count", 0))
		),
		"last_recovery_source": str(recovery.get("last_source", "")).left(32),
		"last_recovery_repaired": bool(recovery.get("last_repaired", false)),
		"last_recovery_bytes": maxi(0, int(recovery.get("last_primary_bytes", 0))),
		"last_recovery_elapsed_usec": maxi(
			0, int(recovery.get("last_elapsed_usec", 0))
		),
		"last_recovery_elapsed_milliseconds": maxf(
			0.0, float(recovery.get("last_elapsed_milliseconds", 0.0))
		),
		"last_success": _last_save_success,
		"last_world_id": _last_save_world_id,
		"last_bytes": _last_save_bytes,
		"last_elapsed_usec": _last_save_elapsed_usec,
		"last_elapsed_milliseconds": float(_last_save_elapsed_usec) / 1000.0,
		"last_timestamp_msec": _last_save_timestamp_msec,
	}


func _snapshot_preferred(
	source_id: String, target: Node, methods: Array
) -> Dictionary:
	if target == null or not is_instance_valid(target):
		_last_source_methods[source_id] = "unavailable"
		_unavailable_source_count += 1
		return {}
	for method_index: int in range(methods.size()):
		var method_name := str(methods[method_index])
		if not target.has_method(method_name):
			continue
		_last_source_methods[source_id] = method_name
		if method_index > 0:
			_fallback_source_count += 1
		var raw_snapshot: Variant = target.call(method_name)
		return raw_snapshot if raw_snapshot is Dictionary else {}
	_last_source_methods[source_id] = "unavailable"
	_unavailable_source_count += 1
	return {}


func _hub_node(property_name: StringName) -> Node:
	if hub == null or not is_instance_valid(hub):
		return null
	var value: Variant = hub.get(property_name)
	return value as Node if value is Node and is_instance_valid(value) else null


func _world_file_size(world_id: String) -> int:
	if world_id.is_empty():
		return 0
	var path := "%s/%s/%s" % [WORLDS_DIR, world_id, WORLD_FILE_NAME]
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return maxi(0, length)


func _connect_save_signals() -> void:
	if save_service == null or not is_instance_valid(save_service):
		return
	if save_service.has_signal("save_recovered"):
		var callback := Callable(self, "_on_save_recovered")
		if not save_service.is_connected("save_recovered", callback):
			save_service.connect("save_recovered", callback)


func _disconnect_save_signals() -> void:
	if save_service == null or not is_instance_valid(save_service):
		return
	if save_service.has_signal("save_recovered"):
		var callback := Callable(self, "_on_save_recovered")
		if save_service.is_connected("save_recovered", callback):
			save_service.disconnect("save_recovered", callback)


func _on_save_recovered(_world_id: String, _source: String) -> void:
	_save_recovery_count += 1
