class_name PlayerMovementController
extends RefCounted

var gravity := 9.8
var walk_speed := 5.4
var sprint_speed := 8.0
var jump_velocity := 6.2
var ground_acceleration := 18.0
var air_acceleration := 5.0
var swim_speed := 3.4
var swim_horizontal_factor := 0.62
var swim_acceleration := 12.0
var swim_sink_speed := 0.35


func configure(config: Dictionary) -> void:
	gravity = maxf(0.0, float(config.get("gravity", gravity)))
	walk_speed = maxf(0.0, float(config.get("walk_speed", walk_speed)))
	sprint_speed = maxf(walk_speed, float(config.get("sprint_speed", sprint_speed)))
	jump_velocity = maxf(0.0, float(config.get("jump_velocity", jump_velocity)))
	ground_acceleration = maxf(0.0, float(config.get("ground_acceleration", ground_acceleration)))
	air_acceleration = maxf(0.0, float(config.get("air_acceleration", air_acceleration)))
	swim_speed = maxf(0.0, float(config.get("swim_speed", swim_speed)))
	swim_horizontal_factor = clampf(
		float(config.get("swim_horizontal_factor", swim_horizontal_factor)), 0.1, 1.0
	)
	swim_acceleration = maxf(0.0, float(config.get("swim_acceleration", swim_acceleration)))
	swim_sink_speed = maxf(0.0, float(config.get("swim_sink_speed", swim_sink_speed)))


func step(
	body: CharacterBody3D,
	delta: float,
	input_vector: Vector2,
	jump_requested: bool,
	sprinting: bool,
	in_fluid: bool,
	grounded_override: bool = false
) -> Dictionary:
	var jumped := false
	var next_velocity := body.velocity
	var grounded := body.is_on_floor() or grounded_override
	if in_fluid:
		next_velocity.y = move_toward(
			next_velocity.y, -swim_sink_speed, gravity * 0.8 * delta
		)
	elif not grounded:
		next_velocity.y -= gravity * delta
	if in_fluid and jump_requested:
		next_velocity.y = swim_speed
		jumped = true
	elif jump_requested and grounded:
		next_velocity.y = jump_velocity
		jumped = true

	var direction := world_direction(body.global_transform.basis, input_vector)
	var target_speed := sprint_speed if sprinting else walk_speed
	if in_fluid:
		target_speed *= swim_horizontal_factor
	var active_acceleration := (
		swim_acceleration
		if in_fluid
		else (ground_acceleration if grounded else air_acceleration)
	)
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
