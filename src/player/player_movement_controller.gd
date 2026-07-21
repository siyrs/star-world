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
var ladder_climb_speed := 3.2
var ladder_acceleration := 16.0
var ladder_horizontal_factor := 0.35
var ladder_detach_speed := 2.4
var ladder_jump_velocity := 4.2


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
	ladder_climb_speed = maxf(0.0, float(config.get("ladder_climb_speed", ladder_climb_speed)))
	ladder_acceleration = maxf(0.0, float(config.get("ladder_acceleration", ladder_acceleration)))
	ladder_horizontal_factor = clampf(
		float(config.get("ladder_horizontal_factor", ladder_horizontal_factor)), 0.0, 1.0
	)
	ladder_detach_speed = maxf(0.0, float(config.get("ladder_detach_speed", ladder_detach_speed)))
	ladder_jump_velocity = maxf(0.0, float(config.get("ladder_jump_velocity", ladder_jump_velocity)))


func step(
	body: CharacterBody3D,
	delta: float,
	input_vector: Vector2,
	jump_requested: bool,
	sprinting: bool,
	in_fluid: bool,
	grounded_override: bool = false,
	ladder_contact: Dictionary = {}
) -> Dictionary:
	var on_ladder := bool(ladder_contact.get("active", false)) and not in_fluid
	if on_ladder:
		return _step_ladder(body, delta, input_vector, jump_requested, ladder_contact)
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
		"jumped":jumped,
		"moving":input_vector.length_squared() > 0.0001,
		"sprinting":sprinting and input_vector.length_squared() > 0.0001,
		"on_ladder":false,
		"climbing":false,
		"detached_ladder":false,
	}


func _step_ladder(
	body: CharacterBody3D,
	delta: float,
	input_vector: Vector2,
	jump_requested: bool,
	ladder_contact: Dictionary
) -> Dictionary:
	var next_velocity := body.velocity
	var climb_input := clampf(-input_vector.y, -1.0, 1.0)
	var detached := jump_requested
	if detached:
		var outward_value: Variant = ladder_contact.get("outward_offset", Vector3i.ZERO)
		var outward := Vector3(outward_value) if outward_value is Vector3i else Vector3.ZERO
		next_velocity.x = outward.x * ladder_detach_speed
		next_velocity.z = outward.z * ladder_detach_speed
		next_velocity.y = ladder_jump_velocity
	else:
		next_velocity.y = move_toward(
			next_velocity.y,
			climb_input * ladder_climb_speed,
			ladder_acceleration * delta
		)
		var strafe_direction := world_direction(
			body.global_transform.basis,
			Vector2(input_vector.x, 0.0)
		)
		var horizontal_speed := walk_speed * ladder_horizontal_factor
		next_velocity.x = move_toward(
			next_velocity.x,
			strafe_direction.x * horizontal_speed,
			ladder_acceleration * delta
		)
		next_velocity.z = move_toward(
			next_velocity.z,
			strafe_direction.z * horizontal_speed,
			ladder_acceleration * delta
		)
	body.velocity = next_velocity
	body.move_and_slide()
	return {
		"jumped":detached,
		"moving":input_vector.length_squared() > 0.0001,
		"sprinting":false,
		"on_ladder":not detached,
		"climbing":not detached and absf(climb_input) > 0.05,
		"climb_input":climb_input,
		"detached_ladder":detached,
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
