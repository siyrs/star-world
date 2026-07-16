extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://non-cube-block-geometry-desktop.png"
const CLEANUP_FRAMES := 6
const TEST_FLOOR_Y := 48

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "production game exposes its service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Non-Cube-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 46271035
	)
	_check(not state.is_empty(), "desktop geometry journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 6:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")), "real player owns gameplay input")
	_check(world != null and bool(world.get("is_started")), "real voxel world starts")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay starts with captured mouse")

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var player_floor := Vector3i(player_block.x, TEST_FLOOR_Y, player_block.z + 1)
	var slab_floor := Vector3i(player_block.x - 1, TEST_FLOOR_Y, player_block.z - 3)
	var stair_floor := Vector3i(player_block.x + 1, TEST_FLOOR_Y, player_block.z - 3)
	_prepare_column(world, player_floor)
	_prepare_column(world, slab_floor)
	_prepare_column(world, stair_floor)
	print("QA NON CUBE PHASE | isolated platform y=%d" % TEST_FLOOR_Y)

	player.global_position = Vector3(player_floor) + Vector3(0.5, 1.05, 0.5)
	player.rotation = Vector3.ZERO
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 5:
		await physics_frame
		await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("stone_slab", 3)
	hub.inventory.add_item("oak_stairs", 3)
	hub.inventory.select_slot(0)
	await process_frame

	await _aim_at(player, Vector3(slab_floor) + Vector3(0.5, 0.96, 0.5))
	var slab_focus: Dictionary = player.call("get_interaction_focus")
	var slab_preview: Dictionary = player.call("get_placement_preview_state")
	print("QA NON CUBE SLAB FOCUS | focus=%s | preview=%s" % [slab_focus, slab_preview])
	_check(_focus_hits(slab_focus, slab_floor), "authoritative focus resolves the slab support block")
	_check(bool(slab_preview.get("valid", false)), "production policy offers a valid slab placement")
	_check((slab_preview.get("placement_boxes", []) as Array).size() == 1, "slab preview contains one geometry box")
	var slab_position := _vector3i_from(slab_preview.get("placement_position", []))
	var slab_before := int(hub.inventory.count_item("stone_slab"))
	await _right_click_center()
	_check(str(world.call("get_block", slab_position)) == "stone_slab", "real right click places a stone slab")
	_check(int(hub.inventory.count_item("stone_slab")) == slab_before - 1, "slab placement consumes exactly one item")

	_scroll_hotbar_down()
	await process_frame
	await process_frame
	await _aim_at(player, Vector3(stair_floor) + Vector3(0.5, 0.96, 0.5))
	var stair_focus: Dictionary = player.call("get_interaction_focus")
	var stair_preview: Dictionary = player.call("get_placement_preview_state")
	print("QA NON CUBE STAIR FOCUS | focus=%s | preview=%s" % [stair_focus, stair_preview])
	_check(_focus_hits(stair_focus, stair_floor), "authoritative focus resolves the stair support block")
	_check(bool(stair_preview.get("valid", false)), "production policy offers a valid stair placement")
	_check((stair_preview.get("placement_boxes", []) as Array).size() == 2, "stair preview contains lower and raised boxes")
	var preview_node: Node = player.call("get_interaction_preview")
	var second_outline := preview_node.get_node_or_null("PlacementOutline_1") as MeshInstance3D
	_check(second_outline != null and second_outline.visible, "real world preview renders the raised stair step")
	var stair_position := _vector3i_from(stair_preview.get("placement_position", []))
	var stair_before := int(hub.inventory.count_item("oak_stairs"))
	await _right_click_center()
	_check(str(world.call("get_block", stair_position)) == "oak_stairs", "real right click places oak stairs")
	_check(int(hub.inventory.count_item("oak_stairs")) == stair_before - 1, "stair placement consumes exactly one item")

	for _frame in 5:
		await physics_frame
		await process_frame
	var slab_hit := _raycast_down(game, Vector3(slab_position) + Vector3(0.5, 2.0, 0.5))
	_check(not slab_hit.is_empty(), "production physics ray hits the placed slab")
	if not slab_hit.is_empty():
		var slab_y := float((slab_hit.get("position", Vector3.ZERO) as Vector3).y)
		_check(absf(slab_y - (float(slab_position.y) + 0.5)) < 0.08, "slab collision surface is half a block high")
	var stair_front_hit := _raycast_down(game, Vector3(stair_position) + Vector3(0.5, 2.0, 0.18))
	var stair_back_hit := _raycast_down(game, Vector3(stair_position) + Vector3(0.5, 2.0, 0.82))
	_check(not stair_front_hit.is_empty() and not stair_back_hit.is_empty(), "production physics rays hit both ends of the stair ramp")
	if not stair_front_hit.is_empty() and not stair_back_hit.is_empty():
		var front_y := float((stair_front_hit.get("position", Vector3.ZERO) as Vector3).y)
		var back_y := float((stair_back_hit.get("position", Vector3.ZERO) as Vector3).y)
		_check(back_y > front_y + 0.20, "stair collision rises from front to rear")
		print("QA NON CUBE COLLISION | front_y=%.3f | back_y=%.3f" % [front_y, back_y])

	for z_offset in range(1, 3):
		var platform_position := stair_position + Vector3i(0, 0, z_offset)
		_prepare_column(world, platform_position)
		world.call("set_block", platform_position, "stone")
	for _frame in 5:
		await physics_frame
		await process_frame
	var local_start_z := 0.18
	var ramp_start_y := float(stair_position.y) + 0.5 + local_start_z * 0.5
	player.global_position = Vector3(
		stair_position.x + 0.5, ramp_start_y + 0.05, stair_position.z + local_start_z
	)
	player.rotation = Vector3(0.0, PI, 0.0)
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 4:
		await physics_frame
		await process_frame
	var start_position := player.global_position
	var maximum_y := player.global_position.y
	Input.action_press("move_forward")
	for _frame in 26:
		await physics_frame
		await process_frame
		maximum_y = maxf(maximum_y, player.global_position.y)
	Input.action_release("move_forward")
	await process_frame
	_check(player.global_position.z > start_position.z + 0.45, "production forward movement traverses the stair direction")
	_check(maximum_y > start_position.y + 0.20, "production character rises along the stair ramp")
	print("QA NON CUBE TRAVERSE | start=%s | end=%s | max_y=%.3f" % [start_position, player.global_position, maximum_y])

	player.global_position = Vector3(player_floor) + Vector3(0.5, 1.05, 0.5)
	player.rotation = Vector3.ZERO
	await _aim_at(player, Vector3(stair_position) + Vector3(0.5, 0.55, 0.5))
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders non-cube geometry evidence")
	if image != null and not image.is_empty():
		_save_image(image)

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real inventory")
	_check(not bool(preview_node.get_node("TargetOutline").visible), "blocking UI hides shape-aware target outlines")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the real inventory")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")
	_check(bool(hub.save_current()), "partial block geometry coexists with the production save transaction")
	await _finish(game, hub)


func _prepare_column(world: Node, floor_position: Vector3i) -> void:
	world.call("force_load_chunk", world.call("block_to_chunk", floor_position))
	world.call("set_block", floor_position, "stone")
	for y_offset in range(1, 5):
		world.call("set_block", floor_position + Vector3i.UP * y_offset, "air")


func _focus_hits(focus: Dictionary, expected: Vector3i) -> bool:
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i_from(focus.get("hit_position", [])) == expected
	)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	camera.look_at(target, Vector3.UP)
	for _frame in 3:
		await physics_frame
		await process_frame
	var ray := player.get_node("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _raycast_down(game: Node3D, from: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return game.get_world_3d().direct_space_state.intersect_ray(query)


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (1 << (int(button) - 1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event)


func _scroll_hotbar_down() -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	root.push_input(event)


func _tap_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "non-cube geometry screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.action_release("move_forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA NON CUBE BLOCK DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA NON CUBE BLOCK DESKTOP FAILURE: %s" % failure)
		print("QA NON CUBE BLOCK DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
