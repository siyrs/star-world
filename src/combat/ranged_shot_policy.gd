class_name RangedShotPolicy
extends RefCounted


func charge_ratio(charge_seconds: float, profile: Dictionary) -> float:
	var draw_seconds := maxf(0.01, float(profile.get("draw_seconds", 1.0)))
	return clampf(maxf(0.0, charge_seconds) / draw_seconds, 0.0, 1.0)


func evaluate_release(
	profile: Dictionary,
	charge_seconds: float,
	direction: Vector3
) -> Dictionary:
	if profile.is_empty():
		return {"accepted": false, "reason": "not_ranged_weapon"}
	var ratio := charge_ratio(charge_seconds, profile)
	if ratio < float(profile.get("minimum_draw_ratio", 0.0)):
		return {"accepted": false, "reason": "undercharged", "charge_ratio": ratio}
	if direction.length_squared() <= 0.0001:
		return {"accepted": false, "reason": "invalid_direction", "charge_ratio": ratio}
	var damage := lerpf(
		float(profile.get("minimum_damage", 1.0)),
		float(profile.get("maximum_damage", 1.0)),
		ratio
	)
	var speed := lerpf(
		float(profile.get("minimum_speed", 1.0)),
		float(profile.get("maximum_speed", 1.0)),
		ratio
	)
	return {
		"accepted": true,
		"reason": "ok",
		"charge_ratio": ratio,
		"damage": damage,
		"speed": speed,
		"direction": direction.normalized(),
	}


func build_shot(profile: Dictionary, evaluation: Dictionary) -> Dictionary:
	var direction: Vector3 = evaluation.get("direction", Vector3.FORWARD)
	return {
		"raw_damage": float(evaluation.get("damage", 0.0)),
		"charge_ratio": float(evaluation.get("charge_ratio", 0.0)),
		"weapon_item_id": str(profile.get("weapon_item_id", "")),
		"ammo_item_id": str(profile.get("ammo_item_id", "")),
		"knockback_horizontal": float(profile.get("knockback_horizontal", 0.0)),
		"knockback_vertical": float(profile.get("knockback_vertical", 0.0)),
		"hit_stun_seconds": float(profile.get("hit_stun_seconds", 0.0)),
		"shot_direction": [direction.x, direction.y, direction.z],
	}
