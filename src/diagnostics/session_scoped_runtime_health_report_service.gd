class_name SessionScopedRuntimeHealthReportService
extends "res://src/diagnostics/runtime_health_report_service.gd"

const ScopedTimelinePolicy = preload(
	"res://src/save/world_scoped_save_checkpoint_timeline_policy.gd"
)

var _world_session_sequence_counter := 0
var _current_world_session_sequence := 0
var _current_world_session_started_after_sequence := 0


func setup(p_hub: Node) -> bool:
	_reset_world_session_scope()
	return super.setup(p_hub)


func begin_world(world_id: String) -> void:
	var normalized_id := world_id.strip_edges().left(
		ScopedTimelinePolicy.BasePolicy.MAX_WORLD_ID_LENGTH
	)
	_current_world_session_started_after_sequence = _save_event_sequence
	if normalized_id.is_empty():
		_current_world_session_sequence = 0
	else:
		_world_session_sequence_counter += 1
		_current_world_session_sequence = _world_session_sequence_counter
	super.begin_world(normalized_id)


func end_world() -> void:
	super.end_world()
	_current_world_session_sequence = 0
	_current_world_session_started_after_sequence = _save_event_sequence


func get_save_timeline_snapshot() -> Dictionary:
	return ScopedTimelinePolicy.project_timeline(_timeline_payload())


func get_world_session_scope_snapshot() -> Dictionary:
	return {
		"active":not _current_world_id.is_empty()
		and _current_world_session_sequence > 0,
		"world_id":_current_world_id,
		"session_sequence":_current_world_session_sequence,
		"started_after_save_sequence":_current_world_session_started_after_sequence,
		"session_count":_world_session_sequence_counter,
	}


func clear_session_counters() -> void:
	var world_active := not _current_world_id.is_empty()
	super.clear_session_counters()
	_current_world_session_started_after_sequence = 0
	if world_active:
		_world_session_sequence_counter = 1
		_current_world_session_sequence = 1
	else:
		_world_session_sequence_counter = 0
		_current_world_session_sequence = 0


func shutdown() -> void:
	_reset_world_session_scope()
	super.shutdown()


func _timeline_payload() -> Dictionary:
	var payload: Dictionary = super._timeline_payload()
	payload["current_world_session_sequence"] = _current_world_session_sequence
	payload["current_world_session_started_after_sequence"] = (
		_current_world_session_started_after_sequence
	)
	return payload


func _reset_world_session_scope() -> void:
	_world_session_sequence_counter = 0
	_current_world_session_sequence = 0
	_current_world_session_started_after_sequence = 0
