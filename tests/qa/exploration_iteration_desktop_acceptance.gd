extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const VoxelWorldScript = preload("res://src/world/voxel_world.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://exploration-iteration-desktop.png"
const TEST_FLOOR_Y := 48
const CLEANUP_FRAMES := 7

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
		"Exploration-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		93621457
	)
	_check(not state.is_empty(), "desktop journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 8:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var inventory: Node = hub.inventory
	var prospecting: Node = hub.get("prospecting_service")
	_check(player != null and bool(player.get("input_enabled")), "production exploration player owns gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(prospecting != null, "production service hub exposes prospecting")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse")
	if player == null or world == null or prospecting == null:
		await _finish(game, hub)
		return

	inventory.clear()
	inventory.add_item("prospecting_kit", 1)
	inventory.add_item("glass_pane", 4)
	inventory.select_slot(0)
	await process_frame
	var camera: Camera3D = player.get_view_camera()
	camera.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
	await _right_click_center()
	var prospect_snapshot: Dictionary = prospecting.call("get_snapshot")
	_check(int(prospect_snapshot.get("record_count", 0)) == 1, "real right click creates one prospecting discovery")
	_check(int(inventory.count_item("prospecting_kit")) == 1, "prospecting kit is reusable and not consumed")
	var last_result: Dictionary = prospect_snapshot.get("last_result", {})
	_check(bool(last_result.get("success", false)), "real prospecting returns a successful production result")
	_check(not last_result.has("positions") and not last_result.has("ore_positions") and not last_result.has("coordinates"), "production prospecting does not expose ore coordinates")
	_check(str(last_result.get("message", "")).contains("粗粒度趋势"), "production result explains its coarse precision")
	var held_view: Node = player.get_node("CameraPivot/Camera3D/HeldItemView")
	var held_snapshot: Dictionary = held_view.call("get_snapshot")
	_check(str(held_snapshot.get("item_id", "")) == "prospecting_kit", "first-person view holds the real prospecting kit")
	_check(str(held_snapshot.get("last_action", "")) == "prospect", "real prospecting triggers the first-person use action")
	var feedback: Node = hub.player_experience.call("get_feedback")
	var toast: Dictionary = feedback.call("get_active_toast")
	_check(str(toast.get("text", "")).contains("粗粒度趋势"), "prospecting result reaches the production feedback UI")
	await _right_click_center()
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == 1, "immediate repeated input is blocked by cooldown")

	var base_block: Vector3i = world.call("world_to_block", player.global_position)
	var supports := {
		"glass_pane": Vector3i(base_block.x - 3, TEST_FLOOR_Y, base_block.z),
		"glass_pane_ns": Vector3i(base_block.x + 3, TEST_FLOOR_Y, base_block.z),
	}
	for support: Vector3i in supports.values():
		_prepare_column(world, support)
	inventory.select_slot(1)
	await process_frame
	await _place_pane(game, inventory, player, world, supports["glass_pane"], "glass_pane")
	await _place_pane(game, inventory, player, world, supports["glass_pane_ns"], "glass_pane_ns")
	_check(int(inventory.count_item("glass_pane")) == 2, "two real pane placements consume exactly two canonical pane items")
	_check(bool(hub.save_current()), "prospecting records and panes participate in the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(not loaded.is_empty(), "saved exploration world reloads")
	var exploration_records: Array = loaded.get("exploration", {}).get("records", [])
	_check(exploration_records.size() == 1, "prospecting discovery persists in the world save")
	var overrides: Dictionary = loaded.get("world", {}).get("block_overrides", {})
	for block_id: String in _placed:
		var position: Vector3i = _placed[block_id]
		var key := "%d,%d,%d" % [position.x, position.y, position.z]
		_check(str(overrides.get(key, "")) == block_id, "%s persists as its directional world variant" % block_id)
	var reloaded_world = VoxelWorldScript.new()
	root.add_child(reloaded_world)
	reloaded_world.start_world("star_continent", 93621457, "exploration-reload", loaded.get("world", {}))
	for block_id: String in _placed:
		var position: Vector3i = _placed[block_id]
		_check(str(reloaded_world.get_block(position)) == block_id, "%s survives a fresh VoxelWorld load" % block_id)
	var removed_id := str(reloaded_world.remove_block(_placed["glass_pane_ns"]))
	_check(removed_id == "glass_pane_ns", "breaking rotated pane returns its exact world variant")
	_check(BlockRegistryScript.get_item_id(removed_id) == "glass_pane", "rotated pane maps back to the canonical inventory item")
	reloaded_world.clear_world()
	reloaded_world.queue_free()
	await process_frame

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real inventory")
	var record_count_before := int(prospecting.call("get_snapshot").get("record_count", 0))
	await _right_click_center()
	_check(int(prospecting.call("get_snapshot").get("record_count", 0)) == record_count_before, "blocking UI prevents prospecting input")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the real inventory")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and bool(player.get("input_enabled")), "closing inventory restores mouse and player input")

	var gallery_center := Vector3(base_block.x, TEST_FLOOR_Y + 0.6, base_block.z)
	player.global_position = Vector3(base_block.x + 0.5, TEST_FLOOR_Y + 1.05, base_block.z + 7.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(gallery_center, Vector3.UP)
	for _frame in 4:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the pane gallery and exploration HUD")
	if image != null and not image.is_empty():
		_save_image(image)
	await _finish(game, hub)


func _place_pane(
	game: Node3D,
	inventory: Node,
	player: CharacterBody3D,
	world: Node,
	support: Vector3i,
	expected_block_id: String
) -> void:
	var forward := Vector3.BACK if expected_block_id == "glass_pane" else Vector3.RIGHT
	var player_floor := support - Vector3i(roundi(forward.x), 0, roundi(forward.z)) * 3
	_prepare_column(world, player_floor)
	player.global_position = Vector3(player_floor) + Vector3(0.5, 1.05, 0.5)
	player.rotation = Vector3(0.0, PI if expected_block_id == "glass_pane" else -PI * 0.5, 0.0)
	player.get_view_camera().rotation = Vector3.ZERO
	player.call("reset_motion")
	for _frame in 4:
		await physics_frame
		await process_frame
	await _aim_at(player, Vector3(support) + Vector3(0.5, 0.96, 0.5))
	var preview: Dictionary = player.call("get_placement_preview_state")
	_check(str(preview.get("selected_block_id", "")) == expected_block_id, "%s resolves from real player orientation" % expected_block_id)
	_check(bool(preview.get("valid", false)), "%s reaches a valid thin placement preview" % expected_block_id)
	var boxes: Array = preview.get("placement_boxes", [])
	_check(boxes.size() == 1, "%s preview renders one thin pane box" % expected_block_id)
	var pane_position := _vector3i_from(preview.get("placement_position", []))
	var before := int(inventory.count_item("glass_pane"))
	await _right_click_center()
	_check(str(world.call("get_block", pane_position)) == expected_block_id, "real right click places %s" % expected_block_id)
	_check(int(inventory.count_item("glass_pane")) == before - 1, "%s consumes one canonical pane item" % expected_block_id)
	_placed[expected_block_id] = pane_position
	for _frame in 5:
		await physics_frame
		await process_frame
	var hit := _raycast_through_pane(game, pane_position, expected_block_id)
	_check(not hit.is_empty(), "%s receives a real production physics ray" % expected_block_id)
	if not hit.is_empty():
		var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
		var local := hit_position - Vector3(pane_position)
		if expected_block_id == "glass_pane":
			_check(local.z >= 0.42 and local.z <= 0.58, "canonical pane collision stays centered and thin on Z")
		else:
			_check(local.x >= 0.42 and local.x <= 0.58, "rotated pane collision stays centered and thin on X")


func _raycast_through_pane(game: Node3D, position: Vector3i, block_id: String) -> Dictionary:
	var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
	var from := center + (Vector3.BACK * 1.5 if block_id == "glass_pane" else Vector3.LEFT * 1.5)
	var to := center + (Vector3.FORWARD * 1.5 if block_id == "glass_pane" else Vector3.RIGHT * 1.5)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return game.get_world_3d().direct_space_state.intersect_ray(query)


func _prepare_column(world: Node, floor_position: Vector3i) -> void:
	world.call("force_load_chunk", world.call("block_to_chunk", floor_position))
	world.call("set_block", floor_position, "stone")
	for y_offset in range(1, 5):
		world.call("set_block", floor_position + Vector3i.UP * y_offset, "air")


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
	_check(error == OK and FileAccess.file_exists(_capture_path), "exploration desktop screenshot is saved")


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
		print("QA EXPLORATION ITERATION DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA EXPLORATION ITERATION DESKTOP FAILURE: %s" % failure)
		print("QA EXPLORATION ITERATION DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
