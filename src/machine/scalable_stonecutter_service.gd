class_name ScalableStonecutterService
extends "res://src/machine/stonecutter_service.gd"

const ActivityIndexScript = preload("res://src/machine/machine_activity_index.gd")
const RuntimeProgressPolicyScript = preload("res://src/machine/machine_progress_policy.gd")
const RUNTIME_STEP_SECONDS := 0.1
const MAX_CHANGED_MACHINE_ID_SAMPLES := 64

var _activity_index = ActivityIndexScript.new()
var _index_ready := false
var _runtime_step_accumulator := 0.0
var _scheduler_call_count := 0
var _evaluation_batch_count := 0
var _evaluated_machine_count := 0
var _avoided_idle_evaluation_count := 0
var _changed_machine_sample_drop_count := 0
var _max_evaluated_machines_in_batch := 0


func _ready() -> void:
	super._ready()
	_connect_activity_signals()


func setup(p_item_registry) -> bool:
	var success := super.setup(p_item_registry)
	_index_ready = true
	_rebuild_activity_index()
	return success


func ensure_machine(machine_id: String) -> bool:
	var success := super.ensure_machine(machine_id)
	if success and _index_ready:
		_sync_activity(machine_id)
	return success


func remove_machine(machine_id: String, require_empty: bool = true) -> bool:
	var removed := super.remove_machine(machine_id, require_empty)
	if removed:
		_activity_index.set_active(machine_id, false)
	return removed


func clear() -> void:
	super.clear()
	_activity_index.clear()
	_runtime_step_accumulator = 0.0
	_scheduler_call_count = 0
	_evaluation_batch_count = 0
	_evaluated_machine_count = 0
	_avoided_idle_evaluation_count = 0
	_changed_machine_sample_drop_count = 0
	_max_evaluated_machines_in_batch = 0
	_runtime_tick_count = 0
	_total_changed_machine_count = 0
	_simulation_iteration_limit_hits = 0


func deserialize(data: Dictionary) -> bool:
	_index_ready = false
	var success := super.deserialize(data)
	_index_ready = true
	_rebuild_activity_index()
	return success


func advance_machine_runtime(seconds: float, emit_events: bool = true) -> Dictionary:
	_scheduler_call_count += 1
	var elapsed := RuntimeProgressPolicyScript.normalize_elapsed(
		seconds, float(MAX_OFFLINE_SECONDS)
	)
	if elapsed <= 0.0:
		return _last_runtime_summary.duplicate(true)
	_runtime_step_accumulator += elapsed
	if _runtime_step_accumulator + EPSILON < RUNTIME_STEP_SECONDS:
		_last_runtime_summary = {
			"machine_type": MACHINE_TYPE,
			"elapsed_seconds": 0.0,
			"accumulated_seconds": _runtime_step_accumulator,
			"machine_count": _machines.size(),
			"active_machine_count": _activity_index.size(),
			"evaluated_machine_count": 0,
			"changed_machine_count": 0,
			"changed_machine_ids": [],
			"dropped_changed_machine_samples": 0,
			"active_snapshot_emitted": false,
			"runtime_tick_count": _runtime_tick_count,
			"reason": "runtime_step_pending",
		}
		return _last_runtime_summary.duplicate(true)
	var runtime_seconds := _runtime_step_accumulator
	_runtime_step_accumulator = 0.0
	var outcome := _advance_indexed(runtime_seconds, emit_events, false)
	_snapshot_accumulator += runtime_seconds
	var active_snapshot_emitted := false
	if _snapshot_accumulator >= SNAPSHOT_INTERVAL_SECONDS:
		_snapshot_accumulator = 0.0
		if not _active_machine_id.is_empty() and _machines.has(_active_machine_id):
			machine_changed.emit(
				_active_machine_id, get_machine_snapshot(_active_machine_id)
			)
			active_snapshot_emitted = true
	_runtime_tick_count += 1
	_total_changed_machine_count += int(outcome.get("changed_count", 0))
	_last_runtime_summary = {
		"machine_type": MACHINE_TYPE,
		"elapsed_seconds": runtime_seconds,
		"accumulated_seconds": _runtime_step_accumulator,
		"machine_count": _machines.size(),
		"active_machine_count": _activity_index.size(),
		"evaluated_machine_count": int(outcome.get("evaluated_count", 0)),
		"changed_machine_count": int(outcome.get("changed_count", 0)),
		"changed_machine_ids": outcome.get("changed_samples", []).duplicate(),
		"dropped_changed_machine_samples": int(outcome.get("dropped_samples", 0)),
		"active_snapshot_emitted": active_snapshot_emitted,
		"runtime_tick_count": _runtime_tick_count,
		"reason": "advanced",
	}
	return _last_runtime_summary.duplicate(true)


func advance_time(seconds: float, emit_events: bool = true) -> Array[String]:
	if not _index_ready:
		return super.advance_time(seconds, emit_events)
	var outcome := _advance_indexed(seconds, emit_events, true)
	var result: Array[String] = []
	for raw_id: Variant in outcome.get("changed_samples", []):
		result.append(str(raw_id))
	return result


func get_health_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"machine_type": MACHINE_TYPE,
		"machine_count": _machines.size(),
		"active_machine_count": _activity_index.size(),
		"idle_machine_count": maxi(0, _machines.size() - _activity_index.size()),
		"externally_scheduled": _external_scheduler,
		"scheduler_call_count": _scheduler_call_count,
		"evaluation_batch_count": _evaluation_batch_count,
		"avoided_idle_evaluation_count": _avoided_idle_evaluation_count,
		"simulation_iteration_limit_hits": _simulation_iteration_limit_hits,
	}


func get_runtime_snapshot() -> Dictionary:
	var result: Dictionary = super.get_runtime_snapshot()
	result["active_machine_count"] = _activity_index.size()
	result["idle_machine_count"] = maxi(0, _machines.size() - _activity_index.size())
	result["runtime_step_seconds"] = RUNTIME_STEP_SECONDS
	result["runtime_step_accumulator"] = _runtime_step_accumulator
	result["scheduler_call_count"] = _scheduler_call_count
	result["evaluation_batch_count"] = _evaluation_batch_count
	result["evaluated_machine_count"] = _evaluated_machine_count
	result["avoided_idle_evaluation_count"] = _avoided_idle_evaluation_count
	result["changed_machine_sample_limit"] = MAX_CHANGED_MACHINE_ID_SAMPLES
	result["changed_machine_sample_drop_count"] = _changed_machine_sample_drop_count
	result["max_evaluated_machines_in_batch"] = _max_evaluated_machines_in_batch
	result["activity_index"] = _activity_index.get_snapshot()
	return result


func _advance_indexed(
	seconds: float, emit_events: bool, collect_all_changed_ids: bool
) -> Dictionary:
	var elapsed := RuntimeProgressPolicyScript.normalize_elapsed(
		seconds, float(MAX_OFFLINE_SECONDS)
	)
	if elapsed <= EPSILON:
		return {
			"evaluated_count": 0,
			"changed_count": 0,
			"changed_samples": [],
			"dropped_samples": 0,
		}
	var ids: Array[String] = _activity_index.ordered_ids_view()
	var changed_samples: Array[String] = []
	var resync_ids: Array[String] = []
	var evaluated_count := 0
	var changed_count := 0
	for machine_id: String in ids:
		if not _machines.has(machine_id):
			resync_ids.append(machine_id)
			continue
		var state: Dictionary = _machines[machine_id]
		evaluated_count += 1
		if _advance_machine(machine_id, state, elapsed, emit_events):
			_machines[machine_id] = state
			changed_count += 1
			if collect_all_changed_ids or changed_samples.size() < MAX_CHANGED_MACHINE_ID_SAMPLES:
				changed_samples.append(machine_id)
		resync_ids.append(machine_id)
	for machine_id: String in resync_ids:
		_sync_activity(machine_id)
	var dropped_samples := maxi(0, changed_count - changed_samples.size())
	_evaluation_batch_count += 1
	_evaluated_machine_count += evaluated_count
	_avoided_idle_evaluation_count += maxi(0, _machines.size() - evaluated_count)
	_changed_machine_sample_drop_count += dropped_samples
	_max_evaluated_machines_in_batch = maxi(
		_max_evaluated_machines_in_batch, evaluated_count
	)
	return {
		"evaluated_count": evaluated_count,
		"changed_count": changed_count,
		"changed_samples": changed_samples,
		"dropped_samples": dropped_samples,
	}


func _is_runnable_state(state: Dictionary) -> bool:
	var recipe: Dictionary = _resolve_recipe(state)
	return not recipe.is_empty() and _can_accept_output(state, recipe)


func _sync_activity(machine_id: String) -> void:
	if not _machines.has(machine_id):
		_activity_index.set_active(machine_id, false)
		return
	_activity_index.set_active(
		machine_id, _is_runnable_state(_machines.get(machine_id, {}))
	)


func _rebuild_activity_index() -> void:
	var active_ids: Array[String] = []
	for raw_id: Variant in _machines.keys():
		var machine_id := str(raw_id)
		if _is_runnable_state(_machines.get(machine_id, {})):
			active_ids.append(machine_id)
	_activity_index.rebuild(active_ids)


func _connect_activity_signals() -> void:
	var changed_callback := Callable(self, "_on_machine_changed_for_activity")
	if not machine_changed.is_connected(changed_callback):
		machine_changed.connect(changed_callback)
	var removed_callback := Callable(self, "_on_machine_removed_for_activity")
	if not machine_removed.is_connected(removed_callback):
		machine_removed.connect(removed_callback)


func _on_machine_changed_for_activity(machine_id: String, _snapshot: Dictionary) -> void:
	if _index_ready:
		_sync_activity(machine_id)


func _on_machine_removed_for_activity(machine_id: String) -> void:
	_activity_index.set_active(machine_id, false)
