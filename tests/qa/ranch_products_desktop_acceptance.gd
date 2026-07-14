extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ranch-products-desktop-acceptance.png"
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _created_world_id := ""


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
	_check(hub != null, "game exposes the ranch progression hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Ranch-Products-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		61829437
	)
	_check(not state.is_empty(), "desktop acceptance creates a temporary ranch world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real world starts before ranch interaction")
	_check(hub.get("animal_attraction_service") != null, "animal attraction service is mounted")
	_check(hub.get("animal_product_service") != null, "animal product service is mounted")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures the mouse before ranch interaction")

	var player: Node3D = game.player
	var spawner: Node = hub.creature_spawner
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	var chicken_position: Vector3 = game.world.resolve_ground_position(
		player.global_position + Vector3(0.0, 1.0, -5.0)
	)
	var chicken_value: Variant = spawner.call("spawn_creature", "chicken", chicken_position)
	_check(chicken_value is Node3D, "real creature spawner creates a chicken")
	if chicken_value is not Node3D:
		await _finish(game, hub)
		return
	var chicken: Node3D = chicken_value
	hub.inventory.clear()
	hub.inventory.add_item("wheat_seeds", 1, {"batch":"desktop-ranch"})
	hub.inventory.select_slot(0)
	await process_frame

	var distance_before := chicken.global_position.distance_to(player.global_position)
	var following_count := int(hub.animal_attraction_service.call("refresh_now"))
	_check(following_count == 1, "holding wheat seeds attracts the nearby chicken")
	var attraction_snapshot: Dictionary = chicken.call("get_attraction_snapshot")
	_check(bool(attraction_snapshot.get("active", false)), "real chicken receives the attraction capability")
	for _frame in 45:
		await physics_frame
	var distance_after := chicken.global_position.distance_to(player.global_position)
	_check(distance_after < distance_before - 0.25, "attracted chicken physically moves toward the player")
	_freeze_creature(chicken)

	await _aim_at(player, chicken.global_position + Vector3(0.0, 0.55, 0.0))
	_check(_ray_hits_entity(player, chicken), "real player ray resolves the attracted chicken")
	var focus := {
		"type":"entity",
		"entity_id":chicken.get_instance_id(),
		"species_id":"chicken",
		"display_name":"鸡",
		"health":4.0,
		"max_health":4.0,
	}
	var feed_prompt: Dictionary = hub.husbandry_interaction.call(
		"get_entity_prompt", focus, "wheat_seeds"
	)
	_check(str(feed_prompt.get("secondary", "")).contains("繁殖状态"), "chicken prompt explains seed feeding")
	await _right_click_center()
	_check(hub.inventory.count_item("wheat_seeds") == 0, "real right click consumes exactly one seed")
	_check(hub.husbandry_service.get_managed_count() == 1, "fed chicken becomes a persistent ranch animal")
	var husbandry_id := str(chicken.get_meta("husbandry_id", ""))
	_check(not husbandry_id.is_empty(), "managed chicken receives a stable husbandry id")

	hub.animal_product_service.call(
		"deserialize",
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				husbandry_id:{
					"species_id":"chicken",
					"remaining_seconds":0.1,
					"pending_count":0,
				}
			},
		}
	)
	var production_result: Dictionary = hub.animal_product_service.call("advance", 1.0)
	_check(int(production_result.get("produced", 0)) == 1, "managed chicken completes a real egg timer")
	_check(int(production_result.get("spawned", 0)) == 1, "nearby completed product spawns into the world")
	var egg_pickup := _find_pickup(spawner, "egg")
	_check(egg_pickup != null, "real ranch runtime creates an egg pickup")
	var product_prompt: Dictionary = hub.husbandry_interaction.call(
		"get_entity_prompt", focus, ""
	)
	_check(str(product_prompt.get("subtitle", "")).contains("下次鸡蛋"), "chicken prompt exposes the next egg timer")

	await _aim_at(player, chicken.global_position + Vector3(0.0, 0.55, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "ranch desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)

	if egg_pickup != null and egg_pickup is Node3D:
		egg_pickup.global_position = player.global_position + Vector3(0.0, 0.8, 0.0)
		for _frame in 4:
			await physics_frame
	_check(hub.inventory.count_item("egg") == 1, "player collects the produced egg through world pickup physics")
	_check(bool(hub.furnace_service.get("recipe_registry").has_input("egg")), "collected egg is accepted by the furnace registry")
	_check(bool(hub.save_current()), "ranch product state participates in the world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	_check(loaded.has("animal_products"), "saved world contains the animal product domain")
	var saved_products: Dictionary = loaded.get("animal_products", {}).get("records", {})
	_check(saved_products.has(husbandry_id), "saved product timer uses the stable husbandry id")
	_check(bool(player.get("input_enabled")), "ranch interaction never locks player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "ranch interaction keeps gameplay mouse captured")
	await _finish(game, hub)


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
			"QA RANCH PRODUCTS DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH PRODUCTS DESKTOP FAILURE: %s" % failure)
		print(
			"QA RANCH PRODUCTS DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _freeze_creature(creature: Node3D) -> void:
	creature.set_physics_process(false)
	if creature is CharacterBody3D:
		creature.velocity = Vector3.ZERO


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(target, Vector3.UP)
	await physics_frame
	await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()


func _ray_hits_entity(player: Node3D, expected: Node) -> bool:
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray == null:
		return false
	ray.force_raycast_update()
	return ray.is_colliding() and ray.get_collider() == expected


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


func _find_pickup(spawner: Node, item_id: String) -> Node:
	for child: Node in spawner.get_children():
		if child is Area3D and str(child.get("item_id")) == item_id:
			return child
	return null


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"ranch products desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
