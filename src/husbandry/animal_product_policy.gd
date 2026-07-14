class_name AnimalProductPolicy
extends RefCounted

const STAGE_ADULT := "adult"


func is_eligible(profile: Dictionary, husbandry_record: Dictionary) -> bool:
	if profile.is_empty() or husbandry_record.is_empty():
		return false
	if str(profile.get("species_id", "")) != str(husbandry_record.get("species_id", "")):
		return false
	if bool(profile.get("adult_only", true)):
		return str(husbandry_record.get("stage", STAGE_ADULT)) == STAGE_ADULT
	return true


func initial_state(profile: Dictionary, stable_key: String) -> Dictionary:
	var interval := maxf(1.0, float(profile.get("interval_seconds", 60.0)))
	var normalized_hash := abs(stable_key.hash()) % 401
	var stagger_ratio := 0.60 + float(normalized_hash) / 1000.0
	return {
		"species_id": str(profile.get("species_id", "")),
		"remaining_seconds": interval * stagger_ratio,
		"pending_count": 0,
	}


func normalize_state(profile: Dictionary, state: Dictionary) -> Dictionary:
	var interval := maxf(1.0, float(profile.get("interval_seconds", 60.0)))
	var max_pending := maxi(1, int(profile.get("max_pending", 1)))
	return {
		"species_id": str(profile.get("species_id", state.get("species_id", ""))),
		"remaining_seconds": clampf(
			float(state.get("remaining_seconds", interval)), 0.0, interval
		),
		"pending_count": clampi(int(state.get("pending_count", 0)), 0, max_pending),
	}


func advance(profile: Dictionary, state: Dictionary, elapsed_seconds: float) -> Dictionary:
	var normalized := normalize_state(profile, state)
	var interval := maxf(1.0, float(profile.get("interval_seconds", 60.0)))
	var max_pending := maxi(1, int(profile.get("max_pending", 1)))
	var remaining := float(normalized.get("remaining_seconds", interval))
	var pending := int(normalized.get("pending_count", 0))
	var elapsed := maxf(0.0, elapsed_seconds)
	var produced := 0
	if elapsed > 0.0 and pending < max_pending:
		remaining -= elapsed
		while remaining <= 0.0 and pending < max_pending:
			pending += 1
			produced += 1
			remaining += interval
	if pending >= max_pending:
		remaining = maxf(0.0, remaining)
	return {
		"state": {
			"species_id": str(normalized.get("species_id", "")),
			"remaining_seconds": clampf(remaining, 0.0, interval),
			"pending_count": pending,
		},
		"produced_count": produced,
		"at_capacity": pending >= max_pending,
	}


func format_duration(seconds: float) -> String:
	var rounded := maxi(0, ceili(seconds))
	if rounded >= 60:
		return "%d 分 %02d 秒" % [rounded / 60, rounded % 60]
	return "%d 秒" % rounded
