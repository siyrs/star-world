class_name HitscanRuntimeService
extends Node3D

signal shot_resolved(result: Dictionary)

const MAX_RAYS_PER_SHOT := 12
const MAX_DISTANCE := 128.0
const MAX_SPREAD_DEGREES := 12.0
const GOLDEN_ANGLE := 2.399963229728653

var combat_service: Node
var _shot_sequence := 0
var _shot_count := 0
var _ray_count := 0
var _impact_count := 0
var _accepted_target_count := 0
var _last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(p_combat_service: Node) -> void:
	combat_service = p_combat_service


func resolve_shot(request: Dictionary) -> Dictionary:
	var origin: Vector3 = request.get("origin", Vector3.ZERO)
	var direction: Vector3 = request.get("direction", Vector3.FORWARD)
	var max_distance := float(request.get("max_distance", 0.0))
	var pellet_count := int(request.get("pellet_count", 0))
	var spread_degrees := float(request.get("spread_degrees", -1.0))
	var collision_mask := int(request.get("collision_mask", 0))
	var attacker: Node3D = request.get("attacker") as Node3D
	var base_shot: Dictionary = request.get("shot", {}).duplicate(true)
	if (
		combat_service == null
		or not combat_service.has_method("resolve_projectile_hit")
		or not _finite_vector(origin)
		or not _finite_vector(direction)
		or direction.length_squared() <= 0.0001
		or max_distance <= 0.0
		or max_distance > MAX_DISTANCE
		or pellet_count <= 0
		or pellet_count > MAX_RAYS_PER_SHOT
		or spread_degrees < 0.0
		or spread_degrees > MAX_SPREAD_DEGREES
		or collision_mask <= 0
		or base_shot.is_empty()
	):
		return {"success": false, "reason": "invalid_hitscan_request"}
	var world_3d := get_world_3d()
	if world_3d == null:
		return {"success": false, "reason": "world_unavailable"}
	var direct_space_state := world_3d.direct_space_state
	if direct_space_state == null:
		return {"success": false, "reason": "physics_space_unavailable"}
	_shot_sequence += 1
	var hitscan_id := _shot_sequence
	var normalized_direction := direction.normalized()
	var grouped_hits: Dictionary = {}
	var miss_count := 0
	var impact_count := 0
	var exclude: Array[RID] = []
	if attacker is CollisionObject3D:
		exclude.append((attacker as CollisionObject3D).get_rid())
	for pellet_index in pellet_count:
		var pellet_direction := _spread_direction(
			normalized_direction,
			spread_degrees,
			hitscan_id,
			pellet_index,
			pellet_count
		)
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			origin + pellet_direction * max_distance,
			collision_mask
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = exclude
		var impact: Dictionary = direct_space_state.intersect_ray(query)
		_ray_count += 1
		if impact.is_empty():
			miss_count += 1
			continue
		impact_count += 1
		var collider: Variant = impact.get("collider")
		if collider is not Node:
			miss_count += 1
			continue
		var target := collider as Node
		var target_id := target.get_instance_id()
		if not grouped_hits.has(target_id):
			grouped_hits[target_id] = {
				"target": target,
				"pellet_hits": 0,
				"impact_position": impact.get("position", origin),
				"impact_normal": impact.get("normal", Vector3.ZERO),
				"shot_direction": pellet_direction,
			}
		var group: Dictionary = grouped_hits[target_id]
		group["pellet_hits"] = int(group.get("pellet_hits", 0)) + 1
		grouped_hits[target_id] = group
	var target_results: Array = []
	var accepted_targets := 0
	for raw_target_id: Variant in grouped_hits.keys():
		var group: Dictionary = grouped_hits[raw_target_id]
		var target: Node = group.get("target") as Node
		if target == null or not is_instance_valid(target):
			continue
		var pellet_hits := maxi(1, int(group.get("pellet_hits", 1)))
		var resolved_shot := base_shot.duplicate(true)
		resolved_shot["raw_damage"] = (
			maxf(0.0, float(base_shot.get("raw_damage", 0.0))) * float(pellet_hits)
		)
		resolved_shot["hitscan_id"] = hitscan_id
		resolved_shot["pellet_hits"] = pellet_hits
		resolved_shot["pellet_count"] = pellet_count
		resolved_shot["impact_position"] = _vector_to_array(
			group.get("impact_position", origin)
		)
		resolved_shot["impact_normal"] = _vector_to_array(
			group.get("impact_normal", Vector3.ZERO)
		)
		resolved_shot["shot_direction"] = _vector_to_array(
			group.get("shot_direction", normalized_direction)
		)
		var hit_result: Dictionary = combat_service.call(
			"resolve_projectile_hit",
			target,
			attacker,
			resolved_shot
		)
		if bool(hit_result.get("accepted", false)):
			accepted_targets += 1
		target_results.append(hit_result.duplicate(true))
	_shot_count += 1
	_impact_count += impact_count
	_accepted_target_count += accepted_targets
	_last_result = {
		"success": true,
		"status": "resolved",
		"reason": "ok",
		"hitscan_id": hitscan_id,
		"pellet_count": pellet_count,
		"ray_count": pellet_count,
		"impact_count": impact_count,
		"miss_count": miss_count,
		"unique_target_count": grouped_hits.size(),
		"accepted_target_count": accepted_targets,
		"target_results": target_results,
	}
	shot_resolved.emit(_last_result.duplicate(true))
	return _last_result.duplicate(true)


func clear(_reason: String = "clear") -> void:
	_last_result.clear()


func get_snapshot() -> Dictionary:
	return {
		"max_rays_per_shot": MAX_RAYS_PER_SHOT,
		"max_distance": MAX_DISTANCE,
		"shot_count": _shot_count,
		"ray_count": _ray_count,
		"impact_count": _impact_count,
		"accepted_target_count": _accepted_target_count,
		"last_result": _last_result.duplicate(true),
	}


func _spread_direction(
	base_direction: Vector3,
	spread_degrees: float,
	hitscan_id: int,
	pellet_index: int,
	pellet_count: int
) -> Vector3:
	if pellet_count <= 1 or spread_degrees <= 0.0001 or pellet_index == 0:
		return base_direction
	var right := base_direction.cross(Vector3.UP)
	if right.length_squared() <= 0.0001:
		right = base_direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(base_direction).normalized()
	var normalized_index := float(pellet_index) / float(maxi(1, pellet_count - 1))
	var radial_strength := sqrt(clampf(normalized_index, 0.0, 1.0))
	var angle := float(pellet_index) * GOLDEN_ANGLE + float(hitscan_id % 17) * 0.37
	var cone_radius := tan(deg_to_rad(spread_degrees)) * radial_strength
	return (
		base_direction
		+ right * cos(angle) * cone_radius
		+ up * sin(angle) * cone_radius
	).normalized()


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _vector_to_array(value: Variant) -> Array:
	if value is Vector3:
		var vector := value as Vector3
		return [vector.x, vector.y, vector.z]
	return [0.0, 0.0, 0.0]
