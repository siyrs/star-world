class_name SaveCheckpointTimelinePolicy
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_EVENTS := 12
const MAX_WORLD_ID_LENGTH := 128

const REASON_MANUAL := &"manual"
const REASON_AUTOSAVE := &"autosave"
const REASON_RETURN_TO_MENU := &"return_to_menu"
const REASON_SYSTEM := &"system"

const ALLOWED_REASONS: Array[StringName] = [
	REASON_MANUAL,
	REASON_AUTOSAVE,
	REASON_RETURN_TO_MENU,
	REASON_SYSTEM,
]
const REASON_LABELS := {
	"manual":"手动保存",
	"autosave":"自动保存",
	"return_to_menu":"返回主菜单保存",
	"system":"系统保存",
}


static func empty_reason_counts() -> Dictionary:
	return {
		"manual":0,
		"autosave":0,
		"return_to_menu":0,
		"system":0,
	}


static func normalize_reason(raw_reason: Variant) -> StringName:
	var candidate := StringName(str(raw_reason).strip_edges().to_lower())
	for allowed: StringName in ALLOWED_REASONS:
		if candidate == allowed:
			return allowed
	return REASON_SYSTEM


static func reason_label(raw_reason: Variant) -> String:
	return str(REASON_LABELS.get(str(normalize_reason(raw_reason)), "系统保存"))


static func create_event(
	sequence: int,
	raw_reason: Variant,
	world_id: String,
	success: bool,
	elapsed_usec: int,
	bytes: int,
	timestamp_msec: int
) -> Dictionary:
	var reason := normalize_reason(raw_reason)
	var safe_elapsed := maxi(0, elapsed_usec)
	return {
		"schema_version":SCHEMA_VERSION,
		"sequence":maxi(1, sequence),
		"reason":str(reason),
		"reason_label":reason_label(reason),
		"world_id":world_id.strip_edges().left(MAX_WORLD_ID_LENGTH),
		"success":success,
		"elapsed_usec":safe_elapsed,
		"elapsed_milliseconds":float(safe_elapsed) / 1000.0,
		"bytes":maxi(0, bytes),
		"timestamp_msec":maxi(0, timestamp_msec),
	}


static func project_event(raw_event: Variant) -> Dictionary:
	if raw_event is not Dictionary:
		return {}
	var event: Dictionary = raw_event
	var sequence := maxi(0, int(event.get("sequence", 0)))
	if sequence <= 0:
		return {}
	return create_event(
		sequence,
		event.get("reason", REASON_SYSTEM),
		str(event.get("world_id", "")),
		bool(event.get("success", false)),
		maxi(0, int(event.get("elapsed_usec", 0))),
		maxi(0, int(event.get("bytes", 0))),
		maxi(0, int(event.get("timestamp_msec", 0)))
	)


static func append_bounded(raw_history: Variant, raw_event: Variant) -> Array[Dictionary]:
	var result := project_history(raw_history)
	var event := project_event(raw_event)
	if event.is_empty():
		return result
	result.append(event)
	while result.size() > MAX_EVENTS:
		result.pop_front()
	return result


static func project_history(raw_history: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_history is not Array:
		return result
	var source: Array = raw_history
	var start_index := maxi(0, source.size() - MAX_EVENTS)
	for index in range(start_index, source.size()):
		var event := project_event(source[index])
		if not event.is_empty():
			result.append(event)
	return result


static func project_reason_counts(raw_counts: Variant) -> Dictionary:
	var result := empty_reason_counts()
	if raw_counts is not Dictionary:
		return result
	var source: Dictionary = raw_counts
	for reason_key: String in result.keys():
		result[reason_key] = maxi(0, int(source.get(reason_key, 0)))
	return result


static func project_autosave(raw_snapshot: Variant) -> Dictionary:
	if raw_snapshot is not Dictionary:
		return {
			"enabled":false,
			"active":false,
			"paused":false,
			"pending":false,
			"saving":false,
			"interval_seconds":0.0,
			"next_in_seconds":0.0,
			"consecutive_failure_count":0,
			"last_retry_delay_seconds":0.0,
		}
	var snapshot: Dictionary = raw_snapshot
	return {
		"enabled":bool(snapshot.get("enabled", false)),
		"active":bool(snapshot.get("active", false)),
		"paused":bool(snapshot.get("paused", false)),
		"pending":bool(snapshot.get("pending", false)),
		"saving":bool(snapshot.get("saving", false)),
		"interval_seconds":maxf(0.0, float(snapshot.get("interval_seconds", 0.0))),
		"next_in_seconds":maxf(0.0, float(snapshot.get("next_in_seconds", 0.0))),
		"consecutive_failure_count":maxi(
			0, int(snapshot.get("consecutive_failure_count", 0))
		),
		"last_retry_delay_seconds":maxf(
			0.0, float(snapshot.get("last_retry_delay_seconds", 0.0))
		),
	}


static func project_timeline(raw_timeline: Variant) -> Dictionary:
	var source: Dictionary = raw_timeline if raw_timeline is Dictionary else {}
	var history := project_history(source.get("history", []))
	var current_world_id := str(source.get("current_world_id", "")).strip_edges().left(
		MAX_WORLD_ID_LENGTH
	)
	var current_world_history: Array[Dictionary] = []
	if not current_world_id.is_empty():
		for event: Dictionary in history:
			if str(event.get("world_id", "")) == current_world_id:
				current_world_history.append(event.duplicate(true))
	var last_event: Dictionary = history.back().duplicate(true) if not history.is_empty() else {}
	var last_current_world_event: Dictionary = (
		current_world_history.back().duplicate(true)
		if not current_world_history.is_empty()
		else {}
	)
	return {
		"schema_version":SCHEMA_VERSION,
		"history":history,
		"history_count":history.size(),
		"history_limit":MAX_EVENTS,
		"history_dropped_count":maxi(
			0, int(source.get("history_dropped_count", 0))
		),
		"reason_counts":project_reason_counts(source.get("reason_counts", {})),
		"current_world_id":current_world_id,
		"current_world_history":current_world_history,
		"current_world_history_count":current_world_history.size(),
		"last_event":last_event,
		"last_current_world_event":last_current_world_event,
		"autosave":project_autosave(source.get("autosave", {})),
		"captured_at_msec":maxi(0, int(source.get("captured_at_msec", 0))),
	}
