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
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	var participant: Node = hub.get("machine_runtime_participant") as Node if hub != null else null
	var scheduler: Node = hub.get("machine_runtime") as Node if hub != null else null
	var furnace: Node = hub.get("furnace_service") as Node if hub != null else null
	var cutter: Node = hub.get("stonecutter_service") as Node if hub != null else null
	var router: Node = hub.get("machine_interaction_router") as Node if hub != null else null
	_check(
		hub != null and participant != null and scheduler != null
		and furnace != null and cutter != null and router != null,
		"production game mounts both machine domains and the generic router"
	)
	if hub == null or participant == null or scheduler == null or furnace == null or cutter == null or router == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Stonecutter-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		86742015
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop stonecutter journey creates a temporary world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production world reaches a bounded ready state")
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(bool(scheduler.call("is_active")), "shared machine scheduler is active")
	_check(int((scheduler.call("get_snapshot") as Dictionary).get("domain_count", 0)) == 2, "production scheduler owns two machine domains")
	_check(bool(router.call("has_machine_type", &"stonecutter")), "generic router exposes stonecutter")
	if player == null or world == null:
		await _finish(game, hub)
		return

	var arena: Dictionary = _build_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	var cutter_position: Vector3i = arena.get("machine_position", Vector3i.ZERO)
	world.call("set_block", cutter_position, "stonecutter")
	for _frame in 4:
		await physics_frame
		await process_frame
	await _aim_at(player, world.call("block_to_world", cutter_position))
	_check(_focus_hits_block(player, cutter_position), "real center focus resolves the stonecutter block")

	var inventory: Node = hub.get("inventory") as Node
	inventory.call("clear")
	inventory.call("add_item", "stone", 2)
	inventory.call("add_item", "raw_iron", 1)
	inventory.call("add_item", "coal", 1)
	await _right_click_center()
	for _frame in 3:
		await process_frame
	var game_ui: Node = hub.get("game_ui") as Node
	_check(int(game_ui.call("get_active_overlay")) == OverlayIds.STONECUTTER, "real right click opens the stonecutter overlay")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "machine overlay isolates gameplay input")
	var panel: Node = game_ui.call("get_stonecutter_panel") as Node
	_check(panel != null and bool(panel.get("visible")), "production stonecutter panel is visible")
	var machine_id: String = str(hub.get("block_interaction").call(
		"get_machine_id", world, cutter_position, "stonecutter"
	))
	_check(panel != null and str(panel.call("get_active_machine_id")) == machine_id, "panel uses the stable position machine id")
	if panel == null:
		await _finish(game, hub)
		return
	var buttons: Array = panel.get("_inventory_buttons")
	var source_button: Control = buttons[0] as Control if not buttons.is_empty() else null
	_check(source_button != null, "stonecutter panel exposes the real source inventory slot")
	if source_button != null:
		await _click_control(source_button)
	var cutter_before: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(int(cutter_before.get("input", {}).get("count", 0)) == 2, "real pointer input transfers both stone items")
	_check(int(cutter_before.get("queued_jobs", 0)) == 2, "stonecutter exposes two queued jobs")
	var live_eta := float(cutter_before.get("estimated_total_seconds", 0.0))
	_check(live_eta > 4.0 and live_eta <= 5.0, "live stonecutter ETA reflects a two-job queue after bounded scheduler progress")

	var furnace_id := "furnace@desktop-cross-domain"
	_check(bool(furnace.call("ensure_machine", furnace_id)), "production furnace registers beside the stonecutter")
	_check(bool(furnace.call("transfer_from_inventory", inventory, 1, "input", furnace_id)), "furnace receives real iron input")
	_check(bool(furnace.call("transfer_from_inventory", inventory, 2, "fuel", furnace_id)), "furnace receives real fuel input")
	var announcements: Array[Dictionary] = []
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void: announcements.append(summary.duplicate(true))
	)
	var audio_before := int((participant.call("get_lifecycle_snapshot") as Dictionary).get("completion_audio_count", 0))
	var batch: Dictionary = scheduler.call("advance_time", 6.1, true)
	for _frame in 4:
		await process_frame
	_check(int(batch.get("advanced_domain_count", 0)) == 2, "one scheduler batch advances both domains")
	_check(int(batch.get("changed_machine_count", 0)) == 2, "cross-domain batch changes both machines")
	_check(announcements.size() == 1, "cross-domain completions create one player summary")
	if not announcements.is_empty():
		var summary: Dictionary = announcements[0]
		_check(int(summary.get("completed_jobs", 0)) == 3, "summary preserves one smelt and two cuts")
		_check(int(summary.get("machine_type_count", 0)) == 2, "summary preserves both machine types")
		_check(str(summary.get("message", "")).contains("铁锭") and str(summary.get("message", "")).contains("石台阶"), "summary names both real outputs")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("completion_audio_count", 0)) == audio_before + 1, "cross-domain completion consumes one sound budget")
	_check(int((cutter.call("get_machine_snapshot", machine_id) as Dictionary).get("output", {}).get("count", 0)) == 4, "stonecutter produces four slabs")
	_check(int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1, "furnace produces one iron ingot")
	panel.call("refresh")
	var output_button: Button = panel.get("_output_button") as Button
	_check(output_button != null and output_button.text.contains("石台阶") and output_button.text.contains("×4"), "real UI displays all cut output")
	var block_interaction: Node = hub.get("block_interaction") as Node
	_check(not bool(block_interaction.call("can_break_block", world, cutter_position, "stonecutter")), "non-empty stonecutter is protected from removal")

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the machine overlay")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "stonecutter evidence uses 1024x576 resolution")
		_save_image(image)
	if output_button != null:
		await _click_control(output_button)
	_check(int(inventory.call("count_item", "stone_slab")) == 4, "real pointer collection transfers all slabs")
	_check(bool(block_interaction.call("can_break_block", world, cutter_position, "stonecutter")), "empty stonecutter becomes removable")
	await _tap_key(KEY_ESCAPE)
	_check(int(game_ui.call("get_active_overlay")) == 0, "Esc closes the stonecutter overlay")
	_check(bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing machine UI restores gameplay input")

	_check(bool(hub.call("save_current")), "stonecutter joins the production save transaction")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check((loaded.get("machines", {}).get("furnaces", {}) as Dictionary).size() == 1, "save preserves furnace state")
	_check((loaded.get("machines", {}).get("stonecutters", {}) as Dictionary).size() == 1, "save preserves stonecutter state")
	var slab_count := int(inventory.call("count_item", "stone_slab"))
	var announcement_count := announcements.size()
	hub.call("return_to_menu")
	for _frame in 8:
		await process_frame
	_check(not bool(scheduler.call("is_active")), "return-to-menu stops shared scheduling")
	_check(int((cutter.call("get_runtime_snapshot") as Dictionary).get("machine_count", -1)) == 0, "return-to-menu clears stonecutter runtime state")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "complete reload reaches a bounded ready state")
	_check(bool(cutter.call("has_machine", machine_id)), "reload restores stonecutter exactly once")
	_check(bool(furnace.call("has_machine", furnace_id)), "reload restores furnace exactly once")
	_check(int(inventory.call("count_item", "stone_slab")) == slab_count, "reload does not duplicate collected output")
	_check(announcements.size() == announcement_count, "reload does not replay completion feedback")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(int(character.get("machine_runtime", {}).get("domain_count", 0)) == 2, "reload diagnostics expose both domains")
	_check(int(character.get("machine_interactions", {}).get("machine_type_count", 0)) == 2, "reload diagnostics expose both interaction types")
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 180:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if world != null and player != null and bool(world.get("is_started")) and str(hub.get("current_world_id")) == _world_id and bool(hub.get("machine_runtime").call("is_active")):
			return true
	return false


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	return {
		"player_position": Vector3(origin.x + 0.5, floor_y + 1.25, origin.z + 0.5),
		"machine_position": Vector3i(origin.x, floor_y + 1, origin.z - 3),
	}


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame


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


func _focus_hits_block(player: Node, expected: Vector3i) -> bool:
	var value: Variant = player.call("get_interaction_focus")
	if value is not Dictionary:
		return false
	var focus: Dictionary = value
	return str(focus.get("type", "")) == "block" and _vector3i(focus.get("hit_position", [])) == expected


func _vector3i(value: Variant) -> Vector3i:
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
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame


func _tap_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event)
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
			hub.get("save_service").delete_world(_world_id)
		if hub.get("audio_service") != null and hub.get("audio_service").has_method("shutdown"):
			hub.get("audio_service").shutdown()
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
