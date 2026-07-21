extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://husbandry-runtime-lifecycle-desktop.png"
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
	var participant: Node = hub.get("husbandry_runtime_participant") if hub != null else null
	var machine_runtime: Node = hub.get("machine_runtime") if hub != null else null
	_check(
		hub != null and coordinator != null and participant != null and machine_runtime != null,
		"production game mounts husbandry and Machine Base lifecycle services"
	)
	if hub == null or coordinator == null or participant == null or machine_runtime == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Husbandry-Lifecycle-%d" % Time.get_ticks_msec(),
		"star_continent",
		74291365
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop husbandry journey creates a temporary world")
	game.begin_world_state(state)
	for _frame in 12:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	var spawner: Node = hub.creature_spawner
	var service: Node = hub.husbandry_service
	var interaction: Node = hub.husbandry_interaction
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production world starts before husbandry lifecycle acceptance")
	_check(service != null and interaction != null, "participant-owned husbandry ports remain available")
	_check(
		int(coordinator.call("get_snapshot").get("participant_count", 0)) == 6,
		"production coordinator exposes six lifecycle participants"
	)
	_check(coordinator.call("has_participant", &"machine_runtime"), "Machine Base is the lifecycle root participant")
	_check(
		coordinator.call("get_participant_dependencies", &"ranch_runtime") == ["husbandry_runtime"],
		"production dependency graph orders ranch after husbandry"
	)
	if player == null or world == null or service == null or interaction == null:
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_flat_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	var raw_positions: Variant = arena.get("cow_positions", [])
	var positions: Array[Vector3] = []
	if raw_positions is Array:
		for raw_position: Variant in raw_positions:
			if raw_position is Vector3:
				positions.append(raw_position)
	var cows: Array[Node3D] = []
	for position: Vector3 in positions:
		var raw_cow: Variant = spawner.call("spawn_creature", "cow", position)
		if raw_cow is Node3D:
			var cow: Node3D = raw_cow
			_freeze_creature(cow)
			cows.append(cow)
	_check(cows.size() == 4, "production spawner creates two breeding pairs")
	if cows.size() != 4:
		await _finish(game, hub)
		return

	var lifecycle_batches: Array[Dictionary] = []
	participant.connect(
		"lifecycle_batch_announced",
		func(summary: Dictionary) -> void: lifecycle_batches.append(summary.duplicate(true))
	)
	hub.inventory.clear()
	hub.inventory.add_item("wheat", 4, {"batch":"husbandry-lifecycle"})
	hub.inventory.select_slot(0)
	await _aim_at(player, cows[0].global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits_entity(player, cows[0]), "real player ray resolves the first breeding animal")
	await _right_click_center()
	_check(hub.inventory.count_item("wheat") == 3, "real right click consumes the first feed item")
	_check(service.get_managed_count() == 1, "real right click adopts the first managed animal")

	var second_result: Dictionary = service.call("interact_entity", cows[1], hub.inventory)
	var third_result: Dictionary = service.call("interact_entity", cows[2], hub.inventory)
	var fourth_result: Dictionary = service.call("interact_entity", cows[3], hub.inventory)
	_check(str(second_result.get("action", "")) == "breed_animals", "second cow completes the first breeding pair")
	_check(str(third_result.get("action", "")) == "prepare_breeding", "third cow prepares the second breeding pair")
	_check(str(fourth_result.get("action", "")) == "breed_animals", "fourth cow completes the second breeding pair")
	_check(hub.inventory.count_item("wheat") == 0, "four production feeds consume exactly four wheat")
	for _frame in 3:
		await process_frame
	_check(service.get_managed_count() == 6, "two breeding pairs create four parents and two babies")
	_check(lifecycle_batches.size() == 1, "two synchronous births create one player-facing lifecycle batch")
	if not lifecycle_batches.is_empty():
		var birth_summary: Dictionary = lifecycle_batches[0]
		_check(int(birth_summary.get("newborn_count", 0)) == 2, "birth batch preserves both newborns")
		_check(str(birth_summary.get("message", "")).contains("幼年牛 ×2"), "birth batch communicates the complete newborn yield")
	var lifecycle_snapshot: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle_snapshot.get("lifecycle_audio_count", 0)) == 1, "two births play exactly one craft sound")

	var babies := _find_babies(spawner, service)
	_check(babies.size() == 2, "production world contains both live baby cows")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the multi-baby husbandry state")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "husbandry lifecycle evidence uses the 1024x576 product resolution")
		_save_image(image)

	service.call("_process", 9999.0)
	for _frame in 3:
		await process_frame
	_check(lifecycle_batches.size() == 2, "two synchronous growth completions create one additional batch")
	if lifecycle_batches.size() >= 2:
		var growth_summary: Dictionary = lifecycle_batches[1]
		_check(int(growth_summary.get("grown_count", 0)) == 2, "growth batch preserves both adulthood transitions")
		_check(str(growth_summary.get("message", "")).contains("牛 ×2"), "growth batch communicates both adult cows")
	lifecycle_snapshot = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle_snapshot.get("lifecycle_audio_count", 0)) == 1, "growth-only batches do not add a craft sound")

	_check(bool(hub.save_current()), "husbandry participant joins the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check((loaded.get("husbandry", {}).get("animals", {}) as Dictionary).size() == 6, "saved world preserves all six managed animals")
	var old_player: Node = player
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	lifecycle_snapshot = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle_snapshot.get("bound_player_id", -1)) == 0, "return-to-menu releases the husbandry player reference")
	_check(not bool(machine_runtime.call("is_active")), "return-to-menu also stops shared machine processing")
	if old_player != null and is_instance_valid(old_player):
		_check(old_player.get("entity_interaction_service") == null, "old player no longer retains the husbandry interaction port")
	_check((service.call("get_snapshot") as Dictionary).get("managed_animals", -1) == 0, "return-to-menu clears husbandry runtime records")

	game.begin_world_state(loaded)
	for _frame in 14:
		await process_frame
	await physics_frame
	player = game.player
	lifecycle_snapshot = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle_snapshot.get("bound_player_id", 0)) == player.get_instance_id(), "full reload binds the new production player")
	_check(player.get("entity_interaction_service") == interaction, "full reload restores the same husbandry interaction port")
	_check(service.get_managed_count() == 6, "full reload restores managed animals exactly once")
	_check(lifecycle_batches.size() == 2, "world reload does not replay birth or growth notifications")
	_check(bool(machine_runtime.call("is_active")), "full reload reactivates Machine Base")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(character_snapshot.has("husbandry") and character_snapshot.has("animal_products"), "production diagnostics preserve husbandry and ranch fields")
	_check(character_snapshot.has("machine_runtime"), "production diagnostics preserve Machine Base state")

	game.call("_abort_world_start", "qa_husbandry_lifecycle_failure")
	for _frame in 4:
		await process_frame
	lifecycle_snapshot = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle_snapshot.get("bound_player_id", -1)) == 0, "failed-start cleanup removes the current husbandry binding")
	_check(hub.current_world_id.is_empty(), "failed-start cleanup resets the production world identity")
	_check(not bool(machine_runtime.call("is_active")), "failed-start cleanup stops Machine Base")
	await _finish(game, hub)


func _build_flat_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-8, 9):
		for z_offset in range(-7, 3):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	var base := Vector3(float(origin.x) + 0.5, float(floor_y) + 1.05, float(origin.z) + 0.5)
	return {
		"player_position": base,
		"cow_positions": [
			base + Vector3(-4.5, 0.0, -4.0),
			base + Vector3(-2.5, 0.0, -4.0),
			base + Vector3(2.5, 0.0, -4.0),
			base + Vector3(4.5, 0.0, -4.0),
		],
	}


func _find_babies(spawner: Node, service: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in spawner.get_children():
		if child is not Node3D:
			continue
		var husbandry_id := str(child.get_meta("husbandry_id", ""))
		if husbandry_id.is_empty():
			continue
		var record: Dictionary = service.call("get_record", husbandry_id)
		if str(record.get("stage", "")) == "baby":
			result.append(child as Node3D)
	return result


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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "husbandry lifecycle desktop screenshot is saved")


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
		print("QA HUSBANDRY RUNTIME LIFECYCLE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HUSBANDRY RUNTIME LIFECYCLE DESKTOP FAILURE: %s" % failure)
		print("QA HUSBANDRY RUNTIME LIFECYCLE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
