extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const OverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://machine-capability-desktop.png"
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
	var router: Node = hub.get("machine_interaction_router") as Node if hub != null else null
	var scheduler: Node = hub.get("machine_runtime") as Node if hub != null else null
	var furnace: Node = hub.get("furnace_service") as Node if hub != null else null
	var cutter: Node = hub.get("stonecutter_service") as Node if hub != null else null
	_check(
		hub != null and router != null and scheduler != null
		and furnace != null and cutter != null,
		"production game mounts machine capability services"
	)
	if hub == null or router == null or scheduler == null or furnace == null or cutter == null:
		await _finish(game, hub)
		return

	var state: Dictionary = hub.get("save_service").create_world(
		"Machine-Capability-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		90173425
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "machine capability journey creates a temporary world")
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub), "production world reaches a bounded ready state")
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	_check(player != null and bool(player.get("input_enabled")), "production player starts in gameplay context")
	_check(bool(scheduler.call("is_active")), "shared machine scheduler is active")

	var furnace_id := "furnace@capability-desktop"
	var cutter_id := "stonecutter@capability-desktop"
	_check(bool(furnace.call("ensure_machine", furnace_id)), "production furnace capability target exists")
	_check(bool(cutter.call("ensure_machine", cutter_id)), "production stonecutter capability target exists")
	var furnace_capabilities: Dictionary = router.call(
		"get_machine_capabilities", &"furnace", furnace_id
	)
	var cutter_capabilities: Dictionary = router.call(
		"get_machine_capabilities", &"stonecutter", cutter_id
	)
	_check((furnace_capabilities.get("slots", []) as Array).size() == 3, "desktop furnace exposes three capabilities")
	_check((cutter_capabilities.get("slots", []) as Array).size() == 2, "desktop stonecutter exposes two capabilities")
	_check(int(furnace_capabilities.get("max_transfer_items", 0)) == 64, "desktop capability reports the transfer hard limit")

	var inventory: Node = hub.get("inventory") as Node
	inventory.call("clear")
	inventory.call("add_item", "raw_iron", 2)
	inventory.call("add_item", "coal", 1)
	inventory.call("add_item", "stone", 2)
	var iron_index := _find_slot(inventory, "raw_iron")
	var coal_index := _find_slot(inventory, "coal")
	var stone_index := _find_slot(inventory, "stone")
	_check(iron_index >= 0 and coal_index >= 0 and stone_index >= 0, "real inventory exposes all automation sources")
	_check(
		bool((router.call(
			"insert_transaction", &"furnace", furnace_id, "input", inventory, iron_index, 2
		) as Dictionary).get("success", false)),
		"unified capability inserts furnace input"
	)
	_check(
		bool((router.call(
			"insert_transaction", &"furnace", furnace_id, "fuel", inventory, coal_index, 1
		) as Dictionary).get("success", false)),
		"unified capability inserts furnace fuel"
	)
	_check(
		bool((router.call(
			"insert_transaction", &"stonecutter", cutter_id, "input", inventory, stone_index, 2
		) as Dictionary).get("success", false)),
		"same capability path inserts stonecutter input"
	)
	_check(inventory.call("count_item", "raw_iron") == 0, "automation removes exact furnace input")
	_check(inventory.call("count_item", "coal") == 0, "automation removes exact fuel input")
	_check(inventory.call("count_item", "stone") == 0, "automation removes exact cutter input")

	var batch: Dictionary = scheduler.call("advance_time", 12.1, true)
	for _frame in 4:
		await process_frame
	_check(int(batch.get("advanced_domain_count", 0)) == 3, "one scheduler batch advances both capability domains and bounded automation")
	_check(int((furnace.call("get_slot", furnace_id, "output") as Dictionary).get("count", 0)) == 2, "furnace creates two iron outputs")
	_check(int((cutter.call("get_slot", cutter_id, "output") as Dictionary).get("count", 0)) == 4, "stonecutter creates four slab outputs")

	var opened: Dictionary = router.call(
		"open_machine_type", &"stonecutter", cutter_id, "能力合同石材切割机"
	)
	_check(bool(opened.get("success", false)), "production capability router opens the real machine UI")
	var game_ui: Node = hub.get("game_ui") as Node
	_check(int(game_ui.call("get_active_overlay")) == OverlayIds.STONECUTTER, "real machine overlay owns the input context")
	_check(player != null and not bool(player.get("input_enabled")), "machine overlay blocks gameplay input")
	var panel: Node = game_ui.call("get_stonecutter_panel") as Node
	if panel != null:
		panel.call("refresh")
		var output_button: Button = panel.get("_output_button") as Button
		_check(output_button != null and output_button.text.contains("石台阶") and output_button.text.contains("×4"), "real UI reflects capability-produced output")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the capability journey")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "capability evidence uses 1024x576 resolution")
		_save_image(image)
	await _tap_key(KEY_ESCAPE)
	_check(int(game_ui.call("get_active_overlay")) == 0, "Esc closes the capability machine overlay")
	_check(player != null and bool(player.get("input_enabled")), "closing capability UI restores gameplay input")

	inventory.call("clear")
	for index in int(inventory.get("slot_count")):
		inventory.call("add_item", "wooden_pickaxe", 1, {"serial":index})
	var inventory_before: Dictionary = inventory.call("serialize")
	var output_before: Dictionary = cutter.call("get_slot", cutter_id, "output")
	var rejected: Dictionary = router.call(
		"extract_transaction", &"stonecutter", cutter_id, "output", inventory, 1
	)
	_check(str(rejected.get("reason", "")) == "inventory_full", "full real inventory rejects automated extraction")
	_check(inventory.call("serialize") == inventory_before, "failed desktop extraction performs zero inventory writes")
	_check(cutter.call("get_slot", cutter_id, "output") == output_before, "failed desktop extraction performs zero machine writes")

	for index in 6:
		inventory.call("remove_from_slot", index, 1)
	_check(
		bool((router.call(
			"extract_transaction", &"stonecutter", cutter_id, "output", inventory, 1
		) as Dictionary).get("success", false)),
		"desktop capability extracts one requested slab"
	)
	_check(
		bool((router.call(
			"extract_transaction", &"stonecutter", cutter_id, "output", inventory
		) as Dictionary).get("success", false)),
		"desktop capability extracts the remaining slab stack"
	)
	_check(
		bool((router.call(
			"extract_transaction", &"furnace", furnace_id, "output", inventory
		) as Dictionary).get("success", false)),
		"desktop capability extracts furnace output through the same port"
	)
	_check(int(inventory.call("count_item", "stone_slab")) == 4, "real inventory receives all four slabs")
	_check(int(inventory.call("count_item", "iron_ingot")) == 2, "real inventory receives both iron ingots")
	_check((cutter.call("get_slot", cutter_id, "output") as Dictionary).is_empty(), "successful extraction clears cutter output")
	_check((furnace.call("get_slot", furnace_id, "output") as Dictionary).is_empty(), "successful extraction clears furnace output")

	var router_snapshot: Dictionary = router.call("get_snapshot")
	_check(int(router_snapshot.get("transfer_success_count", 0)) == 6, "production diagnostics count six successful transfers")
	_check(int(router_snapshot.get("transfer_rejection_count", 0)) == 1, "production diagnostics count the blocked extraction")
	_check(int(router_snapshot.get("inserted_item_count", 0)) == 5, "production diagnostics preserve inserted item totals")
	_check(int(router_snapshot.get("extracted_item_count", 0)) == 6, "production diagnostics preserve extracted item totals")

	_check(bool(hub.call("save_current")), "capability machines join the production save transaction")
	var loaded: Dictionary = hub.get("save_service").load_world(_world_id)
	var saved_machines: Dictionary = loaded.get("machines", {})
	_check((saved_machines.get("furnaces", {}) as Dictionary).size() == 1, "save preserves furnace capability state")
	_check((saved_machines.get("stonecutters", {}) as Dictionary).size() == 1, "save preserves stonecutter capability state")
	_check(not saved_machines.has("automation_jobs"), "transient automation jobs never enter the world save")
	_check(not saved_machines.has("last_transfer"), "capability diagnostics never enter the world save")
	var slab_count := int(inventory.call("count_item", "stone_slab"))
	var iron_count := int(inventory.call("count_item", "iron_ingot"))
	hub.call("return_to_menu")
	for _frame in 8:
		await process_frame
	_check(not bool(scheduler.call("is_active")), "return-to-menu stops capability machine scheduling")
	game.call("begin_world_state", loaded)
	_check(await _wait_for_world_ready(game, hub), "complete reload reaches a bounded ready state")
	_check(bool(furnace.call("has_machine", furnace_id)), "reload restores furnace capability target once")
	_check(bool(cutter.call("has_machine", cutter_id)), "reload restores cutter capability target once")
	_check(int(inventory.call("count_item", "stone_slab")) == slab_count, "reload does not duplicate extracted slabs")
	_check(int(inventory.call("count_item", "iron_ingot")) == iron_count, "reload does not duplicate extracted ingots")
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


func _find_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


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


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "machine capability screenshot is saved")


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
		print("QA MACHINE CAPABILITY DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE CAPABILITY DESKTOP FAILURE: %s" % failure)
		print("QA MACHINE CAPABILITY DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
