extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://agriculture-runtime-desktop.png"
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
	var coordinator: Node = hub.get("feature_lifecycle") as Node if hub != null else null
	var participant: Node = hub.get("agriculture_runtime_participant") as Node if hub != null else null
	var agriculture: Node = hub.get("agriculture_service") as Node if hub != null else null
	var interaction: Node = hub.get("agriculture_interaction") as Node if hub != null else null
	_check(
		hub != null
		and coordinator != null
		and participant != null
		and agriculture != null
		and interaction != null,
		"production game mounts the agriculture runtime participant and public ports"
	)
	if hub == null or participant == null or agriculture == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Agriculture-Runtime-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		7102026
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop agriculture journey creates a temporary world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production world reaches a bounded ready state")
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	_check(world != null and player != null, "production world and player are available")
	_check(
		coordinator.has_participant(&"agriculture_runtime")
		and agriculture.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"production agriculture is lifecycle-managed and explicitly pausable"
	)
	if world == null or player == null:
		await _finish(game, hub)
		return
	var arena: Dictionary = _build_arena(world, player)
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	var first_soil: Vector3i = arena.get("first_soil", Vector3i.ZERO)
	var second_soil: Vector3i = arena.get("second_soil", Vector3i.ZERO)
	var first_crop := first_soil + Vector3i.UP
	var second_crop := second_soil + Vector3i.UP
	world.call("set_block", first_soil, "grass")
	world.call("set_block", second_soil, "dirt")
	world.call("set_block", first_soil + Vector3i(3, 0, 0), "water")
	world.call("set_block", second_soil + Vector3i(3, 0, 0), "water")
	for _frame in 4:
		await physics_frame
		await process_frame
	var inventory: Node = hub.get("inventory") as Node
	inventory.call("clear")
	inventory.call("add_item", "wooden_hoe", 1)
	inventory.call("add_item", "wheat_seeds", 2)
	inventory.call("add_item", "carrot", 2)
	inventory.call("select_slot", 0)
	await _aim_at(player, world.call("block_to_world", first_soil))
	_check(_focus_hits_position(player, first_soil), "real center focus resolves the first soil block")
	await _right_click_center()
	_check(str(world.call("get_block", first_soil)) == "farmland_wet", "real right click tills and hydrates the first field")
	inventory.call("select_slot", 1)
	await process_frame
	await _aim_at(player, world.call("block_to_world", first_soil))
	await _right_click_center()
	_check(str(world.call("get_block", first_crop)) == "wheat_stage_0", "real right click plants wheat through the production interaction extension")
	inventory.call("select_slot", 0)
	await process_frame
	await _aim_at(player, world.call("block_to_world", second_soil))
	await _right_click_center()
	_check(str(world.call("get_block", second_soil)) == "farmland_wet", "same production interaction tills the second field")
	inventory.call("select_slot", 2)
	await process_frame
	await _aim_at(player, world.call("block_to_world", second_soil))
	await _right_click_center()
	_check(str(world.call("get_block", second_crop)) == "carrot_stage_0", "second field plants a different crop through the same adapter")
	_check(int(agriculture.call("get_runtime_snapshot").get("crop_count", 0)) == 2, "runtime owns both real position-based crop records")

	var elapsed_before_pause := float(
		agriculture.call("get_runtime_snapshot").get("runtime_elapsed_seconds", 0.0)
	)
	await _tap_key(KEY_ESCAPE)
	var game_ui: Node = hub.get("game_ui") as Node
	_check(paused and int(game_ui.call("get_active_overlay")) == 5, "real Esc opens pause and pauses the SceneTree")
	_check(not bool(player.get("input_enabled")), "real pause blocks player input")
	await create_timer(0.75, true, false, true).timeout
	var elapsed_during_pause := float(
		agriculture.call("get_runtime_snapshot").get("runtime_elapsed_seconds", 0.0)
	)
	_check(
		is_equal_approx(elapsed_during_pause, elapsed_before_pause),
		"agriculture runtime elapsed time remains frozen during a real pause"
	)
	await _tap_key(KEY_ESCAPE)
	_check(not paused and int(game_ui.call("get_active_overlay")) == 0, "second Esc resumes gameplay")
	await create_timer(0.75, true, false, true).timeout
	var elapsed_after_resume := float(
		agriculture.call("get_runtime_snapshot").get("runtime_elapsed_seconds", 0.0)
	)
	_check(elapsed_after_resume > elapsed_during_pause, "agriculture runtime resumes after the pause closes")

	var maturity_batches: Array[Dictionary] = []
	participant.connect(
		"maturity_batch_announced",
		func(summary: Dictionary) -> void: maturity_batches.append(summary.duplicate(true))
	)
	agriculture.call("advance_time", 220.0)
	for _frame in 3:
		await process_frame
	_check(str(world.call("get_block", first_crop)) == "wheat_stage_3", "production wheat reaches the mature world stage")
	_check(str(world.call("get_block", second_crop)) == "carrot_stage_3", "production carrot reaches the mature world stage")
	_check(maturity_batches.size() == 1, "two mature fields publish one bounded player notification")
	if not maturity_batches.is_empty():
		_check(int(maturity_batches[0].get("matured_count", 0)) == 2, "desktop maturity batch preserves both fields")
	await _aim_at(player, world.call("block_to_world", first_soil))
	player.call("_update_interaction_focus", true)
	var focus: Dictionary = player.call("get_interaction_focus")
	_check(str(focus.get("block_id", "")) == "wheat_stage_3", "focus proxy presents the mature non-colliding crop")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the mature production fields")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "agriculture evidence uses 1024x576 resolution")
		_save_image(image)
	await _right_click_center()
	_check(str(world.call("get_block", first_crop)) == "wheat_stage_0", "real pointer harvest atomically replants wheat")
	_check(int(inventory.call("count_item", "wheat")) == 1, "real pointer harvest grants wheat")
	await _aim_at(player, world.call("block_to_world", second_soil))
	await _right_click_center()
	_check(str(world.call("get_block", second_crop)) == "carrot_stage_0", "same pointer path atomically replants carrot")
	_check(int(inventory.call("count_item", "carrot")) == 3, "real carrot harvest grants both outputs and preserves the spare item")
	var runtime_snapshot: Dictionary = agriculture.call("get_runtime_snapshot")
	_check(int(runtime_snapshot.get("atomic_harvest_count", 0)) == 2, "production diagnostics count both atomic harvests")
	_check(bool(hub.call("save_current")), "agriculture participant joins the production save transaction")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check((loaded.get("agriculture", {}).get("crops", {}) as Dictionary).size() == 2, "save persists both replanted fields")
	_check(not loaded.get("agriculture", {}).has("last_maturity_summary"), "transient maturity diagnostics never enter the world save")
	var wheat_count := int(inventory.call("count_item", "wheat"))
	var carrot_count := int(inventory.call("count_item", "carrot"))
	var batch_count := maturity_batches.size()
	hub.call("return_to_menu")
	for _frame in 8:
		await process_frame
	_check(int(agriculture.call("get_runtime_snapshot").get("crop_count", -1)) == 0, "return-to-menu clears agriculture runtime state")
	_check(not bool(participant.call("get_lifecycle_snapshot").get("active", true)), "return-to-menu deactivates the agriculture participant")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "complete production reload reaches a bounded ready state")
	_check(int(agriculture.call("get_runtime_snapshot").get("crop_count", 0)) == 2, "reload restores both crop records exactly once")
	_check(int(inventory.call("count_item", "wheat")) == wheat_count, "reload does not duplicate wheat outputs")
	_check(int(inventory.call("count_item", "carrot")) == carrot_count, "reload does not duplicate carrot outputs")
	_check(maturity_batches.size() == batch_count, "reload does not replay maturity feedback")
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 220:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		var participant: Node = hub.get("agriculture_runtime_participant") as Node if is_instance_valid(hub) else null
		if (
			world != null
			and player != null
			and participant != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(participant.call("get_lifecycle_snapshot").get("active", false))
		):
			return true
	return false


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	world.call("force_load_chunk", world.call("block_to_chunk", origin))
	var floor_y := clampi(origin.y - 1, 2, 58)
	for x_offset in range(-5, 7):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 5):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	return {
		"player_position":Vector3(origin.x + 0.5, floor_y + 1.25, origin.z + 0.5),
		"first_soil":Vector3i(origin.x - 1, floor_y + 1, origin.z - 3),
		"second_soil":Vector3i(origin.x + 1, floor_y + 1, origin.z - 3),
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


func _focus_hits_position(player: Node, expected: Vector3i) -> bool:
	var value: Variant = player.call("get_interaction_focus")
	if value is not Dictionary:
		return false
	var focus: Dictionary = value
	return _vector3i(focus.get("hit_position", [])) == expected


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
	root.push_input(event, true)


func _tap_key(keycode: Key) -> void:
	for pressed_value: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed_value
		root.push_input(event, true)
		await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "agriculture runtime screenshot is saved")


func _finish(game: Node, hub: Node) -> void:
	paused = false
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
			"QA AGRICULTURE RUNTIME DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AGRICULTURE RUNTIME DESKTOP FAILURE: %s" % failure)
		print(
			"QA AGRICULTURE RUNTIME DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
