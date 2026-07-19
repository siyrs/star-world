extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://hostile-attack-windup-desktop.png"
const CLEANUP_FRAMES := 8
const MAX_WAIT_FRAMES := 180

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
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Hostile-Windup-%d" % Time.get_ticks_msec(), "star_continent", 73198452
	)
	_check(not state.is_empty(), "desktop windup journey creates a temporary world")
	if state.is_empty():
		await _finish(game, hub)
		return
	_world_id = str(state.get("metadata", {}).get("id", ""))
	game.begin_world_state(state)
	for _frame in 10:
		await process_frame
	await physics_frame
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "desktop combat keeps the mouse captured")
	if player == null or world == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := _find_floor_y(world, player_block)
	_prepare_arena(world, player_block.x, player_block.z, floor_y)
	var player_start := Vector3(player_block.x + 0.5, floor_y + 1.05, player_block.z + 0.5)
	player.global_position = player_start
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.set("_hostile_damage_grace_remaining", 0.0)
	player.set("_hostile_damage_cooldown_remaining", 0.0)
	hub.survival.health = hub.survival.max_health
	hub.survival.hunger = 10.0
	hub.creature_spawner.clear_creatures()
	var zombie_variant: Variant = hub.creature_spawner.call(
		"spawn_creature",
		"zombie",
		player_start + Vector3(0.0, 0.0, -1.35)
	)
	_check(zombie_variant is Node3D, "production spawner creates a live zombie attacker")
	if zombie_variant is not Node3D:
		await _finish(game, hub)
		return
	var zombie: Node3D = zombie_variant
	hub.creature_spawner.set_active(false)
	zombie.set("move_speed", 0.0)
	zombie.set("target", player)
	zombie.set("_decision_timer", 999.0)
	await _aim_at(player, zombie.global_position + Vector3(0.0, 1.2, 0.0))
	var entered_windup := await _wait_attack_state(zombie, "windup")
	_check(entered_windup, "real hostile AI enters windup before dealing damage")
	var windup_snapshot: Dictionary = zombie.call("get_hostile_attack_snapshot")
	var health_before_dodge := float(hub.survival.health)
	_check(bool(windup_snapshot.get("telegraph_visible", false)), "production red warning telegraph is visible")
	_check(float(windup_snapshot.get("windup_remaining", 0.0)) > 0.0, "windup exposes positive remaining time")
	player.call("_update_interaction_focus", true)
	await process_frame
	var feedback: Node = hub.player_experience.call("get_feedback")
	var prompt: Dictionary = feedback.call("get_prompt") if feedback != null else {}
	_check(str(prompt.get("subtitle", "")).contains("正在蓄力"), "real interaction prompt warns about the incoming attack")
	_check(str(prompt.get("secondary", "")).contains("离开红色预警圈"), "real prompt teaches the dodge response")
	_check(str(prompt.get("tone", "")) == "error", "windup warning uses urgent HUD presentation")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the hostile telegraph")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "hostile telegraph evidence uses the 1024x576 product resolution")
		_save_image(image)

	# Drive the real movement input backwards until the player exits the warning ring.
	await _hold_key(KEY_S, 28)
	var cancelled := await _wait_attack_state(zombie, "cooldown")
	var cancelled_snapshot: Dictionary = zombie.call("get_hostile_attack_snapshot")
	_check(cancelled, "real backward movement cancels the hostile windup")
	_check(str(cancelled_snapshot.get("last_cancel_reason", "")) == "target_evaded", "dodge cancellation exposes a stable reason")
	_check(not bool(cancelled_snapshot.get("telegraph_visible", true)), "successful dodge hides the warning ring")
	_check(is_equal_approx(float(hub.survival.health), health_before_dodge), "successful real dodge prevents all player damage")
	_check(player.global_position.distance_to(zombie.global_position) > float(cancelled_snapshot.get("attack_range", 0.0)), "real WASD movement leaves the committed hit range")

	# Re-enter after the short cancel recovery and remain in range for one committed hit.
	await create_timer(0.75).timeout
	player.global_position = player_start
	player.call("reset_motion")
	player.set("_hostile_damage_grace_remaining", 0.0)
	player.set("_hostile_damage_cooldown_remaining", 0.0)
	zombie.global_position = player_start + Vector3(0.0, 0.0, -1.35)
	zombie.set("target", player)
	await physics_frame
	var second_windup := await _wait_attack_state(zombie, "windup")
	_check(second_windup, "hostile begins a second telegraphed attack after recovery")
	var health_before_hit := float(hub.survival.health)
	var hit_committed := await _wait_for_health_below(hub.survival, health_before_hit)
	var hit_snapshot: Dictionary = zombie.call("get_hostile_attack_snapshot")
	_check(hit_committed, "remaining inside the warning ring commits one real hit")
	_check(is_equal_approx(float(hub.survival.health), health_before_hit - 1.0), "committed zombie attack applies the production one-point damage")
	_check(str(hit_snapshot.get("state", "")) == "cooldown", "successful hit enters data-driven cooldown")
	_check(float(hit_snapshot.get("cooldown_remaining", 0.0)) > 0.0, "cooldown remains externally diagnosable")
	var health_after_hit := float(hub.survival.health)
	for _frame in 45:
		await physics_frame
		await process_frame
	_check(is_equal_approx(float(hub.survival.health), health_after_hit), "cooldown prevents an immediate duplicate hostile hit")
	_check(bool(player.get("input_enabled")), "hostile telegraph and dodge never disable player control")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "hostile combat never releases the gameplay mouse")
	_check(bool(hub.save_current()), "transient hostile windup coexists with the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(not loaded.has("hostile_attack"), "transient hostile attack state does not expand the world save schema")
	await _finish(game, hub)


func _wait_attack_state(creature: Node, expected: String) -> bool:
	for _frame in MAX_WAIT_FRAMES:
		var snapshot: Dictionary = creature.call("get_hostile_attack_snapshot")
		if str(snapshot.get("state", "")) == expected:
			return true
		await physics_frame
		await process_frame
	return false


func _wait_for_health_below(survival: Node, previous: float) -> bool:
	for _frame in MAX_WAIT_FRAMES:
		if float(survival.get("health")) < previous:
			return true
		await physics_frame
		await process_frame
	return false


func _hold_key(keycode: Key, physics_frames: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	root.push_input(press)
	for _frame in physics_frames:
		await physics_frame
		await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	root.push_input(release)
	await physics_frame
	await process_frame


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


func _prepare_arena(world: Node, center_x: int, center_z: int, floor_y: int) -> void:
	for x_offset in range(-4, 5):
		for z_offset in range(-8, 6):
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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "hostile windup desktop screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
			hub.audio_service.shutdown()
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA HOSTILE ATTACK WINDUP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HOSTILE ATTACK WINDUP DESKTOP FAILURE: %s" % failure)
		print("QA HOSTILE ATTACK WINDUP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
