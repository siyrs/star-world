class_name WorldScopedSaveCheckpointTimelinePolicy
extends RefCounted

const BasePolicy = preload("res://src/save/save_checkpoint_timeline_policy.gd")


static func project_timeline(raw_timeline: Variant) -> Dictionary:
	var source: Dictionary = raw_timeline if raw_timeline is Dictionary else {}
	var result: Dictionary = BasePolicy.project_timeline(source)
	var current_world_id := str(result.get("current_world_id", ""))
	var session_sequence := maxi(
		0, int(source.get("current_world_session_sequence", 0))
	)
	var started_after_sequence := maxi(
		0, int(source.get("current_world_session_started_after_sequence", 0))
	)
	var scope_available := (
		not current_world_id.is_empty()
		and session_sequence > 0
		and source.has("current_world_session_started_after_sequence")
	)
	var current_session_history: Array[Dictionary] = []
	if scope_available:
		var raw_history: Variant = result.get("history", [])
		if raw_history is Array:
			for raw_event: Variant in raw_history:
				if raw_event is not Dictionary:
					continue
				var event: Dictionary = raw_event
				if (
					str(event.get("world_id", "")) == current_world_id
					and int(event.get("sequence", 0)) > started_after_sequence
				):
					current_session_history.append(event.duplicate(true))
	elif not current_world_id.is_empty():
		var legacy_history: Variant = result.get("current_world_history", [])
		if legacy_history is Array:
			for raw_event: Variant in legacy_history:
				if raw_event is Dictionary:
					current_session_history.append(raw_event.duplicate(true))
	var last_current_session_event: Dictionary = (
		current_session_history.back().duplicate(true)
		if not current_session_history.is_empty()
		else {}
	)
	result["world_session_scope_active"] = scope_available
	result["current_world_session_sequence"] = session_sequence
	result["current_world_session_started_after_sequence"] = started_after_sequence
	result["current_session_history"] = current_session_history
	result["current_session_history_count"] = current_session_history.size()
	result["last_current_session_event"] = last_current_session_event
	# Compatibility aliases now intentionally mean the current world entry session,
	# not every retained event that happens to share the same persistent world ID.
	result["current_world_history"] = current_session_history.duplicate(true)
	result["current_world_history_count"] = current_session_history.size()
	result["last_current_world_event"] = last_current_session_event.duplicate(true)
	return result
