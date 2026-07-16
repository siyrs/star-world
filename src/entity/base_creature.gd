class_name BaseCreature
extends CharacterBody3D

signal damaged(amount: float, remaining_health: float)
signal died(species_id: String, drops: Dictionary, world_position: Vector3)
signal attack_landed(target: Node, damage: float)
signal combat_hit_applied(result: Dictionary)

const KNOCKBACK_DRAG := 7.5
const MOTION_EPSILON := 0.0001

@export var species_id: String = "creature"
@export var display_name: String = "Creature"
@export var max_health: float = 10.0
@export var move_speed: float = 2.0
@export var attack_damage: float = 0.0
@export var hostile: bool = false
@export var detection_range: float = 12.0
@export var attack_range: float = 1.7
@export var collision_size: Vector3 = Vector3(0.8, 1.2, 0.8)

var health: float = 10.0
var drops: Dictionary = {}
var target: Node3D
var attraction_target: Node3D
var inventory_service
var _configured: bool = false
var _dead: bool = false
var _wander_direction := Vector3.ZERO
var _decision_timer: float = 0.0
var _attack_timer: float = 0.0
var _flee_timer: float = 0.0
var _flee_direction := Vector3.ZERO
var _attraction_remaining_seconds: float = 0.0
var _attraction_stop_distance: float = 2.0
var _hit_stun_remaining: float = 0.0
var _locomotion_horizontal := Vector2.ZERO
var _combat_impulse := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _gravity: float = 9.8


func _ready() -> void:
	_rng.randomize()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	health = max_health
	add_to_group("creatures")
	add_to_group(species_id)
	_create_collision()
	_build_model()


func apply_profile(profile: Dictionary) -> void:
	_configured = true
	display_name = str(profile.get("name", display_name))
	max_health = float(profile.get("max_health", max_health))
	move_speed = float(profile.get("speed", move_speed))
	attack_damage = float(profile.get("damage", attack_damage))
	drops = profile.get("drops", {}).duplicate(true)
	health = max_health


func set_attraction_target(
	p_target: Node3D, duration_seconds: float = 0.75, stop_distance: float = 2.0
) -> void:
	if _dead or p_target == null or not is_instance_valid(p_target):
		clear_attraction_target()
		return
	attraction_target = p_target
	_attraction_remaining_seconds = maxf(0.1, duration_seconds)
	_attraction_stop_distance = maxf(0.25, stop_distance)


func clear_attraction_target() -> void:
	attraction_target = null
	_attraction_remaining_seconds = 0.0


func has_active_attraction() -> bool:
	return (
		_attraction_remaining_seconds > 0.0
		and attraction_target != null
		and is_instance_valid(attraction_target)
	)


func get_attraction_snapshot() -> Dictionary:
	return {
		"active": has_active_attraction(),
		"remaining_seconds": _attraction_remaining_seconds,
		"stop_distance": _attraction_stop_distance,
		"target_id": attraction_target.get_instance_id() if has_active_attraction() else 0,
	}


func is_combat_target_available() -> bool:
	return not _dead and health > 0.0 and not is_queued_for_deletion()


func apply_combat_hit(hit: Dictionary, attacker: Node3D = null) -> Dictionary:
	if not is_combat_target_available():
		return {"applied": false, "reason": "target_unavailable"}
	var damage := maxf(0.0, float(hit.get("final_damage", hit.get("damage", 0.0))))
	if damage <= 0.0:
		return {"applied": false, "reason": "no_damage"}
	# A creature close enough to be hit must immediately participate in physics,
	# even if a distance-budget service previously paused its far-away simulation.
	set_physics_process(true)
	var before := health
	var knockback := _vector3_from(hit.get("knockback", Vector3.ZERO))
	_combat_impulse.x = knockback.x
	_combat_impulse.z = knockback.z
	velocity.y = maxf(velocity.y, knockback.y)
	_hit_stun_remaining = maxf(
		_hit_stun_remaining, maxf(0.0, float(hit.get("hit_stun_seconds", 0.0)))
	)
	take_damage(damage, attacker)
	var result := {
		"applied": true,
		"health_before": before,
		"health_after": health,
		"remaining_health": health,
		"defeated": _dead,
		"target_position": [global_position.x, global_position.y, global_position.z],
		"knockback": [knockback.x, knockback.y, knockback.z],
		"hit_stun_seconds": _hit_stun_remaining,
	}
	combat_hit_applied.emit(result.duplicate(true))
	return result


func clear_combat_motion() -> void:
	_combat_impulse = Vector3.ZERO
	_locomotion_horizontal = Vector2.ZERO
	_hit_stun_remaining = 0.0
	velocity = Vector3.ZERO


func get_combat_snapshot() -> Dictionary:
	return {
		"available": is_combat_target_available(),
		"health": health,
		"max_health": max_health,
		"hit_stun_remaining": _hit_stun_remaining,
		"velocity": [velocity.x, velocity.y, velocity.z],
		"combat_impulse": [_combat_impulse.x, _combat_impulse.y, _combat_impulse.z],
		"locomotion_horizontal": [_locomotion_horizontal.x, _locomotion_horizontal.y],
	}


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_flee_timer = maxf(0.0, _flee_timer - delta)
	_attraction_remaining_seconds = maxf(0.0, _attraction_remaining_seconds - delta)
	_hit_stun_remaining = maxf(0.0, _hit_stun_remaining - delta)
	if _attraction_remaining_seconds <= 0.0:
		attraction_target = null
	_decision_timer -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y <= 0.0:
		velocity.y = -0.1
	var direction := Vector3.ZERO if _hit_stun_remaining > 0.0 else _choose_direction()
	var active_acceleration := maxf(4.0, move_speed * 5.0)
	_locomotion_horizontal.x = move_toward(
		_locomotion_horizontal.x, direction.x * move_speed, active_acceleration * delta
	)
	_locomotion_horizontal.y = move_toward(
		_locomotion_horizontal.y, direction.z * move_speed, active_acceleration * delta
	)
	velocity.x = _locomotion_horizontal.x + _combat_impulse.x
	velocity.z = _locomotion_horizontal.y + _combat_impulse.z
	if direction.length_squared() > 0.05:
		rotation.y = lerp_angle(
			rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 8.0)
		)
	move_and_slide()
	_combat_impulse.x = move_toward(_combat_impulse.x, 0.0, KNOCKBACK_DRAG * delta)
	_combat_impulse.z = move_toward(_combat_impulse.z, 0.0, KNOCKBACK_DRAG * delta)
	if absf(_combat_impulse.x) <= MOTION_EPSILON:
		_combat_impulse.x = 0.0
	if absf(_combat_impulse.z) <= MOTION_EPSILON:
		_combat_impulse.z = 0.0


func _choose_direction() -> Vector3:
	if _flee_timer > 0.0:
		return _flee_direction.normalized()
	if not hostile and has_active_attraction():
		var attraction_offset := attraction_target.global_position - global_position
		attraction_offset.y = 0.0
		if attraction_offset.length() <= _attraction_stop_distance:
			return Vector3.ZERO
		return attraction_offset.normalized()
	if hostile:
		_acquire_target()
		if target != null and is_instance_valid(target):
			var offset := target.global_position - global_position
			offset.y = 0.0
			if offset.length() <= attack_range:
				_attempt_attack()
				return Vector3.ZERO
			if offset.length() <= detection_range:
				return offset.normalized()
	if _decision_timer <= 0.0:
		_decision_timer = _rng.randf_range(1.5, 4.5)
		if _rng.randf() < 0.28:
			_wander_direction = Vector3.ZERO
		else:
			var angle := _rng.randf_range(0.0, TAU)
			_wander_direction = Vector3(sin(angle), 0.0, cos(angle))
	return _wander_direction


func _acquire_target() -> void:
	if (
		target != null
		and is_instance_valid(target)
		and global_position.distance_to(target.global_position) <= detection_range * 1.4
	):
		return
	target = null
	for candidate in get_tree().get_nodes_in_group("player"):
		if (
			candidate is Node3D
			and (
				target == null
				or global_position.distance_to(candidate.global_position)
				< global_position.distance_to(target.global_position)
			)
		):
			target = candidate


func _attempt_attack() -> void:
	if _attack_timer > 0.0 or target == null:
		return
	_attack_timer = 1.1
	if target.has_method("take_damage"):
		target.call("take_damage", attack_damage, "zombie")
	elif target.has_method("get_survival_service"):
		var survival = target.call("get_survival_service")
		if survival != null:
			survival.take_damage(attack_damage, "zombie")
	attack_landed.emit(target, attack_damage)


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if _dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if attacker != null and not hostile:
		_flee_direction = global_position - attacker.global_position
		_flee_direction.y = 0.0
		_flee_timer = 2.5
	damaged.emit(amount, health)
	if health <= 0.0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	clear_combat_motion()
	clear_attraction_target()
	set_physics_process(false)
	var generated_drops := _roll_drops()
	died.emit(species_id, generated_drops, global_position)
	_spawn_pickups(generated_drops)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.25)
	tween.tween_callback(queue_free)


func _roll_drops() -> Dictionary:
	var result: Dictionary = {}
	for item_id in drops:
		var range_value = drops[item_id]
		if range_value is Array and range_value.size() >= 2:
			var amount := _rng.randi_range(int(range_value[0]), int(range_value[1]))
			if amount > 0:
				result[item_id] = amount
		elif int(range_value) > 0:
			result[item_id] = int(range_value)
	return result


func _spawn_pickups(generated_drops: Dictionary) -> void:
	var pickup_script = load("res://src/entity/item_pickup.gd")
	if pickup_script == null or get_parent() == null:
		return
	for item_id in generated_drops:
		var pickup = pickup_script.new()
		pickup.setup(str(item_id), int(generated_drops[item_id]), inventory_service)
		get_parent().add_child(pickup)
		pickup.global_position = global_position + Vector3(
			_rng.randf_range(-0.35, 0.35), 0.65, _rng.randf_range(-0.35, 0.35)
		)


func _create_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = collision_size
	collision.shape = shape
	collision.position.y = collision_size.y * 0.5
	add_child(collision)


func _build_model() -> void:
	_make_box(
		"Body",
		collision_size,
		Vector3(0.0, collision_size.y * 0.5, 0.0),
		Color("#888888")
	)


func _make_box(
	part_name: String, size: Vector3, local_position: Vector3, color: Color
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
