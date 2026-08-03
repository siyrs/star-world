extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const OverlayIds = preload("res://src/ui/game_ui_extension_overlay_ids.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const StonecutterScript = preload("res://src/machine/stonecutter_service.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://stonecutter-machine-desktop.png"
const WORLD_READY_FRAMES := 720
const CLEANUP_FRAMES := 24
const MACHINE_DISTANCE := 3
const CHUNK_SIZE := 16

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(
		OS.get_cmdline_user_args(),
		OUTPUT_PATH,
	)
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	for _frame in 4:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return

	var participant: Node = hub.get("machine_runtime_participant") as Node
	var scheduler: Node = hub.get("machine_runtime") as Node
	var furnace: Node = hub.get("furnace_service") as Node
	var cutter: Node = hub.get("stonecutter_service") as Node
	var router: Node = hub.get("machine_interaction_router") as Node
	_check(
		participant != null
		and scheduler != null
		and furnace != null
		and cutter != null
		and router != null,
		"production composition mounts shared scheduling, furnace, stonecutter and routing",
	)
	if (
		participant == null
		or scheduler == null
		or furnace == null
		or cutter == null
		or router == null
	):
		await _finish(game, hub)
		return

	var state: Dictionary = hub.get("save_service").create_world(
		"Stonecutter-Closed-Loop-%d" % Time.get_ticks_msec(),
		"star_continent",
		86742015,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "stonecutter journey creates a temporary production world")
	if _world_id.is_empty():
		await _finish(game, hub)
		return
	game.call("begin_world_state", state)
	var ready := await _wait_for_world_ready(game, hub)
	_check(ready, "production world reaches a bounded ready state")
	if not ready:
		await _finish(game, hub)
		return

	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var world: Node = game.get("world") as Node
	var inventory: Node = hub.get("inventory") as Node
	var game_ui: Node = hub.get("game_ui") as Node
	var block_interaction: Node = hub.get("block_interaction") as Node
	_check(
		player != null
		and world != null
		and inventory != null
		and game_ui != null
		and block_interaction != null,
		"production player, voxel world, inventory, machine UI and block interaction are mounted",
	)
	if (
		player == null
		or world == null
		or inventory == null
		or game_ui == null
		or block_interaction == null
	):
		await _finish(game, hub)
		return
	_check(bool(scheduler.call("is_active")), "shared machine scheduler is active")
	_check(
		int((scheduler.call("get_snapshot") as Dictionary).get("domain_count", 0)) == 3,
		"shared scheduler owns furnace, stonecutter and bounded automation",
	)
	_check(bool(router.call("has_machine_type", &"stonecutter")), "generic router exposes stonecutter")

	var arena: Dictionary = _build_arena(world, player)
	var arena_position: Vector3 = arena.get("player_position", player.global_position)
	var floor_y := int(arena.get("floor_y", 0))
	player.global_position = arena_position
	player.rotation = Vector3.ZERO
	player.call("reset_motion")
	player.velocity.y = -1.0
	await _settle_player(player, 180)
	var settled_position := player.global_position
	_check(
		_is_finite_position(settled_position)
		and settled_position.y >= float(floor_y) + 0.75
		and settled_position.y <= float(floor_y) + 3.5
		and Vector2(
			settled_position.x - arena_position.x,
			settled_position.z - arena_position.z,
		).length() <= 1.0,
		"QA arena keeps the production player stable on live collision",
	)

	var cutter_position: Vector3i = arena.get("machine_position", Vector3i.ZERO)
	var placed := bool(world.call("set_block", cutter_position, "stonecutter"))
	_check(
		placed or str(world.call("get_block", cutter_position)) == "stonecutter",
		"QA setup places one real stonecutter voxel",
	)
	for _frame in 4:
		await physics_frame
		await process_frame

	inventory.call("clear")
	_check(
		int(inventory.call("add_item", "apple", 1)) == 0
		and int(inventory.call("add_item", "stone", 2)) == 0
		and int(inventory.call("add_item", "raw_iron", 1)) == 0
		and int(inventory.call("add_item", "coal", 1)) == 0,
		"fixture grants one unsupported item, two cut inputs and one cross-domain furnace job",
	)

	var processed_events: Array[Dictionary] = []
	cutter.connect(
		"item_processed",
		func(machine_id: String, recipe_id: String, output: Dictionary) -> void:
			processed_events.append({
				"machine_id": machine_id,
				"recipe_id": recipe_id,
				"output": output.duplicate(true),
			})
	)
	var announcements: Array[Dictionary] = []
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void:
			announcements.append(summary.duplicate(true))
	)

	await _aim_at(player, world.call("block_to_world", cutter_position))
	_check(_focus_hits_block(player, cutter_position), "real center focus resolves the stonecutter block")
	await _right_click_center()
	_check(
		int(game_ui.call("get_active_overlay")) == OverlayIds.STONECUTTER,
		"real right click opens the stonecutter overlay",
	)
	_check(
		hub.get("input_context").call("get_context") == InputContextScript.CONTEXT_MACHINE,
		"stonecutter overlay enters the production machine input context",
	)
	_check(
		not bool(player.get("input_enabled"))
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"machine overlay isolates gameplay input and releases the pointer",
	)
	var panel: Control = game_ui.call("get_stonecutter_panel") as Control
	_check(panel != null and panel.visible, "production stonecutter panel is visible")
	if panel == null:
		await _finish(game, hub)
		return
	_check(
		_rect_is_inside_viewport(panel.get_global_rect()),
		"complete stonecutter panel stays inside the 1024x576 viewport",
	)
	var layout: Dictionary = panel.call("get_layout_rects")
	_check(
		Rect2(layout.get("input", Rect2())).size.y > 0.0
		and Rect2(layout.get("output", Rect2())).size.y > 0.0
		and Rect2(layout.get("inventory", Rect2())).size.y > 0.0,
		"stonecutter panel exposes measurable machine and inventory layouts",
	)

	var machine_id := str(
		block_interaction.call(
			"get_machine_id",
			world,
			cutter_position,
			"stonecutter",
		)
	)
	_check(
		not machine_id.is_empty()
		and str(panel.call("get_active_machine_id")) == machine_id,
		"panel and service share the stable world-position machine identity",
	)
	var input_button: Button = panel.call(
		"get_machine_slot_button",
		StonecutterScript.SLOT_INPUT,
	) as Button
	var output_button: Button = panel.call(
		"get_machine_slot_button",
		StonecutterScript.SLOT_OUTPUT,
	) as Button
	_check(
		input_button != null and output_button != null,
		"both production machine slots expose real clickable controls",
	)
	_check(
		input_button != null
		and str(input_button.get_meta("slot_name", "")) == "input"
		and str(input_button.get_meta("target_id", "")) == "stonecutter-slot:input"
		and output_button != null
		and str(output_button.get_meta("slot_name", "")) == "output"
		and str(output_button.get_meta("target_id", "")) == "stonecutter-slot:output",
		"machine controls publish stable slot and target identities",
	)
	var apple_button: Button = panel.call("get_inventory_button", 0) as Button
	var stone_button: Button = panel.call("get_inventory_button", 1) as Button
	_check(
		apple_button != null
		and stone_button != null
		and str(apple_button.get_meta("target_id", "")) == "inventory:0"
		and str(stone_button.get_meta("target_id", "")) == "inventory:1",
		"player inventory controls expose stable slot identities",
	)

	var before_unsupported_inventory: Dictionary = inventory.call("serialize")
	var before_unsupported_machine: Dictionary = cutter.call(
		"get_machine_snapshot",
		machine_id,
	)
	if apple_button != null:
		await _click_control(apple_button)
	_check(
		inventory.call("serialize") == before_unsupported_inventory,
		"unsupported real pointer input cannot remove the player item",
	)
	_check(
		_stonecutter_slot_state(cutter.call("get_machine_snapshot", machine_id))
		== _stonecutter_slot_state(before_unsupported_machine),
		"unsupported real pointer input cannot mutate either machine slot",
	)
	var unsupported_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(unsupported_snapshot.get("status_kind", "")) == "warning"
		and str(unsupported_snapshot.get("status_reason", "")) == "unsupported_item"
		and str(unsupported_snapshot.get("status_target_id", "")) == "inventory:0"
		and str(unsupported_snapshot.get("status_text", "")).contains("不能在石材切割机"),
		"exact service rejection remains visible instead of being overwritten by generic UI text",
	)

	if stone_button != null:
		await _click_control(stone_button)
	var queued: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(
		str(queued.get("input", {}).get("item_id", "")) == "stone"
		and int(queued.get("input", {}).get("count", 0)) == 2
		and int(inventory.call("count_item", "stone")) == 0,
		"real pointer input transfers both stone items into the production machine",
	)
	_check(int(queued.get("queued_jobs", 0)) == 2, "stonecutter exposes two queued jobs")
	var live_eta := float(queued.get("estimated_total_seconds", 0.0))
	_check(
		live_eta > 4.0 and live_eta <= 5.0,
		"live stonecutter ETA reflects the complete two-job queue",
	)
	var input_feedback: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(input_feedback.get("status_kind", "")) == "success"
		and str(input_feedback.get("status_reason", "")) == "inventory_to_machine"
		and str(input_feedback.get("status_text", "")).contains("原料槽"),
		"successful input transfer publishes player-visible target-level feedback",
	)

	var furnace_id := "furnace@stonecutter-cross-domain"
	_check(bool(furnace.call("ensure_machine", furnace_id)), "production furnace registers beside the stonecutter")
	_check(
		bool(furnace.call("transfer_from_inventory", inventory, 2, FurnaceScript.SLOT_INPUT, furnace_id)),
		"shared scheduler companion receives real iron input",
	)
	_check(
		bool(furnace.call("transfer_from_inventory", inventory, 3, FurnaceScript.SLOT_FUEL, furnace_id)),
		"shared scheduler companion receives real fuel",
	)
	var audio_before := int(
		(participant.call("get_lifecycle_snapshot") as Dictionary).get(
			"completion_audio_count",
			0,
		)
	)
	var batch: Dictionary = scheduler.call("advance_time", 6.1, true)
	for _frame in 4:
		await process_frame
	panel.call("refresh")
	_check(
		int(batch.get("advanced_domain_count", 0)) == 3,
		"one scheduler batch advances both machine domains and bounded automation",
	)
	_check(
		int(batch.get("changed_machine_count", 0)) == 2,
		"cross-domain batch changes the stonecutter and companion furnace",
	)
	_check(processed_events.size() == 2, "two completed cuts emit exactly two production events")
	_check(announcements.size() == 1, "cross-domain completions create one bounded player summary")
	if not announcements.is_empty():
		var summary: Dictionary = announcements[0]
		_check(int(summary.get("completed_jobs", 0)) == 3, "summary preserves one smelt and two cuts")
		_check(int(summary.get("machine_type_count", 0)) == 2, "summary preserves both machine types")
		_check(
			str(summary.get("message", "")).contains("铁锭")
			and str(summary.get("message", "")).contains("石台阶"),
			"summary names both real outputs",
		)
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(
		int(lifecycle.get("completion_audio_count", 0)) == audio_before + 1,
		"cross-domain completion consumes one sound budget",
	)
	var completed: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(
		str(completed.get("output", {}).get("item_id", "")) == "stone_slab"
		and int(completed.get("output", {}).get("count", 0)) == 4
		and completed.get("input", {}).is_empty(),
		"bounded machine time produces exactly four visible stone slabs",
	)
	_check(
		int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1,
		"shared scheduler companion produces exactly one iron ingot",
	)
	var processed_feedback: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(processed_feedback.get("status_kind", "")) == "success"
		and str(processed_feedback.get("status_reason", "")) == "item_processed"
		and str(processed_feedback.get("status_text", "")).contains("石台阶"),
		"processing completion publishes exact visible output feedback",
	)
	_check(
		not bool(
			block_interaction.call(
				"can_break_block",
				world,
				cutter_position,
				"stonecutter",
			)
		),
		"non-empty stonecutter remains protected from destructive removal",
	)

	_check(
		int(inventory.call("add_item", "wooden_pickaxe", 35)) == 0,
		"fixture fills every remaining inventory slot with non-stackable items",
	)
	_check(_count_empty_slots(inventory) == 0, "player inventory is genuinely full before output collection")
	var before_full_inventory: Dictionary = inventory.call("serialize")
	var before_full_machine: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	if output_button != null:
		await _click_control(output_button)
	_check(
		inventory.call("serialize") == before_full_inventory,
		"full-inventory output failure cannot partially mutate player slots",
	)
	_check(
		_stonecutter_slot_state(cutter.call("get_machine_snapshot", machine_id))
		== _stonecutter_slot_state(before_full_machine),
		"full-inventory output failure keeps all slabs safely inside the machine",
	)
	var full_failure: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(full_failure.get("status_kind", "")) == "warning"
		and str(full_failure.get("status_reason", "")) == "inventory_full"
		and str(full_failure.get("status_target_id", "")) == "stonecutter-slot:output"
		and str(full_failure.get("status_text", "")).contains("安全保留"),
		"full-inventory rejection exposes exact reason, output target and conservation guarantee",
	)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(
		image != null and not image.is_empty(),
		"stonecutter closed-loop journey renders a non-empty desktop frame",
	)
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "stonecutter evidence uses the requested 1024x576 viewport")
		_save_image(image)

	await _tap_key(KEY_ESCAPE)
	_check(
		int(game_ui.call("get_active_overlay")) == 0
		and hub.get("input_context").call("get_context") == InputContextScript.CONTEXT_GAMEPLAY,
		"Esc closes the stonecutter and restores the gameplay context",
	)
	_check(
		bool(player.get("input_enabled"))
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"closing stonecutter restores production player input and mouse capture",
	)

	var expected_pending_inventory: Dictionary = inventory.call("serialize")
	var processed_count_before_reload := processed_events.size()
	var announcement_count_before_reload := announcements.size()
	_check(bool(hub.call("save_current")), "pending stonecutter output joins the authoritative world save")
	var pending_state: Dictionary = hub.get("save_service").call("load_world", _world_id)
	_check(not pending_state.is_empty(), "saved shared-machine world is loadable")
	_check(
		_canonical_inventory(pending_state.get("inventory", {}))
		== _canonical_inventory(expected_pending_inventory),
		"world.json contains the exact full player inventory in canonical form",
	)
	var pending_cutter: Dictionary = (
		pending_state.get("machines", {})
		.get("stonecutters", {})
		.get(machine_id, {})
	)
	var pending_furnace: Dictionary = (
		pending_state.get("machines", {})
		.get("furnaces", {})
		.get(furnace_id, {})
	)
	_check(
		str(pending_cutter.get("output", {}).get("item_id", "")) == "stone_slab"
		and int(pending_cutter.get("output", {}).get("count", 0)) == 4,
		"world.json retains the uncollected slab output exactly once",
	)
	_check(
		str(pending_furnace.get("output", {}).get("item_id", "")) == "iron_ingot"
		and int(pending_furnace.get("output", {}).get("count", 0)) == 1,
		"world.json preserves the adjacent machine output exactly once",
	)
	var saved_overrides: Dictionary = pending_state.get("world", {}).get("block_overrides", {})
	var cutter_key := "%d,%d,%d" % [
		cutter_position.x,
		cutter_position.y,
		cutter_position.z,
	]
	_check(
		str(saved_overrides.get(cutter_key, "")) == "stonecutter",
		"authoritative save retains the real stonecutter world override",
	)

	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	_check(
		str(hub.get("current_world_id")).is_empty()
		and not bool(scheduler.call("is_active")),
		"return to menu clears the machine session and stops shared scheduling",
	)
	_check(
		int((cutter.call("get_runtime_snapshot") as Dictionary).get("machine_count", -1)) == 0,
		"return to menu clears in-memory stonecutter records",
	)

	game.call("begin_world_state", pending_state)
	var first_reload := await _wait_for_world_ready(game, hub)
	_check(first_reload, "saved pending-output world reloads through production composition")
	if not first_reload:
		await _finish(game, hub)
		return
	_check(
		inventory.call("serialize") == expected_pending_inventory,
		"first reload restores the exact full inventory without drift",
	)
	_check(
		int(cutter.call("get_machine_ids").count(machine_id)) == 1,
		"first reload restores exactly one stonecutter record",
	)
	_check(
		int(furnace.call("get_machine_ids").count(furnace_id)) == 1,
		"first reload restores exactly one adjacent furnace record",
	)
	var reloaded_pending: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(
		str(reloaded_pending.get("output", {}).get("item_id", "")) == "stone_slab"
		and int(reloaded_pending.get("output", {}).get("count", 0)) == 4,
		"first reload restores the pending slabs without loss or duplication",
	)
	_check(
		int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1,
		"first reload preserves the adjacent machine output without duplication",
	)
	_check(
		processed_events.size() == processed_count_before_reload
		and announcements.size() == announcement_count_before_reload,
		"reload does not replay historical processing or summary feedback",
	)
	_check(
		str(world.call("get_block", cutter_position)) == "stonecutter",
		"first reload restores the real stonecutter voxel",
	)

	var machine_chunk: Vector2i = world.call("block_to_chunk", cutter_position)
	_check(
		(world.call("get_loaded_chunk_coords") as Array).has(machine_chunk),
		"stonecutter chunk is loaded before the unload lifecycle check",
	)
	var unloaded_chunks: Array[Vector2i] = []
	world.connect(
		"chunk_unloaded",
		func(chunk_coord: Vector2i) -> void:
			unloaded_chunks.append(chunk_coord)
	)
	var far_chunk := machine_chunk + Vector2i(int(world.get("unload_distance")) + 3, 0)
	var far_focus := Vector3(
		far_chunk.x * CHUNK_SIZE + 8.5,
		player.global_position.y,
		far_chunk.y * CHUNK_SIZE + 8.5,
	)
	world.call("set_focus", far_focus)
	for _frame in 8:
		await process_frame
	_check(
		not (world.call("get_loaded_chunk_coords") as Array).has(machine_chunk)
		and unloaded_chunks.has(machine_chunk),
		"moving streaming focus beyond the unload radius removes the real machine chunk",
	)
	_check(
		bool(cutter.call("has_machine", machine_id))
		and int((cutter.call("get_machine_snapshot", machine_id) as Dictionary).get("output", {}).get("count", 0)) == 4,
		"chunk unload preserves authoritative machine identity and pending output",
	)
	_check(
		int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1,
		"stonecutter chunk unload cannot mutate the adjacent machine domain",
	)
	world.call("set_focus", player)
	world.call("force_load_chunk", machine_chunk)
	for _frame in 4:
		await process_frame
	_check(
		(world.call("get_loaded_chunk_coords") as Array).has(machine_chunk),
		"returning focus reloads the original stonecutter chunk",
	)
	_check(
		str(world.call("get_block", cutter_position)) == "stonecutter"
		and int((cutter.call("get_machine_snapshot", machine_id) as Dictionary).get("output", {}).get("count", 0)) == 4,
		"chunk reload restores the real voxel while retaining exact machine output",
	)

	await _aim_at(player, world.call("block_to_world", cutter_position))
	_check(_focus_hits_block(player, cutter_position), "reloaded player can focus the persisted stonecutter")
	await _right_click_center()
	_check(
		int(game_ui.call("get_active_overlay")) == OverlayIds.STONECUTTER,
		"reloaded stonecutter remains usable through real right click",
	)
	var reopened_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(reopened_snapshot.get("status_kind", "")) == "idle"
		and str(reopened_snapshot.get("status_reason", "")) != "inventory_full",
		"reopening after reload clears stale failure feedback",
	)
	output_button = panel.call(
		"get_machine_slot_button",
		StonecutterScript.SLOT_OUTPUT,
	) as Button
	var before_reloaded_full_inventory: Dictionary = inventory.call("serialize")
	if output_button != null:
		await _click_control(output_button)
	_check(
		inventory.call("serialize") == before_reloaded_full_inventory
		and int((cutter.call("get_machine_snapshot", machine_id) as Dictionary).get("output", {}).get("count", 0)) == 4,
		"reloaded full-inventory failure remains atomic",
	)
	var reloaded_failure: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(reloaded_failure.get("status_reason", "")) == "inventory_full"
		and str(reloaded_failure.get("status_target_id", "")) == "stonecutter-slot:output",
		"reloaded failure still exposes the exact production rejection",
	)

	var freed_index := _find_item_slot(inventory, "wooden_pickaxe")
	_check(
		freed_index >= 0
		and not inventory.call("remove_from_slot", freed_index, 1).is_empty(),
		"fixture frees exactly one real inventory slot",
	)
	_check(_count_empty_slots(inventory) == 1, "one and only one inventory slot is available for collection")
	output_button = panel.call(
		"get_machine_slot_button",
		StonecutterScript.SLOT_OUTPUT,
	) as Button
	if output_button != null:
		await _click_control(output_button)
	_check(
		int(inventory.call("count_item", "stone_slab")) == 4,
		"real pointer collection transfers all pending slabs after space is freed",
	)
	var collected_machine: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(
		collected_machine.get("input", {}).is_empty()
		and collected_machine.get("output", {}).is_empty(),
		"successful collection leaves no hidden stonecutter items",
	)
	_check(
		int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1,
		"collecting slabs cannot consume or duplicate the adjacent furnace output",
	)
	var collected_feedback: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(collected_feedback.get("status_kind", "")) == "success"
		and str(collected_feedback.get("status_reason", "")) == "machine_to_inventory"
		and str(collected_feedback.get("status_text", "")).contains("石台阶"),
		"successful output collection publishes exact visible feedback",
	)
	_check(
		bool(
			block_interaction.call(
				"can_break_block",
				world,
				cutter_position,
				"stonecutter",
			)
		),
		"empty stonecutter becomes safely removable",
	)

	await _tap_key(KEY_ESCAPE)
	var expected_final_inventory: Dictionary = inventory.call("serialize")
	_check(bool(hub.call("save_current")), "collected stonecutter result joins a second authoritative save")
	var final_state: Dictionary = hub.get("save_service").call("load_world", _world_id)
	_check(
		_canonical_inventory(final_state.get("inventory", {}))
		== _canonical_inventory(expected_final_inventory),
		"final world.json contains the exact collected inventory",
	)
	var final_cutter: Dictionary = (
		final_state.get("machines", {})
		.get("stonecutters", {})
		.get(machine_id, {})
	)
	var final_furnace: Dictionary = (
		final_state.get("machines", {})
		.get("furnaces", {})
		.get(furnace_id, {})
	)
	_check(
		final_cutter.get("input", {}).is_empty()
		and final_cutter.get("output", {}).is_empty(),
		"final world.json records an empty stonecutter without resurrecting consumed input",
	)
	_check(
		str(final_furnace.get("output", {}).get("item_id", "")) == "iron_ingot"
		and int(final_furnace.get("output", {}).get("count", 0)) == 1,
		"final world.json preserves the adjacent machine output exactly once",
	)

	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	game.call("begin_world_state", final_state)
	var second_reload := await _wait_for_world_ready(game, hub)
	_check(second_reload, "collected-result world completes a second production reload")
	if not second_reload:
		await _finish(game, hub)
		return
	_check(
		inventory.call("serialize") == expected_final_inventory,
		"second reload restores the exact collected inventory",
	)
	_check(
		int(inventory.call("count_item", "stone_slab")) == 4
		and int(inventory.call("count_item", "stone")) == 0,
		"second reload preserves slab conservation without duplicated output or resurrected stone",
	)
	var second_cutter: Dictionary = cutter.call("get_machine_snapshot", machine_id)
	_check(
		second_cutter.get("input", {}).is_empty()
		and second_cutter.get("output", {}).is_empty(),
		"second reload preserves the empty stonecutter exactly",
	)
	_check(
		int((furnace.call("get_machine_snapshot", furnace_id) as Dictionary).get("output", {}).get("count", 0)) == 1,
		"second reload preserves exactly one adjacent iron ingot",
	)
	_check(
		processed_events.size() == processed_count_before_reload
		and announcements.size() == announcement_count_before_reload,
		"two complete reloads never replay the original processing or summary events",
	)
	_check(
		str(world.call("get_block", cutter_position)) == "stonecutter",
		"second reload retains the player-visible stonecutter block",
	)

	await _aim_at(player, world.call("block_to_world", cutter_position))
	await _right_click_center()
	var final_panel_snapshot: Dictionary = panel.call("get_visual_snapshot")
	_check(
		str(final_panel_snapshot.get("status_kind", "")) == "idle"
		and int(
			final_panel_snapshot.get("machine_slots", {})
			.get("output", {})
			.get("count", -1)
		) == 0,
		"final reload reopens a clean usable stonecutter without stale output or feedback",
	)
	await _tap_key(KEY_ESCAPE)
	await _finish(game, hub)


func _wait_for_world_ready(game: Node, hub: Node) -> bool:
	for _frame in WORLD_READY_FRAMES:
		await process_frame
		var world: Node = game.get("world") as Node if is_instance_valid(game) else null
		var player: Node = game.get("player") as Node if is_instance_valid(game) else null
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(hub.get("current_world_id")) == _world_id
			and bool(hub.get("machine_runtime").call("is_active"))
		):
			return true
	return false


func _build_arena(world: Node, player: Node3D) -> Dictionary:
	var origin: Vector3i = world.call("world_to_block", player.global_position)
	var floor_y := clampi(origin.y - 1, 2, 58)
	var changes: Array = []
	for x_offset in range(-5, 6):
		for z_offset in range(-7, 4):
			var floor_position := Vector3i(
				origin.x + x_offset,
				floor_y,
				origin.z + z_offset,
			)
			changes.append({
				"position": floor_position,
				"block_id": "stone",
			})
			for y_offset in range(1, 5):
				changes.append({
					"position": floor_position + Vector3i(0, y_offset, 0),
					"block_id": "air",
				})
	if world.has_method("apply_block_mutations"):
		world.call("apply_block_mutations", changes, "qa_stonecutter_closed_loop_arena")
	else:
		for change: Dictionary in changes:
			world.call(
				"set_block",
				change.get("position", Vector3i.ZERO),
				str(change.get("block_id", "air")),
			)
	return {
		"floor_y": floor_y,
		"player_position": Vector3(
			origin.x + 0.5,
			floor_y + 1.25,
			origin.z + 0.5,
		),
		"machine_position": Vector3i(
			origin.x,
			floor_y + 1,
			origin.z - MACHINE_DISTANCE,
		),
	}


func _settle_player(player: CharacterBody3D, frame_limit: int) -> void:
	var stable_frames := 0
	var previous := player.global_position
	for _frame in frame_limit:
		await physics_frame
		await process_frame
		var current := player.global_position
		if current.distance_to(previous) <= 0.002:
			stable_frames += 1
			if stable_frames >= 8:
				return
		else:
			stable_frames = 0
		previous = current


func _aim_at(player: Node3D, target: Vector3) -> void:
	var camera: Camera3D = player.call("get_view_camera") as Camera3D
	if camera != null:
		camera.look_at(target, Vector3.UP)
	for _frame in 2:
		await physics_frame
		await process_frame
	var ray := player.get_node_or_null(
		"CameraPivot/Camera3D/InteractionRay",
	) as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _focus_hits_block(player: Node, expected: Vector3i) -> bool:
	var raw_focus: Variant = player.call("get_interaction_focus")
	if raw_focus is not Dictionary:
		return false
	var focus: Dictionary = raw_focus
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


func _is_finite_position(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


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
	if control == null or not is_instance_valid(control):
		return
	var visible := await _ensure_control_visible(control)
	var identity := str(control.get_meta("target_id", control.name))
	_check(
		visible,
		"real pointer target is visible inside its scroll viewport: %s" % identity,
	)
	if not visible:
		return
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


func _ensure_control_visible(control: Control) -> bool:
	var scroll := _ancestor_scroll_container(control)
	if scroll != null:
		scroll.ensure_control_visible(control)
		for _frame in 3:
			await process_frame
		scroll.ensure_control_visible(control)
		await RenderingServer.frame_post_draw
		await process_frame
		return scroll.get_global_rect().grow(-3.0).has_point(
			control.get_global_rect().get_center()
		)
	await process_frame
	return Rect2(Vector2.ZERO, Vector2(root.size)).has_point(
		control.get_global_rect().get_center()
	)


func _ancestor_scroll_container(control: Control) -> ScrollContainer:
	var current: Node = control.get_parent()
	while current != null:
		if current is ScrollContainer:
			return current as ScrollContainer
		current = current.get_parent()
	return null


func _tap_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _rect_is_inside_viewport(rect: Rect2) -> bool:
	var transformed_start := _canvas_to_viewport(rect.position)
	var transformed_end := _canvas_to_viewport(rect.end)
	var transformed_rect := Rect2(
		transformed_start,
		transformed_end - transformed_start,
	)
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	return (
		transformed_rect.position.x >= -0.5
		and transformed_rect.position.y >= -0.5
		and transformed_rect.end.x <= bounds.end.x + 0.5
		and transformed_rect.end.y <= bounds.end.y + 0.5
	)


func _canvas_to_viewport(position: Vector2) -> Vector2:
	return root.get_final_transform() * position


func _canonical_inventory(raw_data: Variant) -> Dictionary:
	if raw_data is not Dictionary:
		return {}
	var data: Dictionary = raw_data
	var verifier = InventoryScript.new(
		maxi(9, int(data.get("slot_count", 36))),
		maxi(1, int(data.get("hotbar_size", 9))),
	)
	var restored := bool(verifier.deserialize(data))
	var result: Dictionary = verifier.serialize() if restored else {}
	verifier.free()
	return result


func _stonecutter_slot_state(raw_snapshot: Variant) -> Dictionary:
	if raw_snapshot is not Dictionary:
		return {}
	var snapshot: Dictionary = raw_snapshot
	return {
		"input": _canonical_slot(snapshot.get("input", {})),
		"output": _canonical_slot(snapshot.get("output", {})),
	}


func _canonical_slot(raw_slot: Variant) -> Dictionary:
	if raw_slot is not Dictionary:
		return {}
	var slot: Dictionary = raw_slot
	var item_id := str(slot.get("item_id", ""))
	var count := int(slot.get("count", 0))
	if item_id.is_empty() or count <= 0:
		return {}
	var result := {"item_id": item_id, "count": count}
	var raw_metadata: Variant = slot.get("metadata", {})
	if raw_metadata is Dictionary and not raw_metadata.is_empty():
		result["metadata"] = raw_metadata.duplicate(true)
	return result


func _count_empty_slots(inventory: Node) -> int:
	var empty_count := 0
	for index in int(inventory.get("slot_count")):
		if inventory.call("get_slot", index).is_empty():
			empty_count += 1
	return empty_count


func _find_item_slot(inventory: Node, item_id: String) -> int:
	for index in int(inventory.get("slot_count")):
		var slot: Dictionary = inventory.call("get_slot", index)
		if str(slot.get("item_id", "")) == item_id:
			return index
	return -1


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(
		error == OK and FileAccess.file_exists(_capture_path),
		"stonecutter desktop screenshot is saved",
	)


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in 12:
				await process_frame
		if (
			not _world_id.is_empty()
			and hub.get("save_service") != null
			and bool(hub.get("save_service").call("world_exists", _world_id))
		):
			hub.get("save_service").call("delete_world", _world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null:
			if audio.has_method("dispose"):
				audio.call("dispose")
			elif audio.has_method("shutdown"):
				audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA STONECUTTER MACHINE DESKTOP PASS | checks=%d | capture=%s"
			% [checks, _capture_path]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA STONECUTTER MACHINE DESKTOP FAILURE: %s" % failure)
	print(
		"QA STONECUTTER MACHINE DESKTOP FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
