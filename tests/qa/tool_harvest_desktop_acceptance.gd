extends SceneTree

const PlayerScene = preload("res://scenes/game/player.tscn")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const HarvestScript = preload("res://src/harvest/block_harvest_service.gd")
const ExperienceScript = preload("res://src/experience/player_experience_coordinator.gd")
const HarvestOverlayScript = preload("res://src/ui/harvest_progress_overlay.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://tool-harvest-desktop-acceptance.png"
const TARGET_POSITION := Vector3i(0, 1, -3)

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


class InteractionProbe:
	extends Node
	var removed_count := 0

	func can_break_block(_world, _position: Vector3i, _block_id: String) -> bool:
		return true

	func on_block_removed(_world, _position: Vector3i, _block_id: String) -> void:
		removed_count += 1

	func get_interaction_hint(_block_id: String) -> String:
		return ""


class DesktopWorld:
	extends Node3D
	var block_id := "stone"
	var target_body: StaticBody3D

	func build() -> void:
		_build_floor()
		target_body = StaticBody3D.new()
		target_body.name = "HarvestTarget"
		target_body.collision_layer = 1
		target_body.collision_mask = 0
		target_body.position = Vector3(0.0, 1.62, -3.0)
		add_child(target_body)
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		var collision := CollisionShape3D.new()
		collision.shape = shape
		target_body.add_child(collision)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh_instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#777C82")
		mesh_instance.material_override = material
		target_body.add_child(mesh_instance)

	func world_to_block(_point: Vector3) -> Vector3i:
		return TARGET_POSITION

	func get_block(position: Vector3i) -> String:
		return block_id if position == TARGET_POSITION else "air"

	func remove_block(position: Vector3i) -> String:
		if position != TARGET_POSITION or block_id == "air":
			return "air"
		var previous := block_id
		block_id = "air"
		if is_instance_valid(target_body):
			target_body.queue_free()
		return previous

	func _build_floor() -> void:
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		floor_body.position = Vector3(0.0, -0.1, -1.5)
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
		material.albedo_color = Color("#4F7F45")
		mesh_instance.material_override = material
		floor_body.add_child(mesh_instance)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var host := Node3D.new()
	root.add_child(host)
	var world = DesktopWorld.new()
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var interactions = InteractionProbe.new()
	var harvest = HarvestScript.new()
	var experience = ExperienceScript.new()
	var player = PlayerScene.instantiate()
	for node in [world, inventory, tools, interactions, harvest, experience, player]:
		host.add_child(node)
	world.build()
	var overlay = HarvestOverlayScript.new()
	root.add_child(overlay)
	await process_frame
	await process_frame
	tools.setup(inventory.registry)
	harvest.setup(tools, interactions)
	experience.setup(inventory, null, interactions, null)
	experience.attach_player(player)
	experience.begin_gameplay()
	overlay.setup(harvest, tools, experience)
	inventory.clear()
	inventory.add_item("wooden_pickaxe", 1)
	inventory.select_slot(0)
	player.bind_world(world)
	player.setup_gameplay_services(
		{
			"inventory": inventory,
			"interaction": interactions,
			"tools": tools,
			"harvest": harvest,
			"experience": experience,
		}
	)
	player.global_position = Vector3.ZERO
	player.reset_motion()
	player.get_view_camera().current = true
	player.set_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await physics_frame
	_check(root.get_camera_3d() == player.get_view_camera(), "the player camera owns the desktop viewport")
	await _press_primary()
	for _frame in 5:
		await process_frame
	_check(world.block_id == "stone", "pressing left mouse does not instantly remove a hard block")
	_check(not harvest.get_active_snapshot().is_empty(), "holding left mouse starts the harvest state machine")
	_check(overlay.get_layout_rect().size.y > 0.0, "the progress surface has a measurable desktop layout")
	_check(overlay.get_node_or_null("PanelContainer") == null or overlay.visible, "the progress surface remains non-blocking")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop harvest acceptance captures a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	var frames := 0
	while world.block_id != "air" and frames < 180:
		frames += 1
		await process_frame
	await _release_primary()
	_check(world.block_id == "air", "holding left mouse eventually removes the target block")
	_check(inventory.count_item("cobblestone") == 1, "desktop harvesting grants the configured drop")
	_check(
		int(inventory.get_slot(0).get("metadata", {}).get("durability", 60)) == 59,
		"desktop harvesting updates visible tool durability",
	)
	_check(interactions.removed_count == 1, "desktop harvesting runs interaction cleanup exactly once")
	_check(harvest.get_active_snapshot().is_empty(), "completion releases the active harvest target")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "harvesting never releases the gameplay mouse")
	player.set_input_enabled(false)
	experience.end_gameplay()
	harvest.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.queue_free()
	host.queue_free()
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("QA TOOL HARVEST DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure in failures:
			push_error("QA TOOL HARVEST DESKTOP FAILURE: %s" % failure)
		print("QA TOOL HARVEST DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _press_primary() -> void:
	var center := Vector2(root.size) * 0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame


func _release_primary() -> void:
	var center := Vector2(root.size) * 0.5
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "desktop harvest screenshot is saved")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
