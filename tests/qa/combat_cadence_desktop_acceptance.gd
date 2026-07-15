extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://combat-cadence-desktop-acceptance.png"
const CLEANUP_FRAMES := 6
const MAX_READY_FRAMES := 120

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
	_check(hub != null, "game exposes the production service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Combat-Cadence-Desktop-%d" % Time.get_ticks_msec(), "star_continent", 81726354
	)
	_check(not state.is_empty(), "desktop combat journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	_check(game.world != null and bool(game.world.get("is_started")), "real voxel world starts")
	_check(game.player != null and bool(game.player.get("input_enabled")), "real player owns gameplay input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "combat starts with captured mouse")
	_check(hub.get("combat_service") != null, "CombatService is mounted in the production hub")
	var overlay: Node = hub.game_ui.call("get_combat_feedback_overlay")
	_check(overlay != null, "production UI mounts the combat feedback overlay")

	var player: Node3D = game.player
	var world: Node = game.world
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("iron_sword", 1, {"custom_name":"桌面验收铁剑"})
	_check(hub.equipment_service.equip_from_inventory(hub.inventory, 0), "real inventory equips an iron sword")
	_check(str(hub.equipment_service.get_slot("main_hand").get("item_id", "")) == "iron_sword", "main-hand equipment owns the sword")
	var durability_before := int(
		hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 251)
	)

	var target_position := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z - 3.0)
	var target_variant: Variant = hub.creature_spawner.call("spawn_creature", "cow", target_position)
	_check(target_variant is Node3D, "real creature spawner creates a combat target")
	if target_variant is not Node3D:
		await _finish(game, hub)
		return
	var target: Node3D = target_variant
	target.set("move_speed", 0.8)
	target.set("_decision_timer", 999.0)
	target.set("_wander_direction", Vector3.ZERO)
	await process_frame
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits(player, target), "center ray resolves the live cow")
	var target_start := target.global_position
	var health_before := float(target.get("health"))
	await _left_click_center()
	var first_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	_check(str(first_result.get("status", "")) == "hit", "real left click commits one CombatService hit")
	_check(is_equal_approx(float(target.get("health")), health_before - 6.0), "iron sword deals six real damage")
	_check(
		int(hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 251))
		== durability_before - 1,
		"first accepted hit consumes exactly one weapon durability",
	)
	var health_after_first := float(target.get("health"))
	var durability_after_first := int(
		hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 251)
	)
	# The rejection is asserted immediately after the first input cycle. Measuring
	# knockback or capturing a frame first can consume the entire cooldown on a
	# slow software renderer and would no longer represent a repeated click.
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	await _left_click_center()
	var rejected: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	_check(str(rejected.get("reason", "")) == "cooldown", "immediate second real click is rejected by cooldown")
	_check(is_equal_approx(float(target.get("health")), health_after_first), "cooldown click cannot deal duplicate damage")
	_check(
		int(hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 251))
		== durability_after_first,
		"cooldown click cannot consume durability",
	)

	for _frame in 10:
		await physics_frame
	_check(
		Vector2(target.global_position.x - target_start.x, target.global_position.z - target_start.z).length() > 0.12,
		"accepted hit produces visible horizontal knockback",
	)
	var feedback: Dictionary = overlay.call("get_snapshot")
	_check(bool(feedback.get("hit_visible", false)), "combat response remains visible after the strike")
	_check(bool(feedback.get("cooldown_visible", false)), "attack recovery indicator is visible")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "combat desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)

	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 1, "E opens the real character inventory")
	_check(not bool(overlay.call("get_snapshot").get("cooldown_visible", true)), "blocking UI hides combat feedback")
	await _tap_key(KEY_E)
	_check(hub.game_ui.get_active_overlay() == 0, "E closes the inventory")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")

	# Knockback has already been proven by real movement. Re-center and freeze the
	# target so the final post-cooldown strike tests cadence rather than flee AI.
	target.set("move_speed", 0.0)
	target.set("_flee_timer", 0.0)
	target.global_position = target_start
	if target is CharacterBody3D:
		target.velocity = Vector3.ZERO
	await physics_frame
	await process_frame
	for _frame in MAX_READY_FRAMES:
		if bool(hub.combat_service.get_cooldown_snapshot().get("ready", false)):
			break
		await process_frame
	_check(bool(hub.combat_service.get_cooldown_snapshot().get("ready", false)), "real cooldown returns to ready")
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits(player, target), "center ray reacquires the target after cooldown")
	await _left_click_center()
	var final_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	_check(str(final_result.get("status", "")) == "hit", "attack succeeds again after recovery")
	_check(bool(final_result.get("defeated", false)), "second accepted iron-sword hit defeats the cow")
	_check(
		int(hub.equipment_service.get_slot("main_hand").get("metadata", {}).get("durability", 251))
		== durability_before - 2,
		"two accepted hits consume exactly two durability",
	)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "combat never releases the gameplay mouse")
	_check(bool(player.get("input_enabled")), "combat never locks WASD input")
	_check(bool(hub.save_current()), "transient combat cadence coexists with the world save transaction")
	await _finish(game, hub)


func _prepare_arena(world: Node, x: int, z: int, floor_y: int) -> void:
	for offset_z in range(-6, 2):
		world.call("set_block", Vector3i(x, floor_y, z + offset_z), "stone")
		for y in range(floor_y + 1, floor_y + 4):
			world.call("set_block", Vector3i(x, y, z + offset_z), "air")


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 10):
		var candidate_y := player_block.y - offset - 1
		if str(world.call("get_block", Vector3i(player_block.x, candidate_y, player_block.z))) != "air":
			return candidate_y
	return maxi(1, player_block.y - 1)


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(target, Vector3.UP)
	await physics_frame
	await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _ray_hits(player: Node3D, expected: Node) -> bool:
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray == null:
		return false
	ray.force_raycast_update()
	return ray.is_colliding() and ray.get_collider() == expected


func _left_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _tap_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"combat cadence desktop screenshot is saved",
	)


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
		print("QA COMBAT CADENCE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA COMBAT CADENCE DESKTOP FAILURE: %s" % failure)
		print("QA COMBAT CADENCE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
