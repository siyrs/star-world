class_name ProjectileRuntimeService
extends Node3D

signal projectile_spawned(projectile_id: int, snapshot: Dictionary)
signal projectile_hit(projectile_id: int, result: Dictionary)
signal projectile_removed(projectile_id: int, reason: String)
signal spawn_rejected(reason: String, snapshot: Dictionary)

const MAX_ACTIVE_PROJECTILES := 64
const MIN_SEGMENT_LENGTH := 0.0001

var combat_service: Node
var _projectiles: Dictionary = {}
var _next_projectile_id := 1
var _spawn_count := 0
var _hit_count := 0
var _world_impact_count := 0
var _expired_count := 0
var _capacity_rejection_count := 0
var _peak_active_count := 0
var _raycast_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(true)


func setup(p_combat_service: Node) -> void:
	combat_service = p_combat_service


func can_spawn() -> bool:
	return _projectiles.size() < MAX_ACTIVE_PROJECTILES


func spawn_projectile(request: Dictionary) -> Dictionary:
	if not can_spawn():
		_capacity_rejection_count += 1
		var capacity_result := {
			"success": false,
			"reason": "projectile_capacity",
			"active_count": _projectiles.size(),
			"capacity": MAX_ACTIVE_PROJECTILES,
		}
		spawn_rejected.emit("projectile_capacity", capacity_result.duplicate(true))
		return capacity_result
	var origin: Variant = request.get("origin", Vector3.ZERO)
	var velocity: Variant = request.get("velocity", Vector3.ZERO)
	if origin is not Vector3 or velocity is not Vector3 or velocity.length_squared() <= 0.0001:
		var invalid_result := {"success": false, "reason": "invalid_projectile_request"}
		spawn_rejected.emit("invalid_projectile_request", invalid_result.duplicate(true))
		return invalid_result
	var projectile_id := _next_projectile_id
	_next_projectile_id += 1
	var visual := _build_visual()
	visual.name = "Projectile_%d" % projectile_id
	add_child(visual)
	visual.global_position = origin
	_orient_visual(visual, velocity)
	var attacker: Variant = request.get("attacker", null)
	var excluded_rids: Array[RID] = []
	if attacker is CollisionObject3D:
		excluded_rids.append((attacker as CollisionObject3D).get_rid())
	_projectiles[projectile_id] = {
		"id": projectile_id,
		"position": origin,
		"velocity": velocity,
		"gravity": maxf(0.0, float(request.get("gravity", 0.0))),
		"max_distance": maxf(0.1, float(request.get("max_distance", 64.0))),
		"max_lifetime_seconds": maxf(
			0.1, float(request.get("max_lifetime_seconds", 5.0))
		),
		"lifetime_seconds": 0.0,
		"travel_distance": 0.0,
		"collision_mask": maxi(1, int(request.get("collision_mask", 5))),
		"attacker": weakref(attacker) if attacker is Object else null,
		"excluded_rids": excluded_rids,
		"shot": (
			request.get("shot", {}).duplicate(true)
			if request.get("shot", {}) is Dictionary
			else {}
		),
		"visual": visual,
	}
	_spawn_count += 1
	_peak_active_count = maxi(_peak_active_count, _projectiles.size())
	var result := {
		"success": true,
		"projectile_id": projectile_id,
		"active_count": _projectiles.size(),
	}
	projectile_spawned.emit(projectile_id, result.duplicate(true))
	return result


func clear(reason: String = "clear") -> void:
	var ids: Array = _projectiles.keys()
	for raw_id: Variant in ids:
		_remove_projectile(int(raw_id), reason)


func get_snapshot() -> Dictionary:
	return {
		"active_count": _projectiles.size(),
		"capacity": MAX_ACTIVE_PROJECTILES,
		"spawn_count": _spawn_count,
		"hit_count": _hit_count,
		"world_impact_count": _world_impact_count,
		"expired_count": _expired_count,
		"capacity_rejection_count": _capacity_rejection_count,
		"peak_active_count": _peak_active_count,
		"raycast_count": _raycast_count,
	}


func _physics_process(delta: float) -> void:
	if _projectiles.is_empty() or not is_inside_tree():
		return
	var world_3d := get_world_3d()
	if world_3d == null:
		return
	var space := world_3d.direct_space_state
	var safe_delta := maxf(0.0, delta)
	var ids: Array = _projectiles.keys()
	for raw_id: Variant in ids:
		var projectile_id := int(raw_id)
		if not _projectiles.has(projectile_id):
			continue
		var record: Dictionary = _projectiles[projectile_id]
		var start: Vector3 = record.get("position", Vector3.ZERO)
		var velocity: Vector3 = record.get("velocity", Vector3.ZERO)
		velocity += Vector3.DOWN * float(record.get("gravity", 0.0)) * safe_delta
		var finish := start + velocity * safe_delta
		var segment_length := start.distance_to(finish)
		var collision: Dictionary = {}
		if segment_length > MIN_SEGMENT_LENGTH:
			var query := PhysicsRayQueryParameters3D.create(
				start,
				finish,
				int(record.get("collision_mask", 5)),
				record.get("excluded_rids", [])
			)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			collision = space.intersect_ray(query)
			_raycast_count += 1
		if not collision.is_empty():
			_resolve_impact(projectile_id, record, collision, velocity)
			continue
		record["position"] = finish
		record["velocity"] = velocity
		record["travel_distance"] = float(record.get("travel_distance", 0.0)) + segment_length
		record["lifetime_seconds"] = float(record.get("lifetime_seconds", 0.0)) + safe_delta
		_projectiles[projectile_id] = record
		var visual: Variant = record.get("visual", null)
		if visual is Node3D and is_instance_valid(visual):
			visual.global_position = finish
			_orient_visual(visual, velocity)
		if (
			float(record.get("travel_distance", 0.0))
			>= float(record.get("max_distance", 64.0))
			or float(record.get("lifetime_seconds", 0.0))
			>= float(record.get("max_lifetime_seconds", 5.0))
		):
			_expired_count += 1
			_remove_projectile(projectile_id, "expired")


func _resolve_impact(
	projectile_id: int,
	record: Dictionary,
	collision: Dictionary,
	velocity: Vector3
) -> void:
	var collider: Variant = collision.get("collider", null)
	var target := collider as Node if collider is Node else null
	var shot: Dictionary = record.get("shot", {}).duplicate(true)
	var impact_position: Vector3 = collision.get("position", record.get("position", Vector3.ZERO))
	var impact_normal: Vector3 = collision.get("normal", Vector3.ZERO)
	shot["impact_position"] = [impact_position.x, impact_position.y, impact_position.z]
	shot["impact_normal"] = [impact_normal.x, impact_normal.y, impact_normal.z]
	shot["impact_velocity"] = [velocity.x, velocity.y, velocity.z]
	shot["projectile_id"] = projectile_id
	var attacker := _attacker_from(record)
	var result := {"handled": false, "accepted": false, "reason": "world_impact"}
	if (
		target != null
		and combat_service != null
		and combat_service.has_method("resolve_projectile_hit")
	):
		var raw_result: Variant = combat_service.call(
			"resolve_projectile_hit", target, attacker, shot
		)
		if raw_result is Dictionary:
			result = raw_result.duplicate(true)
	if bool(result.get("accepted", false)):
		_hit_count += 1
		projectile_hit.emit(projectile_id, result.duplicate(true))
	else:
		_world_impact_count += 1
	_remove_projectile(projectile_id, "hit" if bool(result.get("accepted", false)) else "world_impact")


func _attacker_from(record: Dictionary) -> Node3D:
	var reference: Variant = record.get("attacker", null)
	if reference is WeakRef:
		var value: Variant = reference.get_ref()
		if value is Node3D and is_instance_valid(value):
			return value
	return null


func _remove_projectile(projectile_id: int, reason: String) -> void:
	if not _projectiles.has(projectile_id):
		return
	var record: Dictionary = _projectiles[projectile_id]
	var visual: Variant = record.get("visual", null)
	if visual is Node and is_instance_valid(visual):
		visual.queue_free()
	_projectiles.erase(projectile_id)
	projectile_removed.emit(projectile_id, reason)


func _build_visual() -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.62)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#C8A46A")
	material.roughness = 0.82
	mesh.material = material
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	return root


func _orient_visual(visual: Node3D, velocity: Vector3) -> void:
	if velocity.length_squared() <= 0.0001:
		return
	visual.look_at(visual.global_position + velocity.normalized(), Vector3.UP, true)
