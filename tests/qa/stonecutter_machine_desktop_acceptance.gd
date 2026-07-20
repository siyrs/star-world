extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const OverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://stonecutter-machine-desktop.png"
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
	var participant: Node = hub.get("machine_runtime_participant") if hub != null else null
	var scheduler: Node = hub.get("machine_runtime") if hub != null else null
	var furnace: Node = hub.get("furnace_service") if hub != null else null
	var cutter: Node = hub.get("stonecutter_service") if hub != null else null
	var router: Node = hub.get("machine_interaction_router") if hub != null else null
	_check(
		hub != null
		and participant != null
		and scheduler != null
		and furnace != null
		and cutter != null
		and router != null,
		"production game mounts both Machine Base domains and the interaction router"
	)
	if (
		hub == null
		or participant == null
		or scheduler == null
		or furnace == null
		or cutter == null
		or router == null
	):
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Stonecutter-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		86742015
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop stonecutter journey creates a temporary world")
	game.begin_world_state(state)
	_check(await _wait_for_world_ready(game, hub, _world_id), "production world reaches a bounded ready state")
	var player: CharacterBody3D = game.player
	var world: Node = game.world
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts before stonecutter acceptance")
	_check(scheduler.call("is_active"), "shared machine scheduler is active")
	var runtime_snapshot: Dictionary = scheduler.call("get_snapshot")
	_check(int(runtime_snapshot.get("domain_count", 0)) == 2, "production scheduler owns furnace and stonecutter domains")
	_check(router.call("has_machine_type", &"stonecutter"), "generic router exposes the stonecutter machine type")
	if player == null or world == null:
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_machine_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	var stonecutter_position: Vector3i = arena.get("stonecutter_position", Vector3i.ZERO)
	world.call("set_block", stonecutter_position, "stonecutter")
	for _frame in 4:
		await physics_frame
		await process_frame
	await _aim_at(player, world.call("block_to_world", stonecutter_position))
	_check(_focus_hits_block(player, stonecutter_position), "authoritative center focus resolves the placed stonecutter block")

	hub.inventory.clear()
	hub.inventory.add_item("stone", 2)
	hub.inventory.add_item("raw_iron", 1)
	hub.inventory.add_item("coal", 1)
	await _right_click_center()
	for _frame in 3:
		await process_frame
	_check(hub.game_ui.get_active_overlay() == OverlayIds.STONECUTTER, "real right click opens the stonecutter machine overlay")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "stonecutter overlay isolates gameplay input")
	var panel: Node = hub.game_ui.get_stonecutter_panel()
	_check(panel != null and bool(panel.get("visible")), "production stonecutter panel is visible")
	var machine_id := hub.block_interaction.get_machine_id(
		world,
		stonecutter_position,
		"stonecutter"
	)
	_check(panel != null and panel.get_active_machine_id() == machine_id, "stonecutter panel uses the stable position machine id")
	if panel == null:
		await _finish(game, hub)
		return
	var inventory_buttons: Array = panel.get("_inventory_buttons")
	var input_button: Control = inventory_buttons[0] as Control if not inventory_buttons.is_empty() else null
	_check(input_button != null, "real stonecutter inventory exposes the source slot")
	if input_button != null:
		await _click_control(input_button)
	_check(int(cutter.get_machine_snapshot(machine_id).get("input", {}).get("count", 0)) == 2, "real pointer input transfers both stone items")
	var before: Dictionary = cutter.get_machine_snapshot(machine_id)
	_check(int(before.get("queued_jobs", 0)) == 2, "stonecutter UI source creates two queued jobs")
	_check(is_equal_approx(float(before.get("estimated_total_seconds", 0.0)), 5.0), "stonecutter exposes the five-second total ETA")

	var furnace_id := "furnace@desktop-cross-domain"
	_check(furnace.ensure_machine(furnace_id), "production furnace registers beside the stonecutter")
	_check(furnace.transfer_from_inventory(hub.inventory, 1, furnace.SLOT_INPUT, furnace_id), "furnace receives real iron input")
	_check(furnace.transfer_from_inventory(hub.inventory, 2, furnace.SLOT_FUEL, furnace_id), "furnace receives real fuel input")
	var announced: Array[Dictionary] = []
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void: announced.append(summary.duplicate(true))
	)
	var audio_before := int(participant.call("get_lifecycle_snapshot").get("completion_audio_count", 0))
	var batch: Dictionary = scheduler.call("advance_time", 6.1, true)
	for _frame in 4:
		await process_frame
	_check(int(batch.get("advanced_domain_count", 0)) == 2, "one real scheduler batch advances both machine domains")
	_check(int(batch.get("changed_machine_count", 0)) == 2, "cross-domain batch changes both machine instances")
	_check(announced.size() == 1, "furnace and stonecutter completions create one player-facing summary")
	if not announced.is_empty():
		var summary: Dictionary = announced[0]
		_check(int(summary.get("completed_jobs", 0)) == 3, "completion summary preserves one smelt and two cuts")
		_check(int(summary.get("machine_type_count", 0)) == 2, "completion summary preserves both machine types")
		_check(str(summary.get("message", "")).contains("铁锭") and str(summary.get("message", "")).contains("石台阶"), "completion summary names furnace and stonecutter outputs")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("completion_audio_count", 0)) == audio_before + 1, "cross-domain completion batch consumes one sound budget")
	_check(int(cutter.get_machine_snapshot(machine_id).get("output", {}).get("count", 0)) == 4, "stonecutter produces four real slabs")
	_check(int(furnace.get_machine_snapshot(furnace_id).get("output", {}).get("count", 0)) == 1, "furnace produces one real iron ingot")
	panel.call("refresh")
	var output_button: Button = panel.get("_output_button") as Button
	_check(output_button != null and output_button.text.contains("石台阶") and output_button.text.contains("×4"), "real stonecutter UI displays the complete output")
	_check(not hub.block_interaction.can_break_block(world, stonecutter_position, "stonecutter"), "production removal protection rejects a non-empty stonecutter")

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the stonecutter machine overlay")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "stonecutter evidence uses the 1024x576 product resolution")
		_save_image(image)

	if output_button != null:
		await _click_control(output_button)
	_check(hub.inventory.count_item("stone_slab") == 4, "real pointer collection transfers all cut slabs")
	_check(hub.block_interaction.can_break_block(world, stonecutter_position, "stonecutter"), "empty stonecutter becomes removable")
	await _tap_key(KEY_ESCAPE)
	_check(hub.game_ui.get_active_overlay() == 0, "Esc closes the real stonecutter overlay")
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing stonecutter restores gameplay input")

	_check(bool(hub.save_current()), "stonecutter joins the production world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	_check((loaded.get("machines", {}).get("furnaces", {}) as Dictionary).size() == 1, "save preserves the furnace domain")
	_check((loaded.get("machines", {}).get("stonecutters", {}) as Dictionary).size() == 1, "save preserves the stonecutter domain")
	var slabs_before_reload := int(hub.inventory.count_item("stone_slab"))
	var announced_before_reload := announced.size()
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	_check(not scheduler.call("is_active"), "return-to-menu stops the shared scheduler")
	_check(int(cutter.get_runtime_snapshot().get("machine_count", -1)) == 0, "return-to-menu clears stonecutter runtime state")
	game.begin_world_state(loaded)
	_check(await _wait_for_world_ready(game, hub, _world_id), "full reload reaches a bounded ready state")
	player = game.player
	world = game.world
	_check(cutter.has_machine(machine_id), "full reload restores the stonecutter instance exactly once")
	_check(furnace.has_machine(furnace_id), "full reload restores the furnace instance exactly once")
	_check(hub.inventory.count_item("stone_slab") == slabs_before_reload, "full reload does not duplicate collected stonecutter output")
	_check(announced.size() == announced_before_reload, "reload does not replay transient machine completion feedback")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(int(character.get("machine_runtime", {}).get("domain_count", 0)) == 2, "reloaded diagnostics expose both machine domains")
	_check(int(character.get("machine_interactions", {}).get("machine_type_count", 0)) == 2, "reloaded diagnostics expose both machine interaction types")
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in 180:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
			and bool(hub.get("machine_runtime").call("is_active"))
		):
			return true
	return false


func _build_machine_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	var base := Vector3(float(origin.x) + 0.5, float(floor_y) + 1.25, float(origin.z) + 0.5)
	return {
		"player_position": base,
		"stonecutter_position": Vector3i(origin.x, floor_y + 1, origin.z - 3),
	}


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera")
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


func _focus_hits_block(player: Node, expected: Vector3i) -> bool:
	var focus_value: Variant = player.call("get_interaction_focus")
	if focus_value is not Dictionary:
		return false
	var focus: Dictionary = focus_value
	return str(focus.get("type", "")) == "block" and _vector3i_from(focus.get("hit_position", [])) == expected


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _right_click_center() -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (1 << (int(button) - 1)) if pressed else 0
	event.pressed = pressed
	root.push_input(event)


func _click_control(control: Control) -> void:
	await process_frame
	var target := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = target
	press.global_position = target
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = target
	release.global_position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
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
	_check(error == OK and FileAccess.file_exists(_capture_path), "stonecutter desktop screenshot is saved")


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
		print("QA STONECUTTER MACHINE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA STONECUTTER MACHINE DESKTOP FAILURE: %s" % failure)
		print("QA STONECUTTER MACHINE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
