class_name HostileRangedTacticsPolicy
extends RefCounted

const MOTION_APPROACH := "approach"
const MOTION_RETREAT := "retreat"
const MOTION_HOLD := "hold"
const MOTION_STRAFE := "strafe"
const MOTION_COVER := "cover"
const MAX_COVER_PROBES := 8


static func can_begin(
	distance: float,
	minimum_range: float,
	attack_range: float,
	has_line_of_sight: bool,
	requires_line_of_sight: bool,
	cooldown_remaining: float,
	windup_remaining: float,
	runtime_available: bool
) -> bool:
	return (
		is_finite(distance)
		and distance >= maxf(0.0, minimum_range)
		and distance <= maxf(minimum_range + 0.1, attack_range)
		and (has_line_of_sight or not requires_line_of_sight)
		and cooldown_remaining <= 0.0
		and windup_remaining <= 0.0
		and runtime_available
	)


static func cancellation_reason(
	target_valid: bool,
	distance: float,
	minimum_range: float,
	attack_range: float,
	cancel_range_multiplier: float,
	has_line_of_sight: bool,
	requires_line_of_sight: bool,
	hit_stun_remaining: float
) -> String:
	if not target_valid:
		return "target_unavailable"
	if hit_stun_remaining > 0.0:
		return "interrupted"
	if not is_finite(distance):
		return "target_unavailable"
	if distance < maxf(0.0, minimum_range):
		return "target_too_close"
	if distance > maxf(0.1, attack_range) * maxf(1.0, cancel_range_multiplier):
		return "target_evaded"
	if requires_line_of_sight and not has_line_of_sight:
		return "line_of_sight_lost"
	return ""


static func motion_kind(
	distance: float,
	minimum_range: float,
	preferred_range: float,
	attack_range: float,
	has_line_of_sight: bool,
	cooldown_remaining: float,
	cover_available: bool
) -> String:
	if not is_finite(distance):
		return MOTION_HOLD
	if distance < maxf(0.0, minimum_range):
		return MOTION_RETREAT
	if not has_line_of_sight or distance > maxf(preferred_range, attack_range * 0.82):
		return MOTION_APPROACH
	if cooldown_remaining > 0.0 and cover_available:
		return MOTION_COVER
	if cooldown_remaining > 0.0:
		return MOTION_STRAFE
	if distance > maxf(minimum_range, preferred_range):
		return MOTION_APPROACH
	return MOTION_HOLD


static func strafe_direction(to_target: Vector3, sign_value: float) -> Vector3:
	var horizontal := Vector3(to_target.x, 0.0, to_target.z)
	if horizontal.length_squared() <= 0.0001:
		return Vector3.ZERO
	var side := Vector3.UP.cross(horizontal.normalized())
	return side.normalized() * (-1.0 if sign_value < 0.0 else 1.0)


static func lead_direction(
	origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	projectile_speed: float,
	max_lead_seconds: float = 0.35
) -> Vector3:
	var speed := maxf(0.1, projectile_speed)
	var distance := origin.distance_to(target_position)
	var lead_seconds := clampf(distance / speed, 0.0, maxf(0.0, max_lead_seconds))
	var aim_position := target_position + target_velocity * lead_seconds
	var direction := aim_position - origin
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD


static func cover_probe_directions(to_target: Vector3, requested_count: int) -> Array[Vector3]:
	var count := clampi(requested_count, 0, MAX_COVER_PROBES)
	var result: Array[Vector3] = []
	if count <= 0:
		return result
	var horizontal := Vector3(to_target.x, 0.0, to_target.z)
	if horizontal.length_squared() <= 0.0001:
		horizontal = Vector3.FORWARD
	var away := -horizontal.normalized()
	var offsets: Array[float] = [0.0, 0.55, -0.55, 1.05, -1.05, 1.55, -1.55, PI]
	for index in count:
		result.append(away.rotated(Vector3.UP, offsets[index]).normalized())
	return result
