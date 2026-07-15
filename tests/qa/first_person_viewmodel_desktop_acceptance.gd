extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://first-person-viewmodel-desktop-acceptance.png"
const CLEANUP_FRAMES := 6

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
		"Held-Item-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 93511742
	)
	_check(not state.is_empty(), "desktop viewmodel journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 5:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")), "real player owns gameplay input")
	_check(world != null and bool(world.get("is_started")), "real voxel world starts")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay starts with captured mouse")
	var view: Node3D = player.get_node_or_null("CameraPivot/Camera3D/HeldItemView") as Node3D
	_check(view != null, "production camera mounts the held item view")
	if view == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y: int = _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 4:
		await physics_frame
		await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("wooden_pickaxe", 1)
	hub.inventory.add_item("grass_block", 6)
	hub.inventory.add_item("iron_sword", 1)
	hub.inventory.select_slot(0)
	await process_frame
	view.call("refresh_for_test")
	var snapshot: Dictionary = view.call("get_snapshot")
	_check(str(snapshot.get("item_id", "")) == "wooden_pickaxe", "real hotbar selection displays the wooden pickaxe")
	_check(str(snapshot.get("model_kind", "")) == "tool", "pickaxe uses the procedural tool model")
	_check(bool(snapshot.get("visible", false)), "held pickaxe is visible in the production camera")
	_check(int(snapshot.get("part_count", 0)) >= 3, "held pickaxe has multiple low-poly parts")

	var target_block := Vector3i(player_block.x, floor_y + 2, player_block.z - 3)
	world.call("force_load_chunk", world.call("block_to_chunk", target_block))
	world.call("set_block", target_block, "stone")
	for y in range(floor_y + 1, floor_y + 5):
		if y != target_block.y:
			world.call("set_block", Vector3i(target_block.x, y, target_block.z), "air")
	for _frame in 3:
		await physics_frame
		await process_frame
	await _aim_at(player, world.call("block_to_world", target_block))
	var target_focus_value: Variant = player.call("get_interaction_focus")
	var target_focus: Dictionary = target_focus_value if target_focus_value is Dictionary else {}
	var target_ray := player.get_node("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	print(
		"QA VIEWMODEL TARGET | expected=%s | colliding=%s | point=%s | normal=%s | focus=%s"
		% [
			target_block,
			target_ray.is_colliding(),
			target_ray.get_collision_point() if target_ray.is_colliding() else Vector3.ZERO,
			target_ray.get_collision_normal() if target_ray.is_colliding() else Vector3.ZERO,
			target_focus,
		]
	)
	await RenderingServer.frame_post_draw
	_save_stage_image(root.get_texture().get_image(), "target")
	_check(_focus_hits_block(player, target_block), "authoritative center focus resolves the real stone target")
	var rest_position: Vector3 = view.position
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	for _frame in 2:
		await physics_frame
		await process_frame
	snapshot = view.call("get_snapshot")
	_check(bool(snapshot.get("mining_active", false)), "holding real left mouse enables continuous mining animation")
	_check(view.position.distance_to(rest_position) > 0.01, "mining visibly moves the held pickaxe")
	_check(str(world.call("get_block", target_block)) == "stone", "short mining sample does not fake completion")
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await process_frame
	_check(not bool(view.call("get_snapshot").get("mining_active", true)), "releasing real left mouse stops mining animation")

	_scroll_hotbar_down()
	await process_frame
	await process_frame
	view.call("refresh_for_test")
	snapshot = view.call("get_snapshot")
	_check(str(snapshot.get("item_id", "")) == "grass_block", "real mouse wheel switches to grass block")
	_check(str(snapshot.get("model_kind", "")) == "block", "grass block uses a textured cube viewmodel")
	_check(str(snapshot.get("block_id", "")) == "grass", "held block resolves the production block id")
	player.call("_update_interaction_focus", true)
	var preview: Dictionary = player.call("get_placement_preview_state")
	_check(bool(preview.get("valid", false)), "production placement policy exposes a valid target")
	var placement_position: Vector3i = _vector3i_from(preview.get("placement_position", []))
	var grass_before: int = int(hub.inventory.count_item("grass_block"))
	await _right_click_center()
	_check(str(world.call("get_block", placement_position)) == "grass", "real right click places the block at the previewed voxel")
	_check(int(hub.inventory.count_item("grass_block")) == grass_before - 1, "real placement consumes exactly one held block")
	var placement_snapshot: Dictionary = view.call("get_snapshot")
	_check(str(placement_snapshot.get("last_action", "")) == "place", "successful placement reaches the held-item use action")

	world.call("set_block", placement_position, "air")
	world.call("set_block", target_block, "air")
	await process_frame
	await physics_frame

	_scroll_hotbar_down()
	await process_frame
	await process_frame
	view.call("refresh_for_test")
	snapshot = view.call("get_snapshot")
	_check(str(snapshot.get("item_id", "")) == "iron_sword", "second real wheel step displays the iron sword")
	_check(str(snapshot.get("model_kind", "")) == "tool", "iron sword uses the tool model family")
	var cow_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 2.8)
	var cow_variant: Variant = hub.creature_spawner.call("spawn_creature", "cow", cow_position)
	_check(cow_variant is Node3D, "real creature spawner creates an attack target")
	if cow_variant is Node3D:
		var cow: Node3D = cow_variant
		cow.set("move_speed", 0.0)
		cow.set("_decision_timer", 999.0)
		await _aim_at(player, cow.global_position + Vector3(0.0, 0.65, 0.0))
		_check(_ray_hits_entity(player, cow), "center ray resolves the live cow")
		await _left_click_center()
		_check(str(view.call("get_snapshot").get("last_action", "")) == "attack", "real attack reaches the held-item swing action")
		cow.queue_free()
		await process_frame

	for _frame in 60:
		if float(view.call("get_snapshot").get("swing_remaining", 0.0)) <= 0.0:
			break
		await process_frame
	var camera: Camera3D = player.call("get_view_camera")
	camera.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	for _frame in 30:
		if player.is_on_floor():
			break
		await physics_frame
		await process_frame
	_check(player.is_on_floor(), "player is grounded before walk-bob acceptance")
	var player_start: Vector3 = player.global_position
	var view_start: Vector3 = view.position
	var max_player_distance := 0.0
	var max_view_distance := 0.0
	Input.action_press("move_forward")
	_check(Input.is_action_pressed("move_forward"), "move_forward action enters pressed state")
	for _frame in 18:
		await physics_frame
		await process_frame
		max_player_distance = maxf(
			max_player_distance,
			Vector2(player.global_position.x - player_start.x, player.global_position.z - player_start.z).length()
		)
		max_view_distance = maxf(max_view_distance, view.position.distance_to(view_start))
	Input.action_release("move_forward")
	await process_frame
	_check(max_player_distance > 0.05, "pressed move_forward action moves the player")
	_check(max_view_distance > 0.005, "real movement produces measurable first-person walk bob")

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders held item evidence")
	if image != null and not image.is_empty():
		_save_image(image)

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real character inventory")
	_check(not bool(view.call("get_snapshot").get("visible", true)), "blocking inventory overlay hides the held item")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the inventory")
	_check(bool(view.call("get_snapshot").get("visible", false)), "closing inventory restores the held item")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	_check(bool(player.get("input_enabled")), "closing inventory restores WASD input")
	_check(bool(hub.save_current()), "viewmodel coexists with the production save transaction")
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-4, 5):
		for z_offset in range(-7, 4):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 5):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 12):
		var candidate: int = player_block.y - offset - 1
		if str(world.call("get_block", Vector3i(player_block.x, candidate, player_block.z))) != "air":
			return candidate
	return maxi(1, player_block.y - 1)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	camera.look_at(target, Vector3.UP)
	for _frame in 2:
		await physics_frame
		await process_frame
	var ray := player.get_node("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_hits_block(player: Node, expected: Vector3i) -> bool:
	var focus_value: Variant = player.call("get_interaction_focus")
	if focus_value is not Dictionary:
		return false
	var focus: Dictionary = focus_value
	return str(focus.get("type", "")) == "block" and _vector3i_from(focus.get("hit_position", [])) == expected


func _ray_hits_entity(player: Node3D, expected: Node) -> bool:
	var ray := player.get_node("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	ray.force_raycast_update()
	return ray.is_colliding() and ray.get_collider() == expected


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


func _left_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await process_frame
	await process_frame


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _tap_key(keycode: Key) -> void:
	_key_event(keycode, true)
	await process_frame
	_key_event(keycode, false)
	await process_frame
	await process_frame


func _key_event(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	root.push_input(event)


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _save_stage_image(image: Image, suffix: String) -> void:
	if image == null or image.is_empty():
		return
	var path := "%s-%s.png" % [_capture_path.get_basename(), suffix]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error: Error = image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "first-person viewmodel screenshot is saved")


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
		print("QA FIRST PERSON VIEWMODEL DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA FIRST PERSON VIEWMODEL DESKTOP FAILURE: %s" % failure)
		print("QA FIRST PERSON VIEWMODEL DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
