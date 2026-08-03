extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ranch-products-closed-loop-desktop.png"
const CLEANUP_FRAMES := 10

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the ranch service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Ranch-Products-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		61829437,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "ranch journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production ranch world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var spawner: Node = hub.get("creature_spawner") as Node
	var inventory: Node = hub.get("inventory") as Node
	var husbandry: Node = hub.get("husbandry_service") as Node
	var product: Node = hub.get("animal_product_service") as Node
	var runtime: Node = hub.get("ranch_runtime_participant") as Node
	_check(
		player != null and world != null and spawner != null and inventory != null
		and husbandry != null and product != null and runtime != null,
		"production attraction, husbandry, product and inventory composition is mounted",
	)
	if player == null or world == null or spawner == null or inventory == null or husbandry == null or product == null or runtime == null:
		await _finish(game, hub)
		return
	_check(product is ReliableAnimalProductService, "production ranch uses collection-backed product persistence")

	var product_batches: Array[Dictionary] = []
	runtime.product_batch_announced.connect(
		func(summary: Dictionary) -> void:
			product_batches.append(summary.duplicate(true))
	)

	var lane: Dictionary = _build_flat_ranch_lane(world, player)
	player.global_position = lane.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	await process_frame
	var chicken_value: Variant = spawner.call(
		"spawn_creature",
		"chicken",
		lane.get("chicken_position", player.global_position + Vector3(0.0, 0.0, -4.0)),
	)
	_check(chicken_value is Node3D, "real creature spawner creates a production chicken")
	if chicken_value is not Node3D:
		await _finish(game, hub)
		return
	var chicken := chicken_value as Node3D
	_freeze_creature(chicken)
	inventory.clear()
	inventory.add_item("wheat_seeds", 1, {"batch":"ranch-product-loop"})
	inventory.select_slot(0)
	await _aim_at(player, chicken.global_position + Vector3(0.0, 0.55, 0.0))
	_check(_ray_hits_entity(player, chicken), "production center ray resolves the chicken")
	await _right_click_center()
	_check(inventory.count_item("wheat_seeds") == 0, "real feed consumes exactly one seed")
	_check(int(husbandry.call("get_managed_count")) == 1, "fed chicken becomes a persistent ranch animal")
	var husbandry_id := str(chicken.get_meta("husbandry_id", ""))
	_check(not husbandry_id.is_empty(), "managed chicken receives a stable husbandry identity")

	product.call(
		"deserialize",
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":{
				husbandry_id:{
					"species_id":"chicken",
					"remaining_seconds":0.2,
					"pending_count":0,
				},
			},
		},
	)
	_fill_inventory(inventory)
	_check(_occupied_slot_count(inventory) == 36, "fixture fills all real player inventory slots")
	var full_inventory: Dictionary = inventory.call("serialize")
	_check(bool(hub.call("save_current")), "pre-production timer and full inventory join the authoritative save")
	var timer_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(
		float(timer_loaded.get("animal_products", {}).get("records", {}).get(husbandry_id, {}).get("remaining_seconds", 0.0)) > 0.0,
		"world.json preserves the unfinished egg timer",
	)

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	await create_timer(1.0).timeout
	game.call("begin_world_state", timer_loaded)
	_check(await _wait_for_world_ready(game, hub), "offline timer world completes a full production reload")
	player = game.get("player") as CharacterBody3D
	spawner = hub.get("creature_spawner") as Node
	inventory = hub.get("inventory") as Node
	product = hub.get("animal_product_service") as Node
	_check(inventory.call("serialize") == full_inventory, "first reload restores the exact full inventory")
	var restored_record: Dictionary = product.call("get_record", husbandry_id)
	_check(int(restored_record.get("pending_count", 0)) == 1, "offline elapsed time creates exactly one persisted pending egg")
	_check(int(product.call("get_snapshot").get("active_pickups", 0)) == 1, "first reload materializes exactly one pending pickup")
	_check(_pickup_count(spawner, "egg") == 1, "world contains one and only one restored egg pickup")
	_check(product_batches.is_empty(), "offline restore does not replay a historical product announcement")

	var pickup: Node3D = _find_pickup(spawner, "egg") as Node3D
	_check(pickup != null, "restored pending egg has a live pickup node")
	if pickup != null:
		pickup.global_position = player.global_position + Vector3(0.0, 0.7, 0.0)
		for _frame in 6:
			await physics_frame
	_check(inventory.call("serialize") == full_inventory, "full-inventory pickup contact cannot partially mutate any player slot")
	_check(int(product.call("get_record", husbandry_id).get("pending_count", 0)) == 1, "full-inventory pickup contact preserves authoritative pending product")
	_check(_pickup_count(spawner, "egg") == 1, "full-inventory pickup contact preserves the world pickup")

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "ranch product closed-loop viewport renders a desktop frame")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "ranch product evidence uses 1024x576 resolution")
		_save_image(image)

	_check(bool(hub.call("save_current")), "full-inventory pending pickup joins a second authoritative save")
	var pending_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(
		int(pending_loaded.get("animal_products", {}).get("records", {}).get(husbandry_id, {}).get("pending_count", 0)) == 1,
		"second world.json preserves exactly one uncollected egg",
	)
	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", pending_loaded)
	_check(await _wait_for_world_ready(game, hub), "pending-product world completes a second production reload")
	player = game.get("player") as CharacterBody3D
	spawner = hub.get("creature_spawner") as Node
	inventory = hub.get("inventory") as Node
	product = hub.get("animal_product_service") as Node
	_check(_pickup_count(spawner, "egg") == 1, "second reload still materializes only one pickup")
	_check(int(product.call("get_record", husbandry_id).get("pending_count", 0)) == 1, "second reload preserves the uncollected authoritative count")
	_check(product_batches.is_empty(), "two complete reloads never replay product feedback")

	var freed_slot := _first_occupied_slot(inventory)
	_check(freed_slot >= 0, "fixture finds one real occupied slot to release")
	if freed_slot >= 0:
		inventory.call("remove_from_slot", freed_slot, 1)
	_check(_occupied_slot_count(inventory) == 35, "exactly one player inventory slot is available for collection")
	pickup = _find_pickup(spawner, "egg") as Node3D
	if pickup != null:
		pickup.global_position = player.global_position + Vector3(0.0, 0.7, 0.0)
		for _frame in 8:
			await physics_frame
	_check(inventory.count_item("egg") == 1, "player collects the single pending egg through production pickup physics")
	_check(int(product.call("get_record", husbandry_id).get("pending_count", -1)) == 0, "accepted collection commits the authoritative pending count")
	_check(_pickup_count(spawner, "egg") == 0, "accepted collection removes the transient pickup exactly once")

	var collected_inventory: Dictionary = inventory.call("serialize")
	_check(bool(hub.call("save_current")), "collected egg state joins a final authoritative save")
	var final_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(
		int(final_loaded.get("animal_products", {}).get("records", {}).get(husbandry_id, {}).get("pending_count", -1)) == 0,
		"final world.json records the egg as collected",
	)
	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", final_loaded)
	_check(await _wait_for_world_ready(game, hub), "collected-product world completes the final production reload")
	inventory = hub.get("inventory") as Node
	product = hub.get("animal_product_service") as Node
	spawner = hub.get("creature_spawner") as Node
	_check(inventory.call("serialize") == collected_inventory, "final reload restores the exact collected inventory")
	_check(inventory.count_item("egg") == 1, "final reload contains one egg without duplication")
	_check(int(product.call("get_record", husbandry_id).get("pending_count", -1)) == 0, "final reload cannot resurrect a pending egg")
	_check(_pickup_count(spawner, "egg") == 0, "final reload cannot resurrect a world pickup")
	_check(product_batches.is_empty(), "final reload still contains no replayed product announcement")
	_check(bool((game.get("player") as CharacterBody3D).get("input_enabled")), "final ranch reload remains playable")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "ranch loop preserves gameplay mouse capture")
	await _finish(game, hub)


func _build_flat_ranch_lane(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for z_offset in range(-7, 3):
		for x_offset in range(-3, 4):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	return {
		"player_position": Vector3(origin.x + 0.5, floor_y + 1.05, origin.z + 0.5),
		"chicken_position": Vector3(origin.x + 0.5, floor_y + 1.05, origin.z - 4.5),
	}


func _fill_inventory(inventory: Node) -> void:
	inventory.clear()
	for index in 36:
		inventory.call("add_item", "wooden_pickaxe", 1, {"fixture_slot":index})


func _occupied_slot_count(inventory: Node) -> int:
	var count := 0
	for index in int(inventory.get("slot_count")):
		if not (inventory.call("get_slot", index) as Dictionary).is_empty():
			count += 1
	return count


func _first_occupied_slot(inventory: Node) -> int:
	for index in int(inventory.get("slot_count")):
		if not (inventory.call("get_slot", index) as Dictionary).is_empty():
			return index
	return -1


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 240:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			world != null and player != null and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(player.get("input_enabled"))
		):
			return true
	return false


func _freeze_creature(creature: Node3D) -> void:
	creature.set_physics_process(false)
	if creature is CharacterBody3D:
		creature.velocity = Vector3.ZERO


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(target, Vector3.UP)
	for _frame in 2:
		await physics_frame
		await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _ray_hits_entity(player: Node3D, expected: Node) -> bool:
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray == null:
		return false
	ray.force_raycast_update()
	return ray.is_colliding() and ray.get_collider() == expected


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.global_position = center
		event.button_index = MOUSE_BUTTON_RIGHT
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _find_pickup(spawner: Node, item_id: String) -> Node:
	for child: Node in spawner.get_children():
		if child is Area3D and str(child.get("item_id")) == item_id and not child.is_queued_for_deletion():
			return child
	return null


func _pickup_count(spawner: Node, item_id: String) -> int:
	var count := 0
	for child: Node in spawner.get_children():
		if child is Area3D and str(child.get("item_id")) == item_id and not child.is_queued_for_deletion():
			count += 1
	return count


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "ranch products desktop screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.get("save_service").delete_world(_world_id)
		if hub.get("audio_service") != null and hub.get("audio_service").has_method("shutdown"):
			hub.get("audio_service").shutdown()
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA RANCH PRODUCTS CLOSED LOOP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH PRODUCTS CLOSED LOOP DESKTOP FAILURE: %s" % failure)
		print("QA RANCH PRODUCTS CLOSED LOOP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
