class_name WorldSessionRecoveryPolicy
extends RefCounted

const SCHEMA_VERSION := 1
const STATE_LOADING := "loading"
const STATE_ACTIVE := "active"
const ALLOWED_STATES := [STATE_LOADING, STATE_ACTIVE]
const MAX_WORLD_ID_LENGTH := 128
const MAX_WORLD_NAME_LENGTH := 128
const MAX_MAP_ID_LENGTH := 64
const MAX_CHECKPOINT_COUNT := 1000000


static func create_marker(world_state: Variant, now_unix: int) -> Dictionary:
	var state: Dictionary = world_state if world_state is Dictionary else {}
	var metadata: Dictionary = (
		state.get("metadata", {}) if state.get("metadata", {}) is Dictionary else {}
	)
	var world_id := _text(metadata.get("id", ""), MAX_WORLD_ID_LENGTH)
	if world_id.is_empty():
		return {}
	var safe_now := maxi(0, now_unix)
	return {
		"schema_version": SCHEMA_VERSION,
		"session": {
			"world_id": world_id,
			"world_name": _text(metadata.get("name", world_id), MAX_WORLD_NAME_LENGTH),
			"map_id": _text(metadata.get("map_id", "star_continent"), MAX_MAP_ID_LENGTH),
			"state": STATE_LOADING,
			"started_at_unix": safe_now,
			"updated_at_unix": safe_now,
			"last_checkpoint_at_unix": 0,
			"checkpoint_count": 0,
		},
	}


static func normalize(raw_marker: Variant) -> Dictionary:
	var source: Dictionary = raw_marker if raw_marker is Dictionary else {}
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return {}
	var raw_session: Variant = source.get("session", {})
	if raw_session is not Dictionary:
		return {}
	var session: Dictionary = raw_session
	var world_id := _text(session.get("world_id", ""), MAX_WORLD_ID_LENGTH)
	if world_id.is_empty():
		return {}
	var state := str(session.get("state", STATE_LOADING))
	if state not in ALLOWED_STATES:
		state = STATE_LOADING
	var started_at := maxi(0, int(session.get("started_at_unix", 0)))
	var updated_at := maxi(started_at, int(session.get("updated_at_unix", started_at)))
	var last_checkpoint_at := clampi(
		int(session.get("last_checkpoint_at_unix", 0)),
		0,
		updated_at
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"session": {
			"world_id": world_id,
			"world_name": _text(session.get("world_name", world_id), MAX_WORLD_NAME_LENGTH),
			"map_id": _text(session.get("map_id", "star_continent"), MAX_MAP_ID_LENGTH),
			"state": state,
			"started_at_unix": started_at,
			"updated_at_unix": updated_at,
			"last_checkpoint_at_unix": last_checkpoint_at,
			"checkpoint_count": clampi(
				int(session.get("checkpoint_count", 0)),
				0,
				MAX_CHECKPOINT_COUNT
			),
		},
	}


static func mark_active(raw_marker: Variant, world_id: String, now_unix: int) -> Dictionary:
	var marker := normalize(raw_marker)
	if marker.is_empty():
		return {}
	var session: Dictionary = marker.get("session", {})
	if str(session.get("world_id", "")) != world_id:
		return {}
	session["state"] = STATE_ACTIVE
	session["updated_at_unix"] = maxi(
		int(session.get("updated_at_unix", 0)), maxi(0, now_unix)
	)
	marker["session"] = session
	return marker


static func record_checkpoint(
	raw_marker: Variant,
	world_id: String,
	now_unix: int
) -> Dictionary:
	var marker := normalize(raw_marker)
	if marker.is_empty():
		return {}
	var session: Dictionary = marker.get("session", {})
	if str(session.get("world_id", "")) != world_id:
		return {}
	var safe_now := maxi(
		int(session.get("updated_at_unix", 0)), maxi(0, now_unix)
	)
	session["state"] = STATE_ACTIVE
	session["updated_at_unix"] = safe_now
	session["last_checkpoint_at_unix"] = safe_now
	session["checkpoint_count"] = mini(
		MAX_CHECKPOINT_COUNT,
		maxi(0, int(session.get("checkpoint_count", 0))) + 1
	)
	marker["session"] = session
	return marker


static func candidate(raw_marker: Variant) -> Dictionary:
	var marker := normalize(raw_marker)
	if marker.is_empty():
		return {}
	var session: Dictionary = marker.get("session", {})
	return {
		"schema_version": SCHEMA_VERSION,
		"world_id": str(session.get("world_id", "")),
		"world_name": str(session.get("world_name", "")),
		"map_id": str(session.get("map_id", "")),
		"state": str(session.get("state", STATE_LOADING)),
		"started_at_unix": maxi(0, int(session.get("started_at_unix", 0))),
		"updated_at_unix": maxi(0, int(session.get("updated_at_unix", 0))),
		"last_checkpoint_at_unix": maxi(
			0, int(session.get("last_checkpoint_at_unix", 0))
		),
		"checkpoint_count": clampi(
			int(session.get("checkpoint_count", 0)), 0, MAX_CHECKPOINT_COUNT
		),
	}


static func is_valid(raw_marker: Variant) -> bool:
	return not normalize(raw_marker).is_empty()


static func _text(value: Variant, limit: int) -> String:
	return str(value).strip_edges().left(maxi(0, limit))
