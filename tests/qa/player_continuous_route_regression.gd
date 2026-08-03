extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const Actions = preload("res://src/input/gameplay_input_actions.gd")
const BlockRegistry = preload("res://src/block/block_registry.gd")

const ROUTE_SEED := 112358
const READY_FRAMES := 720
const MAX_SEARCH_RADIUS := 72
const MAX_SEARCH_NODES := 12000
const MIN_ROUTE_STEPS := 20
const TARGET_ROUTE_STEPS := 36
const MIN_ROUTE_DISPLACEMENT := 14.0
const MAX_STEP_FRAMES := 54
const TARGET_HORIZONTAL_TOLERANCE := 0.7
const MAX_ACCEPTABLE_ROUTE_FALL := 4.0

const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]

const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var checks := 0
var failures: Array[String] = []
var _records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Actions.ensure_default_bindings()
	for profile_id: String in PROFILE_IDS:
		await _exercise_profile(profile_id)
	_release_actions()
	_write_optional_report()
	if failures.is_empty():
		print("QA PLAYER CONTINUOUS ROUTE PASS | checks=%d | profiles=%d" % [checks, _records.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PLAYER CONTINUOUS ROUTE FAILURE: %s" % failure)
		print("QA PLAYER CONTINUOUS ROUTE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _exercise_profile(profile_id: String) -> void:
	print("PLAYER_CONTINUOUS_ROUTE_START profile=%s" % profile_id)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var world_id := "qa-continuous-%s-%d" % [profile_id, Time.get_ticks_msec()]
	var state := {
		"metadata":{
			"id":world_id,
			"name":"QA Continuous %s" % profile_id,
			"map_id":profile_id,
			"seed":ROUTE_SEED,
		},
		"player":{},
		"inventory":{},
		"world":{"block_overrides":{}},
		"survival":{"health":20.0, "hunger":20.0},
		"day_night":{"time_of_day":9.0, "day":1},
	}
	game.call("begin_world_state", state)
	var ready := false
	for _frame in READY_FRAMES:
		await process_frame
		var candidate_world: Node = game.get("world") as Node
		var candidate_player: CharacterBody3D = game.get("player") as CharacterBody3D
		if (
			candidate_world != null and candidate_player != null
			and bool(candidate_world.get("is_started"))
			and bool(candidate_player.get("input_enabled"))
		):
			ready = true
			break
	_check(ready, "%s production world reaches active player control" % profile_id)
	if not ready:
		await _dispose_game(game)
		return

	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var hub: Node = game.get("service_hub") as Node
	player.call("restore_orientation", {"rotation":[0.0, 0.0, 0.0], "look_pitch":0.0})
	player.call("reset_motion")
	for _frame in 8:
		await physics_frame
	var start_position := player.global_position
	var start_block: Vector3i = world.call("world_to_block", start_position)
	var generator = GeneratorScript.new()
	generator.configure(profile_id, ROUTE_SEED)
	var planned: Dictionary = _plan_route(generator, Vector2i(start_block.x, start_block.z))
	var route: Array = planned.get("route", [])
	_check(
		route.size() >= MIN_ROUTE_STEPS + 1,
		"%s generated terrain exposes a no-teleport route of at least %d steps (actual=%d)"
		% [profile_id, MIN_ROUTE_STEPS, maxi(0, route.size() - 1)],
	)
	if route.size() < 2:
		await _dispose_game(game)
		return
	var planned_start: Vector3i = route[0]
	_check(
		absi(planned_start.x - start_block.x) <= 1
		and absi(planned_start.z - start_block.z) <= 1,
		"%s route begins at the production spawn rather than a transported region" % profile_id,
	)
	_force_route_collision(world, route)
	world.call("set_focus", player)
	for _frame in 8:
		await physics_frame

	var visited_chunks: Dictionary = {}
	var surface_ids: Dictionary = {}
	var successful_steps := 0
	var route_failures: Array[String] = []
	var minimum_y := player.global_position.y
	var maximum_single_fall := 0.0
	for index in range(1, route.size()):
		var previous: Vector3i = route[index - 1]
		var target: Vector3i = route[index]
		var result: Dictionary = await _walk_step(player, world, previous, target, visited_chunks)
		minimum_y = minf(minimum_y, float(result.get("minimum_y", player.global_position.y)))
		maximum_single_fall = maxf(maximum_single_fall, float(result.get("fall", 0.0)))
		var support_id := str(generator.call("get_block", Vector3i(target.x, target.y, target.z)))
		surface_ids[support_id] = int(surface_ids.get(support_id, 0)) + 1
		if bool(result.get("success", false)):
			successful_steps += 1
		else:
			route_failures.append("step_%d:%s" % [index, str(result.get("reason", "unknown"))])
			break
	var final_position := player.global_position
	var displacement := Vector2(
		final_position.x - start_position.x,
		final_position.z - start_position.z,
	).length()
	_check(route_failures.is_empty(), "%s continuous route contains no collision stall or air-wall stop: %s" % [profile_id, route_failures])
	_check(successful_steps == route.size() - 1, "%s completes every planned route step through production movement input" % profile_id)
	_check(displacement >= MIN_ROUTE_DISPLACEMENT, "%s continuous route reaches at least %.1fm displacement (actual=%.2f)" % [profile_id, MIN_ROUTE_DISPLACEMENT, displacement])
	_check(visited_chunks.size() >= 2, "%s continuous route crosses at least two unique live chunks" % profile_id)
	_check(
		is_finite(final_position.x) and is_finite(final_position.y) and is_finite(final_position.z)
		and final_position.y > -12.0,
		"%s route finishes in finite playable coordinates" % profile_id,
	)
	_check(maximum_single_fall <= MAX_ACCEPTABLE_ROUTE_FALL, "%s route contains no unexpected fall greater than %.1fm" % [profile_id, MAX_ACCEPTABLE_ROUTE_FALL])
	_check(bool(player.get("input_enabled")), "%s route preserves production gameplay input" % profile_id)
	var record := {
		"profile_id":profile_id,
		"seed":ROUTE_SEED,
		"planned_steps":maxi(0, route.size() - 1),
		"successful_steps":successful_steps,
		"start":[start_position.x, start_position.y, start_position.z],
		"final":[final_position.x, final_position.y, final_position.z],
		"horizontal_displacement":displacement,
		"unique_chunks":visited_chunks.size(),
		"minimum_y":minimum_y,
		"maximum_single_fall":maximum_single_fall,
		"surface_ids":surface_ids,
		"search_nodes":int(planned.get("search_nodes", 0)),
		"route_failures":route_failures,
		"transport_after_spawn":false,
	}
	_records.append(record)
	print("PLAYER_CONTINUOUS_ROUTE_RESULT %s" % JSON.stringify(record))
	_release_actions()
	if hub != null:
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
	await _dispose_game(game)


func _plan_route(generator: RefCounted, requested_start: Vector2i) -> Dictionary:
	var start := _resolve_walkable_start(generator, requested_start)
	if start.x == 2147483647:
		return {"route":[], "search_nodes":0}
	var start_height := int(generator.call("find_walkable_surface", start.x, start.y))
	var queue: Array[Vector2i] = [start]
	var head := 0
	var parents: Dictionary = {_key(start):""}
	var heights: Dictionary = {_key(start):start_height}
	var distances: Dictionary = {_key(start):0}
	var best := start
	var best_distance := 0
	while head < queue.size() and head < MAX_SEARCH_NODES:
		var current := queue[head]
		head += 1
		var current_key := _key(current)
		var current_height := int(heights.get(current_key, start_height))
		var current_distance := int(distances.get(current_key, 0))
		if current_distance > best_distance:
			best = current
			best_distance = current_distance
			if best_distance >= TARGET_ROUTE_STEPS:
				break
		for offset: Vector2i in CARDINALS:
			var next := current + offset
			if absi(next.x - start.x) > MAX_SEARCH_RADIUS or absi(next.y - start.y) > MAX_SEARCH_RADIUS:
				continue
			var next_key := _key(next)
			if parents.has(next_key):
				continue
			var next_height := int(generator.call("find_walkable_surface", next.x, next.y))
			if next_height < 1 or absi(next_height - current_height) > 1:
				continue
			if not _is_safe_surface(generator, next.x, next.y, next_height):
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
		route.append(Vector3i(point.x, int(heights.get(_key(point), start_height)), point.y))
	return {"route":route, "search_nodes":head}


func _resolve_walkable_start(generator: RefCounted, requested: Vector2i) -> Vector2i:
	for radius in range(0, 13):
		for x_offset in range(-radius, radius + 1):
			for z_offset in range(-radius, radius + 1):
				if radius > 0 and absi(x_offset) != radius and absi(z_offset) != radius:
					continue
				var x := requested.x + x_offset
				var z := requested.y + z_offset
				var height := int(generator.call("find_walkable_surface", x, z))
				if height >= 1 and _is_safe_surface(generator, x, z, height):
					return Vector2i(x, z)
	return Vector2i(2147483647, 2147483647)


func _is_safe_surface(generator: RefCounted, x: int, z: int, height: int) -> bool:
	var support := str(generator.call("get_block", Vector3i(x, height, z)))
	if support in [BlockRegistry.AIR, "water", "lava", "leaves"]:
		return false
	return (
		str(generator.call("get_block", Vector3i(x, height + 1, z))) == BlockRegistry.AIR
		and str(generator.call("get_block", Vector3i(x, height + 2, z))) == BlockRegistry.AIR
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
		for offset: Vector2i in CARDINALS:
			world.call("force_load_chunk", chunk + offset)


func _walk_step(
	player: CharacterBody3D,
	world: Node,
	previous: Vector3i,
	target: Vector3i,
	visited_chunks: Dictionary,
) -> Dictionary:
	var delta := Vector2i(target.x - previous.x, target.z - previous.z)
	var action := _action_for_delta(delta)
	if action == StringName():
		return {"success":false, "reason":"invalid_direction", "minimum_y":player.global_position.y, "fall":0.0}
	var target_position := Vector3(target.x + 0.5, target.y + 1.05, target.z + 0.5)
	var starting_y := player.global_position.y
	var minimum_y := starting_y
	var best_distance := Vector2(
		player.global_position.x - target_position.x,
		player.global_position.z - target_position.z,
	).length()
	var initial_distance := best_distance
	var jump_frames := 0
	if target.y > previous.y:
		Input.action_press(Actions.JUMP)
		jump_frames = 3
	Input.action_press(action)
	var reached := false
	for frame in MAX_STEP_FRAMES:
		await physics_frame
		var current := player.global_position
		minimum_y = minf(minimum_y, current.y)
		var block: Vector3i = world.call("world_to_block", current)
		var chunk: Vector2i = world.call("block_to_chunk", block)
		visited_chunks[_key(chunk)] = true
		var distance := Vector2(current.x - target_position.x, current.z - target_position.z).length()
		best_distance = minf(best_distance, distance)
		if jump_frames > 0:
			jump_frames -= 1
			if jump_frames == 0:
				Input.action_release(Actions.JUMP)
		if distance <= TARGET_HORIZONTAL_TOLERANCE:
			reached = true
			break
		if current.y < target_position.y - MAX_ACCEPTABLE_ROUTE_FALL or current.y <= -12.0:
			break
	Input.action_release(action)
	Input.action_release(Actions.JUMP)
	for _frame in 3:
		await physics_frame
	var final := player.global_position
	var final_distance := Vector2(final.x - target_position.x, final.z - target_position.z).length()
	var progress := initial_distance - best_distance
	var stable := (
		is_finite(final.x) and is_finite(final.y) and is_finite(final.z)
		and final.y >= target_position.y - MAX_ACCEPTABLE_ROUTE_FALL
		and final.y > -12.0
	)
	return {
		"success":reached and stable and progress > 0.15,
		"reason":("" if reached and stable else ("fall" if not stable else "stalled")),
		"progress":progress,
		"best_distance":best_distance,
		"final_distance":final_distance,
		"minimum_y":minimum_y,
		"fall":maxf(0.0, starting_y - minimum_y),
	}


func _action_for_delta(delta: Vector2i) -> StringName:
	if delta == Vector2i(1, 0):
		return Actions.MOVE_RIGHT
	if delta == Vector2i(-1, 0):
		return Actions.MOVE_LEFT
	if delta == Vector2i(0, -1):
		return Actions.MOVE_FORWARD
	if delta == Vector2i(0, 1):
		return Actions.MOVE_BACKWARD
	return StringName()


func _key(value: Variant) -> String:
	if value is Vector2i:
		return "%d,%d" % [value.x, value.y]
	return str(value)


func _release_actions() -> void:
	for action: StringName in [
		Actions.MOVE_FORWARD,
		Actions.MOVE_BACKWARD,
		Actions.MOVE_LEFT,
		Actions.MOVE_RIGHT,
		Actions.JUMP,
		Actions.SPRINT,
	]:
		Input.action_release(action)


func _dispose_game(game: Node) -> void:
	_release_actions()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in 40:
		await process_frame


func _write_optional_report() -> void:
	var report_path := _user_argument("report")
	if report_path.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(report_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_check(false, "continuous route report path is writable")
		return
	file.store_string(JSON.stringify({
		"schema_version":1,
		"seed":ROUTE_SEED,
		"records":_records,
	}, "\t"))
	file.close()


func _user_argument(key: String) -> String:
	var prefix := "--%s=" % key
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
