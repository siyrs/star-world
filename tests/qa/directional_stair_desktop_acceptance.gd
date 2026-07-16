extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const VoxelWorldScript = preload("res://src/world/voxel_world.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://directional-stair-desktop.png"
const CLEANUP_FRAMES := 6
const TEST_FLOOR_Y := 48

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""
var _placed: Dictionary = {}


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
		"Directional-Stair-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		73190462
	)
	_check(not state.is_empty(), "desktop journey creates a temporary world")
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

	var base_block: Vector3i = world.call("world_to_block", player.global_position)
	var support_positions := {
		"oak_stairs": Vector3i(base_block.x - 6, TEST_FLOOR_Y, base_block.z),
		"oak_stairs_east": Vector3i(base_block.x - 2, TEST_FLOOR_Y, base_block.z),
		"oak_stairs_north": Vector3i(base_block.x + 2, TEST_FLOOR_Y, base_block.z),
		"oak_stairs_west": Vector3i(base_block.x + 6, TEST_FLOOR_Y, base_block.z),
	}
	for support: Vector3i in support_positions.values():
		_prepare_column(world, support)

	hub.inventory.clear()
	hub.inventory.add_item("oak_stairs", 8)
	hub.inventory.select_slot(0)
	await process_frame

	for block_id: String in OrientationPolicyScript.STAIR_VARIANTS:
		var support: Vector3i = support_positions[block_id]
		await _place_from_direction(game, hub, player, world, support, block_id)

	_check(int(hub.inventory.count_item("oak_stairs")) == 4, "four real placements consume exactly four canonical stair items")
	_check(bool(hub.save_current()), "directional stairs participate in the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(not loaded.is_empty(), "saved world reloads from the atomic save service")
	var overrides: Dictionary = loaded.get("world", {}).get("block_overrides", {})
	for block_id: String in _placed:
		var position: Vector3i = _placed[block_id]
		var key := "%d,%d,%d" % [position.x, position.y, position.z]
		_check(str(overrides.get(key, "")) == block_id, "%s persists as its directional block id" % block_id)

	var reloaded_world = VoxelWorldScript.new()
	root.add_child(reloaded_world)
	reloaded_world.start_world(
		"star_continent",
		int(loaded.get("metadata", {}).get("seed", 73190462)),
		"directional-reload",
		loaded.get("world", {})
	)
	for block_id: String in _placed:
		var position: Vector3i = _placed[block_id]
		_check(str(reloaded_world.get_block(position)) == block_id, "%s survives a fresh production VoxelWorld load" % block_id)
	var removed_position: Vector3i = _placed["oak_stairs_west"]
	var removed_id := str(reloaded_world.remove_block(removed_position))
	_check(removed_id == "oak_stairs_west", "breaking a rotated stair returns its exact world variant")
	_check(BlockRegistryScript.get_item_id(removed_id) == "oak_stairs", "rotated stair variants drop the canonical inventory item")
	reloaded_world.clear_world()
	reloaded_world.queue_free()
	await process_frame

	var preview_node: Node = player.call("get_interaction_preview")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real inventory")
	_check(preview_node != null and not bool(preview_node.get_node("TargetOutline").visible), "blocking UI hides directional placement outlines")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the real inventory")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")

	var gallery_center := Vector3(base_block.x, TEST_FLOOR_Y + 0.7, base_block.z)
	player.global_position = Vector3(base_block.x + 0.5, TEST_FLOOR_Y + 1.05, base_block.z + 6.5)
	player.rotation = Vector3.ZERO
	player.get_view_camera().look_at(gallery_center, Vector3.UP)
	for _frame in 3:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the four-direction stair gallery")
	if image != null and not image.is_empty():
		_save_image(image)
	await _finish(game, hub)


func _place_from_direction(
	game: Node3D,
	hub: Node,
	player: CharacterBody3D,
	world: Node,
	support: Vector3i,
	expected_block_id: String
) -> void:
	var rise := OrientationPolicyScript.rise_direction(expected_block_id)
	var player_floor := support - rise * 3
	_prepare_column(world, player_floor)
	player.global_position = Vector3(player_floor) + Vector3(0.5, 1.05, 0.5)
	player.rotation = Vector3(0.0, _yaw_for(expected_block_id), 0.0)
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 4:
		await physics_frame
		await process_frame
	await _aim_at(player, Vector3(support) + Vector3(0.5, 0.96, 0.5))
	var focus: Dictionary = player.call("get_interaction_focus")
	var preview: Dictionary = player.call("get_placement_preview_state")
	_check(_focus_hits(focus, support), "%s uses the intended support surface" % expected_block_id)
	_check(str(player.call("get_resolved_placement_block_id")) == expected_block_id, "%s resolves from the production player yaw" % expected_block_id)
	_check(str(preview.get("selected_block_id", "")) == expected_block_id, "%s reaches the green preview contract" % expected_block_id)
	_check(bool(preview.get("valid", false)), "%s preview is valid" % expected_block_id)
	var boxes: Array = preview.get("placement_boxes", [])
	_check(boxes.size() == 2, "%s preview renders lower and raised halves" % expected_block_id)
	var stair_position := _vector3i_from(preview.get("placement_position", []))
	var before := int(hub.inventory.count_item("oak_stairs"))
	await _right_click_center()
	_check(str(world.call("get_block", stair_position)) == expected_block_id, "real right click places %s" % expected_block_id)
	_check(int(hub.inventory.count_item("oak_stairs")) == before - 1, "%s consumes one canonical item" % expected_block_id)
	_placed[expected_block_id] = stair_position
	for _frame in 5:
		await physics_frame
		await process_frame
	var sample_points := _ramp_samples(expected_block_id)
	var low_local: Vector3 = sample_points[0]
	var high_local: Vector3 = sample_points[1]
	var low_hit := _raycast_down(game, Vector3(stair_position) + low_local)
	var high_hit := _raycast_down(game, Vector3(stair_position) + high_local)
	_check(not low_hit.is_empty() and not high_hit.is_empty(), "%s ramp receives production physics rays on both ends" % expected_block_id)
	if not low_hit.is_empty() and not high_hit.is_empty():
		var low_y := float((low_hit.get("position", Vector3.ZERO) as Vector3).y)
		var high_y := float((high_hit.get("position", Vector3.ZERO) as Vector3).y)
		_check(high_y > low_y + 0.20, "%s collision rises in the persisted orientation" % expected_block_id)
		print("QA DIRECTIONAL STAIR COLLISION | id=%s low=%.3f high=%.3f" % [expected_block_id, low_y, high_y])


func _prepare_column(world: Node, floor_position: Vector3i) -> void:
	world.call("force_load_chunk", world.call("block_to_chunk", floor_position))
	world.call("set_block", floor_position, "stone")
	for y_offset in range(1, 5):
		world.call("set_block", floor_position + Vector3i.UP * y_offset, "air")


func _yaw_for(block_id: String) -> float:
	match OrientationPolicyScript.rotation_quarters(block_id):
		0:
			return PI
		1:
			return -PI * 0.5
		2:
			return 0.0
		3:
			return PI * 0.5
		_:
			return 0.0


func _ramp_samples(block_id: String) -> Array[Vector3]:
	match OrientationPolicyScript.rotation_quarters(block_id):
		1:
			return [Vector3(0.12, 2.0, 0.5), Vector3(0.88, 2.0, 0.5)]
		2:
			return [Vector3(0.5, 2.0, 0.88), Vector3(0.5, 2.0, 0.12)]
		3:
			return [Vector3(0.88, 2.0, 0.5), Vector3(0.12, 2.0, 0.5)]
		_:
			return [Vector3(0.5, 2.0, 0.12), Vector3(0.5, 2.0, 0.88)]


func _focus_hits(focus: Dictionary, expected: Vector3i) -> bool:
	return str(focus.get("type", "")) == "block" and _vector3i_from(focus.get("hit_position", [])) == expected


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
	_check(error == OK and FileAccess.file_exists(_capture_path), "directional stair screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
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
		print("QA DIRECTIONAL STAIR DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DIRECTIONAL STAIR DESKTOP FAILURE: %s" % failure)
		print("QA DIRECTIONAL STAIR DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
