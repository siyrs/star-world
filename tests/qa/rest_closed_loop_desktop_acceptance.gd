extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://rest-closed-loop-desktop.png"
const CLEANUP_FRAMES := 10

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the rest service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Rest-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		42691573,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "rest journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production rest world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var rest: Node = hub.get("rest_service") as Node
	var survival: Node = hub.get("survival") as Node
	var day_night: Node = hub.get("day_night") as Node
	var game_ui: Node = hub.get("game_ui") as Node
	_check(
		player != null and world != null and inventory != null and rest != null
		and survival != null and day_night != null and game_ui != null,
		"production player, world, rest, survival and death UI are mounted",
	)
	if player == null or world == null or inventory == null or rest == null or survival == null or day_night == null or game_ui == null:
		await _finish(game, hub)
		return

	var spawn_changes: Array[Dictionary] = []
	var spawn_clears: Array[String] = []
	var sleeps: Array[Dictionary] = []
	var rejections: Array[Dictionary] = []
	rest.spawn_point_changed.connect(
		func(position: Vector3, bed_position: Vector3i) -> void:
			spawn_changes.append({"position":position, "bed_position":bed_position})
	)
	rest.spawn_point_cleared.connect(
		func(reason: String) -> void:
			spawn_clears.append(reason)
	)
	rest.slept.connect(
		func(previous_time: float, previous_day: int, wake_time: float, wake_day: int) -> void:
			sleeps.append({
				"previous_time":previous_time,
				"previous_day":previous_day,
				"wake_time":wake_time,
				"wake_day":wake_day,
			})
	)
	rest.rest_rejected.connect(
		func(reason: String, context: Dictionary) -> void:
			rejections.append({"reason":reason, "context":context.duplicate(true)})
	)

	var arena: Dictionary = _build_rest_arena(world, player, rest)
	var safe_bed: Vector3i = arena.get("safe_bed", Vector3i.ZERO)
	var obstructed_bed: Vector3i = arena.get("obstructed_bed", Vector3i.ZERO)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	_check(player.is_on_floor(), "production player settles on live collision before bed use")
	_check(str(world.call("get_block", safe_bed)) == "oak_bed", "arena contains one real safe bed")
	_check(str(world.call("get_block", obstructed_bed)) == "oak_bed", "arena contains one real obstructed bed")

	day_night.set("day_count", 3)
	day_night.call("set_time", 21.0)
	await _aim_at(player, world.call("block_to_world", safe_bed))
	_check(_focus_hits_block(player, safe_bed, "oak_bed"), "production center ray resolves the safe bed")
	await _right_click_center()
	_check(bool(rest.call("has_custom_spawn")), "real right click stores a custom bed spawn")
	_check(rest.call("get_bed_position") == safe_bed, "rest service retains the exact safe-bed identity")
	_check(spawn_changes.size() == 1 and sleeps.size() == 1, "night bed use emits one spawn change and one sleep event")
	_check(float(day_night.get("time_of_day")) >= 6.5 and float(day_night.get("time_of_day")) < 7.0, "sleep advances production time into the morning window")
	_check(int(day_night.get("day_count")) == 4, "sleep advances the production calendar exactly one day")
	var bed_spawn: Vector3 = rest.call("get_respawn_position")
	_check(player.call("get_respawn_position").is_equal_approx(bed_spawn), "player receives the service-owned bed spawn")

	var rest_before_obstruction: Dictionary = rest.call("serialize")
	var spawn_before_obstruction: Vector3 = player.call("get_respawn_position")
	var time_before_obstruction := float(day_night.get("time_of_day"))
	await _aim_at(player, world.call("block_to_world", obstructed_bed))
	_check(_focus_hits_block(player, obstructed_bed, "oak_bed"), "production center ray resolves the exposed obstructed bed")
	await _right_click_center()
	_check(not rejections.is_empty(), "obstructed bed emits a production rejection")
	if not rejections.is_empty():
		_check(str(rejections[-1].get("reason", "")) == "spawn_obstructed", "obstructed bed retains the exact spawn_obstructed reason")
	_check(rest.call("serialize") == rest_before_obstruction, "obstructed-bed failure cannot overwrite the existing custom spawn")
	_check(player.call("get_respawn_position").is_equal_approx(spawn_before_obstruction), "obstructed-bed failure cannot mutate the player spawn")
	_check(is_equal_approx(float(day_night.get("time_of_day")), time_before_obstruction), "obstructed-bed failure cannot skip time")
	_check(spawn_changes.size() == 1 and sleeps.size() == 1, "obstructed-bed failure cannot emit false success events")

	_check(bool(hub.call("save_current")), "safe bed and morning state join the authoritative save")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var saved_rest: Dictionary = loaded.get("rest", {})
	_check(bool(saved_rest.get("has_custom_spawn", false)), "world.json records the custom bed spawn")
	_check(_vector3i(saved_rest.get("bed_position", [])) == safe_bed, "world.json records the exact active bed")
	_check((loaded.get("world", {}).get("block_overrides", {}) as Dictionary).has(_block_key(safe_bed)), "world.json preserves the real safe-bed voxel")
	var spawn_change_count := spawn_changes.size()
	var sleep_count := sleeps.size()
	var clear_count := spawn_clears.size()

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	_check(not bool(rest.call("has_custom_spawn")), "return to menu clears the in-memory rest session")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "bed world completes a full production reload")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	inventory = hub.get("inventory") as Node
	rest = hub.get("rest_service") as Node
	survival = hub.get("survival") as Node
	game_ui = hub.get("game_ui") as Node
	_check(bool(rest.call("has_custom_spawn")), "first reload restores the custom bed spawn")
	_check(rest.call("get_bed_position") == safe_bed, "first reload restores the exact active bed identity")
	_check(str(world.call("get_block", safe_bed)) == "oak_bed", "first reload restores the active bed voxel")
	_check(player.call("get_respawn_position").is_equal_approx(bed_spawn), "first reload reapplies the exact bed spawn to the player")
	_check(spawn_changes.size() == spawn_change_count and sleeps.size() == sleep_count and spawn_clears.size() == clear_count, "first reload does not replay spawn, sleep or clear feedback")

	player.global_position = arena.get("death_position", player.global_position + Vector3(5.0, 4.0, 5.0))
	survival.call("take_damage", 999.0, "rest_closed_loop")
	for _frame in 8:
		await process_frame
	_check(not bool(survival.get("alive")), "production survival enters the death state")
	var respawn_button := _find_button(game_ui, "重生")
	_check(respawn_button != null and respawn_button.visible and not respawn_button.disabled, "death panel exposes the real respawn action")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "rest closed-loop viewport renders the real death panel")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "rest evidence uses 1024x576 resolution")
		_save_image(image)
	if respawn_button != null:
		await _click_control(respawn_button)
	for _frame in 8:
		await process_frame
	_check(bool(survival.get("alive")) and float(survival.get("health")) > 0.0, "real respawn button restores a living player")
	_check(player.global_position.distance_to(bed_spawn) < 0.2, "real death and respawn returns the player to the persisted bed")
	_check(bool(rest.call("has_custom_spawn")), "respawning at the bed preserves the custom spawn contract")

	inventory.clear()
	inventory.call("add_item", "diamond_axe", 1)
	inventory.select_slot(0)
	await _aim_at(player, world.call("block_to_world", safe_bed))
	_check(_focus_hits_block(player, safe_bed, "oak_bed"), "post-respawn player can focus the active bed for removal")
	await _press_primary()
	var break_frames := 0
	while str(world.call("get_block", safe_bed)) != "air" and break_frames < 300:
		break_frames += 1
		await process_frame
	await _release_primary()
	_check(str(world.call("get_block", safe_bed)) == "air", "real held primary action removes the active bed")
	_check(not bool(rest.call("has_custom_spawn")), "production block-removal callback clears the custom spawn")
	_check(not spawn_clears.is_empty() and spawn_clears[-1] == "bed_removed", "bed removal emits the exact bed_removed reason")
	var world_spawn: Vector3 = world.call("get_spawn_position")
	_check(player.call("get_respawn_position").is_equal_approx(world_spawn), "bed removal restores the authoritative world spawn")

	var final_clear_count := spawn_clears.size()
	var final_rest: Dictionary = rest.call("serialize")
	_check(bool(hub.call("save_current")), "bed-removed fallback state joins a second authoritative save")
	var final_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(not bool(final_loaded.get("rest", {}).get("has_custom_spawn", true)), "final world.json records no stale custom spawn")
	_check(not (final_loaded.get("world", {}).get("block_overrides", {}) as Dictionary).has(_block_key(safe_bed)) or str((final_loaded.get("world", {}).get("block_overrides", {}) as Dictionary).get(_block_key(safe_bed), "air")) == "air", "final world.json records the active bed as removed")

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", final_loaded)
	_check(await _wait_for_world_ready(game, hub), "bed-removed world completes the final production reload")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	rest = hub.get("rest_service") as Node
	survival = hub.get("survival") as Node
	game_ui = hub.get("game_ui") as Node
	_check(rest.call("serialize") == final_rest, "final reload restores the exact no-custom-spawn state")
	_check(str(world.call("get_block", safe_bed)) == "air", "final reload cannot resurrect the removed bed")
	world_spawn = world.call("get_spawn_position")
	_check(player.call("get_respawn_position").is_equal_approx(world_spawn), "final reload keeps the world-spawn fallback")
	_check(spawn_clears.size() == final_clear_count, "final reload does not replay the historical bed-removal warning")

	player.global_position = arena.get("death_position", player.global_position + Vector3(5.0, 4.0, 5.0))
	survival.call("take_damage", 999.0, "rest_fallback_closed_loop")
	for _frame in 8:
		await process_frame
	respawn_button = _find_button(game_ui, "重生")
	_check(respawn_button != null, "fallback death still exposes the real respawn action")
	if respawn_button != null:
		await _click_control(respawn_button)
	for _frame in 8:
		await process_frame
	_check(bool(survival.get("alive")), "fallback respawn restores a living player")
	_check(player.global_position.distance_to(world_spawn) < 0.2, "fallback respawn returns to the production world spawn")
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "final fallback respawn restores normal gameplay input")
	await _finish(game, hub)


func _build_rest_arena(world: Node, player: Node3D, rest: Node) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 58)
	for x_offset in range(-6, 9):
		for z_offset in range(-8, 5):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 6):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	var safe_bed := Vector3i(origin.x, floor_y + 1, origin.z - 3)
	var obstructed_bed := Vector3i(origin.x + 5, floor_y + 1, origin.z - 4)
	world.call("set_block", safe_bed, "oak_bed")
	world.call("set_block", obstructed_bed, "oak_bed")
	var policy: Variant = rest.get("policy")
	var offsets: Array = policy.call("get_spawn_offsets") if policy != null else []
	for raw_offset: Variant in offsets:
		var offset := _vector3i(raw_offset)
		if offset == Vector3i(0, 1, 0):
			world.call("set_block", obstructed_bed + offset, "stone")
			continue
		world.call("set_block", obstructed_bed + offset + Vector3i.DOWN, "air")
	return {
		"player_position": Vector3(origin.x + 0.5, floor_y + 1.25, origin.z + 0.5),
		"safe_bed": safe_bed,
		"obstructed_bed": obstructed_bed,
		"death_position": Vector3(origin.x - 4.5, floor_y + 4.0, origin.z + 2.5),
	}


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 240:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			world != null and player != null and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(player.get("input_enabled"))
		):
			return true
	return false


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera") as Camera3D
	if camera != null:
		var direction := (target - camera.global_position).normalized()
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		camera.look_at(target, up)
	for _frame in 2:
		await physics_frame
		await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_hits_block(player: Node, expected_position: Vector3i, expected_block_id: String) -> bool:
	var raw_focus: Variant = player.call("get_interaction_focus")
	if raw_focus is not Dictionary:
		return false
	var focus: Dictionary = raw_focus
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i(focus.get("hit_position", [])) == expected_position
		and str(focus.get("block_id", "")) == expected_block_id
	)


func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _block_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.global_position = center
		event.button_index = MOUSE_BUTTON_RIGHT
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _press_primary() -> void:
	var center := Vector2(root.size) * 0.5
	var event := InputEventMouseButton.new()
	event.position = center
	event.global_position = center
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame


func _release_primary() -> void:
	var center := Vector2(root.size) * 0.5
	var event := InputEventMouseButton.new()
	event.position = center
	event.global_position = center
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = 0
	event.pressed = false
	root.push_input(event)
	await process_frame


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _click_control(control: Control) -> void:
	if control == null:
		return
	for _frame in 2:
		await process_frame
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "rest desktop screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.get("save_service").delete_world(_world_id)
		if hub.get("audio_service") != null and hub.get("audio_service").has_method("shutdown"):
			hub.get("audio_service").shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA REST CLOSED LOOP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA REST CLOSED LOOP DESKTOP FAILURE: %s" % failure)
		print("QA REST CLOSED LOOP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
