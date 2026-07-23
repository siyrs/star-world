class_name ScalableMachineAutomationService
extends "res://src/machine/machine_automation_service.gd"

const ScaleAutomationPolicyScript = preload(
	"res://src/machine/machine_automation_policy.gd"
)

var _candidate_order_dirty := false
var _candidate_sort_count := 0
var _deferred_candidate_append_count := 0
var _max_unsorted_candidate_count := 0


func clear() -> void:
	super.clear()
	_candidate_order_dirty = false
	_candidate_sort_count = 0
	_deferred_candidate_append_count = 0
	_max_unsorted_candidate_count = 0
	_cache_rebuild_count = 0
	_candidate_event_count = 0


func get_health_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"machine_count": 0,
		"tracked_machine_count": _candidate_order.size(),
		"active": world != null and is_instance_valid(world) and not _shutdown,
		"shutdown": _shutdown,
		"externally_scheduled": _externally_scheduled,
		"cycle_count": _cycle_count,
		"max_machines_per_cycle": ScaleAutomationPolicyScript.MAX_MACHINES_PER_CYCLE,
		"max_items_per_cycle": ScaleAutomationPolicyScript.MAX_ITEMS_PER_CYCLE,
		"candidate_order_dirty": _candidate_order_dirty,
		"candidate_sort_count": _candidate_sort_count,
	}


func get_runtime_snapshot() -> Dictionary:
	var result: Dictionary = super.get_runtime_snapshot()
	result["candidate_order_dirty"] = _candidate_order_dirty
	result["candidate_sort_count"] = _candidate_sort_count
	result["deferred_candidate_append_count"] = _deferred_candidate_append_count
	result["max_unsorted_candidate_count"] = _max_unsorted_candidate_count
	return result


func _run_cycle(elapsed: float) -> Dictionary:
	_ensure_candidate_order()
	return super._run_cycle(elapsed)


func _add_candidate(
	machine_type: StringName, machine_id: String, count_event: bool = true
) -> void:
	if not bool(
		ScaleAutomationPolicyScript.parse_machine_position(machine_type, machine_id).get(
			"success", false
		)
	):
		return
	var key := "%s|%s" % [str(machine_type), machine_id]
	if _candidates.has(key):
		return
	_candidates[key] = {
		"machine_type": machine_type,
		"machine_id": machine_id,
	}
	_candidate_order.append(key)
	_candidate_order_dirty = _candidate_order.size() > 1
	_deferred_candidate_append_count += 1
	_max_unsorted_candidate_count = maxi(
		_max_unsorted_candidate_count, _candidate_order.size()
	)
	if count_event:
		_candidate_event_count += 1


func _ensure_candidate_order() -> void:
	if not _candidate_order_dirty:
		return
	_candidate_order.sort()
	_candidate_order_dirty = false
	_candidate_sort_count += 1
