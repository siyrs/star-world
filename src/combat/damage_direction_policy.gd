class_name DamageDirectionPolicy
extends RefCounted

const DIRECTION_FRONT := "front"
const DIRECTION_RIGHT := "right"
const DIRECTION_REAR := "rear"
const DIRECTION_LEFT := "left"
const DIRECTIONS: Array[String] = [
	DIRECTION_FRONT,
	DIRECTION_RIGHT,
	DIRECTION_REAR,
	DIRECTION_LEFT,
]
const FRONT_HALF_ANGLE_DEGREES := 45.0
const SIDE_LIMIT_DEGREES := 135.0


static func classify(
	player_position: Vector3,
	player_forward: Vector3,
	source_position: Vector3
) -> Dictionary:
	var forward := Vector3(player_forward.x, 0.0, player_forward.z)
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var source_offset := source_position - player_position
	source_offset.y = 0.0
	if source_offset.length_squared() <= 0.0001:
		return {
			"direction": DIRECTION_FRONT,
			"angle_degrees": 0.0,
			"source_available": false,
		}
	var source_direction := source_offset.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var angle_degrees := rad_to_deg(atan2(
		source_direction.dot(right),
		source_direction.dot(forward)
	))
	var absolute_angle := absf(angle_degrees)
	var direction := DIRECTION_REAR
	if absolute_angle <= FRONT_HALF_ANGLE_DEGREES:
		direction = DIRECTION_FRONT
	elif absolute_angle < SIDE_LIMIT_DEGREES:
		direction = DIRECTION_RIGHT if angle_degrees > 0.0 else DIRECTION_LEFT
	return {
		"direction": direction,
		"angle_degrees": angle_degrees,
		"source_available": true,
	}


static func normalize_direction(value: Variant) -> String:
	var requested := str(value).strip_edges().to_lower()
	return requested if requested in DIRECTIONS else DIRECTION_FRONT


static func localized_label(value: Variant) -> String:
	return str({
		DIRECTION_FRONT: "前方",
		DIRECTION_RIGHT: "右侧",
		DIRECTION_REAR: "后方",
		DIRECTION_LEFT: "左侧",
	}.get(normalize_direction(value), "前方"))

static func localized_source_label(value: Variant) -> String:
	var source := str(value).strip_edges().to_lower()
	if source in ["zombie", "abyss_brute", "hostile_melee", "melee"]:
		return "近战"
	if source in ["abyss_marksman", "hostile_projectile", "projectile"]:
		return "深渊弹"
	if source in ["lava", "fall", "world", "environment", "hazard"]:
		return "环境"
	return "攻击"

