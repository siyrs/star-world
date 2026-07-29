class_name AutosaveSchedulePolicy
extends RefCounted

const SCHEMA_VERSION := 1
const MICROSECONDS_PER_SECOND := 1000000
const MAX_INTERVAL_SECONDS := 15.0 * 60.0
const MAX_INTERVAL_MICROSECONDS := 900000000
const MAX_CARRY_SECONDS := 1.0
const MAX_CARRY_MICROSECONDS := 1000000


static func create(interval_seconds: float = 0.0) -> Dictionary:
	var configured := configure(_empty_state(), interval_seconds)
	var raw_state: Variant = configured.get("state", {})
	return raw_state if raw_state is Dictionary else _empty_state()


static func project(raw_state: Variant) -> Dictionary:
	var source: Dictionary = raw_state if raw_state is Dictionary else {}
	var interval_usec := clampi(
		int(source.get("interval_microseconds", 0)),
		0,
		MAX_INTERVAL_MICROSECONDS
	)
	var remaining_usec := clampi(
		int(source.get("remaining_microseconds", interval_usec)),
		0,
		interval_usec
	)
	var carry_limit := mini(MAX_CARRY_MICROSECONDS, interval_usec)
	var current_carry_usec := clampi(
		int(source.get("current_carry_microseconds", 0)),
		0,
		carry_limit
	)
	var result := {
		"schema_version":SCHEMA_VERSION,
		"interval_microseconds":interval_usec,
		"remaining_microseconds":remaining_usec,
		"fractional_microseconds":clampf(
			float(source.get("fractional_microseconds", 0.0)),
			-0.499999999,
			0.499999999
		),
		"pending":bool(source.get("pending", false)),
		"current_carry_microseconds":current_carry_usec,
		"carried_overshoot_count":maxi(
			0, int(source.get("carried_overshoot_count", 0))
		),
		"carried_overshoot_total_microseconds":maxi(
			0, int(source.get("carried_overshoot_total_microseconds", 0))
		),
		"max_carried_overshoot_microseconds":clampi(
			int(source.get("max_carried_overshoot_microseconds", 0)),
			0,
			MAX_CARRY_MICROSECONDS
		),
		"discarded_overshoot_microseconds":maxi(
			0, int(source.get("discarded_overshoot_microseconds", 0))
		),
		"consecutive_failure_count":maxi(
			0, int(source.get("consecutive_failure_count", 0))
		),
		"last_retry_delay_microseconds":clampi(
			int(source.get("last_retry_delay_microseconds", 0)),
			0,
			interval_usec
		),
		"window_sequence":maxi(0, int(source.get("window_sequence", 0))),
		"transition_count":maxi(0, int(source.get("transition_count", 0))),
	}
	if interval_usec <= 0:
		result["remaining_microseconds"] = 0
		result["pending"] = false
		result["current_carry_microseconds"] = 0
		result["consecutive_failure_count"] = 0
		result["last_retry_delay_microseconds"] = 0
	elif bool(result.get("pending", false)):
		result["remaining_microseconds"] = 0
	return result


static func configure(raw_state: Variant, interval_seconds: float) -> Dictionary:
	var state := project(raw_state)
	var safe_seconds := interval_seconds if is_finite(interval_seconds) else 0.0
	var interval_usec := clampi(
		int(round(clampf(safe_seconds, 0.0, MAX_INTERVAL_SECONDS) * MICROSECONDS_PER_SECOND)),
		0,
		MAX_INTERVAL_MICROSECONDS
	)
	var changed := interval_usec != int(state.get("interval_microseconds", 0))
	if not changed:
		return {"state":state, "changed":false}
	state["interval_microseconds"] = interval_usec
	state["remaining_microseconds"] = interval_usec
	state["fractional_microseconds"] = 0.0
	state["pending"] = false
	state["current_carry_microseconds"] = 0
	state["consecutive_failure_count"] = 0
	state["last_retry_delay_microseconds"] = 0
	state["window_sequence"] = 0
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return {"state":state, "changed":true}


static func reset_for_world(raw_state: Variant) -> Dictionary:
	var state := project(raw_state)
	var interval_usec := int(state.get("interval_microseconds", 0))
	state["remaining_microseconds"] = interval_usec
	state["fractional_microseconds"] = 0.0
	state["pending"] = false
	state["current_carry_microseconds"] = 0
	state["carried_overshoot_count"] = 0
	state["carried_overshoot_total_microseconds"] = 0
	state["max_carried_overshoot_microseconds"] = 0
	state["discarded_overshoot_microseconds"] = 0
	state["consecutive_failure_count"] = 0
	state["last_retry_delay_microseconds"] = 0
	state["window_sequence"] = 0
	state["transition_count"] = 0
	return state


static func advance(raw_state: Variant, delta_seconds: float) -> Dictionary:
	var state := project(raw_state)
	if (
		not is_finite(delta_seconds)
		or int(state.get("interval_microseconds", 0)) <= 0
		or bool(state.get("pending", false))
	):
		return {"state":state, "due":false}
	var exact_usec := (
		maxf(0.0, delta_seconds) * MICROSECONDS_PER_SECOND
		+ float(state.get("fractional_microseconds", 0.0))
	)
	var whole_usec := maxi(0, int(round(exact_usec)))
	state["fractional_microseconds"] = clampf(
		exact_usec - float(whole_usec), -0.499999999, 0.499999999
	)
	var remaining_before := int(state.get("remaining_microseconds", 0))
	if remaining_before <= 0:
		state["pending"] = true
		state["transition_count"] = int(state.get("transition_count", 0)) + 1
		return {"state":state, "due":true}
	var remaining_after := remaining_before - whole_usec
	if remaining_after > 0:
		state["remaining_microseconds"] = remaining_after
		return {"state":state, "due":false}
	var overshoot_usec := maxi(0, -remaining_after)
	var interval_usec := int(state.get("interval_microseconds", 0))
	var carry_limit := mini(MAX_CARRY_MICROSECONDS, interval_usec)
	var carried_usec := mini(overshoot_usec, carry_limit)
	var discarded_usec := maxi(0, overshoot_usec - carried_usec)
	state["remaining_microseconds"] = 0
	state["pending"] = true
	state["current_carry_microseconds"] = carried_usec
	if carried_usec > 0:
		state["carried_overshoot_count"] = (
			int(state.get("carried_overshoot_count", 0)) + 1
		)
		state["carried_overshoot_total_microseconds"] = (
			int(state.get("carried_overshoot_total_microseconds", 0)) + carried_usec
		)
		state["max_carried_overshoot_microseconds"] = maxi(
			int(state.get("max_carried_overshoot_microseconds", 0)),
			carried_usec
		)
	if discarded_usec > 0:
		state["discarded_overshoot_microseconds"] = (
			int(state.get("discarded_overshoot_microseconds", 0)) + discarded_usec
		)
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return {"state":state, "due":true}


static func consume_pending(raw_state: Variant) -> Dictionary:
	var state := project(raw_state)
	if bool(state.get("pending", false)):
		state["pending"] = false
		state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return state


static func record_success(raw_state: Variant) -> Dictionary:
	var state := project(raw_state)
	var interval_usec := int(state.get("interval_microseconds", 0))
	var carried_usec := clampi(
		int(state.get("current_carry_microseconds", 0)),
		0,
		mini(MAX_CARRY_MICROSECONDS, interval_usec)
	)
	state["remaining_microseconds"] = maxi(0, interval_usec - carried_usec)
	state["pending"] = false
	state["current_carry_microseconds"] = 0
	state["consecutive_failure_count"] = 0
	state["last_retry_delay_microseconds"] = 0
	state["window_sequence"] = int(state.get("window_sequence", 0)) + 1
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return state


static func record_failure(raw_state: Variant, retry_delay_seconds: float) -> Dictionary:
	var state := project(raw_state)
	var interval_usec := int(state.get("interval_microseconds", 0))
	var safe_delay := retry_delay_seconds if is_finite(retry_delay_seconds) else 0.0
	var delay_usec := clampi(
		int(round(maxf(0.0, safe_delay) * MICROSECONDS_PER_SECOND)),
		0,
		interval_usec
	)
	state["remaining_microseconds"] = delay_usec
	state["fractional_microseconds"] = 0.0
	state["pending"] = false
	state["current_carry_microseconds"] = 0
	state["consecutive_failure_count"] = (
		int(state.get("consecutive_failure_count", 0)) + 1
	)
	state["last_retry_delay_microseconds"] = delay_usec
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return state


static func record_manual_save(raw_state: Variant) -> Dictionary:
	var state := project(raw_state)
	var interval_usec := int(state.get("interval_microseconds", 0))
	state["remaining_microseconds"] = interval_usec
	state["fractional_microseconds"] = 0.0
	state["pending"] = false
	state["current_carry_microseconds"] = 0
	state["consecutive_failure_count"] = 0
	state["last_retry_delay_microseconds"] = 0
	state["window_sequence"] = int(state.get("window_sequence", 0)) + 1
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	return state


static func is_enabled(raw_state: Variant) -> bool:
	return int(project(raw_state).get("interval_microseconds", 0)) > 0


static func is_pending(raw_state: Variant) -> bool:
	return bool(project(raw_state).get("pending", false))


static func snapshot(raw_state: Variant) -> Dictionary:
	var state := project(raw_state)
	var interval_usec := int(state.get("interval_microseconds", 0))
	var remaining_usec := int(state.get("remaining_microseconds", 0))
	var interval_seconds := float(interval_usec) / MICROSECONDS_PER_SECOND
	var next_in_seconds := float(remaining_usec) / MICROSECONDS_PER_SECOND
	return {
		"schedule_schema_version":SCHEMA_VERSION,
		"precision_unit_microseconds":1,
		"enabled":interval_usec > 0,
		"pending":bool(state.get("pending", false)),
		"interval_seconds":interval_seconds,
		"interval_minutes":interval_seconds / 60.0,
		"elapsed_active_seconds":maxf(0.0, interval_seconds - next_in_seconds),
		"next_in_seconds":next_in_seconds if interval_usec > 0 else 0.0,
		"fractional_microseconds":float(state.get("fractional_microseconds", 0.0)),
		"current_carried_overshoot_seconds":(
			float(state.get("current_carry_microseconds", 0)) / MICROSECONDS_PER_SECOND
		),
		"carried_overshoot_count":maxi(
			0, int(state.get("carried_overshoot_count", 0))
		),
		"carried_overshoot_total_seconds":(
			float(state.get("carried_overshoot_total_microseconds", 0))
			/ MICROSECONDS_PER_SECOND
		),
		"max_carried_overshoot_seconds":(
			float(state.get("max_carried_overshoot_microseconds", 0))
			/ MICROSECONDS_PER_SECOND
		),
		"discarded_overshoot_seconds":(
			float(state.get("discarded_overshoot_microseconds", 0))
			/ MICROSECONDS_PER_SECOND
		),
		"consecutive_failure_count":maxi(
			0, int(state.get("consecutive_failure_count", 0))
		),
		"last_retry_delay_seconds":(
			float(state.get("last_retry_delay_microseconds", 0))
			/ MICROSECONDS_PER_SECOND
		),
		"window_sequence":maxi(0, int(state.get("window_sequence", 0))),
		"transition_count":maxi(0, int(state.get("transition_count", 0))),
	}


static func _empty_state() -> Dictionary:
	return {
		"schema_version":SCHEMA_VERSION,
		"interval_microseconds":0,
		"remaining_microseconds":0,
		"fractional_microseconds":0.0,
		"pending":false,
		"current_carry_microseconds":0,
		"carried_overshoot_count":0,
		"carried_overshoot_total_microseconds":0,
		"max_carried_overshoot_microseconds":0,
		"discarded_overshoot_microseconds":0,
		"consecutive_failure_count":0,
		"last_retry_delay_microseconds":0,
		"window_sequence":0,
		"transition_count":0,
	}
