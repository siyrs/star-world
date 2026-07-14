extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://placement-preview-valid.png"
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _invalid_capture_path := ""
var _created_world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_invalid_capture_path = "%s-invalid.png" % _capture_path.get_basename()
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
		"Placement-Preview-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		46291357
	)
	_check(not state.is_empty(), "desktop acceptance creates a temporary player world")
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
	var preview: Node = player.call("get_interaction_preview")
	_check(preview != null, "production player mounts the world interaction preview")
	if preview == null:
		await _finish(game, hub)
		return

	hub.inventory.clear()
	hub.inventory.add_item("oak_planks", 3, {"batch":"desktop-preview"})
	hub.inventory.select_slot(0)
	await process_frame
	var camera: Camera3D = player.call("get_view_camera")
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var target_y := floori(camera.global_position.y)
	var anchor := Vector3i(player_block.x, target_y, player_block.z - 3)
	var expected_placement := anchor + Vector3i(0, 0, 1)
	var incorrect_above := anchor + Vector3i.UP
	_prepare_target_corridor(world, player_block, anchor)
	world.call("set_block", anchor, "stone")
	world.call("set_block", expected_placement, "air")
	world.call("set_block", incorrect_above, "air")
	await physics_frame
	await process_frame

	await _aim_at(player, world.call("block_to_world", anchor))
	var focus: Dictionary = player.call("get_interaction_focus")
	var preview_state: Dictionary = focus.get("placement_preview", {})
	_check(_array_to_vector3i(focus.get("hit_position", [])) == anchor, "center ray highlights the visible stone voxel")
	_check(_array_to_vector3i(preview_state.get("placement_position", [])) == expected_placement, "green ghost resolves the exact adjacent side cell")
	_check(bool(preview_state.get("valid", false)), "side-face placement preview is valid")
	_check(str(preview_state.get("reason", "")) == "ok", "valid ghost exposes a stable reason")
	var target_outline := preview.get_node_or_null("TargetOutline") as MeshInstance3D
	var placement_outline := preview.get_node_or_null("PlacementOutline") as MeshInstance3D
	var placement_fill := preview.get_node_or_null("PlacementFill") as MeshInstance3D
	_check(target_outline != null and target_outline.visible, "target outline renders in the real world")
	_check(placement_outline != null and placement_outline.visible, "placement outline renders in the real world")
	_check(placement_fill != null and placement_fill.visible, "placement ghost fill renders in the real world")
	var prompt: Dictionary = hub.player_experience.call("get_status").get("prompt", {})
	_check("绿色预览格" in str(prompt.get("subtitle", "")), "HUD explains the valid preview with text")
	_check("放置" in str(prompt.get("secondary", "")), "HUD keeps the right-click action for a valid preview")
	await _capture(_capture_path)

	await _right_click_center()
	_check(str(world.call("get_block", expected_placement)) == "planks", "real right click commits the green ghost cell")
	_check(str(world.call("get_block", incorrect_above)) == "air", "side placement never drifts one voxel upward")
	_check(hub.inventory.count_item("oak_planks") == 2, "successful placement consumes exactly one selected block")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "placement keeps gameplay mouse capture")
	_check(bool(player.get("input_enabled")), "placement keeps player movement input enabled")

	# Move the player close to a voxel boundary so the adjacent cell ahead only
	# partially overlaps the body. The target remains more than one metre from
	# the camera, avoiding near-face ambiguity while still exercising the real
	# red player-overlap preview through Camera3D and RayCast3D.
	var overlap_cell := Vector3i(player_block.x, target_y, player_block.z - 1)
	var overlap_anchor := overlap_cell + Vector3i(0, 0, -1)
	var adjusted_position := player.global_position
	adjusted_position.x = float(player_block.x) + 0.5
	adjusted_position.z = float(player_block.z) + 0.15
	player.global_position = adjusted_position
	player.call("reset_motion")
	world.call("set_block", overlap_anchor, "stone")
	world.call("set_block", overlap_cell, "air")
	await physics_frame
	await process_frame
	var body_bounds := AABB(
		player.global_position + Vector3(-0.32, 0.0, -0.32),
		Vector3(0.64, 1.82, 0.64)
	)
	_check(body_bounds.intersects(AABB(Vector3(overlap_cell), Vector3.ONE)), "test geometry really overlaps the player body")
	await _aim_at(player, world.call("block_to_world", overlap_anchor))
	focus = player.call("get_interaction_focus")
	preview_state = focus.get("placement_preview", {})
	_check(_array_to_vector3i(focus.get("hit_position", [])) == overlap_anchor, "real center ray resolves the stable overlap target")
	_check(_array_to_vector3i(preview_state.get("placement_position", [])) == overlap_cell, "overlap preview resolves the adjacent player cell")
	_check(bool(preview_state.get("placement_visible", false)), "player-overlap target still renders a placement ghost")
	_check(not bool(preview_state.get("valid", true)), "ghost turns invalid when the target cell overlaps the player")
	_check(str(preview_state.get("reason", "")) == "player_overlap", "invalid ghost explains player overlap")
	prompt = hub.player_experience.call("get_status").get("prompt", {})
	_check("不能放在角色身体内" in str(prompt.get("subtitle", "")), "invalid preview is explained with text, not red alone")
	await _capture(_invalid_capture_path)

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real inventory overlay")
	_check(target_outline != null and not target_outline.visible, "blocking UI hides the world target outline")
	_check(placement_fill != null and not placement_fill.visible, "blocking UI hides the placement ghost")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the real inventory overlay")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	_check(bool(hub.save_current()), "placement feedback coexists with the world save transaction")
	await _finish(game, hub)


func _prepare_target_corridor(world: Node, player_block: Vector3i, target: Vector3i) -> void:
	var start_z := mini(player_block.z - 1, target.z + 1)
	var end_z := maxi(player_block.z - 1, target.z + 1)
	for z in range(start_z, end_z + 1):
		for y in range(target.y - 1, target.y + 2):
			world.call("set_block", Vector3i(target.x, y, z), "air")
	world.call("set_block", target + Vector3i.DOWN, "stone")


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


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
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


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "placement preview viewport produces a rendered frame")
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_check(error == OK and FileAccess.file_exists(path), "placement preview screenshot is saved")


func _array_to_vector3i(value: Variant) -> Vector3i:
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _finish(game: Node, hub: Node) -> void:
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
			"QA PLACEMENT PREVIEW DESKTOP PASS | checks=%d | valid=%s | invalid=%s"
			% [checks, _capture_path, _invalid_capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PLACEMENT PREVIEW DESKTOP FAILURE: %s" % failure)
		print(
			"QA PLACEMENT PREVIEW DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
