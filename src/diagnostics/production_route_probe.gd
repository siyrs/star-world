class_name ProductionRouteProbe
extends RefCounted

# Export-safe production-input route probe.
#
# Planning is deterministic for the requested profile and seed. Execution never
# writes the player transform after world activation: movement and buffered jumps
# are delivered through the same Input actions consumed by the production player.
# The result is intentionally data-only so release smoke, long-soak, and QA gates
# can share one route contract without importing test-only scripts.

const GeneratorScript = preload("res://src/world/world_generator.gd")
const Actions = preload("res://src/input/gameplay_input_actions.gd")
const BlockRegistry = preload("res://src/block/block_registry.gd")

const INVALID_COORD := 2147483647
const DEFAULT_MAX_SEARCH_RADIUS := 72
const DEFAULT_MAX_SEARCH_NODES := 12000
const DEFAULT_MIN_ROUTE_STEPS := 20
const DEFAULT_TARGET_ROUTE_STEPS := 36
const DEFAULT_MIN_ROUTE_DISPLACEMENT := 14.0
const DEFAULT_MAX_STEP_FRAMES := 96
const TARGET_HORIZONTAL_TOLERANCE := 0.36
const TARGET_SPEED_TOLERANCE := 0.75
const STEERING_DEADZONE := 0.08
const STEERING_BRAKE_DISTANCE := 0.46
# A one-block descent briefly moves the production body through its air-control
# path. Keep the approach below normal walking speed and start braking before
# the ledge so a valid lower support cell is reached without overshooting it.
const DESCENT_APPROACH_SPEED_LIMIT := 1.65
const DESCENT_BRAKE_DISTANCE := 0.72
const MIN_STEP_PROGRESS := 0.20
const STALL_WINDOW_FRAMES := 16
const MIN_STALL_WINDOW_PROGRESS := 0.04
const MAX_ACCEPTABLE_ROUTE_FALL := 4.0
const MAX_JUMP_ATTEMPTS_PER_STEP := 2
const JUMP_HOLD_FRAMES := 3

const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const CHUNK_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]


func execute(
	tree: SceneTree,
	world: Node,
	player: CharacterBody3D,
	profile_id: String,
	seed: int,
	options: Dictionary = {}
) -> Dictionary:
	Actions.ensure_default_bindings()
	if tree == null or world == null or player == null:
		return {"ok": false, "reason": "runtime_missing", "transport_after_spawn": false}
	if not bool(world.get("is_started")) or not bool(player.get("input_enabled")):
		return {"ok": false, "reason": "runtime_not_ready", "transport_after_spawn": false}

	var min_route_steps := maxi(
		2, int(options.get("min_route_steps", DEFAULT_MIN_ROUTE_STEPS))
	)
	var target_route_steps := maxi(
		min_route_steps,
		int(options.get("target_route_steps", DEFAULT_TARGET_ROUTE_STEPS))
	)
	var min_displacement := maxf(
		2.0,
		float(options.get("min_route_displacement", DEFAULT_MIN_ROUTE_DISPLACEMENT))
	)
	var max_step_frames := clampi(
		int(options.get("max_step_frames", DEFAULT_MAX_STEP_FRAMES)), 48, 180
	)
	var max_search_radius := clampi(
		int(options.get("max_search_radius", DEFAULT_MAX_SEARCH_RADIUS)), 16, 128
	)
	var max_search_nodes := clampi(
		int(options.get("max_search_nodes", DEFAULT_MAX_SEARCH_NODES)), 1000, 30000
	)

	player.call(
		"restore_orientation",
		{"rotation": [0.0, 0.0, 0.0], "look_pitch": 0.0}
	)
	player.call("reset_motion")
	for _frame in 8:
		await tree.physics_frame

	var start_position := player.global_position
	var start_block: Vector3i = world.call("world_to_block", start_position)
	var generator = GeneratorScript.new()
	generator.configure(profile_id, seed)
	var planned: Dictionary = _plan_route(
		generator,
		Vector2i(start_block.x, start_block.z),
		target_route_steps,
		max_search_radius,
		max_search_nodes
	)
	var route: Array = planned.get("route", [])
	if route.size() < min_route_steps + 1:
		_release_actions()
		return {
			"ok": false,
			"reason": "route_too_short",
			"profile_id": profile_id,
			"seed": seed,
			"planned_steps": maxi(0, route.size() - 1),
			"minimum_required_steps": min_route_steps,
			"search_nodes": int(planned.get("search_nodes", 0)),
			"transport_after_spawn": false,
		}
	var planned_start: Vector3i = route[0]
	if (
		absi(planned_start.x - start_block.x) > 1
		or absi(planned_start.z - start_block.z) > 1
	):
		_release_actions()
		return {
			"ok": false,
			"reason": "route_not_at_spawn",
			"profile_id": profile_id,
			"seed": seed,
			"spawn_block": [start_block.x, start_block.y, start_block.z],
			"planned_start": [planned_start.x, planned_start.y, planned_start.z],
			"transport_after_spawn": false,
		}

	_force_route_collision(world, route)
	world.call("set_focus", player)
	for _frame in 12:
		await tree.physics_frame

	var visited_chunks: Dictionary = {}
	var surface_ids: Dictionary = {}
	var route_failures: Array[String] = []
	var step_diagnostics: Array[Dictionary] = []
	var successful_steps := 0
	var minimum_y := player.global_position.y
	var maximum_single_fall := 0.0
	for index in range(1, route.size()):
		var previous: Vector3i = route[index - 1]
		var target: Vector3i = route[index]
		var result: Dictionary = await _walk_step(
			tree, player, world, previous, target, visited_chunks, max_step_frames
		)
		result["step_index"] = index
		step_diagnostics.append(result.duplicate(true))
		minimum_y = minf(
			minimum_y, float(result.get("minimum_y", player.global_position.y))
		)
		maximum_single_fall = maxf(
			maximum_single_fall, float(result.get("fall", 0.0))
		)
		var support_id := str(
			generator.call("get_block", Vector3i(target.x, target.y, target.z))
		)
		surface_ids[support_id] = int(surface_ids.get(support_id, 0)) + 1
		if bool(result.get("success", false)):
			successful_steps += 1
			continue
		route_failures.append(
			"step_%d:%s@%s->%s"
			% [
				index,
				str(result.get("reason", "unknown")),
				str(result.get("final", [])),
				str(result.get("target", [])),
			]
		)
		break

	_release_actions()
	var final_position := player.global_position
	var displacement := Vector2(
		final_position.x - start_position.x,
		final_position.z - start_position.z
	).length()
	var finite_and_playable := (
		is_finite(final_position.x)
		and is_finite(final_position.y)
		and is_finite(final_position.z)
		and final_position.y > -12.0
	)
	var all_steps_completed := successful_steps == route.size() - 1
	var ok := (
		route_failures.is_empty()
		and all_steps_completed
		and displacement >= min_displacement
		and visited_chunks.size() >= 2
		and finite_and_playable
		and maximum_single_fall <= MAX_ACCEPTABLE_ROUTE_FALL
		and bool(player.get("input_enabled"))
	)
	return {
		"ok": ok,
		"reason": "" if ok else "route_contract_failed",
		"profile_id": profile_id,
		"seed": seed,
		"planned_steps": maxi(0, route.size() - 1),
		"successful_steps": successful_steps,
		"start": [start_position.x, start_position.y, start_position.z],
		"final": [final_position.x, final_position.y, final_position.z],
		"horizontal_displacement": displacement,
		"minimum_required_displacement": min_displacement,
		"unique_chunks": visited_chunks.size(),
		"minimum_y": minimum_y,
		"maximum_single_fall": maximum_single_fall,
		"surface_ids": surface_ids,
		"search_nodes": int(planned.get("search_nodes", 0)),
		"route_failures": route_failures,
		"step_diagnostics": step_diagnostics,
		"transport_after_spawn": false,
		"production_input": true,
		"player_transform_writes": 0,
	}


func _plan_route(
	generator: RefCounted,
	requested_start: Vector2i,
	target_steps: int,
	max_search_radius: int,
	max_search_nodes: int
) -> Dictionary:
	var start := _resolve_walkable_start(generator, requested_start)
	if start.x == INVALID_COORD:
		return {"route": [], "search_nodes": 0}
	var start_height := int(generator.call("find_walkable_surface", start.x, start.y))
	var queue: Array[Vector2i] = [start]
	var head := 0
	var parents: Dictionary = {_key(start): ""}
	var heights: Dictionary = {_key(start): start_height}
	var distances: Dictionary = {_key(start): 0}
	var best := start
	var best_distance := 0
	while head < queue.size() and head < max_search_nodes:
		var current := queue[head]
		head += 1
		var current_key := _key(current)
		var current_height := int(heights.get(current_key, start_height))
		var current_distance := int(distances.get(current_key, 0))
		if current_distance > best_distance:
			best = current
			best_distance = current_distance
			if best_distance >= target_steps:
				break
		for offset: Vector2i in CARDINALS:
			var next := current + offset
			if (
				absi(next.x - start.x) > max_search_radius
				or absi(next.y - start.y) > max_search_radius
			):
				continue
			var next_key := _key(next)
			if parents.has(next_key):
				continue
			var next_height := int(
				generator.call("find_walkable_surface", next.x, next.y)
			)
			if next_height < 1 or absi(next_height - current_height) > 1:
				continue
			if not _transition_has_clearance(
				generator, current, current_height, next, next_height
			):
				continue
			parents[next_key] = current_key
			heights[next_key] = next_height
			distances[next_key] = current_distance + 1
			queue.append(next)
	var route_2d: Array[Vector2i] = []
	var cursor_key := _key(best)
	while not cursor_key.is_empty():
		var parts := cursor_key.split(",")
		if parts.size() < 2:
			break
		var point := Vector2i(int(parts[0]), int(parts[1]))
		route_2d.push_front(point)
		cursor_key = str(parents.get(cursor_key, ""))
	var route: Array[Vector3i] = []
	for point: Vector2i in route_2d:
		route.append(
			Vector3i(
				point.x,
				int(heights.get(_key(point), start_height)),
				point.y
			)
		)
	return {"route": route, "search_nodes": head}


func _resolve_walkable_start(generator: RefCounted, requested: Vector2i) -> Vector2i:
	for radius in range(0, 13):
		for x_offset in range(-radius, radius + 1):
			for z_offset in range(-radius, radius + 1):
				if (
					radius > 0
					and absi(x_offset) != radius
					and absi(z_offset) != radius
				):
					continue
				var x := requested.x + x_offset
				var z := requested.y + z_offset
				var height := int(generator.call("find_walkable_surface", x, z))
				if height >= 1 and _is_safe_surface(generator, x, z, height):
					return Vector2i(x, z)
	return Vector2i(INVALID_COORD, INVALID_COORD)


func _transition_has_clearance(
	generator: RefCounted,
	current: Vector2i,
	current_height: int,
	next: Vector2i,
	next_height: int
) -> bool:
	if not _is_safe_surface(generator, current.x, current.y, current_height):
		return false
	if not _is_safe_surface(generator, next.x, next.y, next_height):
		return false
	if next_height > current_height:
		return (
			str(
				generator.call(
					"get_block",
					Vector3i(current.x, current_height + 3, current.y)
				)
			) == BlockRegistry.AIR
		)
	return true


func _is_safe_surface(generator: RefCounted, x: int, z: int, height: int) -> bool:
	var support := str(generator.call("get_block", Vector3i(x, height, z)))
	if support in [
		BlockRegistry.AIR,
		"water",
		"lava",
		"leaves",
		"cactus",
		"glow_crystal",
	]:
		return false
	return (
		str(generator.call("get_block", Vector3i(x, height + 1, z)))
		== BlockRegistry.AIR
		and str(generator.call("get_block", Vector3i(x, height + 2, z)))
		== BlockRegistry.AIR
	)


func _force_route_collision(world: Node, route: Array) -> void:
	var chunks: Dictionary = {}
	for raw_point: Variant in route:
		if raw_point is not Vector3i:
			continue
		var chunk: Vector2i = world.call("block_to_chunk", raw_point)
		chunks[_key(chunk)] = chunk
	for raw_chunk: Variant in chunks.values():
		var chunk := Vector2i(raw_chunk)
		world.call("force_load_chunk", chunk)
		for offset: Vector2i in CHUNK_NEIGHBOURS:
			world.call("force_load_chunk", chunk + offset)


func _walk_step(
	tree: SceneTree,
	player: CharacterBody3D,
	world: Node,
	previous: Vector3i,
	target: Vector3i,
	visited_chunks: Dictionary,
	max_step_frames: int
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
	var cautious_descent := target.y < previous.y
	var peak_horizontal_speed := Vector2(
		player.velocity.x, player.velocity.z
	).length()
	for frame_index in max_step_frames:
		frame_count = frame_index + 1
		var before := player.global_position
		var offset := Vector2(
			target_position.x - before.x,
			target_position.z - before.z
		)
		_apply_target_steering(offset, player.velocity, cautious_descent)
		if ascent and jump_attempts == 0:
			Input.action_press(Actions.JUMP)
			jump_hold_remaining = JUMP_HOLD_FRAMES
			jump_attempts += 1
		await tree.physics_frame
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
		peak_horizontal_speed = maxf(peak_horizontal_speed, horizontal_speed)
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
					Input.action_press(Actions.JUMP)
					jump_hold_remaining = JUMP_HOLD_FRAMES
					jump_attempts += 1
			window_start_distance = best_distance
	_release_movement_actions()
	Input.action_release(Actions.JUMP)
	for _frame in 5:
		await tree.physics_frame
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
		"cautious_descent": cautious_descent,
		"peak_horizontal_speed": peak_horizontal_speed,
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


func _apply_target_steering(
	offset: Vector2, velocity: Vector3, cautious_descent: bool = false
) -> void:
	_release_movement_actions()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if cautious_descent and horizontal_speed >= DESCENT_APPROACH_SPEED_LIMIT:
		return
	_apply_axis_action(
		offset.x,
		velocity.x,
		Actions.MOVE_RIGHT,
		Actions.MOVE_LEFT,
		cautious_descent
	)
	_apply_axis_action(
		offset.y,
		velocity.z,
		Actions.MOVE_BACKWARD,
		Actions.MOVE_FORWARD,
		cautious_descent
	)


func _apply_axis_action(
	offset: float,
	velocity: float,
	positive_action: StringName,
	negative_action: StringName,
	cautious_descent: bool = false
) -> void:
	var distance := absf(offset)
	if distance <= STEERING_DEADZONE:
		return
	var moving_toward := signf(velocity) == signf(offset)
	var brake_distance := (
		DESCENT_BRAKE_DISTANCE if cautious_descent else STEERING_BRAKE_DISTANCE
	)
	if (
		distance <= brake_distance
		and moving_toward
		and absf(velocity) > TARGET_SPEED_TOLERANCE
	):
		return
	Input.action_press(positive_action if offset > 0.0 else negative_action)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _key(value: Variant) -> String:
	if value is Vector2i:
		return "%d,%d" % [value.x, value.y]
	return str(value)


func _release_movement_actions() -> void:
	for action: StringName in [
		Actions.MOVE_FORWARD,
		Actions.MOVE_BACKWARD,
		Actions.MOVE_LEFT,
		Actions.MOVE_RIGHT,
	]:
		Input.action_release(action)


func _release_actions() -> void:
	_release_movement_actions()
	Input.action_release(Actions.JUMP)
	Input.action_release(Actions.SPRINT)
