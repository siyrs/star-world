extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://building-mining-closed-loop-desktop.png"
const CLEANUP_FRAMES := 10
const MAX_HARVEST_FRAMES := 360
const MAX_TEST_SECONDS := 600.0
const AIM_TIMEOUT_FRAMES := 90
const AIM_HEIGHT_OFFSETS: Array[float] = [0.28, 0.12, 0.0, -0.12]

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""
var _finished := false
var _stage := "initialize"


func _initialize() -> void:
	var watchdog := create_timer(MAX_TEST_SECONDS)
	watchdog.timeout.connect(_on_watchdog_timeout)
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
		"Building-Mining-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		61974231,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production building world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var harvest: Node = player.get("harvest_service") as Node
	_check(
		player != null and world != null and inventory != null and harvest != null,
		"production player, world, inventory and harvest service are mounted",
	)
	if player == null or world == null or inventory == null or harvest == null:
		await _finish(game, hub)
		return

	var rejections: Array[Dictionary] = []
	harvest.harvest_rejected.connect(
		func(reason: String, snapshot: Dictionary) -> void:
			rejections.append({"reason": reason, "snapshot": snapshot.duplicate(true)})
	)
	var arena := _build_arena(world, player)
	var failure_anchor: Vector3i = arena["failure_anchor"]
	var failure_target: Vector3i = arena["failure_target"]
	var anchors: Array = arena["anchors"]
	var structure: Array = arena["structure"]
	var mining_target: Vector3i = arena["mining_target"]

	_stage = "placement_collision_failure"
	player.global_position = arena["failure_player_position"]
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	inventory.clear()
	inventory.call("add_item", "oak_planks", 4)
	inventory.call("select_slot", _find_item_slot(inventory, "oak_planks"))
	var failure_inventory: Dictionary = inventory.call("serialize")
	var failure_focus_ready := await _aim_at_block(
		player, world, failure_anchor, "stone"
	)
	_check(failure_focus_ready, "centre ray resolves the placement-failure anchor")
	if not failure_focus_ready:
		await _finish(game, hub)
		return
	await _right_click_center()
	_check(str(world.call("get_block", failure_target)) == "air", "placement cannot create a block inside the live player capsule")
	_check(inventory.call("serialize") == failure_inventory, "rejected placement cannot consume material")

	_stage = "three_block_structure"
	for index in anchors.size():
		var anchor: Vector3i = anchors[index]
		var expected: Vector3i = structure[index]
		# Align the production player with each face before the real right-click.
		# This prevents a previously placed neighbour from becoming the nearer
		# target while still exercising the exact player focus and placement path.
		player.global_position = Vector3(
			float(anchor.x) + 0.5,
			float(arena["floor_y"]) + 1.05,
			float(arena["build_player_z"]),
		)
		player.call("reset_motion")
		player.velocity.y = -1.0
		await _settle_player(player, 120)
		var anchor_ready := await _aim_at_block(player, world, anchor, "stone")
		_check(anchor_ready, "structure anchor %d is targeted by the production ray" % index)
		if not anchor_ready:
			await _finish(game, hub)
			return
		await _right_click_center()
		_check(str(world.call("get_block", expected)) == "planks", "real right click places structure block %d" % index)
	_check(inventory.count_item("oak_planks") == 1, "three successful placements consume exactly three planks")

	_stage = "full_inventory_mining_failure"
	player.global_position = arena["mining_player_position"]
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	_fill_full_mining_inventory(inventory)
	var pickaxe_slot := _find_item_slot(inventory, "iron_pickaxe")
	inventory.call("select_slot", pickaxe_slot)
	var full_inventory: Dictionary = inventory.call("serialize")
	var durability_before := int(
		(inventory.call("get_slot", pickaxe_slot) as Dictionary).get("metadata", {}).get("durability", 251)
	)
	var mining_focus_ready := await _aim_at_block(
		player, world, mining_target, "stone"
	)
	_check(mining_focus_ready, "production ray targets the real mining voxel")
	if not mining_focus_ready:
		await _finish(game, hub)
		return
	await _hold_left_for_frames(180)
	_check(_last_rejection_reason(rejections) == "inventory_full", "full inventory mining retains the exact inventory_full rejection")
	_check(str(world.call("get_block", mining_target)) == "stone", "full inventory mining leaves the world voxel unchanged")
	_check(inventory.call("serialize") == full_inventory, "full inventory mining cannot partially mutate inventory")
	_check(
		int((inventory.call("get_slot", pickaxe_slot) as Dictionary).get("metadata", {}).get("durability", 251)) == durability_before,
		"full inventory mining cannot consume durability",
	)

	_stage = "successful_mining"
	var freed_slot := _first_fixture_pickaxe_slot(inventory)
	_check(freed_slot >= 0, "fixture exposes one slot to release for the mining drop")
	if freed_slot >= 0:
		inventory.call("remove_from_slot", freed_slot, 1)
	_check(
		await _aim_at_block(player, world, mining_target, "stone"),
		"successful mining reacquires the production voxel",
	)
	await _hold_left_until_removed(world, mining_target)
	_check(str(world.call("get_block", mining_target)) == "air", "real hold-to-mine removes the production voxel")
	_check(inventory.count_item("cobblestone") == 1, "successful mining grants exactly one configured drop")
	_check(
		int((inventory.call("get_slot", pickaxe_slot) as Dictionary).get("metadata", {}).get("durability", 251)) == durability_before - 1,
		"successful mining consumes exactly one tool durability",
	)

	_stage = "save_reload"
	var final_inventory: Dictionary = inventory.call("serialize")
	_check(bool(hub.call("save_current")), "structure and mining result join the authoritative save")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(not loaded.is_empty(), "authoritative world reload payload is available")
	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "building and mining world completes a full production reload")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	inventory = hub.get("inventory") as Node
	_check(inventory.call("serialize") == final_inventory, "reload restores exact inventory and durability without duplication")
	for index in structure.size():
		_check(str(world.call("get_block", structure[index])) == "planks", "reload restores structure block %d" % index)
	_check(str(world.call("get_block", mining_target)) == "air", "reload cannot resurrect the mined voxel")
	_check(inventory.count_item("cobblestone") == 1, "reload preserves exact mining-drop conservation")
	_check(bool(player.get("input_enabled")), "reloaded building world remains playable")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "reloaded building world restores mouse capture")

	await _aim_at(player, world.call("block_to_world", structure[1]))
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "building and mining viewport renders a desktop frame")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "building evidence uses 1024x576 resolution")
		_save_image(image)
	await _finish(game, hub)


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 58)
	for x_offset in range(-6, 7):
		for z_offset in range(-2, 8):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 6):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	var failure_anchor := Vector3i(origin.x, floor_y + 2, origin.z + 1)
	var failure_target := failure_anchor + Vector3i(0, 0, 1)
	world.call("set_block", failure_anchor, "stone")
	var anchors: Array[Vector3i] = []
	var structure: Array[Vector3i] = []
	for x_offset in [-1, 0, 1]:
		var anchor := Vector3i(origin.x + x_offset, floor_y + 1, origin.z)
		anchors.append(anchor)
		structure.append(anchor + Vector3i(0, 0, 1))
		world.call("set_block", anchor, "stone")
		world.call("set_block", anchor + Vector3i(0, 0, 1), "air")
	var mining_target := Vector3i(origin.x + 3, floor_y + 2, origin.z)
	world.call("set_block", mining_target, "stone")
	world.call("set_block", mining_target + Vector3i.DOWN, "stone")
	return {
		"floor_y": floor_y,
		"build_player_z": float(origin.z) + 5.5,
		"failure_anchor": failure_anchor,
		"failure_target": failure_target,
		"anchors": anchors,
		"structure": structure,
		"mining_target": mining_target,
		"failure_player_position": Vector3(origin.x + 0.5, floor_y + 1.05, origin.z + 2.45),
		"mining_player_position": Vector3(origin.x + 3.5, floor_y + 1.05, origin.z + 5.5),
	}


func _fill_full_mining_inventory(inventory: Node) -> void:
	inventory.clear()
	inventory.call("add_item", "iron_pickaxe", 1)
	for index in 35:
		inventory.call("add_item", "wooden_pickaxe", 1, {"fixture_slot": "mining_%02d" % index})


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		if str((inventory.call("get_slot", index) as Dictionary).get("item_id", "")) == item_id:
			return index
	return -1


func _first_fixture_pickaxe_slot(inventory: Node) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == "wooden_pickaxe":
			return index
	return -1


func _last_rejection_reason(rejections: Array[Dictionary]) -> String:
	return "" if rejections.is_empty() else str(rejections[-1].get("reason", ""))


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		player.velocity.y = minf(player.velocity.y, -0.5)
		player.move_and_slide()
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 360:
		await process_frame
		var candidate_world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var candidate_player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			candidate_world != null and candidate_player != null
			and bool(candidate_world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(candidate_player.get("input_enabled"))
		):
			return true
	return false


func _aim_at_block(
	player: Node3D,
	world: Node,
	block_position: Vector3i,
	expected_block_id: String
) -> bool:
	var block_center: Vector3 = world.call("block_to_world", block_position)
	for height_offset: float in AIM_HEIGHT_OFFSETS:
		await _aim_at(player, block_center + Vector3.UP * height_offset)
		for _frame in AIM_TIMEOUT_FRAMES / AIM_HEIGHT_OFFSETS.size():
			player.call("_update_interaction_focus", true)
			if _focus_hits_block(player, block_position, expected_block_id):
				return true
			await physics_frame
			await process_frame
	return false


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera := player.call("get_view_camera") as Camera3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if camera == null or pivot == null or ray == null:
		return
	var direction := target - camera.global_position
	var horizontal := Vector2(direction.x, direction.z).length()
	player.rotation.y = atan2(-direction.x, -direction.z)
	pivot.rotation.x = clampf(
		atan2(direction.y, maxf(0.0001, horizontal)),
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	camera.rotation = Vector3.ZERO
	await physics_frame
	await process_frame
	ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_hits_block(player: Node, expected_position: Vector3i, expected_block_id: String) -> bool:
	var raw_focus: Variant = player.call("get_interaction_focus")
	if raw_focus is not Dictionary:
		return false
	var focus: Dictionary = raw_focus
	return (
		str(focus.get("type", "")) == "block"
		and _vector3i(focus.get("hit_position", [])) == expected_position
		and str(focus.get("block_id", "")) == expected_block_id
	)


func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _right_click_center() -> void:
	var center := Vector2(root.size) * 0.5
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.global_position = center
		event.button_index = MOUSE_BUTTON_RIGHT
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _hold_left_for_frames(frame_count: int) -> void:
	var center := Vector2(root.size) * 0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	for _frame in frame_count:
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


func _hold_left_until_removed(world: Node, target: Vector3i) -> void:
	var center := Vector2(root.size) * 0.5
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press)
	for _frame in MAX_HARVEST_FRAMES:
		await process_frame
		if str(world.call("get_block", target)) == "air":
			break
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "building and mining screenshot is saved")


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	push_error("QA BUILDING MINING WATCHDOG: stage=%s" % _stage)
	quit(2)


func _finish(game: Node, hub: Node) -> void:
	_finished = true
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
		print("QA BUILDING MINING CLOSED LOOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA BUILDING MINING CLOSED LOOP FAILURE: %s" % failure)
		print("QA BUILDING MINING CLOSED LOOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
