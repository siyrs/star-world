extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const InputActions = preload("res://src/input/gameplay_input_actions.gd")

const OUTPUT_PATH := "user://tutorial-placement-desktop-acceptance.png"
const CLEANUP_FRAMES := 6
const MAX_HARVEST_FRAMES := 420

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _created_world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "game exposes the production service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Tutorial-Placement-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		94217531
	)
	_check(not state.is_empty(), "desktop journey creates a new player world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real voxel world starts")
	_check(game.player != null and bool(game.player.get("input_enabled")), "real player receives gameplay input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse")
	var player: Node3D = game.player
	var world: Node = game.world
	var experience: Node = hub.player_experience
	var onboarding: Dictionary = experience.call("get_status").get("onboarding", {})
	_check(_step_id(onboarding) == "move", "new-world tutorial starts at movement")

	var hud: Node = hub.game_ui.get("hud")
	var crosshair: Control = hud.call("get_crosshair") if hud != null else null
	_check(crosshair != null, "HUD exposes the geometric crosshair")
	if crosshair != null:
		var aim_point: Vector2 = crosshair.call("get_aim_point")
		_check(
			aim_point.distance_to(root.get_visible_rect().get_center()) <= 0.01,
			"visible crosshair and camera ray share the exact viewport center",
		)

	Input.action_press(InputActions.MOVE_FORWARD)
	_check(Input.is_action_pressed(InputActions.MOVE_FORWARD), "real W gameplay action becomes active")
	for _frame in 20:
		await physics_frame
	Input.action_release(InputActions.MOVE_FORWARD)
	player.call("reset_motion")
	await process_frame
	_check(_current_step(experience) == "look", "real W input advances the tutorial")

	var look_event := InputEventMouseMotion.new()
	look_event.relative = Vector2(26.0, -9.0)
	root.push_input(look_event)
	await process_frame
	_check(_current_step(experience) == "mine", "real mouse look advances the tutorial")
	_check(
		str(_onboarding_state(experience).get("step", {}).get("description", "")).contains("按住"),
		"the live tutorial tells the player to hold the mining button",
	)

	var camera: Camera3D = player.call("get_view_camera")
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var target_y := floori(camera.global_position.y)
	var mining_target := Vector3i(player_block.x, target_y, player_block.z - 3)
	_prepare_target_corridor(world, player_block, mining_target)
	world.call("set_block", mining_target, "iron_ore")
	_check(str(world.call("get_block", mining_target)) == "iron_ore", "journey prepares a real mine target")
	hub.inventory.select_slot(2)
	await _aim_at(player, world.call("block_to_world", mining_target))
	_check(_focus_position(player) == mining_target, "center ray and visible focus identify the same mine target")
	await _hold_left_until_removed(world, mining_target)
	_check(str(world.call("get_block", mining_target)) == "air", "hold-to-harvest removes the focused voxel")
	_check(hub.inventory.count_item("raw_iron") == 0, "underpowered wooden pickaxe correctly grants no iron drop")
	_check(
		_current_step(experience) == "place",
		"successful no-drop harvesting still completes the tutorial mining step",
	)

	var anchor := mining_target
	world.call("set_block", anchor, "stone")
	var camera_cell: Vector3i = world.call("world_to_block", camera.global_position)
	var inside_target := camera_cell + Vector3i(0, 0, -1)
	var expected_placement := camera_cell + Vector3i(0, 0, -2)
	var incorrect_above := inside_target + Vector3i.UP
	world.call("set_block", camera_cell, "leaves")
	world.call("set_block", inside_target, "leaves")
	world.call("set_block", expected_placement, "air")
	world.call("set_block", incorrect_above, "air")
	hub.inventory.select_slot(0)
	camera.look_at(camera.global_position + Vector3(0.0, 0.0, -3.0), Vector3.UP)
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame
	var focus: Dictionary = player.call("get_interaction_focus")
	_check(
		_array_to_vector3i(focus.get("hit_position", [])) == inside_target,
		"placement focus survives when the camera starts inside a tree canopy",
	)
	_check(
		_array_to_vector3i(focus.get("placement_position", [])) == expected_placement,
		"inside-canopy focus resolves the first free exit voxel",
	)
	await _right_click_center()
	_check(
		str(world.call("get_block", expected_placement)) == "planks",
		"right click places a block even when the camera started inside foliage",
	)
	_check(
		str(world.call("get_block", incorrect_above)) == "air",
		"close-up placement never drifts one voxel upward",
	)
	_check(_current_step(experience) == "inventory", "real block placement advances the tutorial")

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real character inventory")
	_check(_current_step(experience) == "crafting", "opening inventory advances the tutorial")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes inventory and restores gameplay")
	await _tap_key(KEY_C)
	_check(hub.game_ui.get_active_overlay() == 2, "C opens real hand crafting")
	_check(
		bool(_onboarding_state(experience).get("completed", false)),
		"the entire real-input tutorial journey completes",
	)
	await _tap_key(KEY_C)
	_check(hub.game_ui.get_active_overlay() == 0, "C closes crafting after tutorial completion")
	_check(bool(player.get("input_enabled")), "closing the journey overlays restores player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing the journey overlays recaptures the mouse")

	_check(bool(hub.save_current()), "completed tutorial participates in the world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(
		bool(loaded.get("experience", {}).get("onboarding", {}).get("completed", false)),
		"completed tutorial survives a real save and reload",
	)
	await _aim_at(player, world.call("block_to_world", anchor))
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "tutorial placement viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	await _finish(game, hub)


func _prepare_target_corridor(world: Node, player_block: Vector3i, target: Vector3i) -> void:
	var start_z := mini(player_block.z - 1, target.z + 1)
	var end_z := maxi(player_block.z - 1, target.z + 1)
	for z in range(start_z, end_z + 1):
		for y in range(target.y - 1, target.y + 2):
			world.call("set_block", Vector3i(target.x, y, z), "air")
	world.call("set_block", target + Vector3i.DOWN, "stone")


func _hold_left_until_removed(world: Node, target: Vector3i) -> void:
	var center := root.get_visible_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	for _frame in MAX_HARVEST_FRAMES:
		await process_frame
		if str(world.call("get_block", target)) == "air":
			break
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _right_click_center() -> void:
	var center := root.get_visible_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_RIGHT
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_RIGHT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


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


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(target, Vector3.UP)
	await physics_frame
	await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_position(player: Node) -> Vector3i:
	var focus: Dictionary = player.call("get_interaction_focus")
	return _array_to_vector3i(focus.get("position", []))


func _array_to_vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _onboarding_state(experience: Node) -> Dictionary:
	return experience.call("get_status").get("onboarding", {})


func _current_step(experience: Node) -> String:
	return _step_id(_onboarding_state(experience))


func _step_id(onboarding: Dictionary) -> String:
	return str(onboarding.get("step", {}).get("id", ""))


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"tutorial placement desktop screenshot is saved",
	)


func _finish(game: Node, hub: Node) -> void:
	Input.action_release(InputActions.MOVE_FORWARD)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _created_world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_created_world_id)
		if hub.get("audio_service") != null:
			if hub.audio_service.has_method("shutdown"):
				hub.audio_service.shutdown()
			else:
				hub.audio_service.stop_ambient()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA TUTORIAL PLACEMENT DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA TUTORIAL PLACEMENT DESKTOP FAILURE: %s" % failure)
		print(
			"QA TUTORIAL PLACEMENT DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
