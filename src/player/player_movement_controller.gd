class_name PlayerMovementController
extends RefCounted

var gravity := 9.8
var walk_speed := 5.4
var sprint_speed := 8.0
var jump_velocity := 6.2
var ground_acceleration := 18.0
var air_acceleration := 5.0


func configure(config: Dictionary) -> void:
	gravity = maxf(0.0, float(config.get("gravity", gravity)))
	walk_speed = maxf(0.0, float(config.get("walk_speed", walk_speed)))
	sprint_speed = maxf(walk_speed, float(config.get("sprint_speed", sprint_speed)))
	jump_velocity = maxf(0.0, float(config.get("jump_velocity", jump_velocity)))
	ground_acceleration = maxf(0.0, float(config.get("ground_acceleration", ground_acceleration)))
	air_acceleration = maxf(0.0, float(config.get("air_acceleration", air_acceleration)))


func step(
	body: CharacterBody3D,
	delta: float,
	input_vector: Vector2,
	jump_requested: bool,
	sprinting: bool,
	in_fluid: bool
) -> Dictionary:
	var jumped := false
	var next_velocity := body.velocity
	if not body.is_on_floor():
		next_velocity.y -= gravity * delta * (0.28 if in_fluid else 1.0)
	if jump_requested and (body.is_on_floor() or in_fluid):
		next_velocity.y = jump_velocity * (0.7 if in_fluid else 1.0)
		jumped = true

	var direction := world_direction(body.global_transform.basis, input_vector)
	var target_speed := sprint_speed if sprinting else walk_speed
	if in_fluid:
		target_speed *= 0.55
	var active_acceleration := ground_acceleration if body.is_on_floor() else air_acceleration
	next_velocity.x = move_toward(
		next_velocity.x, direction.x * target_speed, active_acceleration * delta
	)
	next_velocity.z = move_toward(
		next_velocity.z, direction.z * target_speed, active_acceleration * delta
	)
	body.velocity = next_velocity
	body.move_and_slide()
	return {
		"jumped": jumped,
		"moving": input_vector.length_squared() > 0.0001,
		"sprinting": sprinting and input_vector.length_squared() > 0.0001,
	}


func stop_horizontal(body: CharacterBody3D) -> void:
	body.velocity.x = 0.0
	body.velocity.z = 0.0


static func world_direction(basis: Basis, input_vector: Vector2) -> Vector3:
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var direction := right * input_vector.x + forward * -input_vector.y
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
