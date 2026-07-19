class_name HostileAttackPolicy
extends RefCounted

const STATE_IDLE := "idle"
const STATE_WINDUP := "windup"
const STATE_COOLDOWN := "cooldown"


static func can_begin(
	distance: float,
	attack_range: float,
	cooldown_remaining: float,
	windup_remaining: float
) -> bool:
	return (
		is_finite(distance)
		and distance >= 0.0
		and distance <= maxf(0.1, attack_range)
		and cooldown_remaining <= 0.0
		and windup_remaining <= 0.0
	)


static func cancellation_reason(
	target_valid: bool,
	distance: float,
	attack_range: float,
	cancel_range_multiplier: float,
	hit_stun_remaining: float
) -> String:
	if not target_valid:
		return "target_unavailable"
	if hit_stun_remaining > 0.0:
		return "interrupted"
	if not is_finite(distance):
		return "target_unavailable"
	var cancel_range := maxf(0.1, attack_range) * maxf(1.0, cancel_range_multiplier)
	if distance > cancel_range:
		return "target_evaded"
	return ""


static func can_commit(
	target_valid: bool,
	distance: float,
	attack_range: float,
	hit_stun_remaining: float
) -> bool:
	return (
		target_valid
		and hit_stun_remaining <= 0.0
		and is_finite(distance)
		and distance >= 0.0
		and distance <= maxf(0.1, attack_range)
	)


static func progress_ratio(remaining: float, duration: float) -> float:
	var normalized_duration := maxf(0.001, duration)
	return clampf(1.0 - maxf(0.0, remaining) / normalized_duration, 0.0, 1.0)


static func resolve_state(windup_remaining: float, cooldown_remaining: float) -> String:
	if windup_remaining > 0.0:
		return STATE_WINDUP
	if cooldown_remaining > 0.0:
		return STATE_COOLDOWN
	return STATE_IDLE
