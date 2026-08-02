extends SceneTree

# Release-evidence hardening gate.
#
# This test deliberately does not call generator probes "complete exploration".
# Existing profile_release_journey/profile_deep_journey tests prove menu entry,
# persistence, profile rules and finite domain contracts. This gate adds the missing
# production-player evidence: it loads the real game/world/player, fast-travels to
# geographically separated safe regions, then uses the production input actions and
# CharacterBody3D movement in each loaded region.
#
# Fast travel is only a bounded QA transport between regions. Every local traversal
# assertion is driven through Input.action_press()/physics frames, never by directly
# mutating the player's final position or calling a test-only completion function.

const GameScene = preload("res://scenes/game/game.tscn")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const Actions = preload("res://src/input/gameplay_input_actions.gd")

const TRAVERSAL_SEED := 112358
const READY_FRAMES := 720
const SETTLE_FRAMES := 4
const MOVE_FRAMES := 18
const MIN_REGIONS_PER_PROFILE := 6
const MAX_REGIONS_PER_PROFILE := 9
const MIN_LOCAL_DISPLACEMENT := 0.16
const MAX_ACCEPTABLE_FALL := 4.0

const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]

const REGION_ANCHORS: Array[Vector2i] = [
	Vector2i(-64, -64),
	Vector2i(0, -64),
	Vector2i(64, -64),
	Vector2i(-64, 0),
	Vector2i(0, 0),
	Vector2i(64, 0),
	Vector2i(-64, 64),
	Vector2i(0, 64),
	Vector2i(64, 64),
]

const MOVEMENT_ACTIONS: Array[StringName] = [
	Actions.MOVE_FORWARD,
	Actions.MOVE_RIGHT,
	Actions.MOVE_BACKWARD,
	Actions.MOVE_LEFT,
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
	_release_all_actions()
	_write_optional_report()
	if failures.is_empty():
		print(
			"QA PLAYER REGIONAL TRAVERSAL PASS | checks=%d | profiles=%d"
			% [checks, _records.size()]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA PLAYER REGIONAL TRAVERSAL FAILURE: %s" % failure)
	print(
		"QA PLAYER REGIONAL TRAVERSAL FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _exercise_profile(profile_id: String) -> void:
	print("PLAYER_REGIONAL_TRAVERSAL_START profile=%s" % profile_id)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame

	var world_id := "qa-regional-%s-%d" % [profile_id, Time.get_ticks_msec()]
	var state := {
		"metadata": {
			"id": world_id,
			"name": "QA Regional %s" % profile_id,
			"map_id": profile_id,
			"seed": TRAVERSAL_SEED,
		},
		"player": {},
		"inventory": {},
		"world": {"block_overrides": {}},
		"survival": {"health": 20.0, "hunger": 20.0},
		"day_night": {"time_of_day": 9.0, "day": 1},
	}
	game.call("begin_world_state", state)

	var ready := false
	for _frame in READY_FRAMES:
		await process_frame
		var candidate_world: Node = game.get("world") as Node
		var candidate_player: CharacterBody3D = game.get("player") as CharacterBody3D
		if (
			candidate_world != null
			and candidate_player != null
			and bool(candidate_world.get("is_started"))
			and bool(candidate_player.get("input_enabled"))
		):
			ready = true
			break
	_check(ready, "%s real game reaches active player-controlled world" % profile_id)
	if not ready:
		await _dispose_game(game)
		return

	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var hub: Node = game.get("service_hub") as Node
	var generator = GeneratorScript.new()
	generator.configure(profile_id, TRAVERSAL_SEED)
	var spawn: Vector3 = generator.find_spawn_position()
	var regions := _discover_regions(generator, spawn)
	_check(
		regions.size() >= MIN_REGIONS_PER_PROFILE,
		"%s discovers at least %d geographically separated safe regions (actual=%d)"
		% [profile_id, MIN_REGIONS_PER_PROFILE, regions.size()]
	)

	var successful_regions := 0
	var visited_chunks: Dictionary = {}
	var movement_results: Array[Dictionary] = []
	for region_index in mini(regions.size(), MAX_REGIONS_PER_PROFILE):
		var requested_position: Vector3 = regions[region_index]
		var resolved_position: Vector3 = world.call("resolve_ground_position", requested_position)
		var block_position: Vector3i = world.call("world_to_block", resolved_position)
		var chunk: Vector2i = world.call("block_to_chunk", block_position)
		world.call("force_load_chunk", chunk)
		# Load cardinal neighbours so a movement attempt near a chunk edge always owns
		# production collision instead of passing because the neighbour is absent.
		for offset: Vector2i in [
			Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
		]:
			world.call("force_load_chunk", chunk + offset)
		world.call("set_focus", player)
		player.global_position = resolved_position
		player.call("reset_motion")
		player.call("restore_orientation", {"rotation": [0.0, 0.0, 0.0], "look_pitch": 0.0})
		for _frame in SETTLE_FRAMES:
			await physics_frame

		var settled := player.global_position
		var body_stable := (
			is_finite(settled.x)
			and is_finite(settled.y)
			and is_finite(settled.z)
			and settled.y >= resolved_position.y - MAX_ACCEPTABLE_FALL
			and settled.y > -12.0
		)
		_check(body_stable, "%s region %d starts in a stable live collision body" % [profile_id, region_index + 1])
		if not body_stable:
			continue

		var movement: Dictionary = await _probe_local_movement(player, settled)
		movement["region_index"] = region_index + 1
		movement["chunk"] = [chunk.x, chunk.y]
		movement["start"] = [settled.x, settled.y, settled.z]
		movement_results.append(movement)
		var moved := bool(movement.get("success", false))
		_check(
			moved,
			"%s region %d accepts real WASD movement (max=%.3fm)"
			% [profile_id, region_index + 1, float(movement.get("max_displacement", 0.0))]
		)
		if moved:
			successful_regions += 1
			visited_chunks["%d,%d" % [chunk.x, chunk.y]] = true

	var attempted_regions := mini(regions.size(), MAX_REGIONS_PER_PROFILE)
	_check(
		successful_regions >= MIN_REGIONS_PER_PROFILE,
		"%s has player-driven traversal in at least %d regions (actual=%d/%d)"
		% [profile_id, MIN_REGIONS_PER_PROFILE, successful_regions, attempted_regions]
	)
	_check(
		visited_chunks.size() >= MIN_REGIONS_PER_PROFILE,
		"%s traversal covers at least %d unique chunks (actual=%d)"
		% [profile_id, MIN_REGIONS_PER_PROFILE, visited_chunks.size()]
	)

	var record := {
		"profile_id": profile_id,
		"seed": TRAVERSAL_SEED,
		"candidate_regions": regions.size(),
		"attempted_regions": attempted_regions,
		"successful_regions": successful_regions,
		"unique_chunks": visited_chunks.size(),
		"movement": movement_results,
	}
	_records.append(record)
	print("PLAYER_REGIONAL_TRAVERSAL_RESULT %s" % JSON.stringify(record))

	_release_all_actions()
	if hub != null:
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
	await _dispose_game(game)


func _discover_regions(generator: RefCounted, spawn: Vector3) -> Array[Vector3]:
	var regions: Array[Vector3] = []
	var seen_chunks: Dictionary = {}
	var spawn_x := floori(spawn.x)
	var spawn_z := floori(spawn.z)
	for anchor: Vector2i in REGION_ANCHORS:
		var region := _find_safe_region_near(
			generator,
			spawn_x + anchor.x,
			spawn_z + anchor.y
		)
		if not _is_finite_position(region):
			continue
		var chunk := Vector2i(floori(region.x / 16.0), floori(region.z / 16.0))
		var key := "%d,%d" % [chunk.x, chunk.y]
		if seen_chunks.has(key):
			continue
		seen_chunks[key] = true
		regions.append(region)
	return regions


func _find_safe_region_near(generator: RefCounted, anchor_x: int, anchor_z: int) -> Vector3:
	# The 48m bounded search tolerates void cells in sky islands while retaining a
	# deterministic and finite maximum of 625 candidate columns per anchor.
	for radius in range(0, 49, 4):
		for offset_x in range(-radius, radius + 1, 4):
			for offset_z in range(-radius, radius + 1, 4):
				if radius > 0 and absi(offset_x) != radius and absi(offset_z) != radius:
					continue
				var x := anchor_x + offset_x
				var z := anchor_z + offset_z
				var top := int(generator.call("find_walkable_surface", x, z))
				if top < 1:
					continue
				if _walkable_neighbour_count(generator, x, z, top) < 2:
					continue
				return Vector3(x + 0.5, top + 1.05, z + 0.5)
	return Vector3(INF, INF, INF)


func _walkable_neighbour_count(generator: RefCounted, x: int, z: int, top: int) -> int:
	var count := 0
	for offset: Vector2i in [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
	]:
		var neighbour_top := int(
			generator.call("find_walkable_surface", x + offset.x, z + offset.y)
		)
		if neighbour_top >= 1 and absi(neighbour_top - top) <= 1:
			count += 1
	return count


func _probe_local_movement(player: CharacterBody3D, start: Vector3) -> Dictionary:
	var max_displacement := 0.0
	var selected_action := ""
	var final_position := start
	for action: StringName in MOVEMENT_ACTIONS:
		_release_all_actions()
		player.global_position = start
		player.call("reset_motion")
		for _frame in 2:
			await physics_frame
		Input.action_press(action)
		for _frame in MOVE_FRAMES:
			await physics_frame
		Input.action_release(action)
		for _frame in 2:
			await physics_frame
		var current := player.global_position
		var displacement := Vector2(current.x - start.x, current.z - start.z).length()
		if displacement > max_displacement:
			max_displacement = displacement
			selected_action = str(action)
			final_position = current
		if (
			displacement >= MIN_LOCAL_DISPLACEMENT
			and current.y >= start.y - MAX_ACCEPTABLE_FALL
			and current.y > -12.0
		):
			return {
				"success": true,
				"action": str(action),
				"max_displacement": displacement,
				"final": [current.x, current.y, current.z],
			}
	_release_all_actions()
	return {
		"success": false,
		"action": selected_action,
		"max_displacement": max_displacement,
		"final": [final_position.x, final_position.y, final_position.z],
	}


func _release_all_actions() -> void:
	for action: StringName in MOVEMENT_ACTIONS:
		Input.action_release(action)
	Input.action_release(Actions.JUMP)
	Input.action_release(Actions.SPRINT)


func _dispose_game(game: Node) -> void:
	_release_all_actions()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in 40:
		await process_frame


func _is_finite_position(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _write_optional_report() -> void:
	var report_path := _user_argument("report")
	if report_path.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(report_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_check(false, "regional traversal report path is writable")
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"seed": TRAVERSAL_SEED,
		"records": _records,
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
