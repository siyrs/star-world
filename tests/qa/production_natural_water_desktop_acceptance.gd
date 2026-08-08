extends SceneTree

# Commercial acceptance gap: natural water is located through the production
# PersistentCachedBatchedVoxelWorld mounted by GameScene. The real production
# player then receives keyboard input in that water, swims, exits vertically,
# saves while wet and is restored by a complete GameScene reload.

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const OUTPUT_PATH := "user://production-natural-water.png"
const JOURNEY_SEED := 112358
const WATER_PROFILES: Array[String] = ["star_continent", "frozen_wastes"]
const SCAN_RADIUS := 96
const READY_FRAMES := 360
const CLEANUP_FRAMES := 24

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _capture_saved := false
var _created_world_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)
	print("QA_USER_DATA_ROOT water=%s appdata=%s" % [ProjectSettings.globalize_path("user://"), OS.get_environment("APPDATA")])
	_check(_user_data_uses_inherited_appdata(), "water journey user data resolves under inherited APPDATA")
	var game := GameScene.instantiate()
	root.add_child(game)
	for _frame in 6:
		await process_frame
	var hub := game.get("service_hub") as Node
	_check(hub != null, "production GameScene mounts the water-journey service hub")
	if hub == null:
		await _finish(game, null, [])
		return
	var save := hub.get("save_service") as Node
	_check(save != null, "production water journey uses the authoritative save service")
	var pre_world_ids := _world_ids()

	for profile_id: String in WATER_PROFILES:
		await _exercise_profile(game, hub, save, profile_id)

	var post_world_ids := _world_ids()
	_check(pre_world_ids == post_world_ids, "water journey restores the complete pre-run world directory set")
	_check(_capture_saved, "water journey writes rendered production evidence")
	await _finish(game, hub, pre_world_ids)


func _exercise_profile(game: Node, hub: Node, save: Node, profile_id: String) -> void:
	var state: Dictionary = save.call(
		"create_world",
		"qa-production-water-%s-%d" % [profile_id, Time.get_ticks_msec()],
		profile_id,
		JOURNEY_SEED
	)
	_check(not state.is_empty(), "%s creates an isolated production world" % profile_id)
	if state.is_empty():
		return
	var world_id := str(state.get("metadata", {}).get("id", ""))
	if not world_id.is_empty():
		_created_world_ids.append(world_id)
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub, profile_id), "%s starts through the complete production lifecycle" % profile_id)
	var world := game.get("world") as Node
	var player := game.get("player") as CharacterBody3D
	_check(
		world != null
		and player != null
		and str(world.get_script().resource_path) == "res://src/world/persistent_cached_batched_voxel_world.gd",
		"%s uses the shipping persistent/cached/batched voxel composition" % profile_id
	)
	if world == null or player == null:
		await _return_and_delete(hub, save, world_id)
		return

	var route := _find_natural_water_route(world, profile_id)
	_check(not route.is_empty(), "%s production generator exposes a traversable natural water column" % profile_id)
	if route.is_empty():
		await _return_and_delete(hub, save, world_id)
		return
	var water_cell: Vector3i = route.get("water", Vector3i.ZERO)
	var neighbor_cell: Vector3i = route.get("neighbor", Vector3i.ZERO)
	var cap_cell: Vector3i = route.get("cap", Vector3i.ZERO)
	var direction_cell: Vector3i = route.get("direction", Vector3i.ZERO)
	var generated_cap := str(route.get("generated_cap", ""))
	_check(
		str(world.call("get_initial_block", water_cell)) == "water"
		and str(world.call("get_initial_block", water_cell + Vector3i.UP)) == "water",
		"%s route is a two-block-deep naturally generated water body" % profile_id
	)
	_check(
		str(world.call("get_initial_block", neighbor_cell)) == "water"
		and str(world.call("get_initial_block", neighbor_cell + Vector3i.UP)) == "water",
		"%s natural water has horizontal swim continuity" % profile_id
	)
	var overrides: Dictionary = world.get("block_overrides")
	_check(
		not overrides.has(str(world.call("block_key", water_cell)))
		and not overrides.has(str(world.call("block_key", water_cell + Vector3i.UP))),
		"%s tested water cells are generator-owned rather than test-authored overrides" % profile_id
	)
	_check(
		generated_cap == ("ice" if profile_id == "frozen_wastes" else "air"),
		"%s exposes its expected natural water-surface contract" % profile_id
	)

	_force_collision_neighborhood(world, water_cell, neighbor_cell)
	if profile_id == "frozen_wastes":
		var removed := str(world.call("remove_block", cap_cell))
		_check(removed == "ice", "frozen_wastes opens its natural water by breaking the generated ice cap")
		_check(str(world.call("get_block", cap_cell)) == "air", "frozen_wastes broken ice exposes the natural water column")

	# Put the real production CharacterBody at the supported bottom of the natural
	# water column, then let physics and the shipping fluid detector own contact.
	var wet_position := Vector3(water_cell) + Vector3(0.5, 0.05, 0.5)
	player.global_position = wet_position
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	world.call("set_focus", player)
	await physics_frame
	await process_frame
	_check(bool(player.call("_is_in_fluid")), "%s production player contacts naturally generated water" % profile_id)
	_check(
		str(world.call("get_block", world.call("world_to_block", player.global_position + Vector3.UP * 0.15))) == "water",
		"%s live production node resolves water at the player's feet" % profile_id
	)
	_check(
		hub.get("gameplay_input") != null and bool(hub.get("gameplay_input").call("is_active")),
		"%s production gameplay input is active before swimming" % profile_id
	)

	var swim_direction := Vector3(direction_cell.x, 0.0, direction_cell.z)
	player.look_at(player.global_position + swim_direction, Vector3.UP)
	var horizontal_start := player.global_position
	var swim_result := await _swim_forward(player, hub)
	_check(bool(swim_result.get("raw_input_seen", false)), "%s real W input reaches GameplayInputService" % profile_id)
	_check(
		float(swim_result.get("horizontal_distance", 0.0)) > 0.05,
		"%s real W input moves the production CharacterBody through natural water" % profile_id
	)
	_check(bool(swim_result.get("wet_during_motion", false)), "%s remains in natural water during horizontal swimming" % profile_id)
	_check(
		Vector2(player.global_position.x - horizontal_start.x, player.global_position.z - horizontal_start.z).length() > 0.05,
		"%s water traversal changes the authoritative player transform" % profile_id
	)

	# Return beneath the open surface and use the real Space key until the production
	# fluid detector clears. On frozen_wastes this exits through the ice block broken
	# above; on star_continent it exits the naturally open river surface.
	player.global_position = wet_position
	player.call("reset_motion")
	await physics_frame
	var exit_result := await _swim_up_until_exit(player, hub, wet_position.y)
	_check(bool(exit_result.get("raw_input_seen", false)), "%s real Space input reaches GameplayInputService" % profile_id)
	_check(float(exit_result.get("vertical_gain", 0.0)) > 0.25, "%s Space input produces upward swimming" % profile_id)
	_check(bool(exit_result.get("exited", false)), "%s real swim-up movement exits the natural water" % profile_id)

	# Save while wet, not after the exit. The disk payload must own profile, player,
	# survival and the broken frozen ice before a full menu teardown/reload.
	player.global_position = wet_position
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	_check(bool(player.call("_is_in_fluid")), "%s returns to natural water before the persistence checkpoint" % profile_id)
	var survival := hub.get("survival") as Node
	survival.set("health", 17.0 if profile_id == "star_continent" else 16.0)
	survival.set("hunger", 13.0 if profile_id == "star_continent" else 12.0)
	var survival_before: Dictionary = survival.call("serialize")
	_check(bool(hub.call("save_current")), "%s saves the wet production session" % profile_id)
	var saved: Dictionary = save.call("load_world", world_id)
	var saved_player := _array_to_vector3(saved.get("player", {}).get("position", []), Vector3(INF, INF, INF))
	_check(
		saved_player.distance_to(wet_position) < 0.4,
		"%s disk payload retains the in-water player position" % profile_id
	)
	_check(
		str(saved.get("metadata", {}).get("map_id", "")) == profile_id,
		"%s disk payload retains the water-bearing profile identity" % profile_id
	)
	if profile_id == "frozen_wastes":
		var saved_overrides: Dictionary = saved.get("world", {}).get("block_overrides", {})
		_check(
			str(saved_overrides.get(str(world.call("block_key", cap_cell)), "")) == "air",
			"frozen_wastes save persists the player-opened ice access above natural water"
		)

	hub.call("return_to_menu")
	_check(await _wait_for_menu(hub), "%s tears down the wet world to the production menu" % profile_id)
	var reloaded: Dictionary = save.call("load_world", world_id)
	game.call("begin_world_state", reloaded)
	_check(await _wait_for_world_ready(game, hub, profile_id), "%s completes a full production wet-session reload" % profile_id)
	world = game.get("world") as Node
	player = game.get("player") as CharacterBody3D
	_force_collision_neighborhood(world, water_cell, neighbor_cell)
	await physics_frame
	await process_frame
	_check(str(game.get("current_profile_id")) == profile_id and str(world.get("profile_id")) == profile_id, "%s full reload preserves profile/world identity" % profile_id)
	_check(bool(player.call("_is_in_fluid")), "%s full GameScene reload restores the player inside natural water" % profile_id)
	_check(player.global_position.distance_to(wet_position) < 0.5, "%s full reload restores the wet player transform" % profile_id)
	var survival_after: Dictionary = hub.get("survival").call("serialize")
	_check(
		is_equal_approx(float(survival_after.get("health", 0.0)), float(survival_before.get("health", -1.0)))
		and is_equal_approx(float(survival_after.get("hunger", 0.0)), float(survival_before.get("hunger", -1.0))),
		"%s full reload preserves survival state across the water checkpoint" % profile_id
	)
	_check(str(world.call("get_block", water_cell)) == "water", "%s natural water remains present after reload" % profile_id)
	if profile_id == "frozen_wastes":
		_check(str(world.call("get_block", cap_cell)) == "air", "frozen_wastes full reload preserves the opened ice access")
		await _save_capture()

	await _return_and_delete(hub, save, world_id)


func _find_natural_water_route(world: Node, profile_id: String) -> Dictionary:
	var expected_cap := "ice" if profile_id == "frozen_wastes" else "air"
	var directions: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]
	for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
		for z in range(-SCAN_RADIUS, SCAN_RADIUS + 1):
			for y in range(4, 20):
				var water := Vector3i(x, y, z)
				if not _is_supported_two_deep_water(world, water, expected_cap):
					continue
				for direction: Vector3i in directions:
					var neighbor := water + direction
					if _is_supported_two_deep_water(world, neighbor, expected_cap):
						return {
							"water": water,
							"neighbor": neighbor,
							"cap": water + Vector3i.UP * 2,
							"direction": direction,
							"generated_cap": expected_cap,
						}
	return {}


func _is_supported_two_deep_water(world: Node, water: Vector3i, expected_cap: String) -> bool:
	return (
		str(world.call("get_initial_block", water)) == "water"
		and str(world.call("get_initial_block", water + Vector3i.UP)) == "water"
		and str(world.call("get_initial_block", water + Vector3i.UP * 2)) == expected_cap
		and BlockRegistryScript.is_solid(str(world.call("get_initial_block", water + Vector3i.DOWN)))
	)


func _force_collision_neighborhood(world: Node, first: Vector3i, second: Vector3i) -> void:
	var centers: Array[Vector2i] = [
		world.call("block_to_chunk", first),
		world.call("block_to_chunk", second),
	]
	var loaded: Dictionary = {}
	for center: Vector2i in centers:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var coord := center + Vector2i(dx, dz)
				if loaded.has(coord):
					continue
				loaded[coord] = true
				world.call("force_load_chunk", coord)


func _swim_forward(player: CharacterBody3D, hub: Node) -> Dictionary:
	var start := player.global_position
	_push_key(KEY_W, true)
	await process_frame
	var input := hub.get("gameplay_input") as Node
	var raw_seen := input != null and (input.call("get_movement_vector") as Vector2).y < -0.5
	var wet_during_motion := bool(player.call("_is_in_fluid"))
	for _frame in 14:
		await physics_frame
		await process_frame
		wet_during_motion = wet_during_motion and bool(player.call("_is_in_fluid"))
	_push_key(KEY_W, false)
	await physics_frame
	await process_frame
	return {
		"raw_input_seen": raw_seen,
		"wet_during_motion": wet_during_motion,
		"horizontal_distance": Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length(),
	}


func _swim_up_until_exit(player: CharacterBody3D, hub: Node, start_y: float) -> Dictionary:
	_push_key(KEY_SPACE, true)
	await process_frame
	var input := hub.get("gameplay_input") as Node
	var raw_seen := input != null and bool(input.call("is_jump_pressed"))
	var maximum_y := player.global_position.y
	var exited := false
	for _frame in 90:
		await physics_frame
		await process_frame
		maximum_y = maxf(maximum_y, player.global_position.y)
		if not bool(player.call("_is_in_fluid")):
			exited = true
			break
	_push_key(KEY_SPACE, false)
	await physics_frame
	await process_frame
	return {
		"raw_input_seen": raw_seen,
		"vertical_gain": maximum_y - start_y,
		"exited": exited,
	}


func _push_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	root.push_input(event)


func _wait_for_world_ready(game: Node, hub: Node, profile_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		var player := game.get("player") as CharacterBody3D
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(game.get("current_profile_id")) == profile_id
			and not str(hub.get("current_world_id")).is_empty()
		):
			return true
	return false


func _wait_for_menu(hub: Node) -> bool:
	for _frame in CLEANUP_FRAMES:
		await process_frame
		if hub != null and str(hub.get("current_world_id")).is_empty():
			return true
	return false


func _return_and_delete(hub: Node, save: Node, world_id: String) -> void:
	if hub != null and not str(hub.get("current_world_id")).is_empty():
		hub.call("return_to_menu")
		await _wait_for_menu(hub)
	if save != null and not world_id.is_empty() and bool(save.call("world_exists", world_id)):
		_check(bool(save.call("delete_world", world_id)), "%s deletes its isolated water world" % world_id)


func _save_capture() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production natural-water viewport renders a frame")
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_capture_saved = error == OK and FileAccess.file_exists(_capture_path)
	_check(_capture_saved, "production natural-water screenshot is saved")


func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		var result := Vector3(float(value[0]), float(value[1]), float(value[2]))
		if is_finite(result.x) and is_finite(result.y) and is_finite(result.z):
			return result
	return fallback


func _world_ids() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open("user://worlds")
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and directory.current_is_dir():
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _user_data_uses_inherited_appdata() -> bool:
	var inherited := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/").to_lower()
	if inherited.is_empty():
		return true
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	return user_root.begins_with("%s/" % inherited)


func _finish(game: Node, hub: Node, expected_world_ids: Array[String]) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	_push_key(KEY_W, false)
	_push_key(KEY_SPACE, false)
	if hub != null and is_instance_valid(hub):
		var save := hub.get("save_service") as Node
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			await _wait_for_menu(hub)
		if save != null:
			for world_id: String in _created_world_ids:
				if bool(save.call("world_exists", world_id)):
					save.call("delete_world", world_id)
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_check(_world_ids() == expected_world_ids, "final water cleanup preserves the pre-run world set")
	if failures.is_empty():
		print("QA PRODUCTION NATURAL WATER PASS | checks=%d | profiles=2 | real_input=true | persistence=true | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PRODUCTION NATURAL WATER FAILURE: %s" % failure)
		print("QA PRODUCTION NATURAL WATER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
