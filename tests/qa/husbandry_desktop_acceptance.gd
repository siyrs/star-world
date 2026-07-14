extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://husbandry-desktop-acceptance.png"
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
	_check(hub != null, "game exposes the husbandry progression hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Husbandry-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 73194625
	)
	_check(not state.is_empty(), "desktop acceptance creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real world starts before animal interaction")
	_check(hub.get("husbandry_service") != null, "husbandry service is mounted in desktop runtime")
	_check(hub.get("husbandry_interaction") != null, "entity interaction adapter is mounted")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "gameplay captures mouse before feeding")
	var player: Node3D = game.player
	var spawner: Node = hub.creature_spawner
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	var base_position: Vector3 = player.global_position
	var first_position: Vector3 = game.world.resolve_ground_position(
		base_position + Vector3(-0.85, 1.0, -3.4)
	)
	var second_position: Vector3 = game.world.resolve_ground_position(
		base_position + Vector3(0.85, 1.0, -3.4)
	)
	var first_variant: Variant = spawner.call("spawn_creature", "cow", first_position)
	var second_variant: Variant = spawner.call("spawn_creature", "cow", second_position)
	_check(first_variant is Node3D and second_variant is Node3D, "real creature spawner creates two cows")
	if first_variant is not Node3D or second_variant is not Node3D:
		await _finish(game, hub)
		return
	var first: Node3D = first_variant
	var second: Node3D = second_variant
	_freeze_creature(first)
	_freeze_creature(second)
	hub.inventory.clear()
	hub.inventory.add_item("wheat", 2, {"batch":"desktop-husbandry"})
	hub.inventory.select_slot(0)
	await process_frame

	await _aim_at(player, first.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits_entity(player, first), "real player ray resolves the first cow")
	var first_focus := {
		"type":"entity",
		"entity_id":first.get_instance_id(),
		"species_id":"cow",
		"display_name":"牛",
		"health":10.0,
		"max_health":10.0,
	}
	var first_prompt: Dictionary = hub.husbandry_interaction.call(
		"get_entity_prompt", first_focus, "wheat"
	)
	_check(str(first_prompt.get("secondary", "")).contains("繁殖状态"), "cow prompt explains the wheat breeding action")
	await _right_click_center()
	_check(hub.inventory.count_item("wheat") == 1, "first real feed consumes exactly one wheat")
	_check(hub.husbandry_service.get_managed_count() == 1, "first cow becomes a managed persistent animal")
	_check(first.is_in_group("persistent_creatures"), "fed cow is protected from natural despawn")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "feeding preserves gameplay mouse capture")

	await _aim_at(player, second.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits_entity(player, second), "real player ray resolves the second cow")
	await _right_click_center()
	_check(hub.inventory.count_item("wheat") == 0, "second real feed consumes the remaining wheat")
	_check(hub.husbandry_service.get_managed_count() == 3, "real breeding creates two parents and one baby record")
	var baby: Node3D = _find_baby(spawner)
	_check(baby != null, "real breeding spawns a live baby cow")
	_check(baby != null and baby.scale.x < 0.7, "newborn cow uses the baby visual scale")
	if baby != null:
		_freeze_creature(baby)
		await _aim_at(player, baby.global_position + Vector3(0.0, 0.38, 0.0))
		var baby_id := str(baby.get_meta("husbandry_id", ""))
		var baby_record: Dictionary = hub.husbandry_service.get_record(baby_id)
		_check(str(baby_record.get("stage", "")) == "baby", "newborn domain state is baby")
		var baby_focus := {
			"type":"entity",
			"entity_id":baby.get_instance_id(),
			"species_id":"cow",
			"display_name":"幼年牛",
			"health":10.0,
			"max_health":10.0,
		}
		var baby_prompt: Dictionary = hub.husbandry_interaction.call(
			"get_entity_prompt", baby_focus, "wheat"
		)
		_check(str(baby_prompt.get("subtitle", "")).contains("幼年"), "baby prompt exposes growth state")
		_check(str(baby_prompt.get("secondary", "")).contains("加速成长"), "baby prompt explains growth feeding")

	_check(bool(hub.save_current()), "husbandry state participates in the world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_created_world_id)
	var saved_animals: Dictionary = loaded.get("husbandry", {}).get("animals", {})
	_check(saved_animals.size() == 3, "saved world contains all managed animals")
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "husbandry desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	_check(bool(player.get("input_enabled")), "animal interaction never locks player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "animal interaction leaves gameplay mouse captured")
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
		print("QA HUSBANDRY DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HUSBANDRY DESKTOP FAILURE: %s" % failure)
		print("QA HUSBANDRY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
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


func _find_baby(spawner: Node) -> Node3D:
	for child in spawner.get_children():
		if child is not Node3D:
			continue
		var husbandry_id := str(child.get_meta("husbandry_id", ""))
		if husbandry_id.is_empty():
			continue
		var record: Dictionary = spawner.get_parent().get("husbandry_service").get_record(husbandry_id)
		if str(record.get("stage", "")) == "baby":
			return child
	return null


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"husbandry desktop screenshot is saved",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
