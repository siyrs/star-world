extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const AutomationPolicy = preload("res://src/machine/machine_automation_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://mixed-runtime-endurance-desktop.png"
const READY_FRAMES := 720
const STREAM_FRAMES := 420
const CLEANUP_FRAMES := 12
const HOSTILE_DROP_COUNT := 64
const CROP_WIDTH := 8
const CROP_DEPTH := 8
const CROP_COUNT := CROP_WIDTH * CROP_DEPTH
const FURNACE_COUNT := 8
const STONECUTTER_COUNT := 8
const MACHINE_COUNT := FURNACE_COUNT + STONECUTTER_COUNT
const MAX_SETUP_MILLISECONDS := 30000.0
const MAX_MIXED_MILLISECONDS := 30000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_RELOAD_MILLISECONDS := 30000.0
const MAX_SAVE_BYTES := 3000000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}
var _machine_records: Array[Dictionary] = []
var _sample_blocks: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var menu_node_baseline := 0
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 5:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production mixed endurance exposes its service hub")
	if hub == null:
		await _finish(game, hub)
		return
	menu_node_baseline = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var state: Dictionary = hub.save_service.create_world(
		"Mixed-Endurance-%d" % Time.get_ticks_msec(),
		"star_continent",
		67120539
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "mixed endurance creates a temporary production world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"mixed endurance production world reaches a bounded ready state",
	)
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var scheduler: Node = hub.get("machine_runtime") as Node
	var machine_participant: Node = hub.get("machine_runtime_participant") as Node
	var furnace: Node = hub.get("furnace_service") as Node
	var stonecutter: Node = hub.get("stonecutter_service") as Node
	var automation: Node = hub.get("machine_automation_service") as Node
	var containers: Node = hub.get("container_storage") as Node
	var agriculture: Node = hub.get("agriculture_service") as Node
	var agriculture_participant: Node = hub.get("agriculture_runtime_participant") as Node
	var spawner: Node = hub.get("creature_spawner") as Node
	var pickup_coordinator: Node = hub.get("pickup_stack_coordinator") as Node
	_check(
		world != null
		and player != null
		and scheduler != null
		and machine_participant != null
		and furnace != null
		and stonecutter != null
		and automation != null
		and containers != null
		and agriculture != null
		and agriculture_participant != null
		and spawner != null
		and pickup_coordinator != null,
		"mixed endurance mounts world, machine, agriculture, hostile and pickup runtimes",
	)
	if (
		world == null
		or player == null
		or scheduler == null
		or furnace == null
		or stonecutter == null
		or automation == null
		or containers == null
		or agriculture == null
		or agriculture_participant == null
		or spawner == null
		or pickup_coordinator == null
	):
		await _finish(game, hub)
		return
	_check(
		world.has_method("apply_block_mutations")
		and world.has_method("get_recent_chunk_cache_stats"),
		"mixed endurance uses batched mutations and recent Chunk snapshots",
	)
	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var center_chunk: Vector2i = world.call("block_to_chunk", player_block)
	var floor_y := clampi(player_block.y - 1, 12, 52)
	var base_x := (center_chunk.x + 1) * 16
	var base_z := (center_chunk.y - 1) * 16
	var fixture: Dictionary = _build_mixed_fixture(base_x, base_z, floor_y)
	var mutations: Array = fixture.get("mutations", [])
	var agriculture_state: Dictionary = fixture.get("agriculture", {})
	_machine_records = fixture.get("machines", [])
	_check(
		mutations.size() >= 600 and mutations.size() <= 4096,
		"mixed fixture uses hundreds of bounded production world mutations",
	)
	_check(_machine_records.size() == MACHINE_COUNT, "mixed fixture contains sixteen production machines")
	var target_coords := _unique_chunk_coords(world, mutations)
	_check(target_coords.size() >= 6, "mixed fixture spans at least six real Chunk coordinates")
	_force_load_chunks(world, target_coords)
	world.call("reset_chunk_rebuild_stats")
	var setup_started := Time.get_ticks_usec()
	var setup_result: Dictionary = world.call(
		"apply_block_mutations", mutations, "mixed_runtime_endurance_fixture"
	)
	var setup_milliseconds := float(Time.get_ticks_usec() - setup_started) / 1000.0
	_check(bool(setup_result.get("success", false)), "mixed fixture commits through the production batch API")
	_check(int(setup_result.get("changed", 0)) >= 560, "mixed fixture changes the expected production cells")
	_check(setup_milliseconds <= MAX_SETUP_MILLISECONDS, "mixed fixture setup remains inside thirty seconds")

	var mixed_started := Time.get_ticks_usec()
	_register_and_feed_machines(furnace, stonecutter, containers)
	var automation_before: Dictionary = automation.call("get_runtime_snapshot")
	_check(
		int(automation_before.get("tracked_machine_count", 0)) >= MACHINE_COUNT,
		"mixed endurance registers all machine candidates in the production automation directory",
	)
	# The production automation contract is intentionally bounded by both 16
	# machines and 256 inspected container slots per cycle. Multiple real cycles
	# are required to feed sixteen 27-slot input chests without raising budgets.
	for _cycle in 4:
		scheduler.call("advance_time", 0.5, true)
	scheduler.call("advance_time", 6.5, true)
	var machine_summary: Dictionary = machine_participant.call("flush_pending_completion_batch")
	for _cycle in 4:
		scheduler.call("advance_time", 0.5, true)
	_check(
		int(machine_summary.get("completed_jobs", 0)) == MACHINE_COUNT
		and int(machine_summary.get("item_total", 0)) == FURNACE_COUNT + STONECUTTER_COUNT * 2,
		"mixed endurance completes all furnace and stonecutter jobs exactly",
	)
	var machine_outputs := _count_machine_output_containers(containers)
	_check(
		int(machine_outputs.get("iron_ingot", 0)) == FURNACE_COUNT
		and int(machine_outputs.get("stone_slab", 0)) == STONECUTTER_COUNT * 2,
		"mixed endurance automation collects every machine output into lower chests",
	)

	agriculture.call("deactivate")
	agriculture.call("detach_world")
	_check(agriculture.call("deserialize", agriculture_state), "mixed agriculture accepts the production state schema")
	agriculture.call("attach_world", world, hub.inventory)
	agriculture.call("activate")
	world.call("reset_chunk_rebuild_stats")
	agriculture.call("advance_time", 200.0)
	for _frame in 4:
		await process_frame
	var maturity_summary: Dictionary = agriculture_participant.call("flush_pending_maturity_batch")
	_check(
		int(maturity_summary.get("matured_count", 0)) == CROP_COUNT,
		"mixed endurance matures all sixty-four production crops in one exact batch",
	)

	hub.inventory.clear()
	spawner.call("set_active", true)
	spawner.call("clear_creature_population")
	var drop_center := Vector3(base_x + 10.5, floor_y + 2.0, base_z + 5.5)
	for index in HOSTILE_DROP_COUNT:
		var raw_creature: Variant = spawner.call("spawn_creature", "zombie", drop_center)
		if raw_creature is Node3D:
			var creature: Node3D = raw_creature
			creature.set_physics_process(false)
			creature.set("drops", {"rotten_flesh": 1})
			creature.call("die")
		if index % 16 == 15:
			await process_frame
	for _frame in 30:
		await process_frame
	var pickup_snapshot: Dictionary = pickup_coordinator.call("get_snapshot")
	_check(
		int(pickup_snapshot.get("pickup_node_count", 999)) <= 8
		and int(pickup_snapshot.get("max_pickup_nodes_observed", 999))
		<= int(pickup_snapshot.get("max_pickup_nodes", 128)),
		"mixed endurance keeps physical pickup nodes inside the hard budget",
	)
	_check(
		int(pickup_snapshot.get("visible_item_total", 0)) == HOSTILE_DROP_COUNT
		and int(pickup_snapshot.get("pending_item_total", -1)) == 0,
		"mixed endurance preserves every hostile drop across stacking and collection",
	)
	_check(
		int(pickup_snapshot.get("stacked_pickup_node_count", 0)) > 0
		and int(pickup_snapshot.get("merged_item_count", 0)) >= HOSTILE_DROP_COUNT - 8,
		"mixed endurance produces visible counted piles instead of one Area3D per death",
	)

	var center_world := Vector3(base_x + 18.0, floor_y + 4.0, base_z + 14.0)
	var far_world := center_world + Vector3(16.0 * 10.0, 0.0, 16.0 * 10.0)
	var cache_before: Dictionary = world.call("get_recent_chunk_cache_stats")
	var hits_before := int(cache_before.get("hit_count", 0))
	world.call("set_focus", far_world)
	_check(
		await _wait_for_chunks_unloaded(world, target_coords),
		"mixed endurance unloads its complete multi-system region",
	)
	world.call("set_focus", center_world)
	_check(
		await _wait_for_chunks_loaded(world, target_coords),
		"mixed endurance streams its complete multi-system region back",
	)
	var cache_after: Dictionary = world.call("get_recent_chunk_cache_stats")
	var cache_hit_delta := int(cache_after.get("hit_count", 0)) - hits_before
	_check(
		cache_hit_delta >= target_coords.size(),
		"mixed endurance warm return restores every target Chunk from a numeric snapshot",
	)
	_check(
		int(cache_after.get("entry_count", 0)) <= int(cache_after.get("capacity", 0)),
		"mixed endurance keeps recent Chunk memory inside the sixty-four-entry budget",
	)

	var mixed_milliseconds := float(Time.get_ticks_usec() - mixed_started) / 1000.0
	_check(mixed_milliseconds <= MAX_MIXED_MILLISECONDS, "mixed machine, crop, hostile and revisit work stays inside thirty seconds")
	var node_count_before_capture := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var rebuild: Dictionary = world.call("get_chunk_rebuild_stats")
	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"fixture_mutations": mutations.size(),
		"changed_mutations": int(setup_result.get("changed", 0)),
		"target_chunk_count": target_coords.size(),
		"machine_count": MACHINE_COUNT,
		"machine_summary": machine_summary.duplicate(true),
		"machine_outputs": machine_outputs.duplicate(true),
		"crop_count": CROP_COUNT,
		"maturity_summary": maturity_summary.duplicate(true),
		"hostile_drop_count": HOSTILE_DROP_COUNT,
		"pickup_snapshot": pickup_snapshot.duplicate(true),
		"cache_hit_delta": cache_hit_delta,
		"cache_snapshot": cache_after.duplicate(true),
		"world_rebuild_requests": int(rebuild.get("request_count", 0)),
		"world_rebuild_executions": int(rebuild.get("execution_count", 0)),
		"setup_milliseconds": setup_milliseconds,
		"mixed_milliseconds": mixed_milliseconds,
		"node_count_before_capture": node_count_before_capture,
	}
	await _capture_visual_evidence(game, player, center_world)

	var pickup_nodes := _pickup_nodes(spawner)
	for pickup: Node3D in pickup_nodes:
		if is_instance_valid(pickup):
			pickup.global_position = player.global_position + Vector3(0.0, 0.6, 0.0)
			await physics_frame
			await process_frame
	for _frame in 6:
		await process_frame
	_check(
		int(hub.inventory.count_item("rotten_flesh")) == HOSTILE_DROP_COUNT,
		"mixed endurance preserves every hostile drop across stacking and collection",
	)
	var after_collection: Dictionary = pickup_coordinator.call("get_snapshot")
	_check(
		int(after_collection.get("pickup_node_count", -1)) == 0
		and int(after_collection.get("pending_item_total", -1)) == 0,
		"collecting stacked drops releases all pickup nodes and pending state",
	)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.call("save_current"))
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(saved, "mixed endurance joins the production atomic save transaction")
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "mixed endurance save remains below three megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "mixed endurance save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "mixed endurance reloads through the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "mixed endurance JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("pickup_stack")
		and not serialized.contains("pending_pickups")
		and not serialized.contains("merged_item_count")
		and not serialized.contains("recent_chunk_cache"),
		"pickup stacks, pending items and warm Chunk diagnostics remain transient",
	)
	_report["save_bytes"] = save_bytes
	_report["save_milliseconds"] = save_milliseconds
	_report["load_milliseconds"] = load_milliseconds

	var reload_started := Time.get_ticks_usec()
	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	_check(spawner.get_child_count() == 0, "return to menu clears creatures and physical pickups")
	_check(
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) <= menu_node_baseline + 90,
		"mixed world cleanup returns to a bounded menu node population",
	)
	game.call("begin_world_state", loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full mixed-session reload reaches a bounded playable state",
	)
	var reload_milliseconds := float(Time.get_ticks_usec() - reload_started) / 1000.0
	_check(reload_milliseconds <= MAX_RELOAD_MILLISECONDS, "mixed first-playable reload remains inside thirty seconds")
	world = game.get("world") as Node
	furnace = hub.get("furnace_service") as Node
	stonecutter = hub.get("stonecutter_service") as Node
	agriculture = hub.get("agriculture_service") as Node
	pickup_coordinator = hub.get("pickup_stack_coordinator") as Node
	_check(
		int(furnace.call("get_runtime_snapshot").get("machine_count", 0)) == FURNACE_COUNT
		and int(stonecutter.call("get_runtime_snapshot").get("machine_count", 0)) == STONECUTTER_COUNT,
		"full mixed reload restores both machine domains exactly once",
	)
	_check(
		int(agriculture.call("get_runtime_snapshot").get("crop_count", 0)) == CROP_COUNT,
		"full mixed reload restores all mature crops exactly once",
	)
	_check(
		int(hub.inventory.count_item("rotten_flesh")) == HOSTILE_DROP_COUNT,
		"full mixed reload restores collected hostile drops without duplication",
	)
	var fresh_pickups: Dictionary = pickup_coordinator.call("get_snapshot")
	_check(
		int(fresh_pickups.get("pickup_node_count", -1)) == 0
		and int(fresh_pickups.get("pending_item_total", -1)) == 0
		and int(fresh_pickups.get("merged_item_count", -1)) == 0,
		"new world session resets pickup stack diagnostics and pending items",
	)
	var fresh_cache: Dictionary = world.call("get_recent_chunk_cache_stats")
	_check(
		int(fresh_cache.get("entry_count", -1)) == 0
		and int(fresh_cache.get("hit_count", -1)) == 0,
		"full mixed reload starts with a clean recent Chunk cache",
	)
	for raw_position: Variant in _sample_blocks.keys():
		var sample_position: Vector3i = raw_position
		_check(
			str(world.call("get_block", sample_position)) == str(_sample_blocks[sample_position]),
			"full mixed reload restores sample %s exactly once" % str(sample_position),
		)
	_report["reload_ready_milliseconds"] = reload_milliseconds
	_write_report()
	await _finish(game, hub)


func _build_mixed_fixture(base_x: int, base_z: int, floor_y: int) -> Dictionary:
	var mutations: Array = []
	for x_offset in 20:
		for z_offset in 12:
			var floor_position := Vector3i(base_x + x_offset, floor_y, base_z + z_offset)
			mutations.append({"position": floor_position, "block_id": "stone_bricks"})
			var shape_position := floor_position + Vector3i.UP
			mutations.append({
				"position": shape_position,
				"block_id": "glass_pane" if (x_offset + z_offset) % 2 == 0 else "oak_fence",
			})
	var crops: Dictionary = {}
	var soils: Dictionary = {}
	var crop_ids := ["wheat", "carrot", "potato"]
	for index in CROP_COUNT:
		var crop_x := index % CROP_WIDTH
		var crop_z := int(index / CROP_WIDTH)
		var soil_position := Vector3i(base_x + crop_x, floor_y, base_z + 16 + crop_z)
		var crop_position := soil_position + Vector3i.UP
		var crop_id: String = crop_ids[index % crop_ids.size()]
		mutations.append({"position": soil_position, "block_id": "farmland_wet"})
		mutations.append({"position": crop_position, "block_id": "%s_stage_0" % crop_id})
		crops["crop@%d,%d,%d" % [crop_position.x, crop_position.y, crop_position.z]] = {
			"crop_id": crop_id,
			"position": [crop_position.x, crop_position.y, crop_position.z],
			"stage": 0,
			"elapsed_seconds": 0.0,
		}
		soils["soil@%d,%d,%d" % [soil_position.x, soil_position.y, soil_position.z]] = {
			"position": [soil_position.x, soil_position.y, soil_position.z],
			"manual_remaining_seconds": 600.0,
			"hydrated": true,
		}
	var records: Array[Dictionary] = []
	for global_index in MACHINE_COUNT:
		var furnace_domain := global_index < FURNACE_COUNT
		var domain_index := global_index if furnace_domain else global_index - FURNACE_COUNT
		var position := Vector3i(
			base_x + 24 + (domain_index % 4) * 3,
			floor_y + 2,
			base_z + int(domain_index / 4) * 5 + (0 if furnace_domain else 12)
		)
		var machine_type := "furnace" if furnace_domain else "stonecutter"
		var machine_id := "%s@%d,%d,%d" % [machine_type, position.x, position.y, position.z]
		var input_position := AutomationPolicy.input_position(position)
		var output_position := AutomationPolicy.output_position(position)
		mutations.append({"position": position + Vector3i.DOWN * 2, "block_id": "stone_bricks"})
		mutations.append({"position": output_position, "block_id": "chest"})
		mutations.append({"position": position, "block_id": machine_type})
		mutations.append({"position": input_position, "block_id": "chest"})
		records.append({
			"machine_type": machine_type,
			"machine_id": machine_id,
			"input_container_id": AutomationPolicy.container_id(input_position),
			"output_container_id": AutomationPolicy.container_id(output_position),
		})
	_sample_blocks[Vector3i(base_x, floor_y + 1, base_z)] = "glass_pane"
	_sample_blocks[Vector3i(base_x + 1, floor_y + 1, base_z)] = "oak_fence"
	_sample_blocks[Vector3i(base_x, floor_y + 1, base_z + 16)] = "wheat_stage_3"
	return {
		"mutations": mutations,
		"machines": records,
		"agriculture": {
			"version": 2,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"crops": crops,
			"soil_moisture": {"version": 1, "soils": soils},
		},
	}


func _register_and_feed_machines(furnace: Node, stonecutter: Node, containers: Node) -> void:
	for record: Dictionary in _machine_records:
		var machine_type := str(record.get("machine_type", ""))
		var service: Node = furnace if machine_type == "furnace" else stonecutter
		var machine_id := str(record.get("machine_id", ""))
		_check(bool(service.call("open_machine", machine_id)), "mixed endurance registers %s" % machine_id)
		service.call("close_machine")
		var input_id := str(record.get("input_container_id", ""))
		var output_id := str(record.get("output_container_id", ""))
		containers.call("ensure_container", input_id, "chest", 27)
		containers.call("ensure_container", output_id, "chest", 27)
		if machine_type == "furnace":
			_check(int(containers.call("add_item", input_id, "raw_iron", 1)) == 0, "mixed furnace input receives raw iron")
			_check(int(containers.call("add_item", input_id, "coal", 1)) == 0, "mixed furnace input receives fuel")
		else:
			_check(int(containers.call("add_item", input_id, "stone", 1)) == 0, "mixed stonecutter input receives stone")


func _count_machine_output_containers(containers: Node) -> Dictionary:
	var totals := {"iron_ingot": 0, "stone_slab": 0}
	for record: Dictionary in _machine_records:
		var item_id := "iron_ingot" if str(record.get("machine_type", "")) == "furnace" else "stone_slab"
		var container_id := str(record.get("output_container_id", ""))
		var slot_count := int(containers.call("get_slot_count", container_id))
		for index in slot_count:
			var slot: Dictionary = containers.call("get_slot", container_id, index)
			if str(slot.get("item_id", "")) == item_id:
				totals[item_id] = int(totals.get(item_id, 0)) + maxi(0, int(slot.get("count", 0)))
	return totals


func _pickup_nodes(spawner: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in spawner.get_children():
		if child is Node3D and child.has_method("get_pickup_snapshot"):
			result.append(child as Node3D)
	return result


func _capture_visual_evidence(game: Node3D, player: CharacterBody3D, center_world: Vector3) -> void:
	player.set_physics_process(false)
	player.global_position = center_world + Vector3(0.0, 20.0, -28.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.get_view_camera().look_at(center_world, Vector3.UP)
	_add_metric_overlay(game)
	for _frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production viewport renders the mixed endurance fixture")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "mixed endurance visual evidence uses 1024x576 resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var error := image.save_png(_capture_path)
		_check(error == OK and FileAccess.file_exists(_capture_path), "mixed endurance screenshot is saved")
	player.set_physics_process(true)


func _add_metric_overlay(game: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "MixedRuntimeEnduranceEvidence"
	layer.layer = 97
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(480, 240)
	var label := Label.new()
	var pickup: Dictionary = _report.get("pickup_snapshot", {})
	var cache: Dictionary = _report.get("cache_snapshot", {})
	var machine: Dictionary = _report.get("machine_summary", {})
	var maturity: Dictionary = _report.get("maturity_summary", {})
	label.text = (
		"MIXED RUNTIME ENDURANCE\n"
		+ "World  %d mutations / %d Chunks\n"
		+ "Machines  %d jobs / %d output items\n"
		+ "Crops  %d mature in one batch\n"
		+ "Hostile drops  %d items → %d pickup nodes\n"
		+ "Merged items  %d  |  stacked nodes %d\n"
		+ "Warm Chunk hits  %d  |  cache peak %d/%d\n"
		+ "Nodes at evidence  %d\n"
		+ "Mixed runtime  %.1f ms"
	) % [
		int(_report.get("changed_mutations", 0)),
		int(_report.get("target_chunk_count", 0)),
		int(machine.get("completed_jobs", 0)),
		int(machine.get("item_total", 0)),
		int(maturity.get("matured_count", 0)),
		int(_report.get("hostile_drop_count", 0)),
		int(pickup.get("pickup_node_count", 0)),
		int(pickup.get("merged_item_count", 0)),
		int(pickup.get("stacked_pickup_node_count", 0)),
		int(_report.get("cache_hit_delta", 0)),
		int(cache.get("max_entries", 0)),
		int(cache.get("capacity", 0)),
		int(_report.get("node_count_before_capture", 0)),
		float(_report.get("mixed_milliseconds", 0.0)),
	]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	layer.add_child(panel)
	game.add_child(layer)


func _unique_chunk_coords(world: Node, mutations: Array) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for raw_change: Variant in mutations:
		if raw_change is not Dictionary:
			continue
		var position := _vector3i_from((raw_change as Dictionary).get("position", []))
		unique[world.call("block_to_chunk", position)] = true
	var result: Array[Vector2i] = []
	for raw_coord: Variant in unique.keys():
		result.append(Vector2i(raw_coord))
	return result


func _force_load_chunks(world: Node, coords: Array[Vector2i]) -> void:
	for coord: Vector2i in coords:
		world.call("force_load_chunk", coord)


func _wait_for_chunks_unloaded(world: Node, coords: Array[Vector2i]) -> bool:
	for _frame in STREAM_FRAMES:
		await process_frame
		var loaded: Dictionary = world.get("chunks") as Dictionary
		var building: Dictionary = world.get("_building_chunks") as Dictionary
		var any_present := false
		for coord: Vector2i in coords:
			if loaded.has(coord) or building.has(coord):
				any_present = true
				break
		if not any_present:
			return true
	return false


func _wait_for_chunks_loaded(world: Node, coords: Array[Vector2i]) -> bool:
	for _frame in STREAM_FRAMES:
		await process_frame
		var loaded: Dictionary = world.get("chunks") as Dictionary
		var ready := true
		for coord: Vector2i in coords:
			var chunk: Node = loaded.get(coord) as Node
			if chunk == null or not is_instance_valid(chunk) or not bool(chunk.call("is_build_complete")):
				ready = false
				break
		if ready:
			return true
	return false


func _wait_for_world_ready(game: Node, hub: Node, expected_world_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world: Node = game.get("world") as Node
		var player: Node = game.get("player") as Node
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _write_report() -> void:
	_report["capture_path"] = _capture_path
	_report["report_path"] = _report_path
	_report["checks"] = checks
	_report["failure_count"] = failures.size()
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_check(file != null, "mixed endurance JSON report can be opened")
	if file == null:
		return
	file.store_string(JSON.stringify(_report, "\t", false))
	file.flush()
	file.close()
	_check(FileAccess.file_exists(_report_path), "mixed endurance JSON report is saved")


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
		print(
			"QA MIXED RUNTIME ENDURANCE DESKTOP PASS | checks=%d | capture=%s | report=%s"
			% [checks, _capture_path, _report_path]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MIXED RUNTIME ENDURANCE DESKTOP FAILURE: %s" % failure)
		print(
			"QA MIXED RUNTIME ENDURANCE DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _vector3i_from(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
