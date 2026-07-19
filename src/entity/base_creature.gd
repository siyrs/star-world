class_name BaseCreature
extends CharacterBody3D

signal damaged(amount: float, remaining_health: float)
signal died(species_id: String, drops: Dictionary, world_position: Vector3)
signal attack_windup_started(target: Node, snapshot: Dictionary)
signal attack_windup_cancelled(reason: String, snapshot: Dictionary)
signal attack_state_changed(snapshot: Dictionary)
signal attack_landed(target: Node, damage: float)
signal combat_hit_applied(result: Dictionary)

const HostileAttackPolicyScript = preload("res://src/entity/hostile_attack_policy.gd")
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
@export var attack_windup_seconds: float = 0.0
@export var attack_cooldown_seconds: float = 5.0
@export var attack_cancel_range_multiplier: float = 1.25
@export var attack_cancel_recovery_seconds: float = 0.5
@export var target_leash_multiplier: float = 1.4
@export var attack_telegraph_radius_multiplier: float = 1.0
@export var attack_source_id: String = ""
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
var _attack_windup_remaining: float = 0.0
var _attack_state := HostileAttackPolicyScript.STATE_IDLE
var _last_attack_cancel_reason := ""
var _attack_telegraph: MeshInstance3D
var _attack_telegraph_material: StandardMaterial3D
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
	if attack_source_id.is_empty():
		attack_source_id = species_id
	health = max_health
	add_to_group("creatures")
	add_to_group(species_id)
	_create_collision()
	_build_model()
	_create_attack_telegraph()


func apply_profile(profile: Dictionary) -> void:
	_configured = true
	display_name = str(profile.get("name", display_name))
	max_health = float(profile.get("max_health", max_health))
	move_speed = float(profile.get("speed", move_speed))
	attack_damage = float(profile.get("damage", attack_damage))
	drops = profile.get("drops", {}).duplicate(true)
	var raw_attack: Variant = profile.get("hostile_attack", {})
	if raw_attack is Dictionary and not raw_attack.is_empty():
		var attack_profile: Dictionary = raw_attack
		detection_range = maxf(0.1, float(attack_profile.get("detection_range", detection_range)))
		attack_range = maxf(0.1, float(attack_profile.get("attack_range", attack_range)))
		attack_windup_seconds = maxf(
			0.0, float(attack_profile.get("windup_seconds", attack_windup_seconds))
		)
		attack_cooldown_seconds = maxf(
			0.1, float(attack_profile.get("cooldown_seconds", attack_cooldown_seconds))
		)
		attack_cancel_range_multiplier = maxf(
			1.0,
			float(
				attack_profile.get(
					"cancel_range_multiplier", attack_cancel_range_multiplier
				)
			)
		)
		attack_cancel_recovery_seconds = clampf(
			float(
				attack_profile.get(
					"cancel_recovery_seconds", attack_cancel_recovery_seconds
				)
			),
			0.0,
			attack_cooldown_seconds
		)
		target_leash_multiplier = maxf(
			1.0,
			float(attack_profile.get("target_leash_multiplier", target_leash_multiplier))
		)
		attack_telegraph_radius_multiplier = maxf(
			0.5,
			float(
				attack_profile.get(
					"telegraph_radius_multiplier", attack_telegraph_radius_multiplier
				)
			)
		)
		attack_source_id = str(attack_profile.get("source_id", attack_source_id)).strip_edges()
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
	if _attack_state == HostileAttackPolicyScript.STATE_WINDUP:
		_cancel_attack_windup("interrupted")
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
	_reset_attack_state(false)


func get_combat_snapshot() -> Dictionary:
	return {
		"available": is_combat_target_available(),
		"health": health,
		"max_health": max_health,
		"hit_stun_remaining": _hit_stun_remaining,
		"velocity": [velocity.x, velocity.y, velocity.z],
		"combat_impulse": [_combat_impulse.x, _combat_impulse.y, _combat_impulse.z],
		"locomotion_horizontal": [_locomotion_horizontal.x, _locomotion_horizontal.y],
		"hostile_attack": get_hostile_attack_snapshot(),
	}


func get_hostile_attack_snapshot() -> Dictionary:
	var target_valid := _is_attack_target_valid()
	var target_distance := _target_horizontal_distance() if target_valid else -1.0
	return {
		"enabled": hostile and attack_damage > 0.0 and attack_windup_seconds > 0.0,
		"state": _attack_state,
		"source_id": attack_source_id,
		"windup_seconds": attack_windup_seconds,
		"windup_remaining": _attack_windup_remaining,
		"windup_progress": HostileAttackPolicyScript.progress_ratio(
			_attack_windup_remaining, attack_windup_seconds
		),
		"cooldown_seconds": attack_cooldown_seconds,
		"cooldown_remaining": _attack_timer,
		"attack_range": attack_range,
		"cancel_range": attack_range * attack_cancel_range_multiplier,
		"target_valid": target_valid,
		"target_id": target.get_instance_id() if target_valid else 0,
		"target_distance": target_distance,
		"telegraph_visible": (
			_attack_telegraph != null
			and is_instance_valid(_attack_telegraph)
			and _attack_telegraph.visible
		),
		"last_cancel_reason": _last_attack_cancel_reason,
	}


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var safe_delta := maxf(0.0, delta)
	_attack_timer = maxf(0.0, _attack_timer - safe_delta)
	if (
		_attack_state == HostileAttackPolicyScript.STATE_COOLDOWN
		and _attack_timer <= 0.0
	):
		_set_attack_state(HostileAttackPolicyScript.STATE_IDLE)
	_flee_timer = maxf(0.0, _flee_timer - safe_delta)
	_attraction_remaining_seconds = maxf(
		0.0, _attraction_remaining_seconds - safe_delta
	)
	_hit_stun_remaining = maxf(0.0, _hit_stun_remaining - safe_delta)
	if _attraction_remaining_seconds <= 0.0:
		attraction_target = null
	_decision_timer -= safe_delta
	if not is_on_floor():
		velocity.y -= _gravity * safe_delta
	elif velocity.y <= 0.0:
		velocity.y = -0.1
	if _attack_state == HostileAttackPolicyScript.STATE_WINDUP:
		_advance_attack_windup(safe_delta)
	var direction := Vector3.ZERO
	if (
		_hit_stun_remaining <= 0.0
		and _attack_state != HostileAttackPolicyScript.STATE_WINDUP
	):
		direction = _choose_direction()
	var active_acceleration := maxf(4.0, move_speed * 5.0)
	_locomotion_horizontal.x = move_toward(
		_locomotion_horizontal.x, direction.x * move_speed, active_acceleration * safe_delta
	)
	_locomotion_horizontal.y = move_toward(
		_locomotion_horizontal.y, direction.z * move_speed, active_acceleration * safe_delta
	)
	velocity.x = _locomotion_horizontal.x + _combat_impulse.x
	velocity.z = _locomotion_horizontal.y + _combat_impulse.z
	if direction.length_squared() > 0.05:
		rotation.y = lerp_angle(
			rotation.y, atan2(direction.x, direction.z), minf(1.0, safe_delta * 8.0)
		)
	move_and_slide()
	_combat_impulse.x = move_toward(_combat_impulse.x, 0.0, KNOCKBACK_DRAG * safe_delta)
	_combat_impulse.z = move_toward(_combat_impulse.z, 0.0, KNOCKBACK_DRAG * safe_delta)
	if absf(_combat_impulse.x) <= MOTION_EPSILON:
		_combat_impulse.x = 0.0
	if absf(_combat_impulse.z) <= MOTION_EPSILON:
		_combat_impulse.z = 0.0
	_update_attack_telegraph_visual()


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
		if _is_attack_target_valid():
			var offset := target.global_position - global_position
			offset.y = 0.0
			var distance := offset.length()
			if HostileAttackPolicyScript.can_begin(
				distance,
				attack_range,
				_attack_timer,
				_attack_windup_remaining
			):
				_begin_attack_windup()
				return Vector3.ZERO
			if distance <= detection_range:
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
		_is_attack_target_valid()
		and global_position.distance_to(target.global_position)
		<= detection_range * target_leash_multiplier
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


func _begin_attack_windup() -> bool:
	if not _is_attack_target_valid():
		return false
	var distance := _target_horizontal_distance()
	if not HostileAttackPolicyScript.can_begin(
		distance,
		attack_range,
		_attack_timer,
		_attack_windup_remaining
	):
		return false
	_attack_windup_remaining = maxf(0.05, attack_windup_seconds)
	_last_attack_cancel_reason = ""
	_set_attack_state(HostileAttackPolicyScript.STATE_WINDUP)
	_update_attack_telegraph_visual()
	attack_windup_started.emit(target, get_hostile_attack_snapshot())
	return true


func _advance_attack_windup(delta: float) -> void:
	var target_valid := _is_attack_target_valid()
	var distance := _target_horizontal_distance() if target_valid else INF
	var cancel_reason := HostileAttackPolicyScript.cancellation_reason(
		target_valid,
		distance,
		attack_range,
		attack_cancel_range_multiplier,
		_hit_stun_remaining
	)
	if not cancel_reason.is_empty():
		_cancel_attack_windup(cancel_reason)
		return
	_face_attack_target(delta)
	_attack_windup_remaining = maxf(0.0, _attack_windup_remaining - delta)
	if _attack_windup_remaining > 0.0:
		return
	if HostileAttackPolicyScript.can_commit(
		target_valid, distance, attack_range, _hit_stun_remaining
	):
		_commit_attack()
	else:
		_cancel_attack_windup("target_evaded")


func _commit_attack() -> void:
	var attack_target := target
	_attack_windup_remaining = 0.0
	_attack_timer = maxf(0.1, attack_cooldown_seconds)
	_last_attack_cancel_reason = ""
	_set_attack_state(HostileAttackPolicyScript.STATE_COOLDOWN)
	var applied := false
	if attack_target != null and is_instance_valid(attack_target):
		if attack_target.has_method("take_damage"):
			attack_target.call("take_damage", attack_damage, attack_source_id)
			applied = true
		elif attack_target.has_method("get_survival_service"):
			var survival = attack_target.call("get_survival_service")
			if survival != null and survival.has_method("take_damage"):
				survival.call("take_damage", attack_damage, attack_source_id)
				applied = true
	if applied:
		attack_landed.emit(attack_target, attack_damage)


func _cancel_attack_windup(reason: String) -> void:
	if _attack_state != HostileAttackPolicyScript.STATE_WINDUP:
		return
	_last_attack_cancel_reason = reason
	_attack_windup_remaining = 0.0
	_attack_timer = maxf(_attack_timer, attack_cancel_recovery_seconds)
	_set_attack_state(
		HostileAttackPolicyScript.STATE_COOLDOWN
		if _attack_timer > 0.0
		else HostileAttackPolicyScript.STATE_IDLE
	)
	attack_windup_cancelled.emit(reason, get_hostile_attack_snapshot())


func _set_attack_state(next_state: String) -> void:
	if _attack_state == next_state:
		return
	_attack_state = next_state
	if _attack_telegraph != null and is_instance_valid(_attack_telegraph):
		_attack_telegraph.visible = _attack_state == HostileAttackPolicyScript.STATE_WINDUP
	attack_state_changed.emit(get_hostile_attack_snapshot())


func _reset_attack_state(emit_change: bool) -> void:
	var changed := _attack_state != HostileAttackPolicyScript.STATE_IDLE
	_attack_timer = 0.0
	_attack_windup_remaining = 0.0
	_attack_state = HostileAttackPolicyScript.STATE_IDLE
	_last_attack_cancel_reason = ""
	if _attack_telegraph != null and is_instance_valid(_attack_telegraph):
		_attack_telegraph.visible = false
		_attack_telegraph.scale = Vector3.ONE
	if changed and emit_change:
		attack_state_changed.emit(get_hostile_attack_snapshot())


func _is_attack_target_valid() -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target.has_method("is_combat_target_available"):
		return bool(target.call("is_combat_target_available"))
	return true


func _target_horizontal_distance() -> float:
	if not _is_attack_target_valid():
		return INF
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _face_attack_target(delta: float) -> void:
	if not _is_attack_target_valid():
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= MOTION_EPSILON:
		return
	rotation.y = lerp_angle(
		rotation.y, atan2(offset.x, offset.z), minf(1.0, maxf(0.0, delta) * 12.0)
	)


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if _dead or amount <= 0.0:
		return
	if _attack_state == HostileAttackPolicyScript.STATE_WINDUP:
		_cancel_attack_windup("interrupted")
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


func _create_attack_telegraph() -> void:
	if not hostile or attack_windup_seconds <= 0.0:
		return
	_attack_telegraph = MeshInstance3D.new()
	_attack_telegraph.name = "AttackTelegraph"
	var disc := CylinderMesh.new()
	var radius := maxf(0.25, attack_range * attack_telegraph_radius_multiplier)
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.025
	disc.radial_segments = 32
	_attack_telegraph.mesh = disc
	_attack_telegraph.position.y = 0.035
	_attack_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_telegraph.extra_cull_margin = 2.0
	_attack_telegraph_material = StandardMaterial3D.new()
	_attack_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_attack_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_telegraph_material.albedo_color = Color(1.0, 0.12, 0.03, 0.28)
	_attack_telegraph_material.emission_enabled = true
	_attack_telegraph_material.emission = Color(1.0, 0.06, 0.01)
	_attack_telegraph_material.emission_energy_multiplier = 1.6
	_attack_telegraph.material_override = _attack_telegraph_material
	_attack_telegraph.visible = false
	add_child(_attack_telegraph)


func _update_attack_telegraph_visual() -> void:
	if _attack_telegraph == null or not is_instance_valid(_attack_telegraph):
		return
	var visible := _attack_state == HostileAttackPolicyScript.STATE_WINDUP
	_attack_telegraph.visible = visible
	if not visible:
		_attack_telegraph.scale = Vector3.ONE
		return
	var progress := HostileAttackPolicyScript.progress_ratio(
		_attack_windup_remaining, attack_windup_seconds
	)
	var pulse := 0.92 + progress * 0.14 + sin(progress * TAU * 2.0) * 0.035
	_attack_telegraph.scale = Vector3(pulse, 1.0, pulse)
	if _attack_telegraph_material != null:
		var alpha := lerpf(0.22, 0.5, progress)
		_attack_telegraph_material.albedo_color = Color(1.0, 0.12, 0.03, alpha)


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
