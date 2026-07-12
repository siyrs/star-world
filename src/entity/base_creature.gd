class_name BaseCreature
extends CharacterBody3D

signal damaged(amount: float, remaining_health: float)
signal died(species_id: String, drops: Dictionary, world_position: Vector3)
signal attack_landed(target: Node, damage: float)

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
var inventory_service
var _configured: bool = false
var _dead: bool = false
var _wander_direction := Vector3.ZERO
var _decision_timer: float = 0.0
var _attack_timer: float = 0.0
var _flee_timer: float = 0.0
var _flee_direction := Vector3.ZERO
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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_flee_timer = maxf(0.0, _flee_timer - delta)
	_decision_timer -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.1
	var direction := _choose_direction()
	velocity.x = move_toward(velocity.x, direction.x * move_speed, move_speed * 5.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, move_speed * 5.0 * delta)
	if direction.length_squared() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 8.0))
	move_and_slide()


func _choose_direction() -> Vector3:
	if _flee_timer > 0.0:
		return _flee_direction.normalized()
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
	if target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) <= detection_range * 1.4:
		return
	target = null
	for candidate in get_tree().get_nodes_in_group("player"):
		if candidate is Node3D and (target == null or global_position.distance_to(candidate.global_position) < global_position.distance_to(target.global_position)):
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
		pickup.global_position = global_position + Vector3(_rng.randf_range(-0.35, 0.35), 0.65, _rng.randf_range(-0.35, 0.35))


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
	_make_box("Body", collision_size, Vector3(0.0, collision_size.y * 0.5, 0.0), Color("#888888"))


func _make_box(part_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
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
