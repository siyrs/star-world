extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://directional-ladder-desktop.png"
const TEST_FLOOR_Y := 48
const CLEANUP_FRAMES := 8
const READY_FRAMES := 180
const CLIMB_FRAMES := 60

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""
var _ladder_positions: Array[Vector3i] = []


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
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Directional-Ladder-%d" % Time.get_ticks_msec(),
		"star_continent",
		71930452
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop ladder journey creates a temporary world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded ready state",
	)
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")), "production player owns gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world is ready")
	_check(
		player != null and player.has_method("get_ladder_movement_snapshot"),
		"production player includes ladder climbing diagnostics",
	)
	if player == null or world == null:
		await _finish(game, hub)
		return

	var base_block: Vector3i = world.call("world_to_block", player.global_position)
	var wall_z := base_block.z - 4
	var wall_x := base_block.x
	_prepare_ladder_wall(world, wall_x, wall_z)
	player.global_position = Vector3(wall_x + 0.5, TEST_FLOOR_Y + 1.05, wall_z - 3.5)
	player.rotation = Vector3(0.0, PI, 0.0)
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 5:
		await physics_frame
		await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("ladder", 6, {"batch":"directional-ladder-desktop"})
	var ladder_slot := _find_inventory_slot(hub.inventory, "ladder")
	_check(ladder_slot >= 0, "desktop journey resolves the ladder inventory slot")
	hub.inventory.select_slot(ladder_slot)
	await process_frame

	for y in range(TEST_FLOOR_Y + 1, TEST_FLOOR_Y + 5):
		var support := Vector3i(wall_x, y, wall_z)
		await _aim_at(player, world.call("block_to_world", support) + Vector3(0.0, 0.0, -0.02))
		var focus: Dictionary = player.call("get_interaction_focus")
		var preview: Dictionary = player.call("get_placement_preview_state")
		var expected_position := support + Vector3i.FORWARD
		_check(_focus_hits(focus, support), "real center ray targets wall support y=%d" % y)
		_check(
			str(preview.get("selected_block_id", "")) == "ladder",
			"north wall face resolves the canonical south-supported ladder",
		)
		_check(bool(preview.get("valid", false)), "wall-mounted ladder preview is green")
		_check(
			_vector3i_from(preview.get("placement_position", [])) == expected_position,
			"ladder preview occupies the cell immediately in front of the wall",
		)
		var boxes: Array = preview.get("placement_boxes", [])
		_check(boxes.size() == 1, "ladder preview renders one thin wall panel")
		if boxes.size() == 1 and boxes[0] is Dictionary:
			var box: Dictionary = boxes[0]
			var size := _vector3_from(box.get("size", []))
			_check(
				is_equal_approx(size.z, LadderPolicyScript.THICKNESS),
				"preview thickness matches final ladder geometry",
			)
		var before := int(hub.inventory.count_item("ladder"))
		await _right_click_center()
		_check(
			str(world.call("get_block", expected_position)) == "ladder",
			"real right click commits the directional ladder at y=%d" % y,
		)
		_check(
			int(hub.inventory.count_item("ladder")) == before - 1,
			"real placement consumes exactly one canonical ladder item",
		)
		_ladder_positions.append(expected_position)

	var gallery_support := Vector3i(wall_x, TEST_FLOOR_Y + 5, wall_z)
	await _aim_at(
		player,
		world.call("block_to_world", gallery_support) + Vector3(0.0, 0.0, -0.02)
	)
	var gallery_preview: Dictionary = player.call("get_placement_preview_state")
	_check(bool(gallery_preview.get("valid", false)), "gallery keeps a fifth green ladder preview")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the directional ladder wall")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "ladder evidence uses 1024x576 product resolution")
		_save_image(image)

	var climb_start := Vector3(wall_x + 0.5, TEST_FLOOR_Y + 1.05, wall_z - 0.5)
	player.global_position = climb_start
	player.rotation = Vector3(0.0, PI, 0.0)
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 4:
		await physics_frame
		await process_frame
	var start_y := player.global_position.y
	_set_key(KEY_W, true)
	var climbed := false
	for _frame in CLIMB_FRAMES:
		await physics_frame
		if player.global_position.y >= start_y + 0.65:
			climbed = true
			break
	var active_snapshot: Dictionary = player.call("get_ladder_movement_snapshot")
	_check(climbed, "holding real W climbs the production ladder")
	_check(
		bool(active_snapshot.get("active", false))
		and bool(active_snapshot.get("climbing", false)),
		"runtime diagnostics report an active climbing state",
	)
	_check(
		int(active_snapshot.get("contact_scan_count", 0)) <= LadderPolicyScript.MAX_CONTACT_CELLS,
		"production ladder contact respects the eighteen-cell scan budget",
	)
	_check(
		str(active_snapshot.get("support_direction", "")) == "south",
		"runtime diagnostics retain the backing-wall direction",
	)
	_set_key(KEY_W, false)
	var hold_y := player.global_position.y
	for _frame in 8:
		await physics_frame
	_check(
		absf(player.global_position.y - hold_y) < 0.12,
		"releasing W holds position instead of restoring gravity",
	)
	var hold_snapshot: Dictionary = player.call("get_ladder_movement_snapshot")
	_check(
		bool(hold_snapshot.get("active", false))
		and not bool(hold_snapshot.get("climbing", true)),
		"idle contact remains attached without reporting active movement",
	)

	_set_key(KEY_S, true)
	var descent_start := player.global_position.y
	var descended := false
	for _frame in 36:
		await physics_frame
		if player.global_position.y <= descent_start - 0.35:
			descended = true
			break
	_set_key(KEY_S, false)
	_check(descended, "holding real S descends the production ladder")

	var detach_start := player.global_position
	await _tap_key(KEY_SPACE)
	for _frame in 4:
		await physics_frame
	var detached_snapshot: Dictionary = player.call("get_ladder_movement_snapshot")
	_check(
		not bool(detached_snapshot.get("active", true))
		and str(detached_snapshot.get("last_exit_reason", "")) == "jump_detach",
		"jump exits the ladder through the explicit detach boundary",
	)
	_check(
		player.global_position.z < detach_start.z - 0.02
		or player.velocity.z < -0.2,
		"jump pushes the player outward from the backing wall",
	)

	_check(bool(hub.save_current()), "directional ladders join the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("ladder_runtime")
		and not serialized.contains("ladder_contact")
		and not loaded.has("ladders"),
		"transient climb state never creates a parallel save domain",
	)
	var ladders_before_reload := int(hub.inventory.count_item("ladder"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	game.begin_world_state(loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full ladder reload reaches a bounded ready state",
	)
	world = game.world
	player = game.player
	for ladder_position: Vector3i in _ladder_positions:
		_check(
			str(world.call("get_block", ladder_position)) == "ladder",
			"full reload restores ladder at %s exactly once" % str(ladder_position),
		)
	_check(
		int(hub.inventory.count_item("ladder")) == ladders_before_reload,
		"full reload does not duplicate canonical ladder items",
	)
	var reloaded_snapshot: Dictionary = player.call("get_ladder_movement_snapshot")
	_check(
		not bool(reloaded_snapshot.get("active", true))
		and int(reloaded_snapshot.get("enter_count", -1)) == 0,
		"new world binding clears transient ladder contact and counters",
	)
	await _finish(game, hub)


func _prepare_ladder_wall(world: Node, wall_x: int, wall_z: int) -> void:
	for x in range(wall_x - 2, wall_x + 3):
		for z in range(wall_z - 5, wall_z + 2):
			var floor_position := Vector3i(x, TEST_FLOOR_Y, z)
			world.call("force_load_chunk", world.call("block_to_chunk", floor_position))
			world.call("set_block", floor_position, "stone")
			for y in range(TEST_FLOOR_Y + 1, TEST_FLOOR_Y + 7):
				world.call("set_block", Vector3i(x, y, z), "air")
	for y in range(TEST_FLOOR_Y + 1, TEST_FLOOR_Y + 6):
		world.call("set_block", Vector3i(wall_x, y, wall_z), "stone")
	await physics_frame
	await process_frame


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


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


func _set_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	root.push_input(event)


func _tap_key(keycode: Key) -> void:
	_set_key(keycode, true)
	await process_frame
	_set_key(keycode, false)
	await process_frame


func _focus_hits(focus: Dictionary, expected: Vector3i) -> bool:
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i_from(focus.get("hit_position", [])) == expected
	)


func _find_inventory_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "directional ladder screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	_set_key(KEY_W, false)
	_set_key(KEY_S, false)
	_set_key(KEY_SPACE, false)
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
		print(
			"QA DIRECTIONAL LADDER DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DIRECTIONAL LADDER DESKTOP FAILURE: %s" % failure)
		print(
			"QA DIRECTIONAL LADDER DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
