extends SceneTree

const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://repair-desktop-acceptance.png"
const STATION_POSITION := Vector3i(0, 1, -3)
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


class DesktopRepairWorld:
	extends Node3D

	var blocks: Dictionary = {}
	var block_nodes: Dictionary = {}
	var default_spawn := Vector3(0.5, 0.05, 0.5)

	func build() -> void:
		_build_floor()
		set_test_block(STATION_POSITION, "repair_station")

	func bind_focus(_focus: Node3D) -> void:
		return

	func get_spawn_position() -> Vector3:
		return default_spawn

	func world_to_block(point: Vector3) -> Vector3i:
		return Vector3i(floori(point.x), floori(point.y), floori(point.z))

	func block_to_world(position: Vector3i) -> Vector3:
		return Vector3(position) + Vector3(0.5, 0.5, 0.5)

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(block_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var key := block_key(position)
		var previous := str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		_refresh_block_node(position, block_id)
		return true

	func remove_block(position: Vector3i) -> String:
		var previous := get_block(position)
		if previous == "air":
			return "air"
		set_block(position, "air")
		return previous

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[block_key(position)] = block_id
		_refresh_block_node(position, block_id)

	func serialize_state() -> Dictionary:
		return {"block_overrides": blocks.duplicate(true), "loaded_chunks": []}

	func _refresh_block_node(position: Vector3i, block_id: String) -> void:
		var key := block_key(position)
		var previous = block_nodes.get(key)
		if previous != null and is_instance_valid(previous):
			previous.queue_free()
		block_nodes.erase(key)
		if block_id == "air":
			return
		var body := StaticBody3D.new()
		body.name = "RepairBlock_%s" % key.replace(",", "_")
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(position) + Vector3(0.5, 0.5, 0.5)
		add_child(body)
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3.ONE
		var collision := CollisionShape3D.new()
		collision.shape = box_shape
		body.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = BlockRegistryScript.get_color(block_id)
		material.roughness = 0.82
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
		block_nodes[key] = body

	func _build_floor() -> void:
		var floor_body := StaticBody3D.new()
		floor_body.name = "RepairFloor"
		floor_body.collision_layer = 1
		floor_body.collision_mask = 0
		floor_body.position = Vector3(0.5, -0.1, -1.0)
		add_child(floor_body)
		var floor_shape := BoxShape3D.new()
		floor_shape.size = Vector3(8.0, 0.2, 8.0)
		var collision := CollisionShape3D.new()
		collision.shape = floor_shape
		floor_body.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = floor_shape.size
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#526F45")
		material.roughness = 0.95
		mesh_instance.material_override = material
		floor_body.add_child(mesh_instance)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("#172A42")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("#B9CED7")
	environment_resource.ambient_light_energy = 0.82
	environment.environment = environment_resource
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.05
	root.add_child(sun)
	var host := Node3D.new()
	root.add_child(host)
	var world = DesktopRepairWorld.new()
	var player = PlayerScene.instantiate()
	host.add_child(world)
	host.add_child(player)
	world.build()
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get("repair_service") != null, "service hub mounts repair service")
	_check(hub.get("repair_interaction") != null, "service hub mounts repair interaction adapter")
	_check(hub.game_ui.has_method("get_repair_panel"), "repair-enabled UI exposes its panel")
	player.call("bind_world", world)
	player.global_position = world.default_spawn
	player.rotation = Vector3.ZERO
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot != null:
		pivot.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.call("get_view_camera").current = true
	hub.attach_game(world, player, sun, environment)
	hub.activate_gameplay()
	if hub.get("creature_spawner") != null:
		hub.creature_spawner.set_active(false)
	await process_frame
	await physics_frame
	await process_frame
	_check(root.get_camera_3d() == player.call("get_view_camera"), "real player camera owns the repair viewport")
	_check(str(hub.input_context.get_context()) == "gameplay", "repair fixture begins in gameplay context")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse before repair")

	hub.inventory.clear()
	hub.inventory.add_item(
		"iron_pickaxe", 1, {"durability":50, "custom_name":"桌面验收铁镐"}
	)
	hub.inventory.add_item("iron_ingot", 2)
	hub.inventory.select_slot(0)
	await process_frame
	await _aim_at(player, Vector3(STATION_POSITION) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, STATION_POSITION), "real player ray resolves the repair station")
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
		await _finish(host, hub, environment, sun)
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
	await _finish(host, hub, environment, sun)


func _finish(host: Node, hub: Node, environment: Node, sun: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if hub.get("creature_spawner") != null:
			hub.creature_spawner.set_active(false)
			hub.creature_spawner.clear_creatures()
		if hub.get("audio_service") != null:
			if hub.audio_service.has_method("shutdown"):
				hub.audio_service.shutdown()
			else:
				hub.audio_service.stop_ambient()
		hub.queue_free()
	if host != null:
		host.queue_free()
	if environment != null:
		environment.queue_free()
	if sun != null:
		sun.queue_free()
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
