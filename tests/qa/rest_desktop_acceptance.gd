extends SceneTree

const PlayerScene = preload("res://scenes/game/player.tscn")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const RestScript = preload("res://src/rest/rest_service.gd")
const InteractionScript = preload("res://src/interaction/block_interaction_service.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://rest-desktop-acceptance.png"
const BED_POSITION := Vector3i(0, 1, -3)
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


class DesktopRestWorld:
	extends Node3D
	var blocks: Dictionary = {}
	var block_nodes: Dictionary = {}
	var default_spawn := Vector3(0.5, 0.05, 0.5)

	func build() -> void:
		_build_floor()
		set_test_block(BED_POSITION, "oak_bed")

	func bind_focus(_focus: Node3D) -> void:
		return

	func get_spawn_position() -> Vector3:
		return default_spawn

	func world_to_block(point: Vector3) -> Vector3i:
		return Vector3i(floori(point.x), floori(point.y), floori(point.z))

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var key := _key(position)
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
		blocks[_key(position)] = block_id
		_refresh_block_node(position, block_id)

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func _refresh_block_node(position: Vector3i, block_id: String) -> void:
		var key := _key(position)
		var previous = block_nodes.get(key)
		if previous != null and is_instance_valid(previous):
			previous.queue_free()
		block_nodes.erase(key)
		if block_id == "air":
			return
		var body := StaticBody3D.new()
		body.name = "RestBlock_%s" % key.replace(",", "_")
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
	environment_resource.background_color = Color("#101A31")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("#AFC7D2")
	environment_resource.ambient_light_energy = 0.75
	environment.environment = environment_resource
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var host := Node3D.new()
	root.add_child(host)
	var world = DesktopRestWorld.new()
	var inventory = InventoryScript.new()
	var day_night = DayNightScript.new()
	var rest = RestScript.new()
	var interactions = InteractionScript.new()
	var player = PlayerScene.instantiate()
	for node in [world, inventory, day_night, rest, interactions, player]:
		host.add_child(node)
	world.build()
	await process_frame
	await process_frame
	day_night.attach_lighting(sun, environment)
	day_night.day_count = 3
	day_night.set_time(21.0)
	rest.setup(day_night)
	interactions.setup(null, null, inventory, null)
	interactions.register_extension(rest)
	player.bind_world(world)
	player.setup_gameplay_services(
		{
			"inventory": inventory,
			"interaction": interactions,
		}
	)
	rest.attach_world(world, player)
	player.global_position = world.default_spawn
	player.reset_motion()
	player.get_view_camera().current = true
	player.set_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await physics_frame
	_check(root.get_camera_3d() == player.get_view_camera(), "the player camera owns the rest desktop viewport")
	_check(
		str(interactions.get_interaction_hint_for_item("oak_bed", "")).contains("睡到清晨"),
		"night bed prompt explains sleep and respawn behavior",
	)
	await _aim_at(player, Vector3(BED_POSITION) + Vector3(0.5, 0.5, 0.5))
	_check(_ray_hits_block(player, world, BED_POSITION), "the real player ray resolves the bed")
	await _right_click()
	_check(rest.has_custom_spawn(), "a real right click stores a custom bed spawn")
	_check(
		day_night.time_of_day >= 6.5 and day_night.time_of_day < 7.0,
		"sleep advances the running day-night service into the morning window",
	)
	_check(day_night.day_count == 4, "sleep advances the calendar to the next day")
	_check(
		player.get_respawn_position().is_equal_approx(rest.get_respawn_position()),
		"the player receives the service-owned respawn point",
	)
	var bed_spawn: Vector3 = player.get_respawn_position()
	player.global_position = Vector3(4.0, 8.0, 4.0)
	player.respawn()
	_check(player.global_position.is_equal_approx(bed_spawn), "player respawn returns to the bed")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "sleep interaction preserves gameplay mouse capture")
	await _aim_at(player, Vector3(BED_POSITION) + Vector3(0.5, 0.5, 0.5))
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "rest desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	var removed := world.remove_block(BED_POSITION)
	interactions.on_block_removed(world, BED_POSITION, removed)
	_check(not rest.has_custom_spawn(), "removing the active bed clears custom spawn state")
	_check(
		player.get_respawn_position().is_equal_approx(world.default_spawn),
		"bed removal restores the world spawn",
	)
	player.set_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rest.clear()
	host.queue_free()
	environment.queue_free()
	sun.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA REST DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA REST DESKTOP FAILURE: %s" % failure)
		print("QA REST DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	if camera != null:
		var direction := (target - camera.global_position).normalized()
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		camera.look_at(target, up)
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
		"rest desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
