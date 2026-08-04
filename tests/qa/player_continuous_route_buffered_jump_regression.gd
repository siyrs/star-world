extends "res://tests/qa/player_continuous_route_regression.gd"

# The base gate owns route planning, evidence reporting, target-centred steering and
# all release assertions. This production-input executor adds the missing input
# timing contract for one-block ascents: jump is buffered before the first physics
# frame instead of being suppressed by a transient CharacterBody3D floor flag.
# Bounded retries only occur on an actual stalled ascent; flat/downhill steps never
# receive synthetic jumps.


func _walk_step(
	player: CharacterBody3D,
	world: Node,
	previous: Vector3i,
	target: Vector3i,
	visited_chunks: Dictionary
) -> Dictionary:
	var planned_delta := Vector2i(target.x - previous.x, target.z - previous.z)
	if planned_delta not in CARDINALS:
		return {
			"success": false,
			"reason": "invalid_direction",
			"minimum_y": player.global_position.y,
			"fall": 0.0,
			"target": [target.x, target.y, target.z],
			"final": [
				player.global_position.x,
				player.global_position.y,
				player.global_position.z,
			],
		}
	var target_position := Vector3(
		target.x + 0.5, target.y + 1.05, target.z + 0.5
	)
	var starting_position := player.global_position
	var starting_y := starting_position.y
	var minimum_y := starting_y
	var initial_distance := _horizontal_distance(starting_position, target_position)
	var best_distance := initial_distance
	var window_start_distance := initial_distance
	var stall_windows := 0
	var jump_attempts := 0
	var jump_hold_remaining := 0
	var reached := false
	var frame_count := 0
	var ascent := target.y > previous.y
	for frame_index in MAX_STEP_FRAMES:
		frame_count = frame_index + 1
		var before := player.global_position
		var offset := Vector2(
			target_position.x - before.x,
			target_position.z - before.z
		)
		_apply_target_steering(offset, player.velocity)
		if ascent and jump_attempts == 0:
			# Production input services consume an edge-triggered jump request. Queue it
			# before the physics frame so a one-frame floor-state transition cannot
			# discard the only ascent attempt.
			Input.action_press(Actions.JUMP)
			jump_hold_remaining = JUMP_HOLD_FRAMES
			jump_attempts += 1
		await physics_frame
		if jump_hold_remaining > 0:
			jump_hold_remaining -= 1
			if jump_hold_remaining == 0:
				Input.action_release(Actions.JUMP)
		var current := player.global_position
		minimum_y = minf(minimum_y, current.y)
		var block: Vector3i = world.call("world_to_block", current)
		var chunk: Vector2i = world.call("block_to_chunk", block)
		visited_chunks[_key(chunk)] = true
		var distance := _horizontal_distance(current, target_position)
		best_distance = minf(best_distance, distance)
		var horizontal_speed := Vector2(
			player.velocity.x, player.velocity.z
		).length()
		if (
			distance <= TARGET_HORIZONTAL_TOLERANCE
			and horizontal_speed <= TARGET_SPEED_TOLERANCE
			and absf(current.y - target_position.y) <= 1.35
		):
			reached = true
			break
		if (
			current.y < target_position.y - MAX_ACCEPTABLE_ROUTE_FALL
			or current.y <= -12.0
		):
			break
		if (
			(frame_index + 1) % STALL_WINDOW_FRAMES == 0
			and distance > TARGET_HORIZONTAL_TOLERANCE
		):
			var window_progress := window_start_distance - best_distance
			if window_progress < MIN_STALL_WINDOW_PROGRESS:
				stall_windows += 1
				if ascent and jump_attempts < MAX_JUMP_ATTEMPTS_PER_STEP:
					# Keeping the action pressed for a bounded window lets the normal
					# gameplay controller consume it on the next grounded physics tick.
					Input.action_press(Actions.JUMP)
					jump_hold_remaining = JUMP_HOLD_FRAMES
					jump_attempts += 1
			window_start_distance = best_distance
	_release_movement_actions()
	Input.action_release(Actions.JUMP)
	for _frame in 5:
		await physics_frame
	var final := player.global_position
	var final_distance := _horizontal_distance(final, target_position)
	var progress := initial_distance - best_distance
	var stable := (
		is_finite(final.x)
		and is_finite(final.y)
		and is_finite(final.z)
		and final.y >= target_position.y - MAX_ACCEPTABLE_ROUTE_FALL
		and final.y > -12.0
	)
	var success := reached and stable and progress > MIN_STEP_PROGRESS
	var reason := ""
	if not success:
		if not stable:
			reason = "fall"
		elif progress <= MIN_STEP_PROGRESS:
			reason = "blocked"
		else:
			reason = "missed_target"
	return {
		"success": success,
		"reason": reason,
		"progress": progress,
		"initial_distance": initial_distance,
		"best_distance": best_distance,
		"final_distance": final_distance,
		"frame_count": frame_count,
		"stall_windows": stall_windows,
		"jump_attempts": jump_attempts,
		"minimum_y": minimum_y,
		"fall": maxf(0.0, starting_y - minimum_y),
		"start": [
			starting_position.x,
			starting_position.y,
			starting_position.z,
		],
		"target": [target_position.x, target_position.y, target_position.z],
		"final": [final.x, final.y, final.z],
	}
