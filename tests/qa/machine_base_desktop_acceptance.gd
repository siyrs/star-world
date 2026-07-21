extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://machine-base-desktop.png"
const CLEANUP_FRAMES := 8
const SLOT_INPUT := "input"
const SLOT_FUEL := "fuel"

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
	_check(hub != null and participant != null and scheduler != null and furnace != null, "production game mounts Machine Base services")
	if hub == null or participant == null or scheduler == null or furnace == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Machine-Base-Desktop-%d" % Time.get_ticks_msec(),
		"star_continent",
		7864215
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop Machine Base journey creates a temporary world")
	game.begin_world_state(state)
	_check(await _wait_for_world_ready(game, hub, _world_id), "production world reaches a bounded ready state")
	var player: CharacterBody3D = game.player
	_check(player != null and bool(player.get("input_enabled")), "production player starts with gameplay input")
	_check(bool(scheduler.call("is_active")), "world activation starts the shared machine scheduler")
	_check(bool(furnace.call("is_externally_scheduled")) and not furnace.is_processing(), "production furnace has no duplicate private process loop")
	_check(int(hub.feature_lifecycle.call("get_snapshot").get("participant_count", 0)) == 6, "production composition exposes six lifecycle participants")

	var first_id := "furnace@desktop-one"
	var second_id := "furnace@desktop-two"
	_check(bool(furnace.call("ensure_machine", first_id)) and bool(furnace.call("ensure_machine", second_id)), "two production furnace instances register with stable ids")
	hub.inventory.clear()
	hub.inventory.add_item("raw_iron", 2)
	hub.inventory.add_item("raw_gold", 1)
	hub.inventory.add_item("coal", 1, {"machine":"one"})
	hub.inventory.add_item("coal", 1, {"machine":"two"})
	var iron_index := _find_inventory_slot(hub.inventory, "raw_iron")
	var gold_index := _find_inventory_slot(hub.inventory, "raw_gold")
	var first_fuel_index := _find_inventory_slot(hub.inventory, "coal", {"machine":"one"})
	var second_fuel_index := _find_inventory_slot(hub.inventory, "coal", {"machine":"two"})
	_check(iron_index >= 0 and gold_index >= 0 and first_fuel_index >= 0 and second_fuel_index >= 0, "desktop journey resolves all real inventory slots")
	_check(bool(furnace.call("transfer_from_inventory", hub.inventory, iron_index, SLOT_INPUT, first_id)), "first furnace receives iron input")
	_check(bool(furnace.call("transfer_from_inventory", hub.inventory, first_fuel_index, SLOT_FUEL, first_id)), "first furnace receives its own fuel stack")
	_check(bool(furnace.call("transfer_from_inventory", hub.inventory, gold_index, SLOT_INPUT, second_id)), "second furnace receives gold input")
	_check(bool(furnace.call("transfer_from_inventory", hub.inventory, second_fuel_index, SLOT_FUEL, second_id)), "second furnace receives its own fuel stack")
	var first_before: Dictionary = furnace.call("get_machine_snapshot", first_id)
	_check(int(first_before.get("queued_jobs", 0)) == 2, "production snapshot exposes the two-item iron queue")
	_check(is_equal_approx(float(first_before.get("estimated_total_seconds", 0.0)), 12.0), "production snapshot exposes queue ETA")
	_check(bool(hub.game_ui.open_furnace(first_id, "共享调度熔炉")), "production machine overlay opens the first furnace")
	_check(hub.game_ui.get_active_overlay() == GameUIScript.Overlay.FURNACE, "machine overlay owns the real UI context")
	var panel: Node = hub.game_ui.get_furnace_panel()
	_check(panel != null and str(panel.call("get_active_machine_id")) == first_id, "real furnace panel uses the stable machine id")

	var announced: Array[Dictionary] = []
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void: announced.append(summary.duplicate(true))
	)
	var audio_before := int(participant.call("get_lifecycle_snapshot").get("completion_audio_count", 0))
	var runtime_batch: Dictionary = scheduler.call("advance_time", 6.1, true)
	for _frame in 3:
		await process_frame
	_check(int(runtime_batch.get("changed_machine_count", 0)) == 2, "one production scheduler batch advances both furnaces")
	_check(announced.size() == 1, "two synchronous furnace completions create one player-facing summary")
	if not announced.is_empty():
		var summary: Dictionary = announced[0]
		_check(int(summary.get("completed_jobs", 0)) == 2, "completion summary preserves both finished jobs")
		_check(int(summary.get("machine_count", 0)) == 2, "completion summary preserves both contributing machines")
		_check(str(summary.get("message", "")).contains("铁锭") and str(summary.get("message", "")).contains("金锭"), "completion summary names both real outputs")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("completion_audio_count", 0)) == audio_before + 1, "two completions consume one sound budget")
	var first_after: Dictionary = furnace.call("get_machine_snapshot", first_id)
	var second_after: Dictionary = furnace.call("get_machine_snapshot", second_id)
	_check(int(first_after.get("output", {}).get("count", 0)) == 1, "first production furnace creates one iron ingot")
	_check(int(second_after.get("output", {}).get("count", 0)) == 1, "second production furnace creates one gold ingot")
	panel.call("refresh")
	var output_button: Button = panel.get("_output_button") as Button
	_check(
		output_button != null
		and output_button.tooltip_text.contains("铁锭")
		and output_button.get("_icon_rect").texture != null,
		"real furnace UI refreshes from the Machine Base snapshot"
	)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the shared machine overlay")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "Machine Base evidence uses the 1024x576 product resolution")
		_save_image(image)

	_check(bool(hub.save_current()), "Machine Base joins the production world save transaction")
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var saved_furnaces: Dictionary = loaded.get("machines", {}).get("furnaces", {})
	_check(saved_furnaces.size() == 2, "both machine instances persist under machines.furnaces")
	var announced_before_reload := announced.size()
	hub.return_to_menu()
	for _frame in 8:
		await process_frame
	_check(not bool(scheduler.call("is_active")), "return-to-menu stops shared machine processing")
	_check(int(furnace.call("get_runtime_snapshot").get("machine_count", -1)) == 0, "return-to-menu clears machine runtime state")
	game.begin_world_state(loaded)
	_check(await _wait_for_world_ready(game, hub, _world_id), "full reload reaches a bounded production ready state")
	_check(bool(scheduler.call("is_active")), "full reload reactivates the same shared scheduler")
	_check(int((furnace.call("get_machine_snapshot", first_id) as Dictionary).get("output", {}).get("count", 0)) == 1, "full reload restores iron output exactly once")
	_check(int((furnace.call("get_machine_snapshot", second_id) as Dictionary).get("output", {}).get("count", 0)) == 1, "full reload restores gold output exactly once")
	_check(announced.size() == announced_before_reload, "world reload does not replay transient completion feedback")
	var reloaded_character: Dictionary = hub.call("get_character_snapshot")
	_check(reloaded_character.has("machine_runtime") and reloaded_character.has("machines"), "production diagnostics survive complete reload")
	await _finish(game, hub)


func _find_inventory_slot(inventory: Node, item_id: String, metadata: Dictionary = {}) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id and slot.get("metadata", {}) == metadata:
			return index
	return -1


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in 180:
		await process_frame
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		var runtime: Node = hub.get("machine_runtime") as Node
		if (
			world != null
			and player != null
			and runtime != null
			and bool(world.get("is_started"))
			and str(hub.get("current_world_id")) == expected_world_id
			and bool(runtime.call("is_active"))
		):
			return true
	return false


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "Machine Base screenshot is saved")


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
		print("QA MACHINE BASE DESKTOP PASS | checks=%d | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE BASE DESKTOP FAILURE: %s" % failure)
		print("QA MACHINE BASE DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
