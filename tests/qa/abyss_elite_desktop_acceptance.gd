extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://abyss-elite-desktop-acceptance.png"
const CLEANUP_FRAMES := 8
const MAX_WAIT_FRAMES := 240

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""
var _death_drops: Dictionary = {}
var _cancel_reason := ""


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
		"Abyss-Elite-%d" % Time.get_ticks_msec(), "abyss_world", 91643057
	)
	_check(not state.is_empty(), "desktop elite journey creates a temporary abyss world")
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
	_check(world != null and bool(world.get("is_started")), "production abyss voxel world starts")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "elite combat starts with captured mouse")
	if player == null or world == null:
		await _finish(game, hub)
		return

	hub.day_night.set_time(21.0)
	_check(str(hub.day_night.get_phase()) == "night", "desktop journey applies the production abyss night condition")
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
	hub.inventory.clear()
	hub.inventory.add_item("diamond_sword", 1, {"custom_name":"深渊验收剑"})
	_check(hub.equipment_service.equip_from_inventory(hub.inventory, 0), "real inventory equips a diamond sword for interruption")
	_check(str(hub.equipment_service.get_slot("main_hand").get("item_id", "")) == "diamond_sword", "production equipment owns the diamond sword")

	hub.creature_spawner.clear_creatures()
	var brute_variant: Variant = hub.creature_spawner.call(
		"spawn_creature",
		"abyss_brute",
		player_start + Vector3(0.0, 0.0, -1.8)
	)
	_check(brute_variant is Node3D, "production spawner creates the abyss elite")
	if brute_variant is not Node3D:
		await _finish(game, hub)
		return
	var brute: Node3D = brute_variant
	hub.creature_spawner.set_active(false)
	brute.set("move_speed", 0.0)
	brute.set("target", player)
	brute.set("_decision_timer", 999.0)
	brute.connect(
		"died",
		func(_species_id: String, drops: Dictionary, _position: Vector3) -> void:
			_death_drops = drops.duplicate(true)
	)
	brute.connect(
		"attack_windup_cancelled",
		func(reason: String, _snapshot: Dictionary) -> void:
			_cancel_reason = reason
	)
	_check(brute.is_in_group("hostile") and brute.is_in_group("elite"), "production elite owns generic hostile and elite identities")
	_check(str(brute.get("display_name")) == "深渊重击者", "production elite exposes its player-facing name")
	_check(is_equal_approx(float(brute.get("danger_weight")), 2.0), "production elite contributes double hostile pressure")
	_check(hub.creature_spawner.get_species_count("abyss_brute") == 1, "spawner diagnostics expose one bounded elite")
	_check(hub.creature_spawner.get_nearby_hostile_count(player.global_position, 18.0) == 1, "generic nearby hostile count includes the elite")
	_check(is_equal_approx(hub.creature_spawner.get_nearby_hostile_pressure(player.global_position, 18.0), 2.0), "nearby hostile pressure distinguishes the elite from one normal body")
	var danger: Dictionary = hub.exploration_danger_service.refresh_now()
	_check(is_equal_approx(float(danger.get("hostile_pressure", 0.0)), 2.0), "production danger service consumes elite pressure")
	_check((danger.get("reasons", []) as Array).has("附近精英敌对生物"), "production danger feedback explains the elite threat")

	await _aim_at(player, brute.global_position + Vector3(0.0, 1.45, 0.0))
	var entered_windup := await _wait_attack_state(brute, "windup")
	_check(entered_windup, "real abyss elite enters its heavy windup before damage")
	var first_attack: Dictionary = brute.call("get_hostile_attack_snapshot")
	var health_before_dodge := float(hub.survival.health)
	_check(is_equal_approx(float(first_attack.get("windup_seconds", 0.0)), 1.35), "real elite uses its longer authoritative windup")
	_check(is_equal_approx(float(first_attack.get("attack_range", 0.0)), 2.2), "real elite exposes its larger warning range")
	_check(bool(first_attack.get("telegraph_visible", false)), "elite red warning telegraph is visible")
	player.call("_update_interaction_focus", true)
	await process_frame
	var feedback: Node = hub.player_experience.call("get_feedback")
	var prompt: Dictionary = feedback.call("get_prompt") if feedback != null else {}
	_check(str(prompt.get("title", "")).contains("精英"), "real focus labels the elite explicitly")
	_check(str(prompt.get("subtitle", "")).contains("精英重击蓄力"), "real prompt explains the heavy windup")
	_check(str(prompt.get("secondary", "")).contains("离开红色预警圈"), "real prompt teaches the dodge response")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the elite telegraph")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "elite evidence uses the 1024x576 product resolution")
		_save_image(image)

	_cancel_reason = ""
	await _hold_key(KEY_S, 34)
	var post_dodge: Dictionary = brute.call("get_hostile_attack_snapshot")
	_check(_cancel_reason == "target_evaded" and str(post_dodge.get("state", "")) != "windup", "real backward movement cancels the elite heavy attack")
	_check(not bool(post_dodge.get("telegraph_visible", true)), "successful elite dodge hides the warning zone")
	_check(is_equal_approx(float(hub.survival.health), health_before_dodge), "successful real dodge prevents all elite damage")
	_check(player.global_position.distance_to(brute.global_position) > float(post_dodge.get("attack_range", 0.0)), "real WASD movement exits the committed hit range")

	await create_timer(1.0).timeout
	player.global_position = player_start
	player.call("reset_motion")
	player.set("_hostile_damage_grace_remaining", 0.0)
	player.set("_hostile_damage_cooldown_remaining", 0.0)
	brute.global_position = player_start + Vector3(0.0, 0.0, -1.8)
	brute.set("target", player)
	await physics_frame
	var second_windup := await _wait_attack_state(brute, "windup")
	_check(second_windup, "elite begins a second telegraphed heavy attack after recovery")
	var health_before_hit := float(hub.survival.health)
	var hit_committed := await _wait_for_health_below(hub.survival, health_before_hit)
	var committed: Dictionary = brute.call("get_hostile_attack_snapshot")
	_check(hit_committed, "remaining inside the elite warning zone commits one real hit")
	_check(is_equal_approx(float(hub.survival.health), health_before_hit - 4.0), "committed elite attack applies exactly four production damage")
	_check(str(committed.get("state", "")) == "cooldown", "successful elite hit enters the slower data-driven cooldown")
	var health_after_hit := float(hub.survival.health)
	for _frame in 45:
		await physics_frame
		await process_frame
	_check(is_equal_approx(float(hub.survival.health), health_after_hit), "elite cooldown prevents immediate duplicate damage")

	# Start one final heavy windup, then use a real mouse click to interrupt and defeat it.
	brute.set("_attack_timer", 0.0)
	brute.call("_set_attack_state", "idle")
	brute.global_position = player_start + Vector3(0.0, 0.0, -1.8)
	brute.set("target", player)
	brute.set("health", 7.0)
	player.global_position = player_start
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	await _aim_at(player, brute.global_position + Vector3(0.0, 1.45, 0.0))
	_check(await _wait_attack_state(brute, "windup"), "elite starts a final windup for real interruption")
	_cancel_reason = ""
	await _left_click_center()
	for _frame in 8:
		await physics_frame
		await process_frame
	_check(_cancel_reason == "interrupted", "real player attack interrupts the elite windup")
	_check(int(_death_drops.get("abyss_cinder", 0)) == 1, "real elite death produces exactly one useful abyss cinder")
	_check(int(_death_drops.get("rotten_flesh", 0)) >= 1, "elite death retains the normal hostile material route")
	_check(_has_pickup_item("abyss_cinder"), "production death creates a real abyss cinder pickup")
	var collected_cinder := await _walk_forward_until_item(
		hub.inventory,
		"abyss_cinder",
		1,
		72
	)
	_check(collected_cinder, "real W movement crosses the pickup and transfers the elite material")
	_check(hub.inventory.count_item("abyss_cinder") == 1, "elite material is collected exactly once")
	_check(bool(player.get("input_enabled")), "elite combat never disables player input")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "elite combat never releases the gameplay mouse")

	_check(bool(hub.save_current()), "elite drop joins the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check(not loaded.has("hostile_attack") and not loaded.has("elite_ecology"), "transient elite combat state does not expand the save schema")
	var cinder_before_reload := int(hub.inventory.count_item("abyss_cinder"))
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	game.begin_world_state(loaded)
	for _frame in 10:
		await process_frame
	await physics_frame
	hub = game.service_hub
	_check(str(game.current_profile_id) == "abyss_world", "full reload preserves the abyss map")
	_check(hub.inventory.count_item("abyss_cinder") == cinder_before_reload, "full world reload preserves the elite drop exactly once")
	_check(hub.creature_spawner.get_species_count("abyss_brute") == 0, "transient elite instances are not serialized as persistent entities")
	await _finish(game, hub)


func _wait_attack_state(creature: Node, expected: String) -> bool:
	for _frame in MAX_WAIT_FRAMES:
		if not is_instance_valid(creature):
			return false
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


func _walk_forward_until_item(
	inventory: Node,
	item_id: String,
	expected: int,
	max_physics_frames: int
) -> bool:
	var press := InputEventKey.new()
	press.keycode = KEY_W
	press.physical_keycode = KEY_W
	press.pressed = true
	root.push_input(press)
	var collected := false
	for _frame in maxi(1, max_physics_frames):
		await physics_frame
		await process_frame
		if int(inventory.call("count_item", item_id)) >= expected:
			collected = true
			break
	var release := InputEventKey.new()
	release.keycode = KEY_W
	release.physical_keycode = KEY_W
	release.pressed = false
	root.push_input(release)
	await physics_frame
	await process_frame
	return collected


func _has_pickup_item(item_id: String) -> bool:
	for pickup: Node in root.get_tree().get_nodes_in_group("pickups"):
		if str(pickup.get("item_id")) == item_id and int(pickup.get("item_count")) > 0:
			return true
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
	for x_offset in range(-5, 6):
		for z_offset in range(-10, 7):
			world.call(
				"set_block",
				Vector3i(center_x + x_offset, floor_y, center_z + z_offset),
				"stone"
			)
			for y in range(floor_y + 1, floor_y + 6):
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
	_check(error == OK and FileAccess.file_exists(_capture_path), "abyss elite desktop screenshot is saved")


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
		print("QA ABYSS ELITE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA ABYSS ELITE DESKTOP FAILURE: %s" % failure)
		print("QA ABYSS ELITE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
