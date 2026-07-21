extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const AutomationPolicy = preload("res://src/machine/machine_automation_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://machine-automation-desktop.png"
const CLEANUP_FRAMES := 8
const CONTAINER_OVERLAY := 4

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
	for _frame in 5:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	var scheduler: Node = hub.get("machine_runtime") as Node if hub != null else null
	var automation: Node = hub.get("machine_automation_service") as Node if hub != null else null
	var furnace: Node = hub.get("furnace_service") as Node if hub != null else null
	var cutter: Node = hub.get("stonecutter_service") as Node if hub != null else null
	var storage: Node = hub.get("container_storage") as Node if hub != null else null
	_check(
		hub != null and scheduler != null and automation != null
		and furnace != null and cutter != null and storage != null,
		"production game mounts shared machines, chest storage and bounded automation"
	)
	if hub == null or scheduler == null or automation == null or furnace == null or cutter == null or storage == null:
		await _finish(game, hub)
		return

	var state: Dictionary = hub.get("save_service").create_world(
		"Machine-Automation-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		93017521
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "automation journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production world reaches a bounded ready state")
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	_check(player != null and bool(player.get("input_enabled")), "production player starts in gameplay context")
	_check(world != null and bool(world.get("is_started")), "production voxel world starts")
	_check(bool(scheduler.call("is_active")), "shared machine scheduler starts active")
	var runtime_before: Dictionary = scheduler.call("get_snapshot")
	_check(int(runtime_before.get("domain_count", 0)) == 3, "scheduler owns furnace, cutter and one bounded automation domain")
	if player == null or world == null:
		await _finish(game, hub)
		return

	scheduler.call("deactivate")
	var arena: Dictionary = _build_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	var furnace_position: Vector3i = arena.get("furnace_position", Vector3i.ZERO)
	var cutter_position: Vector3i = arena.get("cutter_position", Vector3i.ZERO)
	_configure_machine_stack(world, storage, furnace_position, "furnace")
	_configure_machine_stack(world, storage, cutter_position, "stonecutter")
	for _frame in 4:
		await physics_frame
		await process_frame
	var block_interaction: Node = hub.get("block_interaction") as Node
	var furnace_id := str(block_interaction.call(
		"get_machine_id", world, furnace_position, "furnace"
	))
	var cutter_id := str(block_interaction.call(
		"get_machine_id", world, cutter_position, "stonecutter"
	))
	_check(furnace_id == _machine_id("furnace", furnace_position), "production furnace uses the stable position id")
	_check(cutter_id == _machine_id("stonecutter", cutter_position), "production cutter uses the stable position id")
	_check(bool(furnace.call("open_machine", furnace_id)), "physical furnace creates its production runtime state")
	furnace.call("close_machine")
	_check(bool(cutter.call("open_machine", cutter_id)), "physical cutter creates its production runtime state")
	cutter.call("close_machine")

	var furnace_input := AutomationPolicy.container_id(
		AutomationPolicy.input_position(furnace_position)
	)
	var furnace_output := AutomationPolicy.container_id(
		AutomationPolicy.output_position(furnace_position)
	)
	var cutter_input := AutomationPolicy.container_id(
		AutomationPolicy.input_position(cutter_position)
	)
	var cutter_output := AutomationPolicy.container_id(
		AutomationPolicy.output_position(cutter_position)
	)
	storage.call("add_item", furnace_input, "raw_iron", 2)
	storage.call("add_item", furnace_input, "coal", 1)
	storage.call("add_item", cutter_input, "stone", 2)
	storage.call("add_item", cutter_input, "apple", 1)
	var activations: Array[Dictionary] = []
	automation.connect(
		"automation_machine_activated",
		func(summary: Dictionary) -> void: activations.append(summary.duplicate(true))
	)

	var supply_batch: Dictionary = scheduler.call("advance_time", 0.5, true)
	var supply: Dictionary = supply_batch.get("domain_summaries", {}).get("automation", {})
	_check(int(supply.get("input_items", 0)) == 5, "one real scheduler cycle supplies both adjacent machines")
	_check(int((furnace.call("get_slot", furnace_id, "input") as Dictionary).get("count", 0)) == 2, "upper furnace chest supplies exact ore count")
	_check(int((furnace.call("get_slot", furnace_id, "fuel") as Dictionary).get("count", 0)) == 1, "upper furnace chest supplies valid fuel")
	_check(int((cutter.call("get_slot", cutter_id, "input") as Dictionary).get("count", 0)) == 2, "upper cutter chest supplies exact stone count")
	_check(_count_container_item(storage, cutter_input, "apple") == 1, "unsupported adjacent item remains in its chest")
	_check(activations.size() == 2, "each machine explains adjacent automation only on first real transfer")

	var production_batch: Dictionary = scheduler.call("advance_time", 12.1, true)
	var production: Dictionary = production_batch.get("domain_summaries", {}).get("automation", {})
	_check(int(production.get("output_items", 0)) == 6, "same scheduler batch collects all produced items")
	_check(_count_container_item(storage, furnace_output, "iron_ingot") == 2, "lower furnace chest receives both ingots")
	_check(_count_container_item(storage, cutter_output, "stone_slab") == 4, "lower cutter chest receives all slabs")
	_check((furnace.call("get_slot", furnace_id, "output") as Dictionary).is_empty(), "committed automatic collection clears furnace output")
	_check((cutter.call("get_slot", cutter_id, "output") as Dictionary).is_empty(), "committed automatic collection clears cutter output")
	var automation_snapshot: Dictionary = automation.call("get_runtime_snapshot")
	_check(int(automation_snapshot.get("max_items_in_cycle", 0)) <= 64, "production diagnostics retain the item budget")
	_check(int(automation_snapshot.get("tracked_machine_count", 0)) == 2, "event cache tracks only the two physical machines")

	var cutter_output_position := AutomationPolicy.output_position(cutter_position)
	await _aim_at(player, world.call("block_to_world", cutter_output_position))
	_check(_focus_hits_block(player, cutter_output_position), "real center focus resolves the lower output chest")
	await _right_click_center()
	for _frame in 3:
		await process_frame
	var game_ui: Node = hub.get("game_ui") as Node
	var panel: Node = game_ui.get("container_panel") as Node
	_check(int(game_ui.call("get_active_overlay")) == CONTAINER_OVERLAY, "real right click opens the production container overlay")
	_check(panel != null and bool(panel.get("visible")), "production chest panel is visible")
	_check(panel != null and str(panel.call("get_active_container_id")) == cutter_output, "container UI opens the same stable output chest")
	_check(not bool(player.get("input_enabled")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "container overlay isolates gameplay input")
	if panel != null:
		panel.call("refresh")
		var buttons: Array = panel.get("_container_buttons")
		var first_button: Button = buttons[0] as Button if not buttons.is_empty() else null
		_check(first_button != null and first_button.text.contains("石台阶") and first_button.text.contains("×4"), "real chest UI displays automatically collected slabs")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the automated output chest")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "automation evidence uses 1024x576 resolution")
		_save_image(image)
	await _tap_key(KEY_ESCAPE)
	_check(int(game_ui.call("get_active_overlay")) == 0, "Esc closes the automated chest overlay")
	_check(bool(player.get("input_enabled")), "closing chest UI restores gameplay input")

	scheduler.call("activate")
	_check(bool(hub.call("save_current")), "machines and adjacent chests join one production save transaction")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var saved_containers: Dictionary = loaded.get("containers", {}).get("containers", {})
	_check(saved_containers.has(furnace_input) and saved_containers.has(furnace_output), "save preserves both furnace-adjacent chests")
	_check(saved_containers.has(cutter_input) and saved_containers.has(cutter_output), "save preserves both cutter-adjacent chests")
	_check(not loaded.has("automation_jobs"), "world root excludes transient automation jobs")
	_check(not loaded.get("machines", {}).has("automation"), "machine schema excludes automation cursor and cache state")
	var iron_before_reload := _count_container_item(storage, furnace_output, "iron_ingot")
	var slabs_before_reload := _count_container_item(storage, cutter_output, "stone_slab")
	hub.call("return_to_menu")
	for _frame in 8:
		await process_frame
	_check(not bool(scheduler.call("is_active")), "return-to-menu stops shared automation scheduling")
	_check(not bool(automation.call("get_runtime_snapshot").get("active", true)), "return-to-menu releases the old world from automation")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "complete reload reaches a bounded ready state")
	_check(bool(furnace.call("has_machine", furnace_id)), "reload restores furnace once")
	_check(bool(cutter.call("has_machine", cutter_id)), "reload restores stonecutter once")
	_check(_count_container_item(storage, furnace_output, "iron_ingot") == iron_before_reload, "reload does not duplicate automated ingots")
	_check(_count_container_item(storage, cutter_output, "stone_slab") == slabs_before_reload, "reload does not duplicate automated slabs")
	_check(_count_container_item(storage, cutter_input, "apple") == 1, "reload preserves rejected input exactly once")
	var reloaded_automation: Dictionary = automation.call("get_runtime_snapshot")
	_check(int(reloaded_automation.get("tracked_machine_count", 0)) == 2, "reload rebuilds automation candidates once from restored machines")
	_check(int(reloaded_automation.get("total_input_items", -1)) == 0 and int(reloaded_automation.get("total_output_items", -1)) == 0, "reload does not replay transient transfer history")
	var character: Dictionary = hub.call("get_character_snapshot")
	_check(character.get("machine_runtime", {}).get("domains", {}).has("automation"), "character diagnostics expose bounded automation after reload")
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 180:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		var runtime: Node = hub.get("machine_runtime") as Node if is_instance_valid(hub) else null
		if (
			world != null and player != null and runtime != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(runtime.call("is_active"))
		):
			return true
	return false


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 56)
	for x_offset in range(-7, 8):
		for z_offset in range(-8, 4):
			var floor_position := Vector3i(
				origin.x + x_offset, floor_y, origin.z + z_offset
			)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 6):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	return {
		"player_position": Vector3(origin.x + 0.5, floor_y + 1.25, origin.z + 0.5),
		"furnace_position": Vector3i(origin.x - 2, floor_y + 2, origin.z - 4),
		"cutter_position": Vector3i(origin.x + 2, floor_y + 2, origin.z - 4),
	}


func _configure_machine_stack(
	world: Node,
	storage: Node,
	machine_position: Vector3i,
	machine_block_id: String
) -> void:
	var input_position := AutomationPolicy.input_position(machine_position)
	var output_position := AutomationPolicy.output_position(machine_position)
	world.call("set_block", output_position, "chest")
	world.call("set_block", machine_position, machine_block_id)
	world.call("set_block", input_position, "chest")
	storage.call(
		"ensure_container",
		AutomationPolicy.container_id(input_position),
		"chest",
		AutomationPolicy.CONTAINER_SLOT_COUNT
	)
	storage.call(
		"ensure_container",
		AutomationPolicy.container_id(output_position),
		"chest",
		AutomationPolicy.CONTAINER_SLOT_COUNT
	)


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
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i(focus.get("hit_position", [])) == expected
	)


func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_RIGHT
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func _tap_key(keycode: Key) -> void:
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
	await process_frame
	await process_frame


func _machine_id(machine_type: String, position: Vector3i) -> String:
	return "%s@%d,%d,%d" % [machine_type, position.x, position.y, position.z]


func _count_container_item(storage: Node, container_id: String, item_id: String) -> int:
	var total := 0
	for index in int(storage.call("get_slot_count", container_id)):
		var slot: Dictionary = storage.call("get_slot", container_id, index)
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "machine automation screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null:
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.get("save_service").delete_world(_world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA MACHINE AUTOMATION DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE AUTOMATION DESKTOP FAILURE: %s" % failure)
		print(
			"QA MACHINE AUTOMATION DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
