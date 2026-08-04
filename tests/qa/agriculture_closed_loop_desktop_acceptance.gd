extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://agriculture-closed-loop-desktop.png"
const CLEANUP_FRAMES := 10
const MAX_TEST_SECONDS := 600.0

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
	_stage = "create_world"
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the agriculture service hub")
	if hub == null:
		await _finish(game, null)
		return
	var state: Dictionary = hub.get("save_service").create_world(
		"Agriculture-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		57294163,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "agriculture journey creates a temporary production world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production agriculture world reaches a bounded ready state")

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var agriculture: Node = hub.get("agriculture_service") as Node
	var runtime: Node = hub.get("agriculture_runtime_participant") as Node
	_check(
		player != null and world != null and inventory != null
		and agriculture != null and runtime != null,
		"production player, voxel world, inventory and agriculture runtime are mounted",
	)
	if player == null or world == null or inventory == null or agriculture == null or runtime == null:
		await _finish(game, hub)
		return

	var rejections: Array[Dictionary] = []
	var maturity_events: Array[Dictionary] = []
	var harvest_events: Array[Dictionary] = []
	agriculture.agriculture_rejected.connect(
		func(reason: String, context: Dictionary) -> void:
			rejections.append({"reason":reason, "context":context.duplicate(true)})
	)
	runtime.maturity_batch_announced.connect(
		func(summary: Dictionary) -> void:
			maturity_events.append(summary.duplicate(true))
	)
	agriculture.crop_harvested.connect(
		func(position: Vector3i, crop_id: String, outputs: Array) -> void:
			harvest_events.append({
				"position":position,
				"crop_id":crop_id,
				"outputs":outputs.duplicate(true),
			})
	)

	_stage = "prepare_arena"
	var arena: Dictionary = _build_farm_arena(world, player)
	var soil_position: Vector3i = arena.get("soil_position", Vector3i.ZERO)
	var crop_position := soil_position + Vector3i.UP
	player.global_position = arena.get("player_position", player.global_position)
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 120)
	_check(player.is_on_floor(), "production player settles on live voxel collision")
	_check(str(world.call("get_block", soil_position)) == "grass", "farm arena exposes one real grass target")

	inventory.clear()
	inventory.add_item("wooden_hoe", 1)
	inventory.add_item("water_bucket", 1)
	inventory.add_item("wheat_seeds", 2)
	inventory.add_item("compost", 1)
	var hoe_slot := _find_item_slot(inventory, "wooden_hoe")
	var water_slot := _find_item_slot(inventory, "water_bucket")
	var seed_slot := _find_item_slot(inventory, "wheat_seeds")
	var compost_slot := _find_item_slot(inventory, "compost")
	_check(
		hoe_slot >= 0 and water_slot >= 0 and seed_slot >= 0 and compost_slot >= 0,
		"fixture grants the complete real agriculture tool and material chain",
	)
	inventory.select_slot(hoe_slot)

	_stage = "blocked_tilling"
	world.call("set_block", crop_position, "stone")
	await _aim_at(player, world.call("block_to_world", soil_position))
	_check(_focus_hits_block(player, soil_position, "grass"), "production focus resolves the blocked grass target")
	var blocked_inventory: Dictionary = inventory.call("serialize")
	await _right_click_center()
	_check(not rejections.is_empty(), "blocked tilling emits a production rejection")
	_check(_last_rejection_reason(rejections) == "space_blocked", "blocked tilling retains the exact space_blocked reason")
	_check(inventory.call("serialize") == blocked_inventory, "blocked tilling cannot consume hoe durability or materials")
	_check(str(world.call("get_block", soil_position)) == "grass", "blocked tilling cannot mutate the target block")
	world.call("set_block", crop_position, "air")

	_stage = "till_water_plant"
	await _aim_at(player, world.call("block_to_world", soil_position))
	await _right_click_center()
	_check(str(world.call("get_block", soil_position)) == "farmland", "real right click tills dry production farmland")
	var tilled_hoe: Dictionary = inventory.call("get_slot", hoe_slot)
	_check(
		int(tilled_hoe.get("metadata", {}).get("durability", 60)) == 59,
		"successful tilling consumes exactly one visible hoe durability",
	)

	inventory.select_slot(water_slot)
	await _aim_at(player, world.call("block_to_world", soil_position))
	await _right_click_center()
	_check(str(world.call("get_block", soil_position)) == "farmland_wet", "real water-bucket input hydrates the production soil")
	_check(inventory.count_item("water_bucket") == 0 and inventory.count_item("bucket") == 1, "watering atomically converts the water bucket into an empty bucket")
	_check(float(agriculture.call("get_soil_state", soil_position).get("manual_remaining_seconds", 0.0)) > 0.0, "hydration timer enters authoritative agriculture state")

	seed_slot = _find_item_slot(inventory, "wheat_seeds")
	inventory.select_slot(seed_slot)
	await _aim_at(player, world.call("block_to_world", soil_position))
	await _right_click_center()
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_0", "real seed input plants wheat in the production world")
	_check(inventory.count_item("wheat_seeds") == 1, "planting consumes exactly one seed")
	var planted_state: Dictionary = agriculture.call("get_crop_state", crop_position)
	_check(str(planted_state.get("crop_id", "")) == "wheat" and int(planted_state.get("stage", -1)) == 0, "planted crop enters canonical stage-zero state")

	_stage = "early_harvest_and_fertilize"
	var early_inventory: Dictionary = inventory.call("serialize")
	var early_crop: Dictionary = planted_state.duplicate(true)
	await _aim_at(player, world.call("block_to_world", soil_position))
	_check(_focus_hits_block(player, crop_position, "wheat_stage_0"), "production focus proxies non-colliding crop through supporting soil")
	await _right_click_center()
	_check(_last_rejection_reason(rejections) == "crop_growing", "early harvest retains the exact crop_growing reason")
	_check(inventory.call("serialize") == early_inventory, "early harvest failure cannot mutate player inventory")
	_check(agriculture.call("get_crop_state", crop_position) == early_crop, "early harvest failure cannot mutate crop state")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_0", "early harvest failure keeps the visible crop unchanged")

	compost_slot = _find_item_slot(inventory, "compost")
	inventory.select_slot(compost_slot)
	await _aim_at(player, world.call("block_to_world", soil_position))
	await _right_click_center()
	var fertilized_state: Dictionary = agriculture.call("get_crop_state", crop_position)
	_check(int(fertilized_state.get("stage", -1)) == 1, "real compost input advances the crop exactly one stage")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_1", "fertilizer commits the matching visible stage")
	_check(inventory.count_item("compost") == 0, "successful fertilization consumes exactly one compost")

	_stage = "mid_growth_save_reload"
	var mid_inventory: Dictionary = inventory.call("serialize")
	var mid_crop: Dictionary = fertilized_state.duplicate(true)
	var mid_soil: Dictionary = agriculture.call("get_soil_state", soil_position)
	_check(bool(hub.call("save_current")), "mid-growth agriculture state joins the authoritative save")
	var mid_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	_check(not (mid_loaded.get("agriculture", {}).get("crops", {}) as Dictionary).is_empty(), "world.json contains the live crop domain")
	_check(not (mid_loaded.get("agriculture", {}).get("soil_moisture", {}).get("soils", {}) as Dictionary).is_empty(), "world.json contains authoritative hydration state")
	var maturity_before_reload := maturity_events.size()
	var harvest_before_reload := harvest_events.size()

	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	_check(int(agriculture.call("get_crop_count")) == 0, "return to menu clears the agriculture runtime session")
	game.call("begin_world_state", mid_loaded)
	_check(await _wait_for_world_ready(game, hub), "mid-growth agriculture world completes a full production reload")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	inventory = hub.get("inventory") as Node
	agriculture = hub.get("agriculture_service") as Node
	_check(inventory.call("serialize") == mid_inventory, "first reload restores the exact mid-growth inventory")
	_check(agriculture.call("get_crop_state", crop_position) == mid_crop, "first reload restores the exact crop stage and elapsed state")
	var reloaded_soil: Dictionary = agriculture.call("get_soil_state", soil_position)
	_check(
		bool(reloaded_soil.get("hydrated", false)) == bool(mid_soil.get("hydrated", false))
		and is_equal_approx(
			float(reloaded_soil.get("manual_remaining_seconds", 0.0)),
			float(mid_soil.get("manual_remaining_seconds", 0.0))
		),
		"first reload restores the exact manual hydration timer",
	)
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_1", "first reload restores the visible stage-one crop")
	_check(maturity_events.size() == maturity_before_reload and harvest_events.size() == harvest_before_reload, "first reload does not replay maturity or harvest feedback")

	_stage = "mature_and_full_inventory_failure"
	agriculture.call("advance_time", 120.0)
	for _frame in 5:
		await process_frame
	var mature_state: Dictionary = agriculture.call("get_crop_state", crop_position)
	_check(int(mature_state.get("stage", -1)) == 3, "bounded production time matures the fertilized wheat")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_3", "mature domain state owns the matching production voxel")
	_check(maturity_events.size() == maturity_before_reload + 1, "maturity creates one bounded player summary")

	_fill_full_harvest_inventory(inventory)
	_check(_occupied_slot_count(inventory) == 36, "fixture fills the real inventory while retaining a seed merge target")
	var full_inventory: Dictionary = inventory.call("serialize")
	var mature_before_failure: Dictionary = mature_state.duplicate(true)
	await _aim_at(player, world.call("block_to_world", soil_position))
	_check(_focus_hits_block(player, crop_position, "wheat_stage_3"), "production focus resolves the mature crop proxy")
	await _right_click_center()
	_check(_last_rejection_reason(rejections) == "inventory_full", "mature full-inventory failure retains the exact inventory_full reason")
	_check(inventory.call("serialize") == full_inventory, "full-inventory harvest cannot partially add seeds or wheat")
	_check(agriculture.call("get_crop_state", crop_position) == mature_before_failure, "full-inventory harvest keeps authoritative crop state mature")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_3", "full-inventory harvest keeps the mature crop visible")
	_check(harvest_events.size() == harvest_before_reload, "failed harvest cannot emit a success event")

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "agriculture closed-loop viewport renders a desktop frame")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "agriculture evidence uses 1024x576 resolution")
		_save_image(image)

	_stage = "mature_save_reload"
	_check(bool(hub.call("save_current")), "mature full-inventory crop joins a second authoritative save")
	var mature_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var maturity_before_second_reload := maturity_events.size()
	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", mature_loaded)
	_check(await _wait_for_world_ready(game, hub), "mature agriculture world completes a second production reload")
	player = game.get("player") as CharacterBody3D
	world = game.get("world") as Node
	inventory = hub.get("inventory") as Node
	agriculture = hub.get("agriculture_service") as Node
	_check(inventory.call("serialize") == full_inventory, "second reload restores the exact full inventory")
	_check(int(agriculture.call("get_crop_state", crop_position).get("stage", -1)) == 3, "second reload preserves the mature crop exactly")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_3", "second reload restores the mature production voxel")
	_check(maturity_events.size() == maturity_before_second_reload, "second reload does not replay the maturity summary")

	_stage = "successful_harvest"
	var freed_slot := _first_pickaxe_slot(inventory)
	_check(freed_slot >= 0, "fixture finds one non-seed slot to release")
	if freed_slot >= 0:
		inventory.call("remove_from_slot", freed_slot, 1)
	_check(_occupied_slot_count(inventory) == 35, "exactly one inventory slot is available for wheat output")
	await _aim_at(player, world.call("block_to_world", soil_position))
	await _right_click_center()
	_check(inventory.count_item("wheat") == 1, "real harvest grants one wheat after space is released")
	_check(inventory.count_item("wheat_seeds") == 3, "real harvest atomically merges both returned seeds")
	_check(int(agriculture.call("get_crop_state", crop_position).get("stage", -1)) == 0, "successful harvest auto-replants canonical stage zero")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_0", "successful harvest commits the replanted production voxel")
	_check(harvest_events.size() == harvest_before_reload + 1, "successful harvest emits exactly one production event")

	_stage = "final_save_reload"
	var final_inventory: Dictionary = inventory.call("serialize")
	var final_crop: Dictionary = agriculture.call("get_crop_state", crop_position)
	var final_harvest_count := harvest_events.size()
	var final_maturity_count := maturity_events.size()
	_check(bool(hub.call("save_current")), "harvested and replanted state joins a final authoritative save")
	var final_loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	hub.call("return_to_menu")
	for _frame in 10:
		await process_frame
	game.call("begin_world_state", final_loaded)
	_check(await _wait_for_world_ready(game, hub), "harvested agriculture world completes the final production reload")
	inventory = hub.get("inventory") as Node
	agriculture = hub.get("agriculture_service") as Node
	world = game.get("world") as Node
	_check(inventory.call("serialize") == final_inventory, "final reload restores exact harvested inventory without duplication")
	_check(inventory.count_item("wheat") == 1 and inventory.count_item("wheat_seeds") == 3, "final reload preserves exact harvest conservation")
	_check(agriculture.call("get_crop_state", crop_position) == final_crop, "final reload restores the exact replanted crop state")
	_check(str(world.call("get_block", crop_position)) == "wheat_stage_0", "final reload cannot resurrect the mature crop")
	_check(harvest_events.size() == final_harvest_count and maturity_events.size() == final_maturity_count, "final reload does not replay harvest or maturity feedback")
	_check(bool((game.get("player") as CharacterBody3D).get("input_enabled")), "final agriculture reload remains playable")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "agriculture loop preserves gameplay mouse capture")
	await _finish(game, hub)


func _build_farm_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 59)
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(origin.x + x_offset, floor_y, origin.z + z_offset)
			world.call("set_block", floor_position, "stone")
			for y_offset in range(1, 6):
				world.call("set_block", floor_position + Vector3i(0, y_offset, 0), "air")
	var soil_position := Vector3i(origin.x, floor_y, origin.z - 3)
	world.call("set_block", soil_position, "grass")
	return {
		"player_position": Vector3(origin.x + 0.5, floor_y + 1.25, origin.z + 0.5),
		"soil_position": soil_position,
	}


func _fill_full_harvest_inventory(inventory: Node) -> void:
	inventory.clear()
	inventory.call("add_item", "wheat_seeds", 1)
	for index in 35:
		inventory.call("add_item", "wooden_pickaxe", 1, {"fixture_slot":index})


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _first_pickaxe_slot(inventory: Node) -> int:
	return _find_item_slot(inventory, "wooden_pickaxe")


func _occupied_slot_count(inventory: Node) -> int:
	var count := 0
	for index in int(inventory.get("slot_count")):
		if not (inventory.call("get_slot", index) as Dictionary).is_empty():
			count += 1
	return count


func _last_rejection_reason(rejections: Array[Dictionary]) -> String:
	if rejections.is_empty():
		return ""
	return str(rejections[-1].get("reason", ""))


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	for _frame in frame_limit:
		player.velocity.y = minf(player.velocity.y, -0.5)
		player.move_and_slide()
		if player.is_on_floor():
			return
		await physics_frame
		await process_frame
	player.velocity.y = -0.5
	player.move_and_slide()


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in 240:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			world != null and player != null and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(player.get("input_enabled"))
		):
			return true
	return false


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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "agriculture desktop screenshot is saved")


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	push_error("QA AGRICULTURE CLOSED LOOP DESKTOP WATCHDOG: stage=%s" % _stage)
	print(
		"QA AGRICULTURE CLOSED LOOP DESKTOP TIMEOUT | stage=%s | checks=%d | failures=%d"
		% [_stage, checks, failures.size()]
	)
	quit(2)


func _finish(game: Node, hub: Node) -> void:
	_finished = true
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
		print("QA AGRICULTURE CLOSED LOOP DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AGRICULTURE CLOSED LOOP DESKTOP FAILURE: %s" % failure)
		print("QA AGRICULTURE CLOSED LOOP DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
