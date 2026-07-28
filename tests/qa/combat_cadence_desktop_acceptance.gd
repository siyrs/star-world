extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://combat-cadence-desktop-acceptance.png"
const WORLD_READY_TIMEOUT_MS := 120000
const UI_TRANSITION_TIMEOUT_MS := 8000
const COMBAT_TRANSITION_TIMEOUT_MS := 12000
const CLEANUP_FRAMES := 40

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _created_world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 3:
		await process_frame
	var hub: Node = game.service_hub
	_check(hub != null, "game exposes the production service hub")
	if hub == null:
		await _finish(game, null)
		return

	var state: Dictionary = hub.save_service.create_world(
		"Combat-Cadence-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		81726354
	)
	_check(not state.is_empty(), "desktop combat journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_created_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	var world_ready := await _wait_until(
		func() -> bool:
			return (
				game.world != null
				and bool(game.world.get("is_started"))
				and game.player != null
				and bool(game.player.get("input_enabled"))
			),
		WORLD_READY_TIMEOUT_MS
	)
	_check(world_ready, "real voxel world and player become ready inside the bounded deadline")
	if not world_ready:
		await _finish(game, hub)
		return
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "combat starts with captured mouse")
	_check(hub.get("combat_service") != null, "CombatService is mounted in the production hub")
	var overlay: Node = hub.game_ui.call("get_combat_feedback_overlay")
	_check(overlay != null, "production UI mounts the combat feedback overlay")
	if overlay == null:
		await _finish(game, hub)
		return

	var player: Node3D = game.player
	var world: Node = game.world
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	player.global_position = Vector3(
		player_block.x + 0.5,
		floor_y + 1.05,
		player_block.z + 0.5
	)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await physics_frame
	await process_frame

	hub.inventory.clear()
	hub.inventory.add_item("iron_sword", 1, {"custom_name":"桌面验收铁剑"})
	_check(
		hub.equipment_service.equip_from_inventory(hub.inventory, 0),
		"real inventory equips an iron sword"
	)
	_check(
		str(hub.equipment_service.get_slot("main_hand").get("item_id", "")) == "iron_sword",
		"main-hand equipment owns the sword"
	)
	var durability_before := _main_hand_durability(hub)

	var target_position := Vector3(
		player_block.x + 0.5,
		floor_y + 1.05,
		player_block.z - 3.0
	)
	var target_variant: Variant = hub.creature_spawner.call(
		"spawn_creature", "cow", target_position
	)
	_check(target_variant is Node3D, "real creature spawner creates a combat target")
	if target_variant is not Node3D:
		await _finish(game, hub)
		return
	var target: Node3D = target_variant
	target.set("move_speed", 0.8)
	target.set("_decision_timer", 999.0)
	target.set("_wander_direction", Vector3.ZERO)
	await process_frame
	_check(target.is_physics_processing(), "spawned combat target participates in physics")
	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits(player, target), "center ray resolves the live cow")
	var target_start := target.global_position
	var health_before := float(target.get("health"))

	# Dispatch both real clicks without frame waits. The authoritative combat service
	# must accept one hit and reject the second event from the same input batch.
	_dispatch_click_batch(2)
	var rejected_visible := await _wait_until(
		func() -> bool:
			var last_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
			return str(last_result.get("reason", "")) == "cooldown",
		COMBAT_TRANSITION_TIMEOUT_MS
	)
	_check(rejected_visible, "rapid double click exposes a cooldown rejection")
	var response: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	_check(
		is_equal_approx(float(target.get("health")), health_before - 6.0),
		"rapid real double click applies exactly one iron-sword hit"
	)
	_check(
		_main_hand_durability(hub) == durability_before - 1,
		"rapid double click consumes exactly one weapon durability"
	)
	_check(
		str(response.get("reason", "")) == "cooldown"
		and str(response.get("status", "")) == "rejected",
		"cooldown rejection is exposed as a stable combat result"
	)
	var impact_snapshot: Dictionary = target.call("get_combat_snapshot")
	var initial_impulse := _array_to_vector3(impact_snapshot.get("combat_impulse", []))
	_check(
		Vector2(initial_impulse.x, initial_impulse.z).length() > 2.5,
		"accepted hit reaches the target's independent combat impulse channel"
	)
	_check(target.is_physics_processing(), "accepted hit keeps the target physics awake")
	print(
		"QA COMBAT KNOCKBACK START | position=%s | velocity=%s | impulse=%s | processing=%s"
		% [target_start, target.get("velocity"), initial_impulse, target.is_physics_processing()]
	)
	var feedback: Dictionary = overlay.call("get_snapshot")
	_check(bool(feedback.get("hit_visible", false)), "combat response is visible after the rapid click batch")
	_check(bool(feedback.get("cooldown_visible", false)), "attack recovery indicator is visible")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "combat desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)

	for frame_index in 12:
		await physics_frame
		await process_frame
		if frame_index in [0, 3, 7, 11]:
			var frame_snapshot: Dictionary = target.call("get_combat_snapshot")
			print(
				"QA COMBAT KNOCKBACK FRAME %d | position=%s | velocity=%s | impulse=%s"
				% [
					frame_index + 1,
					target.global_position,
					target.get("velocity"),
					_array_to_vector3(frame_snapshot.get("combat_impulse", [])),
				]
			)
	var target_end := target.global_position
	var knockback_distance := Vector2(
		target_end.x - target_start.x,
		target_end.z - target_start.z
	).length()
	print(
		"QA COMBAT KNOCKBACK END | start=%s | end=%s | distance=%.4f | velocity=%s"
		% [target_start, target_end, knockback_distance, target.get("velocity")]
	)
	_check(knockback_distance > 0.12, "accepted hit produces visible horizontal knockback")

	var inventory_opened := await _tap_key_until_overlay(
		KEY_E,
		hub.game_ui,
		GameUIScript.Overlay.INVENTORY,
		UI_TRANSITION_TIMEOUT_MS
	)
	_check(inventory_opened, "E opens the real character inventory")
	_check(
		not bool(overlay.call("get_snapshot").get("cooldown_visible", true)),
		"blocking UI hides combat feedback"
	)
	var inventory_closed := await _tap_key_until_overlay(
		KEY_E,
		hub.game_ui,
		GameUIScript.Overlay.NONE,
		UI_TRANSITION_TIMEOUT_MS
	)
	_check(inventory_closed, "E closes the inventory")
	_check(bool(player.get("input_enabled")), "closing inventory restores player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing inventory recaptures the mouse")
	if not inventory_closed:
		hub.game_ui.call("close_overlay")
		await process_frame
		await _finish(game, hub)
		return

	# Knockback has already been proven. Re-center and freeze flee movement so the
	# final real click isolates cadence recovery and defeat semantics.
	target.set("move_speed", 0.0)
	target.set("_flee_timer", 0.0)
	if target.has_method("clear_combat_motion"):
		target.call("clear_combat_motion")
	target.global_position = target_start
	await process_frame
	var cooldown_at_wait_start: Dictionary = hub.combat_service.get_cooldown_snapshot()
	var cooldown_timeout_ms := maxi(
		COMBAT_TRANSITION_TIMEOUT_MS,
		ceili((float(cooldown_at_wait_start.get("remaining_seconds", 0.0)) + 2.0) * 1000.0)
	)
	var cooldown_ready := await _wait_until(
		func() -> bool:
			return bool(hub.combat_service.get_cooldown_snapshot().get("ready", false)),
		cooldown_timeout_ms
	)
	_check(cooldown_ready, "real cooldown returns to ready inside its bounded wall-clock deadline")
	if not cooldown_ready:
		await _finish(game, hub)
		return

	await _aim_at(player, target.global_position + Vector3(0.0, 0.65, 0.0))
	_check(_ray_hits(player, target), "center ray reacquires the target after cooldown")
	# The final real click is also dispatched as one press/release batch. Waiting is
	# exclusively state-based, so a slow software renderer cannot deadlock between
	# the press and release events.
	_dispatch_click_batch(1)
	var second_hit_visible := await _wait_until(
		func() -> bool:
			var last_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
			return str(last_result.get("status", "")) == "hit",
		COMBAT_TRANSITION_TIMEOUT_MS
	)
	_check(second_hit_visible, "attack succeeds again after recovery")
	var final_result: Dictionary = overlay.call("get_snapshot").get("last_result", {})
	_check(bool(final_result.get("defeated", false)), "second accepted iron-sword hit defeats the cow")
	_check(
		_main_hand_durability(hub) == durability_before - 2,
		"two accepted hits consume exactly two durability"
	)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "combat never releases the gameplay mouse")
	_check(bool(player.get("input_enabled")), "combat never locks WASD input")
	_check(bool(hub.save_current()), "transient combat cadence coexists with the world save transaction")

	_report = {
		"checks": checks,
		"failures": failures.duplicate(),
		"viewport": [root.size.x, root.size.y],
		"first_result": response.duplicate(true),
		"second_result": final_result.duplicate(true),
		"knockback_distance": knockback_distance,
		"cooldown_at_wait_start": cooldown_at_wait_start.duplicate(true),
		"durability_before": durability_before,
		"durability_after": _main_hand_durability(hub),
		"final_click_dispatch": "single_input_batch",
	}
	_write_report()
	await _finish(game, hub)


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-3, 4):
		for z_offset in range(-8, 3):
			world.call(
				"set_block",
				Vector3i(center_x + x_offset, floor_y, center_z + z_offset),
				"stone"
			)
			for y in range(floor_y + 1, floor_y + 5):
				world.call(
					"set_block",
					Vector3i(center_x + x_offset, y, center_z + z_offset),
					"air"
				)


func _find_floor_y(world: Node, player_block: Vector3i) -> int:
	for offset in range(0, 10):
		var candidate_y := player_block.y - offset - 1
		if str(world.call("get_block", Vector3i(player_block.x, candidate_y, player_block.z))) != "air":
			return candidate_y
	return maxi(1, player_block.y - 1)


func _aim_at(player: Node3D, target_position: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(target_position, Vector3.UP)
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


func _dispatch_click_batch(click_count: int) -> void:
	var center := Vector2(root.size) * 0.5
	for _click in maxi(1, click_count):
		_push_mouse_button(center, true)
		_push_mouse_button(center, false)


func _push_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func _tap_key_until_overlay(
	keycode: Key,
	game_ui: Node,
	expected_overlay: int,
	timeout_ms: int
) -> bool:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release, true)
	return await _wait_until(
		func() -> bool:
			return int(game_ui.call("get_active_overlay")) == expected_overlay,
		timeout_ms
	)


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(1, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _main_hand_durability(hub: Node) -> int:
	if hub == null or hub.get("equipment_service") == null:
		return 0
	var slot: Dictionary = hub.equipment_service.call("get_slot", "main_hand")
	var metadata: Dictionary = slot.get("metadata", {})
	return int(metadata.get("durability", 251))


func _array_to_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"combat cadence desktop screenshot is saved"
	)


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "combat cadence JSON report opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()
		_check(FileAccess.file_exists(_report_path), "combat cadence JSON report is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 20:
				await process_frame
		if not _created_world_id.is_empty() and hub.get("save_service") != null:
			if bool(hub.save_service.call("world_exists", _created_world_id)):
				hub.save_service.call("delete_world", _created_world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("dispose"):
			audio.call("dispose")
			_check(
				bool(audio.call("is_disposed")) and audio.get_child_count() == 0,
				"combat desktop fixture terminally disposes generated audio nodes"
			)
		elif audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA COMBAT CADENCE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA COMBAT CADENCE DESKTOP FAILURE: %s" % failure)
		print(
			"QA COMBAT CADENCE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
