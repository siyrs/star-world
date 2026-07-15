class_name CombatCadencePolicy
extends RefCounted

const POSITION_EPSILON := 0.0001


func evaluate(
	profile: Dictionary,
	cooldown_remaining: float,
	target_available: bool
) -> Dictionary:
	var cooldown_seconds := maxf(0.10, float(profile.get("cooldown_seconds", 0.72)))
	var remaining := maxf(0.0, cooldown_remaining)
	var result := {
		"handled": target_available,
		"accepted": false,
		"reason": "invalid_target" if not target_available else "cooldown",
		"cooldown_seconds": cooldown_seconds,
		"cooldown_remaining": remaining,
		"ready_ratio": ready_ratio(remaining, cooldown_seconds),
	}
	if not target_available:
		return result
	if remaining > 0.0:
		return result
	result["accepted"] = true
	result["reason"] = "ok"
	result["ready_ratio"] = 1.0
	return result


func build_knockback(
	attacker_position: Vector3,
	target_position: Vector3,
	attacker_forward: Vector3,
	profile: Dictionary
) -> Vector3:
	var direction := target_position - attacker_position
	direction.y = 0.0
	if direction.length_squared() <= POSITION_EPSILON:
		direction = attacker_forward
		direction.y = 0.0
	if direction.length_squared() <= POSITION_EPSILON:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	return (
		direction * maxf(0.0, float(profile.get("knockback_horizontal", 0.0)))
		+ Vector3.UP * maxf(0.0, float(profile.get("knockback_vertical", 0.0)))
	)


func ready_ratio(remaining: float, total: float) -> float:
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - maxf(0.0, remaining) / total, 0.0, 1.0)


static func reason_text(reason: String) -> String:
	match reason:
		"ok":
			return "攻击命中"
		"cooldown":
			return "攻击尚未恢复"
		"invalid_target":
			return "当前目标无法攻击"
		"target_rejected":
			return "目标未接受本次攻击"
		_:
			return "攻击未生效"
