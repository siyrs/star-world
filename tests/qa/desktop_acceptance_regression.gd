extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const SpawnResolverScript = preload("res://src/player/player_spawn_resolver.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://desktop-acceptance.png"

var checks := 0
var failures: Array[String] = []
var _created_world_id := ""
var _capture_path := ""


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
	var menu: Control = hub.main_menu
	_check(menu != null and menu.visible, "main menu is visible on desktop startup")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "startup does not trap the mouse")

	var start_button := _find_button(menu, "开始游戏")
	_check(start_button != null, "main menu exposes the start button")
	if start_button != null:
		await _click_control(start_button)
	var map_panel: Control = menu.get("_map_panel")
	_check(map_panel != null and map_panel.visible, "a real pointer click opens map selection")

	var world_name := map_panel.get("_world_name") as LineEdit
	var seed_input := map_panel.get("_seed") as LineEdit
	if world_name != null:
		world_name.text = "Desktop-Acceptance-%d" % Time.get_ticks_msec()
	if seed_input != null:
		seed_input.text = "24681357"
	var create_button := _find_button(map_panel, "创建并进入世界")
	_check(create_button != null, "map selection exposes the create button")
	if create_button != null:
		await _click_control(create_button)
	await process_frame
	await physics_frame
	await process_frame

	_created_world_id = str(hub.current_world_id)
	_check(game.world != null and bool(game.world.get("is_started")), "world starts through real UI input")
	_check(game.world_root.visible and game.player.visible, "world and player become visible")
	_check(hub.game_ui.visible and not hub.main_menu.visible, "gameplay UI replaces the loading menu")
	_check(int(game.world.call("get_loaded_chunk_count")) > 0, "spawn chunk is loaded")
	_check(_spawn_chunk_is_renderable(game.world), "spawn chunk has visible mesh and collision")
	_check(root.get_camera_3d() == game.player.get_view_camera(), "player camera is the active viewport camera")
	var resolver = SpawnResolverScript.new()
	_check(
		resolver.is_position_supported(game.world, game.player.global_position),
		"new player starts on supported terrain instead of high in empty sky",
	)

	var before_yaw := float(game.player.rotation.y)
	await _move_pointer(Vector2(36.0, -10.0))
	_check(
		not is_equal_approx(before_yaw, float(game.player.rotation.y)),
		"captured desktop mouse motion reaches the player through the HUD",
	)

	await _press_key(KEY_ESCAPE)
	_check(
		hub.game_ui.get_active_overlay() == GameUIScript.Overlay.PAUSE,
		"Escape opens the real pause overlay",
	)
	_check(paused, "pause overlay stops simulation")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "pause overlay releases the mouse")
	var resume_button := _find_button(hub.game_ui, "继续游戏")
	_check(resume_button != null, "pause overlay exposes the resume button")
	if resume_button != null:
		await _click_control(resume_button)
	_check(
		hub.game_ui.get_active_overlay() == GameUIScript.Overlay.NONE,
		"a real pointer click resumes gameplay",
	)
	_check(not paused, "resume clears simulation pause")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume recaptures the mouse")

	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport produces a rendered image")
	if image != null and not image.is_empty():
		_check(_image_has_visual_detail(image), "rendered frame is not a blank or flat-color screen")
		_save_image(image)

	_cleanup(game, hub)
	await process_frame
	await process_frame
	if failures.is_empty():
		print("DESKTOP_ACCEPTANCE_CAPTURE=%s" % _capture_path)
		print("QA DESKTOP ACCEPTANCE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA DESKTOP ACCEPTANCE FAILURE: %s" % failure)
		print("QA DESKTOP ACCEPTANCE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _click_control(control: Control) -> void:
	await process_frame
	var pointer_position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer_position
	motion.global_position = pointer_position
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = pointer_position
	press.global_position = pointer_position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = pointer_position
	release.global_position = pointer_position
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _move_pointer(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	var center := Vector2(root.size) * 0.5
	motion.position = center
	motion.global_position = center
	motion.relative = relative
	root.push_input(motion, true)
	await process_frame


func _press_key(keycode: Key) -> void:
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


func _spawn_chunk_is_renderable(world: Node) -> bool:
	var chunks = world.get("chunks")
	if chunks is not Dictionary or chunks.is_empty():
		return false
	var chunk = chunks.values()[0]
	if not is_instance_valid(chunk) or int(chunk.get("surface_face_count")) <= 0:
		return false
	var mesh_instance := chunk.get_node_or_null("Mesh") as MeshInstance3D
	var collision := chunk.get_node_or_null("Collision") as CollisionShape3D
	return (
		mesh_instance != null
		and mesh_instance.mesh != null
		and collision != null
		and collision.shape != null
	)


func _image_has_visual_detail(image: Image) -> bool:
	var unique: Dictionary = {}
	var step_x := maxi(1, floori(float(image.get_width()) / 40.0))
	var step_y := maxi(1, floori(float(image.get_height()) / 24.0))
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [
				int(color.r * 31.0), int(color.g * 31.0), int(color.b * 31.0)
			]
			unique[key] = true
			if unique.size() >= 12:
				return true
	return false


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"desktop acceptance screenshot is saved",
	)


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _cleanup(game: Node, hub: Node) -> void:
	if hub != null and hub.get("audio_service") != null:
		hub.audio_service.stop_ambient()
	if not _created_world_id.is_empty() and hub != null and hub.get("save_service") != null:
		hub.save_service.delete_world(_created_world_id)
	game.queue_free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
