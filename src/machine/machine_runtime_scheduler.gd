class_name MachineRuntimeScheduler
extends Node

signal domain_registered(domain_id: StringName)
signal domain_unregistered(domain_id: StringName)
signal runtime_batch_advanced(summary: Dictionary)

const ProgressPolicyScript = preload("res://src/machine/machine_progress_policy.gd")
const MAX_DOMAINS := 16
const MAX_FRAME_STEP_SECONDS := 5.0
const MAX_MANUAL_STEP_SECONDS := 4.0 * 60.0 * 60.0

var _domains: Dictionary = {}
var _domain_order: Array[StringName] = []
var _active := false
var _shutdown := false
var _tick_count := 0
var _total_domain_advances := 0
var _total_changed_machines := 0
var _max_domains_per_tick := 0
var _last_batch: Dictionary = {}
var _health_snapshot_count := 0
var _health_fallback_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)


func register_domain(domain_id: StringName, domain: Node) -> Dictionary:
	if _shutdown:
		return {"success":false, "reason":"scheduler_shutdown"}
	var normalized_id := StringName(str(domain_id).strip_edges())
	if str(normalized_id).is_empty():
		return {"success":false, "reason":"invalid_domain_id"}
	if _domains.has(normalized_id):
		return {"success":false, "reason":"duplicate_domain"}
	if _domains.size() >= MAX_DOMAINS:
		return {"success":false, "reason":"domain_capacity"}
	if domain == null or not is_instance_valid(domain):
		return {"success":false, "reason":"invalid_domain"}
	for required_method: String in ["advance_machine_runtime", "get_runtime_snapshot"]:
		if not domain.has_method(required_method):
			return {"success":false, "reason":"domain_contract", "method":required_method}
	for registered: Variant in _domains.values():
		if registered == domain:
			return {"success":false, "reason":"domain_already_registered"}
	_domains[normalized_id] = domain
	_domain_order.append(normalized_id)
	if domain.has_method("set_external_scheduler"):
		domain.call("set_external_scheduler", true)
	domain_registered.emit(normalized_id)
	return {"success":true, "domain_id":normalized_id, "domain":domain}


func unregister_domain(domain_id: StringName) -> bool:
	if not _domains.has(domain_id):
		return false
	var domain: Node = _domains.get(domain_id) as Node
	_domains.erase(domain_id)
	_domain_order.erase(domain_id)
	if domain != null and is_instance_valid(domain) and domain.has_method("set_external_scheduler"):
		domain.call("set_external_scheduler", false)
	domain_unregistered.emit(domain_id)
	return true


func activate() -> void:
	if _shutdown:
		return
	_active = true
	set_process(true)


func deactivate() -> void:
	_active = false
	set_process(false)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	var elapsed := ProgressPolicyScript.normalize_elapsed(delta, MAX_FRAME_STEP_SECONDS)
	if elapsed > 0.0:
		advance_time(elapsed, true)


func advance_time(seconds: float, emit_events: bool = true) -> Dictionary:
	var elapsed := ProgressPolicyScript.normalize_elapsed(seconds, MAX_MANUAL_STEP_SECONDS)
	if elapsed <= 0.0:
		return _last_batch.duplicate(true)
	var domain_summaries: Dictionary = {}
	var changed_machine_count := 0
	var advanced_domains := 0
	for domain_id: StringName in _domain_order:
		var domain: Node = _domains.get(domain_id) as Node
		if domain == null or not is_instance_valid(domain):
			continue
		var raw_summary: Variant = domain.call("advance_machine_runtime", elapsed, emit_events)
		var summary: Dictionary = raw_summary if raw_summary is Dictionary else {}
		domain_summaries[str(domain_id)] = summary.duplicate(true)
		changed_machine_count += maxi(0, int(summary.get("changed_machine_count", 0)))
		advanced_domains += 1
	_tick_count += 1
	_total_domain_advances += advanced_domains
	_total_changed_machines += changed_machine_count
	_max_domains_per_tick = maxi(_max_domains_per_tick, advanced_domains)
	_last_batch = {
		"elapsed_seconds": elapsed,
		"emit_events": emit_events,
		"advanced_domain_count": advanced_domains,
		"changed_machine_count": changed_machine_count,
		"domain_summaries": domain_summaries,
		"tick_count": _tick_count,
	}
	runtime_batch_advanced.emit(_last_batch.duplicate(true))
	return _last_batch.duplicate(true)


func get_domain(domain_id: StringName) -> Node:
	return _domains.get(domain_id) as Node


func get_health_snapshot() -> Dictionary:
	_health_snapshot_count += 1
	var machine_count := 0
	var active_machine_count := 0
	var tracked_machine_count := 0
	var fallback_domain_count := 0
	for domain_id: StringName in _domain_order:
		var domain: Node = _domains.get(domain_id) as Node
		if domain == null or not is_instance_valid(domain):
			continue
		var raw_snapshot: Variant
		if domain.has_method("get_health_snapshot"):
			raw_snapshot = domain.call("get_health_snapshot")
		else:
			fallback_domain_count += 1
			_health_fallback_count += 1
			raw_snapshot = domain.call("get_runtime_snapshot")
		var snapshot: Dictionary = raw_snapshot if raw_snapshot is Dictionary else {}
		machine_count += maxi(0, int(snapshot.get("machine_count", 0)))
		active_machine_count += maxi(0, int(snapshot.get("active_machine_count", 0)))
		tracked_machine_count += maxi(0, int(snapshot.get("tracked_machine_count", 0)))
	return {
		"schema_version": 1,
		"active": _active,
		"shutdown": _shutdown,
		"domain_count": _domain_order.size(),
		"domain_limit": MAX_DOMAINS,
		"machine_count": machine_count,
		"active_machine_count": active_machine_count,
		"tracked_machine_count": tracked_machine_count,
		"tick_count": _tick_count,
		"total_domain_advances": _total_domain_advances,
		"total_changed_machines": _total_changed_machines,
		"max_domains_per_tick": _max_domains_per_tick,
		"health_snapshot_count": _health_snapshot_count,
		"fallback_domain_count": fallback_domain_count,
		"total_health_fallback_count": _health_fallback_count,
	}


func get_snapshot() -> Dictionary:
	var domain_snapshots: Dictionary = {}
	var machine_count := 0
	for domain_id: StringName in _domain_order:
		var domain: Node = _domains.get(domain_id) as Node
		if domain == null or not is_instance_valid(domain):
			continue
		var raw_snapshot: Variant = domain.call("get_runtime_snapshot")
		var snapshot: Dictionary = raw_snapshot if raw_snapshot is Dictionary else {}
		domain_snapshots[str(domain_id)] = snapshot.duplicate(true)
		machine_count += maxi(0, int(snapshot.get("machine_count", 0)))
	return {
		"active": _active,
		"shutdown": _shutdown,
		"domain_count": _domain_order.size(),
		"registered_domains": _string_ids(_domain_order),
		"machine_count": machine_count,
		"tick_count": _tick_count,
		"total_domain_advances": _total_domain_advances,
		"total_changed_machines": _total_changed_machines,
		"max_domains_per_tick": _max_domains_per_tick,
		"last_batch": _last_batch.duplicate(true),
		"domains": domain_snapshots,
	}


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	deactivate()
	_last_batch.clear()


func _string_ids(ids: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for domain_id: StringName in ids:
		result.append(str(domain_id))
	return result
