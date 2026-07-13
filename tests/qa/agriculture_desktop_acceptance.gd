extends SceneTree

const PlayerScene = preload("res://scenes/game/player.tscn")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const AgricultureScript = preload("res://src/agriculture/agriculture_service.gd")
const InteractionScript = preload("res://src/interaction/block_interaction_service.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://agriculture-desktop-acceptance.png"
const SOIL_POSITION := Vector3i(0, 1, -3)
const CROP_POSITION := Vector3i(0, 2, -3)
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


class DesktopFarmWorld:
	extends Node3D
	var blocks: Dictionary = {}
	var block_nodes: Dictionary = {}

	func build() -> void:
		_build_floor()
		set_test_block(SOIL_POSITION, "grass")

	func bind_focus(_focus: Node3D) -> void:
		return

	func get_spawn_position() -> Vector3:
		return Vector3(0.5, 0.05, 0.5)

	func world_to_block(point: Vector3) -> Vector3i:
		return Vector3i(floori(point.x), floori(point.y), floori(point.z))

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

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func _refresh_block_node(position: Vector3i, block_id: String) -> void:
		var key := block_key(position)
		var previous = block_nodes.get(key)
		if previous != null and is_instance_valid(previous):
			previous.queue_free()
		block_nodes.erase(key)
		if block_id == "air":
			return
		var body := StaticBody3D.new()
		body.name = "FarmBlock_%s" % key.replace(",", "_")
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(position) + Vector3(0.5, 0.5, 0.5)
		add_child(body)
		var definition := BlockRegistryScript.get_definition(block_id)
		var shape_name := str(definition.get("shape", "cube"))
		var height := (
			clampf(float(definition.get("crop_height", 1.0)), 0.2, 1.0)
			if shape_name == "crop"
			else 1.0
		)
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.82, height, 0.82) if shape_name == "crop" else Vector3.ONE
		var collision := CollisionShape3D.new()
		collision.position.y = (height - 1.0) * 0.5
		collision.shape = box_shape
		body.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box_shape.size
		mesh_instance.position = collision.position
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = BlockRegistryScript.get_color(block_id)
		material.roughness = 0.9
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
		block_nodes[key] = body

	func _build_floor() -> void:
		var floor_body := StaticBody3D.new()
		floor_body.name = "Floor"
		floor_body.collision_layer = 1
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
		material.albedo_color = Color("#4D7442")
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
	environment_resource.background_color = Color("#76A7D2")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color.WHITE
	environment_resource.ambient_light_energy = 0.85
	environment.environment = environment_resource
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var host := Node3D.new()
	root.add_child(host)
	var world = DesktopFarmWorld.new()
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	var interactions = InteractionScript.new()
	var player = PlayerScene.instantiate()
	for node in [world, inventory, tools, agriculture, interactions, player]:
		host.add_child(node)
	world.build()
	await process_frame
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	agriculture.attach_world(world, inventory)
	interactions.setup(null, null, inventory, null)
	interactions.register_extension(agriculture)
	inventory.clear()
	inventory.add_item("wooden_hoe", 1)
	inventory.add_item("wheat_seeds", 3)
	inventory.select_slot(0)
	player.bind_world(world)
	player.setup_gameplay_services(
		{
			"inventory": inventory,
			"interaction": interactions,
			"tools": tools,
		}
	)
	player.global_position = Vector3(0.5, 0.05, 0.5)
	player.reset_motion()
	player.get_view_camera().current = true
	player.set_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await physics_frame
	_check(root.get_camera_3d() == player.get_view_camera(), "the player camera owns the agriculture desktop viewport")
	_check(
		str(interactions.get_interaction_hint_for_item("grass", "wooden_hoe")).contains("开垦"),
		"the real interaction layer explains hoe usage",
	)
	await _aim_at(player, Vector3(SOIL_POSITION) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, SOIL_POSITION), "the real player ray resolves the soil target")
	await _right_click()
	_check(world.get_block(SOIL_POSITION) == "farmland", "a real right click tills the soil")
	_check(
		int(inventory.get_slot(0).get("metadata", {}).get("durability", 60)) == 59,
		"desktop tilling consumes visible hoe durability",
	)
	inventory.select_slot(1)
	await process_frame
	await _aim_at(player, Vector3(SOIL_POSITION) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, SOIL_POSITION), "the real player ray resolves tilled farmland")
	await _right_click()
	_check(world.get_block(CROP_POSITION) == "wheat_stage_0", "a second real right click plants wheat seeds")
	_check(inventory.count_item("wheat_seeds") == 2, "desktop planting consumes one seed")
	agriculture.advance_time(106.0)
	await process_frame
	_check(world.get_block(CROP_POSITION) == "wheat_stage_3", "desktop crop reaches its mature visual stage")
	_check(
		str(interactions.get_interaction_hint_for_item("wheat_stage_3", "")).contains("收获"),
		"mature crops expose a clear harvest prompt",
	)
	await _aim_at(player, Vector3(CROP_POSITION) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, CROP_POSITION), "the real player ray resolves mature wheat")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "agriculture desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	await _right_click()
	_check(world.get_block(CROP_POSITION) == "wheat_stage_0", "real pointer harvest automatically replants wheat")
	_check(inventory.count_item("wheat") == 1, "real pointer harvest grants wheat")
	_check(inventory.count_item("wheat_seeds") == 4, "real pointer harvest returns seeds")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "agriculture interactions never release the gameplay mouse")
	player.set_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	agriculture.clear()
	host.queue_free()
	environment.queue_free()
	sun.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA AGRICULTURE DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure in failures:
			push_error("QA AGRICULTURE DESKTOP FAILURE: %s" % failure)
		print(
			"QA AGRICULTURE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
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


func _right_click() -> void:
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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"agriculture desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
