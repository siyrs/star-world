extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://repair-desktop-acceptance.png"
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _created_world_id := ""
var _station_position := Vector3i.ZERO


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
	_check(hub != null, "game exposes the repair progression hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Repair-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 92834157
	)
	_check(not state.is_empty(), "repair acceptance creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real world starts before repair interaction")
	_check(hub.get("repair_service") != null, "repair service is mounted in the desktop runtime")
	_check(hub.get("repair_interaction") != null, "repair interaction adapter is mounted")
	_check(hub.game_ui.has_method("get_repair_panel"), "repair-enabled UI exposes its panel")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse before opening repair")

	hub.inventory.clear()
	hub.inventory.add_item(
		"iron_pickaxe", 1, {"durability":50, "custom_name":"桌面验收铁镐"}
	)
	hub.inventory.add_item("iron_ingot", 2)
	hub.inventory.select_slot(0)
	var player: Node3D = game.player
	var world: Node = game.world
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	_station_position = world.call(
		"world_to_block", player.global_position + Vector3(0.0, 1.1, -3.0)
	)
	world.call("set_block", _station_position, "air")
	_check(bool(world.call("set_block", _station_position, "repair_station")), "desktop fixture places a real repair station")
	await process_frame
	await physics_frame
	await process_frame
	_check(str(world.call("get_block", _station_position)) == "repair_station", "world publishes the repair station block")
	await _aim_at(player, Vector3(_station_position) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, _station_position), "real player ray resolves the repair station")
	_check(
		str(hub.block_interaction.get_interaction_hint_for_item("repair_station", "")).contains("修理台"),
		"world prompt explains the repair interaction",
	)
	await _right_click_center()
	_check(str(hub.input_context.get_context()) == "repair", "repair station enters the dedicated input context")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "repair overlay releases the desktop mouse")
	_check(not bool(player.get("input_enabled")), "repair overlay blocks player movement")
	var panel: Node = hub.game_ui.call("get_repair_panel")
	_check(panel != null and panel.visible, "repair panel is visible after real right click")
	if panel == null:
		await _finish(game, hub)
		return
	_check(_rect_is_inside_viewport(panel.get_global_rect()), "repair panel stays inside the 1024x576 viewport")
	var layout: Dictionary = panel.call("get_layout_rects")
	_check(Rect2(layout.get("list", Rect2())).size.y > 0.0, "repair list has a measurable layout")
	var repair_button: Button = panel.call("get_repair_button", "inventory:0")
	_check(repair_button != null, "repair panel exposes the damaged pickaxe action")
	_check(repair_button != null and not repair_button.disabled, "repair action is enabled when material is available")
	if repair_button != null:
		await _left_click_control(repair_button)
	var repaired: Dictionary = hub.inventory.get_slot(0)
	_check(int(repaired.get("metadata", {}).get("durability", 0)) == 113, "real pointer repair updates durability")
	_check(str(repaired.get("metadata", {}).get("custom_name", "")) == "桌面验收铁镐", "desktop repair preserves metadata")
	_check(hub.inventory.count_item("iron_ingot") == 1, "desktop repair consumes exactly one ingot")
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "repair desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	var close_button := _find_button(panel, "关闭 [Esc]")
	_check(close_button != null, "repair panel exposes a close button")
	if close_button != null:
		await _left_click_control(close_button)
	_check(str(hub.input_context.get_context()) == "gameplay", "closing repair restores gameplay context")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing repair recaptures the gameplay mouse")
	_check(bool(player.get("input_enabled")), "closing repair restores player input")
	await _finish(game, hub)


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if game != null and game.get("world") != null:
			var world: Node = game.get("world")
			if str(world.call("get_block", _station_position)) == "repair_station":
				world.call("set_block", _station_position, "air")
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
		print("QA REPAIR DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA REPAIR DESKTOP FAILURE: %s" % failure)
		print("QA REPAIR DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(target, Vector3.UP)
	await physics_frame
	await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()


func _ray_hits_block(player: Node3D, world: Node, expected: Vector3i) -> bool:
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray == null:
		return false
	ray.force_raycast_update()
	if not ray.is_colliding():
		return false
	var point := ray.get_collision_point()
	var normal := ray.get_collision_normal()
	var resolved: Vector3i = world.call("world_to_block", point - normal * 0.01)
	return resolved == expected


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


func _left_click_control(control: Control) -> void:
	await process_frame
	var pointer_position := _canvas_to_viewport(control.get_global_rect().get_center())
	var motion := InputEventMouseMotion.new()
	motion.position = pointer_position
	motion.global_position = pointer_position
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = pointer_position
	press.global_position = pointer_position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = pointer_position
	release.global_position = pointer_position
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func _rect_is_inside_viewport(rect: Rect2) -> bool:
	var transformed_start := _canvas_to_viewport(rect.position)
	var transformed_end := _canvas_to_viewport(rect.end)
	var transformed_rect := Rect2(transformed_start, transformed_end - transformed_start)
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	return (
		transformed_rect.position.x >= -0.5
		and transformed_rect.position.y >= -0.5
		and transformed_rect.end.x <= bounds.end.x + 0.5
		and transformed_rect.end.y <= bounds.end.y + 0.5
	)


func _canvas_to_viewport(position: Vector2) -> Vector2:
	return root.get_final_transform() * position


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"repair desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
