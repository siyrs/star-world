extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://husbandry-closed-loop-desktop.png"
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
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Husbandry-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		73194625,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "husbandry journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var spawner: Node = hub.get("creature_spawner") as Node
	var husbandry: Node = hub.get("husbandry_service") as Node
	var runtime: Node = hub.get("husbandry_runtime_participant") as Node
	var inventory: Node = hub.get("inventory") as Node
	_check(
		player != null and world != null and spawner != null
		and husbandry != null and runtime != null and inventory != null,
		"production husbandry composition is fully mounted",
	)
	if player == null or world == null or spawner == null or husbandry == null or runtime == null or inventory == null:
		await _finish(game, hub)
		return

	var lifecycle_events: Array[Dictionary] = []
	var interaction_events: Array[Dictionary] = []
	var rejection_events: Array[Dictionary] = []
	runtime.lifecycle_batch_announced.connect(
		func(summary: Dictionary) -> void:
			lifecycle_events.append(summary.duplicate(true))
	)
	runtime.interaction_announced.connect(
		func(kind: String, result: Dictionary) -> void:
			interaction_events.append({"kind":kind, "result":result.duplicate(true)})
	)
	husbandry.interaction_rejected.connect(
		func(reason: String, context: Dictionary) -> void:
			rejection_events.append({"reason":reason, "context":context.duplicate(true)})
	)

	var pair: Array[Node3D] = await _spawn_parent_pair(game, hub)
	_check(pair.size() == 2, "real creature spawner creates two bounded parent cows")
	if pair.size() != 2:
		await _finish(game, hub)
		return
	var first := pair[0]
	var second := pair[1]
	inventory.clear()
	inventory.add_item("wheat", 2, {"batch":"husbandry-closed-loop"})
	inventory.select_slot(0)
	await process_frame

	await _aim_at(player, first.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits_entity(player, first), "production center ray resolves the first parent")
	await _right_click_center()
	_check(inventory.count_item("wheat") == 1, "first real feed consumes exactly one wheat")
	await _aim_at(player, second.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits_entity(player, second), "production center ray resolves the second parent")
	await _right_click_center()
	for _frame in 4:
		await process_frame
	_check(inventory.count_item("wheat") == 0, "second real feed consumes the remaining wheat")
	_check(int(husbandry.call("get_managed_count")) == 3, "real breeding creates two parent records and one baby")
	var first_parent_id := str(first.get_meta("husbandry_id", ""))
	var second_parent_id := str(second.get_meta("husbandry_id", ""))
	var first_baby_id := _only_new_id(
		_husbandry_ids(husbandry),
		[first_parent_id, second_parent_id],
	)
	_check(
		not first_parent_id.is_empty() and not second_parent_id.is_empty()
		and not first_baby_id.is_empty(),
		"all first-generation animals expose stable husbandry identities",
	)
	var first_baby: Node3D = husbandry.call("get_live_entity", first_baby_id) as Node3D
	_check(first_baby != null, "first-generation baby exists as a live production creature")
	_check(
		first_baby != null and first_baby.scale.x < 0.7
		and str(husbandry.call("get_record", first_baby_id).get("stage", "")) == "baby",
		"first-generation baby restores baby domain and visual scale",
	)
	if first_baby != null:
		_freeze_creature(first_baby)
	var lifecycle_count_after_birth := lifecycle_events.size()
	var interaction_count_after_birth := interaction_events.size()
	_check(lifecycle_count_after_birth == 1, "first breeding produces one bounded lifecycle summary")

	_check(bool(hub.call("save_current")), "first-generation live state joins the authoritative save")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var saved_animals: Dictionary = loaded.get("husbandry", {}).get("animals", {})
	_check(saved_animals.size() == 3, "world.json contains all three first-generation records")
	_check(
		saved_animals.has(first_parent_id) and saved_animals.has(second_parent_id)
		and saved_animals.has(first_baby_id),
		"world.json preserves all stable first-generation identities",
	)

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	_check(int(husbandry.call("get_managed_count")) == 0, "return to menu clears the live husbandry session")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "first complete husbandry reload reaches gameplay")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	_check(int(husbandry.call("get_managed_count")) == 3, "first reload restores exactly three managed animals")
	_check(
		lifecycle_events.size() == lifecycle_count_after_birth
		and interaction_events.size() == interaction_count_after_birth,
		"first reload does not replay historical birth or interaction feedback",
	)
	first = husbandry.call("get_live_entity", first_parent_id) as Node3D
	second = husbandry.call("get_live_entity", second_parent_id) as Node3D
	first_baby = husbandry.call("get_live_entity", first_baby_id) as Node3D
	_check(first != null and second != null and first_baby != null, "first reload restores all three live creatures")
	_check(
		first_baby != null and first_baby.scale.x < 0.7
		and str(husbandry.call("get_record", first_baby_id).get("stage", "")) == "baby",
		"first reload preserves baby stage and scale",
	)
	for creature: Node3D in [first, second, first_baby]:
		if creature != null:
			_freeze_creature(creature)

	inventory.clear()
	inventory.add_item("wheat", 1)
	inventory.select_slot(0)
	var inventory_before_cooldown: Dictionary = inventory.call("serialize")
	var records_before_cooldown: Dictionary = husbandry.call("get_managed_records")
	await _aim_at(player, first.global_position + Vector3(0.0, 0.65, 0.0))
	await _right_click_center()
	_check(not rejection_events.is_empty(), "real cooldown interaction emits a production rejection")
	if not rejection_events.is_empty():
		_check(
			str(rejection_events[-1].get("reason", "")) == "breed_cooldown",
			"cooldown rejection retains the exact breed_cooldown reason",
		)
	_check(inventory.call("serialize") == inventory_before_cooldown, "cooldown failure cannot consume player wheat")
	_check(husbandry.call("get_managed_records") == records_before_cooldown, "cooldown failure cannot mutate any animal record")

	husbandry.call("_process", 181.0)
	inventory.clear()
	inventory.add_item("wheat", 2, {"generation":2})
	inventory.select_slot(0)
	await _aim_at(player, first.global_position + Vector3(0.0, 0.65, 0.0))
	await _right_click_center()
	await _aim_at(player, second.global_position + Vector3(0.0, 0.65, 0.0))
	await _right_click_center()
	for _frame in 4:
		await process_frame
	_check(int(husbandry.call("get_managed_count")) == 4, "second real breeding creates one additional baby")
	var second_baby_id := _only_new_id(
		_husbandry_ids(husbandry),
		[first_parent_id, second_parent_id, first_baby_id],
	)
	_check(not second_baby_id.is_empty(), "second-generation baby receives a unique stable identity")
	var second_baby: Node3D = husbandry.call("get_live_entity", second_baby_id) as Node3D
	_check(
		second_baby != null
		and str(husbandry.call("get_record", second_baby_id).get("stage", "")) == "baby",
		"second-generation baby is live and starts in the baby stage",
	)
	if second_baby != null:
		_freeze_creature(second_baby)

	inventory.clear()
	inventory.add_item("iron_sword", 1)
	inventory.select_slot(0)
	if first_baby != null:
		first_baby.set("health", 1.0)
		await _aim_at(player, first_baby.global_position + Vector3(0.0, 0.38, 0.0))
		_check(_ray_hits_entity(player, first_baby), "production center ray resolves the first-generation baby for combat")
		await _left_click_center()
	for _frame in 6:
		await process_frame
	_check(husbandry.call("get_record", first_baby_id).is_empty(), "real player attack removes the defeated baby record")
	_check(int(husbandry.call("get_managed_count")) == 3, "defeat leaves two parents and one surviving second-generation baby")

	var final_records: Dictionary = husbandry.call("get_managed_records")
	_check(bool(hub.call("save_current")), "post-death multi-generation state joins a second authoritative save")
	var final_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var final_saved_animals: Dictionary = final_loaded.get("husbandry", {}).get("animals", {})
	_check(final_saved_animals.size() == 3, "second save contains exactly three surviving animal records")
	_check(
		not final_saved_animals.has(first_baby_id)
		and final_saved_animals.has(first_parent_id)
		and final_saved_animals.has(second_parent_id)
		and final_saved_animals.has(second_baby_id),
		"second save cannot resurrect the defeated baby or lose surviving generations",
	)
	var lifecycle_count_before_final_reload := lifecycle_events.size()
	var interaction_count_before_final_reload := interaction_events.size()

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", final_loaded)
	_check(await _wait_for_world_ready(game, hub), "second complete husbandry reload reaches gameplay")
	_check(husbandry.call("get_managed_records") == final_records, "second reload restores the exact surviving domain records")
	_check(husbandry.call("get_live_entity", first_baby_id) == null, "defeated first-generation baby does not respawn")
	_check(
		husbandry.call("get_live_entity", first_parent_id) != null
		and husbandry.call("get_live_entity", second_parent_id) != null
		and husbandry.call("get_live_entity", second_baby_id) != null,
		"second reload restores every surviving animal exactly once",
	)
	_check(
		lifecycle_events.size() == lifecycle_count_before_final_reload
		and interaction_events.size() == interaction_count_before_final_reload,
		"second reload does not replay birth, death or feed feedback",
	)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "husbandry closed-loop viewport renders a desktop frame")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "husbandry evidence uses 1024x576 resolution")
		_save_image(image)
	_check(bool((game.get("player") as CharacterBody3D).get("input_enabled")), "final husbandry reload remains playable")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "husbandry loop preserves gameplay mouse capture")
	await _finish(game, hub)


func _spawn_parent_pair(game: Node, hub: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var player: Node3D = game.get("player") as Node3D
	var world: Node = game.get("world") as Node
	var spawner: Node = hub.get("creature_spawner") as Node
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	var base_position := player.global_position
	for x_offset: float in [-0.85, 0.85]:
		var position: Vector3 = world.call(
			"resolve_ground_position",
			base_position + Vector3(x_offset, 1.0, -3.4),
		)
		var value: Variant = spawner.call("spawn_creature", "cow", position)
		if value is Node3D:
			var creature := value as Node3D
			_freeze_creature(creature)
			result.append(creature)
	return result


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


func _husbandry_ids(husbandry: Node) -> Array[String]:
	var ids: Array[String] = []
	var records: Dictionary = husbandry.call("get_managed_records")
	for raw_id: Variant in records.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func _only_new_id(ids: Array[String], existing: Array[String]) -> String:
	for husbandry_id: String in ids:
		if husbandry_id not in existing:
			return husbandry_id
	return ""


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
	await _mouse_click(MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT)


func _left_click_center() -> void:
	await _mouse_click(MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT)


func _mouse_click(button: MouseButton, mask: int) -> void:
	var center := Vector2(root.size) * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.global_position = center
		event.button_index = button
		event.button_mask = mask if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "husbandry desktop screenshot is saved")


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
		print("QA HUSBANDRY CLOSED LOOP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HUSBANDRY CLOSED LOOP DESKTOP FAILURE: %s" % failure)
		print("QA HUSBANDRY CLOSED LOOP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
