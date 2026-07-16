extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://mining-crack-feedback-desktop.png"
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
		"Mining-Crack-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 7719321
	)
	_check(not state.is_empty(), "desktop mining journey creates a temporary world")
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
	var overlay: Node3D = player.get_node_or_null("MiningCrackOverlay") as Node3D
	var held_view: Node3D = player.get_node_or_null("CameraPivot/Camera3D/HeldItemView") as Node3D
	_check(overlay != null, "production player mounts the mining crack overlay")
	_check(held_view != null, "mining cracks coexist with the first-person held item view")
	if overlay == null or held_view == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	var platform := _create_test_platform(floor_y, player_block.x, player_block.z)
	game.add_child(platform)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 5:
		await physics_frame
		await process_frame
	_check(player.is_on_floor(), "player is grounded before mining acceptance")

	hub.inventory.clear()
	hub.inventory.add_item("wooden_pickaxe", 1)
	hub.inventory.add_item("wooden_shovel", 1)
	hub.inventory.select_slot(0)
	await process_frame
	held_view.call("refresh_for_test")
	_check(str(held_view.call("get_snapshot").get("item_id", "")) == "wooden_pickaxe", "real hotbar selection displays the wooden pickaxe")

	var target := Vector3i(player_block.x, floor_y + 2, player_block.z - 3)
	world.call("force_load_chunk", world.call("block_to_chunk", target))
	world.call("set_block", target, "diamond_ore")
	for y in range(floor_y + 1, floor_y + 5):
		if y != target.y:
			world.call("set_block", Vector3i(target.x, y, target.z), "air")
	for _frame in 3:
		await physics_frame
		await process_frame
	await _aim_at(player, world.call("block_to_world", target))
	_check(_focus_hits_block(player, target), "center focus resolves the real ore target")
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	var active_snapshot: Dictionary = {}
	for _frame in 120:
		await physics_frame
		await process_frame
		active_snapshot = overlay.call("get_snapshot")
		if bool(active_snapshot.get("visible", false)) and float(active_snapshot.get("ratio", 0.0)) >= 0.05:
			break
	_check(bool(active_snapshot.get("visible", false)), "holding real left mouse shows mining cracks")
	_check(float(active_snapshot.get("ratio", 0.0)) > 0.0, "real harvest progress reaches the overlay")
	_check(int(active_snapshot.get("stage", -1)) >= 0, "real progress resolves a crack stage")
	_check(_vector3i_from(active_snapshot.get("block_position", [])) == target, "cracks remain centered on the authoritative target")
	_check(str(world.call("get_block", target)) == "diamond_ore", "mid-progress evidence does not fake block completion")
	_check(bool(held_view.call("get_snapshot").get("mining_active", false)), "held pickaxe animation and world cracks run together")
	await RenderingServer.frame_post_draw
	var active_image := root.get_texture().get_image()
	_check(active_image != null and not active_image.is_empty(), "desktop viewport renders active crack evidence")
	if active_image != null and not active_image.is_empty():
		_save_image(active_image, _capture_path)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await process_frame
	await physics_frame
	_check(not bool(overlay.call("get_snapshot").get("visible", true)), "releasing left mouse clears mining cracks")
	_check(not bool(held_view.call("get_snapshot").get("mining_active", true)), "releasing left mouse stops the held mining animation")

	_scroll_hotbar_down()
	await process_frame
	await process_frame
	held_view.call("refresh_for_test")
	_check(str(held_view.call("get_snapshot").get("item_id", "")) == "wooden_shovel", "real wheel input switches to the wooden shovel")
	world.call("set_block", target, "dirt")
	await _aim_at(player, world.call("block_to_world", target))
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	var completed := false
	for _frame in 120:
		await physics_frame
		await process_frame
		if str(world.call("get_block", target)) == "air":
			completed = true
			break
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await process_frame
	_check(completed, "holding real left mouse completes a fast shovel harvest")
	_check(not bool(overlay.call("get_snapshot").get("visible", true)), "completed harvest removes the crack overlay")
	_check(hub.inventory.count_item("dirt") >= 1, "completed harvest still grants the normal block drop")

	_scroll_hotbar_up()
	await process_frame
	world.call("set_block", target, "stone")
	await _aim_at(player, world.call("block_to_world", target))
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	var visible_before_ui := false
	for _frame in 60:
		await physics_frame
		await process_frame
		if bool(overlay.call("get_snapshot").get("visible", false)):
			visible_before_ui = true
			break
	_check(visible_before_ui, "fresh mining starts before UI interruption")
	await _tap_key(KEY_E)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_check(hub.game_ui.get_active_overlay() == GameUIScript.Overlay.INVENTORY, "E opens the real inventory during mining")
	_check(not bool(overlay.call("get_snapshot").get("visible", true)), "blocking inventory immediately hides mining cracks")
	_check(not bool(held_view.call("get_snapshot").get("visible", true)), "blocking inventory hides the held item too")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == GameUIScript.Overlay.NONE, "E closes the real inventory")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")
	_check(bool(held_view.call("get_snapshot").get("visible", false)), "closing inventory restores the selected held item")
	_check(not bool(overlay.call("get_snapshot").get("visible", true)), "stale cracks do not return after UI closes")
	_check(bool(hub.save_current()), "mining feedback coexists with the production save transaction")
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-4, 5):
		for z_offset in range(-6, 4):
			world.call("set_block", Vector3i(center_x + x_offset, floor_y, center_z + z_offset), "stone")
			for y in range(floor_y + 1, floor_y + 5):
				world.call("set_block", Vector3i(center_x + x_offset, y, center_z + z_offset), "air")


func _create_test_platform(floor_y: int, center_x: int, center_z: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "MiningAcceptancePlatform"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(center_x + 0.5, floor_y + 0.9, center_z - 1.5)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 0.2, 12.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 12):
		var candidate := player_block.y - offset - 1
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
	var value: Variant = player.call("get_interaction_focus")
	if value is not Dictionary:
		return false
	var focus: Dictionary = value
	return str(focus.get("type", "")) == "block" and _vector3i_from(focus.get("hit_position", [])) == expected


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


func _scroll_hotbar_up() -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_WHEEL_UP
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


func _save_image(image: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), "active mining crack screenshot is saved")


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
		print("QA MINING CRACK DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MINING CRACK DESKTOP FAILURE: %s" % failure)
		print("QA MINING CRACK DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
