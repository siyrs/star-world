extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://ranch-runtime-lifecycle-desktop.png"
const CLEANUP_FRAMES := 8

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


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
	var coordinator: Node = hub.get("feature_lifecycle") if hub != null else null
	var participant: Node = hub.get("ranch_runtime_participant") if hub != null else null
	_check(hub != null and coordinator != null and participant != null, "production game mounts the ranch lifecycle composition")
	if hub == null or coordinator == null or participant == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Ranch-Lifecycle-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		73184529
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop ranch journey creates a temporary world")
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var spawner: Node = hub.creature_spawner
	var attraction: Node = hub.animal_attraction_service
	var products: Node = hub.animal_product_service
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts before ranch lifecycle tests")
	_check(attraction != null and products != null, "participant-owned ranch services keep their public ports")
	_check(int(coordinator.call("get_snapshot").get("participant_count", 0)) == 3, "production coordinator exposes all three participants")
	if player == null or world == null or attraction == null or products == null:
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_flat_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	var positions: Array[Vector3] = []
	var raw_positions: Variant = arena.get("chicken_positions", [])
	if raw_positions is Array:
		for raw_position: Variant in raw_positions:
			if raw_position is Vector3:
				var position: Vector3 = raw_position
				positions.append(position)
	var chickens: Array[Node3D] = []
	for position: Vector3 in positions:
		var raw_chicken: Variant = spawner.call("spawn_creature", "chicken", position)
		if raw_chicken is Node3D:
			var chicken: Node3D = raw_chicken
			_freeze_creature(chicken)
			chickens.append(chicken)
	_check(chickens.size() == 3, "production spawner creates three ranch chickens")
	if chickens.size() != 3:
		await _finish(game, hub)
		return

	var following_events: Array[Dictionary] = []
	participant.connect(
		"following_transition_announced",
		func(kind: String, count: int, snapshot: Dictionary) -> void:
			following_events.append({"kind":kind, "count":count, "snapshot":snapshot.duplicate(true)})
	)
	hub.inventory.clear()
	hub.inventory.add_item("wheat_seeds", 3)
	hub.inventory.add_item("carrot", 1)
	hub.inventory.select_slot(0)
	var following_count := int(attraction.call("refresh_now"))
	await process_frame
	_check(following_count == 3, "holding production feed attracts all three nearby chickens")
	_check(following_events.size() == 1 and str(following_events[0].get("kind", "")) == "started", "multiple followers create one player-facing start transition")
	hub.inventory.select_slot(1)
	await process_frame
	_check(int(attraction.call("refresh_now")) == 0, "switching to the wrong feed releases all followers")
	_check(following_events.size() == 2 and str(following_events[1].get("kind", "")) == "stopped", "releasing multiple followers creates one stop transition")

	hub.inventory.select_slot(0)
	var husbandry_ids: Array[String] = []
	for chicken: Node3D in chickens:
		var interaction: Dictionary = hub.husbandry_service.call(
			"interact_entity", chicken, hub.inventory
		)
		_check(bool(interaction.get("success", false)), "production husbandry transaction manages a chicken")
		var husbandry_id := str(chicken.get_meta("husbandry_id", ""))
		if not husbandry_id.is_empty():
			husbandry_ids.append(husbandry_id)
	_check(husbandry_ids.size() == 3, "three managed chickens receive stable husbandry ids")

	var product_records: Dictionary = {}
	for husbandry_id: String in husbandry_ids:
		product_records[husbandry_id] = {
			"species_id":"chicken",
			"remaining_seconds":0.1,
			"pending_count":0,
		}
	products.call(
		"deserialize",
		{
			"version":1,
			"saved_at_unix":int(Time.get_unix_time_from_system()),
			"records":product_records,
		}
	)
	var product_batches: Array[Dictionary] = []
	participant.connect(
		"product_batch_announced",
		func(summary: Dictionary) -> void: product_batches.append(summary.duplicate(true))
	)
	var production_result: Dictionary = products.call("advance", 1.0)
	await process_frame
	await process_frame
	_check(int(production_result.get("produced", 0)) == 3, "three managed chickens complete production in one update")
	_check(int(production_result.get("spawned", 0)) == 3, "three completed products create production pickups")
	_check(product_batches.size() == 1, "three synchronous product events create one player notification")
	if not product_batches.is_empty():
		var summary: Dictionary = product_batches[0]
		_check(int(summary.get("total_count", 0)) == 3, "batch notification preserves the complete egg quantity")
		_check(int(summary.get("animal_count", 0)) == 3, "batch notification preserves the producing animal count")
		_check(str(summary.get("message", "")).contains("鸡蛋 ×3"), "batch notification communicates the real ranch yield")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("product_batch_count", 0)) == 1, "runtime diagnostics record one product batch")
	_check(int(lifecycle.get("product_audio_count", 0)) == 1, "one product batch plays exactly one pickup sound")

	var egg_pickups := _find_pickups(spawner, "egg")
	_check(egg_pickups.size() == 3, "production ranch creates three separate physical egg pickups")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the batched ranch yield")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "ranch lifecycle evidence uses the 1024x576 product resolution")
		_save_image(image)
	for pickup: Node3D in egg_pickups:
		pickup.global_position = player.global_position + Vector3(0.0, 0.7, 0.0)
		await physics_frame
		await process_frame
	_check(hub.inventory.count_item("egg") == 3, "physical pickup collection transfers the full batched yield")

	_check(bool(hub.save_current()), "ranch participant joins the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check((loaded.get("animal_products", {}).get("records", {}) as Dictionary).size() >= 3, "saved world preserves all managed product timers")
	var eggs_before_reload := int(hub.inventory.count_item("egg"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("bound_player_id", -1)) == 0, "return-to-menu releases the ranch player reference")
	_check(not bool((attraction.call("get_snapshot") as Dictionary).get("active", true)), "return-to-menu deactivates attraction processing")
	_check(not bool((products.call("get_snapshot") as Dictionary).get("active", true)), "return-to-menu deactivates product processing")
	_check(attraction.get("player") == null and products.get("player") == null, "return-to-menu releases both ranch service player references")

	game.begin_world_state(loaded)
	for _frame in 12:
		await process_frame
	await physics_frame
	player = game.player
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("bound_player_id", 0)) == player.get_instance_id(), "full reload binds the new production player")
	_check(hub.inventory.count_item("egg") == eggs_before_reload, "full reload restores the collected yield exactly once")
	_check(int((products.call("get_snapshot") as Dictionary).get("tracked_animals", 0)) >= 3, "full reload restores product timers for managed chickens")
	_check(hub.husbandry_interaction.get("product_service") == products, "reload keeps the product read model connected to prompts")

	game.call("_abort_world_start", "qa_ranch_runtime_failure")
	for _frame in 4:
		await process_frame
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("bound_player_id", -1)) == 0, "world-start failure clears ranch runtime references")
	_check(hub.current_world_id.is_empty(), "world-start failure resets the production world identity")
	await _finish(game, hub)


func _build_flat_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-10, 11):
		for z_offset in range(-7, 3):
			var floor_position := Vector3i(
				origin.x + x_offset, floor_y, origin.z + z_offset
			)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call(
					"set_block", floor_position + Vector3i(0, y_offset, 0), "air"
				)
	var base := Vector3(
		float(origin.x) + 0.5,
		float(floor_y) + 1.05,
		float(origin.z) + 0.5
	)
	return {
		"player_position": base,
		"chicken_positions": [
			base + Vector3(-7.0, 0.0, -3.0),
			base + Vector3(0.0, 0.0, -5.0),
			base + Vector3(7.0, 0.0, -3.0),
		],
	}


func _find_pickups(spawner: Node, item_id: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in spawner.get_children():
		if child is Node3D and str(child.get("item_id")) == item_id:
			result.append(child as Node3D)
	return result


func _freeze_creature(creature: Node3D) -> void:
	creature.set_physics_process(false)
	if creature is CharacterBody3D:
		creature.velocity = Vector3.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "ranch lifecycle desktop screenshot is saved")


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
		print("QA RANCH RUNTIME LIFECYCLE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RANCH RUNTIME LIFECYCLE DESKTOP FAILURE: %s" % failure)
		print("QA RANCH RUNTIME LIFECYCLE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
