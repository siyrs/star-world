extends SceneTree

const GameScene = preload("res://scenes/game/game.tscn")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const LadderPolicyScript = preload("res://src/block/block_ladder_policy.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://structural-integrity-desktop.png"
const TARGET_DOOR_COUNT := 128
const TARGET_LADDER_COUNT := 256
const FALLBACK_DOOR_COUNT := 6
const FALLBACK_LADDER_COUNT := 10
const READY_FRAMES := 600
const INTEGRITY_SETTLE_FRAMES := 360
const CLEANUP_FRAMES := 12
const MAX_MAIN_CLEANUP_MILLISECONDS := 5000.0
const MAX_SAVE_MILLISECONDS := 10000.0
const MAX_LOAD_MILLISECONDS := 10000.0
const MAX_SAVE_BYTES := 2500000

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _report_path := ""
var _world_id := ""
var _report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	_report_path = _capture_path.get_basename() + ".json"
	root.size = Vector2i(1024, 576)
	var game = GameScene.instantiate()
	root.add_child(game)
	for _frame in 6:
		await process_frame
	var hub: Node = game.get("service_hub") as Node
	_check(hub != null, "production game exposes the service hub")
	if hub == null:
		await _finish(game, hub)
		return
	var state: Dictionary = hub.save_service.create_world(
		"Structural-Integrity-%d" % Time.get_ticks_msec(),
		"star_continent",
		93041726,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "desktop integrity journey creates a temporary world")
	game.begin_world_state(state)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"production world reaches a bounded playable state",
	)
	var world: Node = game.get("world") as Node
	var player: CharacterBody3D = game.get("player") as CharacterBody3D
	var inventory: Node = hub.get("inventory") as Node
	var integrity: Node = hub.get("structural_integrity_service") as Node
	var pickup_coordinator: Node = hub.get("pickup_stack_coordinator") as Node
	var pickup_parent: Node3D = hub.get("creature_spawner") as Node3D
	_check(
		world != null
		and world.has_method("apply_block_mutations")
		and world.has_method("reset_chunk_rebuild_stats"),
		"production world exposes bounded mutation and rebuild diagnostics",
	)
	_check(
		integrity != null
		and hub.get_node_or_null("StructuralIntegrity") == integrity
		and integrity.has_method("get_snapshot"),
		"production service hub exposes the stable structural integrity runtime",
	)
	_check(
		pickup_coordinator != null and pickup_parent != null,
		"production world composes bounded physical pickup fallback",
	)
	if world == null or player == null or inventory == null or integrity == null:
		await _finish(game, hub)
		return

	var player_block: Vector3i = world.call("world_to_block", player.global_position)
	var center_chunk: Vector2i = world.call("block_to_chunk", player_block)
	var floor_y := clampi(player_block.y - 1, 12, 50)
	var fixture: Dictionary = _build_main_fixture(center_chunk, floor_y)
	var setup_mutations: Array = fixture.get("mutations", [])
	var support_positions: Array[Vector3i] = fixture.get("support_positions", [])
	var target_door_cells: Array[Vector3i] = fixture.get("target_door_cells", [])
	var target_ladder_cells: Array[Vector3i] = fixture.get("target_ladder_cells", [])
	var control_doors: Array[Dictionary] = fixture.get("control_doors", [])
	var control_ladders: Array[Dictionary] = fixture.get("control_ladders", [])
	var gallery_origin: Vector3i = fixture.get("gallery_origin", Vector3i.ZERO)
	_check(
		setup_mutations.size() < 4096,
		"complete target and control gallery fits inside one production mutation batch",
	)
	_check(
		support_positions.size() == TARGET_DOOR_COUNT + TARGET_LADDER_COUNT,
		"target fixture owns one unique support per structure",
	)
	_check(
		target_door_cells.size() == TARGET_DOOR_COUNT * 2
		and target_ladder_cells.size() == TARGET_LADDER_COUNT,
		"fixture contains the exact door-half and ladder cell counts",
	)
	_force_load_mutation_chunks(world, setup_mutations)
	var setup_result: Dictionary = world.call(
		"apply_block_mutations",
		setup_mutations,
		"structural_integrity_scale_fixture",
	)
	_check(bool(setup_result.get("success", false)), "production world accepts the structural fixture batch")
	_check(
		await _wait_for_integrity_idle(integrity),
		"valid fixture drains the event queue without removing supported structures",
	)
	_check(_all_non_air(world, target_door_cells), "all target door halves exist before support removal")
	_check(_all_non_air(world, target_ladder_cells), "all target ladders exist before support removal")
	_check(_controls_valid(world, control_doors, control_ladders), "visual control structures begin valid")

	inventory.call("clear")
	integrity.call("clear", true)
	world.call("reset_chunk_rebuild_stats")
	var support_removals: Array = []
	for position: Vector3i in support_positions:
		support_removals.append({"position": position, "block_id": "air"})
	var cleanup_started := Time.get_ticks_usec()
	var support_result: Dictionary = world.call(
		"apply_block_mutations",
		support_removals,
		"structural_integrity_remove_supports",
	)
	_check(
		int(support_result.get("changed", 0)) == support_positions.size()
		and int(support_result.get("rejected", 0)) == 0,
		"one real batch removes every target support exactly once",
	)
	_check(
		await _wait_for_integrity_idle(integrity),
		"shared integrity runtime drains all cross-Chunk candidates",
	)
	var cleanup_milliseconds := float(Time.get_ticks_usec() - cleanup_started) / 1000.0
	_check(
		cleanup_milliseconds <= MAX_MAIN_CLEANUP_MILLISECONDS,
		"384 unsupported structures clean up inside the five-second desktop budget",
	)
	_check(_all_air(world, target_door_cells), "support loss leaves no floating or half-door cells")
	_check(_all_air(world, target_ladder_cells), "support loss leaves no un-climbable ladder remnants")
	_check(_controls_valid(world, control_doors, control_ladders), "supported control structures survive adjacent scale cleanup")
	_check(
		int(inventory.call("count_item", "oak_door")) == TARGET_DOOR_COUNT
		and int(inventory.call("count_item", "ladder")) == TARGET_LADDER_COUNT,
		"cleanup returns the exact canonical door and ladder totals",
	)
	var integrity_snapshot: Dictionary = integrity.call("get_snapshot")
	_check(
		int(integrity_snapshot.get("door_cleanup_count", 0)) == TARGET_DOOR_COUNT
		and int(integrity_snapshot.get("ladder_cleanup_count", 0)) == TARGET_LADDER_COUNT,
		"integrity diagnostics retain exact per-kind cleanup totals",
	)
	_check(
		int(integrity_snapshot.get("removed_block_count", 0))
		== TARGET_DOOR_COUNT * 2 + TARGET_LADDER_COUNT,
		"structure totals remain distinct from the 512 removed block cells",
	)
	_check(
		int(integrity_snapshot.get("cleanup_batch_count", 0)) == 1
		and int(integrity_snapshot.get("flush_count", 0)) == 1,
		"all unsupported structures coalesce into one shared cleanup flush",
	)
	_check(
		int(integrity_snapshot.get("candidate_overflow_count", -1)) == 0
		and int(integrity_snapshot.get("max_pending_candidates_observed", 0))
		<= int(integrity_snapshot.get("candidate_queue_budget", 0)),
		"cross-Chunk pressure remains inside the bounded candidate queue",
	)
	_check(
		int(integrity_snapshot.get("inventory_drop_count", 0))
		== TARGET_DOOR_COUNT + TARGET_LADDER_COUNT
		and int(integrity_snapshot.get("pickup_drop_count", -1)) == 0,
		"available inventory receives every structural return without physical overflow",
	)
	var rebuild: Dictionary = world.call("get_chunk_rebuild_stats")
	_check(
		int(rebuild.get("flush_count", 0)) == 2,
		"support removal and dependent cleanup use exactly two world rebuild flushes",
	)
	_check(
		int(rebuild.get("execution_count", 0)) <= 64
		and int(rebuild.get("max_dirty_chunks", 0)) <= 64,
		"hundreds of cell changes remain bounded by cross-Chunk population, not structure count",
	)
	_check(
		int(rebuild.get("coalesced_count", 0)) > int(rebuild.get("execution_count", 0)),
		"world diagnostics prove repeated boundary rebuild requests were coalesced",
	)

	var save_started := Time.get_ticks_usec()
	var saved := bool(hub.call("save_current"))
	var save_milliseconds := float(Time.get_ticks_usec() - save_started) / 1000.0
	_check(saved, "cleaned structures join the production atomic save transaction")
	var save_path := "user://worlds/%s/world.json" % _world_id
	var save_bytes := _file_length(save_path)
	_check(save_bytes > 0 and save_bytes <= MAX_SAVE_BYTES, "structural save remains below two and a half megabytes")
	_check(save_milliseconds <= MAX_SAVE_MILLISECONDS, "structural save remains inside ten seconds")
	var load_started := Time.get_ticks_usec()
	var loaded: Dictionary = hub.save_service.load_world(_world_id)
	var load_milliseconds := float(Time.get_ticks_usec() - load_started) / 1000.0
	_check(not loaded.is_empty(), "cleaned structural world reloads through the production save service")
	_check(load_milliseconds <= MAX_LOAD_MILLISECONDS, "structural JSON load remains inside ten seconds")
	var serialized := JSON.stringify(loaded)
	_check(
		not serialized.contains("structural_integrity")
		and not serialized.contains("pending_candidates")
		and not serialized.contains("loaded_chunks"),
		"integrity queues, counters and streaming snapshots never enter persistence",
	)
	var doors_before_reload := int(inventory.call("count_item", "oak_door"))
	var ladders_before_reload := int(inventory.call("count_item", "ladder"))
	hub.call("return_to_menu")
	for _frame in 12:
		await process_frame
	game.call("begin_world_state", loaded)
	_check(
		await _wait_for_world_ready(game, hub, _world_id),
		"full structural reload reaches a bounded playable state",
	)
	world = game.get("world") as Node
	player = game.get("player") as CharacterBody3D
	inventory = hub.get("inventory") as Node
	integrity = hub.get("structural_integrity_service") as Node
	pickup_coordinator = hub.get("pickup_stack_coordinator") as Node
	pickup_parent = hub.get("creature_spawner") as Node3D
	_check(await _wait_for_integrity_idle(integrity), "world-start override repair reaches an idle state")
	_check(_all_air(world, target_door_cells), "full reload preserves removal of every unsupported door half")
	_check(_all_air(world, target_ladder_cells), "full reload preserves removal of every unsupported ladder")
	_check(_controls_valid(world, control_doors, control_ladders), "full reload preserves supported control structures")
	_check(
		int(inventory.call("count_item", "oak_door")) == doors_before_reload
		and int(inventory.call("count_item", "ladder")) == ladders_before_reload,
		"full reload never duplicates structural return items",
	)
	var reload_integrity: Dictionary = integrity.call("get_snapshot")
	_check(
		int(reload_integrity.get("invalid_structure_count", -1)) == 0
		and int(reload_integrity.get("initial_override_scan_count", 0)) > 0,
		"world-start scan validates persisted controls without manufacturing cleanup",
	)

	var fallback: Dictionary = _build_fallback_fixture(gallery_origin, floor_y)
	var fallback_setup: Array = fallback.get("mutations", [])
	var fallback_supports: Array[Vector3i] = fallback.get("support_positions", [])
	var fallback_cells: Array[Vector3i] = fallback.get("structure_cells", [])
	_force_load_mutation_chunks(world, fallback_setup)
	var fallback_setup_result: Dictionary = world.call(
		"apply_block_mutations",
		fallback_setup,
		"structural_integrity_pickup_fixture",
	)
	_check(bool(fallback_setup_result.get("success", false)), "physical fallback fixture commits through production batching")
	_check(await _wait_for_integrity_idle(integrity), "supported fallback fixture reaches integrity idle")
	integrity.call("clear", true)
	var stone_capacity := int(inventory.call("get_add_capacity", "stone"))
	_check(int(inventory.call("add_item", "stone", stone_capacity)) == 0, "fallback phase fills every remaining inventory slot")
	_check(
		int(inventory.call("get_add_capacity", "oak_door")) == 0
		and int(inventory.call("get_add_capacity", "ladder")) == 0,
		"canonical structural stacks have no remaining inventory capacity",
	)
	var pickups_before := _pickup_totals(pickup_parent)
	var pickup_snapshot_before: Dictionary = (
		pickup_coordinator.call("get_snapshot")
		if pickup_coordinator != null and pickup_coordinator.has_method("get_snapshot")
		else {}
	)
	var fallback_removals: Array = []
	for position: Vector3i in fallback_supports:
		fallback_removals.append({"position": position, "block_id": "air"})
	world.call(
		"apply_block_mutations",
		fallback_removals,
		"structural_integrity_pickup_supports",
	)
	_check(await _wait_for_integrity_idle(integrity), "full-inventory cleanup drains through physical fallback")
	for _frame in 8:
		await process_frame
	var pickups_after := _pickup_totals(pickup_parent)
	_check(_all_air(world, fallback_cells), "full-inventory fallback also removes every invalid structural cell")
	_check(
		int(pickups_after.get("oak_door", 0)) - int(pickups_before.get("oak_door", 0))
		== FALLBACK_DOOR_COUNT
		and int(pickups_after.get("ladder", 0)) - int(pickups_before.get("ladder", 0))
		== FALLBACK_LADDER_COUNT,
		"physical fallback preserves exact door and ladder totals",
	)
	var fallback_snapshot: Dictionary = integrity.call("get_snapshot")
	_check(
		int(fallback_snapshot.get("inventory_drop_count", -1)) == 0
		and int(fallback_snapshot.get("pickup_drop_count", 0))
		== FALLBACK_DOOR_COUNT + FALLBACK_LADDER_COUNT
		and int(fallback_snapshot.get("pickup_node_count", 0)) <= 2,
		"full inventory aggregates sixteen returns into at most two pickup nodes",
	)
	var pickup_snapshot_after: Dictionary = (
		pickup_coordinator.call("get_snapshot")
		if pickup_coordinator != null and pickup_coordinator.has_method("get_snapshot")
		else {}
	)
	_check(
		int(pickup_snapshot_after.get("visible_item_total", 0))
		- int(pickup_snapshot_before.get("visible_item_total", 0))
		== FALLBACK_DOOR_COUNT + FALLBACK_LADDER_COUNT,
		"shared pickup runtime observes every structural fallback item",
	)

	await _position_for_capture(player, world, gallery_origin, floor_y)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "desktop viewport renders the surviving structure gallery and fallback drops")
	if image != null and not image.is_empty():
		_check(image.get_size() == root.size, "structural integrity evidence uses 1024x576 resolution")
		DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
		var image_error := image.save_png(_capture_path)
		_check(image_error == OK and FileAccess.file_exists(_capture_path), "structural integrity screenshot is saved")

	_report = {
		"schema_version": 1,
		"world_id": _world_id,
		"target_door_count": TARGET_DOOR_COUNT,
		"target_ladder_count": TARGET_LADDER_COUNT,
		"target_structure_count": TARGET_DOOR_COUNT + TARGET_LADDER_COUNT,
		"target_removed_block_count": TARGET_DOOR_COUNT * 2 + TARGET_LADDER_COUNT,
		"support_removal_count": support_positions.size(),
		"cleanup_milliseconds": cleanup_milliseconds,
		"integrity": integrity_snapshot,
		"world_rebuild": rebuild,
		"save_bytes": save_bytes,
		"save_milliseconds": save_milliseconds,
		"load_milliseconds": load_milliseconds,
		"fallback_door_count": FALLBACK_DOOR_COUNT,
		"fallback_ladder_count": FALLBACK_LADDER_COUNT,
		"fallback_integrity": fallback_snapshot,
		"pickup_runtime": pickup_snapshot_after,
	}
	_write_report()
	await _finish(game, hub)


func _build_main_fixture(center_chunk: Vector2i, floor_y: int) -> Dictionary:
	var mutation_map: Dictionary = {}
	var support_positions: Array[Vector3i] = []
	var support_seen: Dictionary = {}
	var target_door_cells: Array[Vector3i] = []
	var target_ladder_cells: Array[Vector3i] = []
	var control_doors: Array[Dictionary] = []
	var control_ladders: Array[Dictionary] = []
	var base_chunk := center_chunk - Vector2i(2, 2)

	for door_index in TARGET_DOOR_COUNT:
		var chunk_index := int(door_index / 8)
		var within := door_index % 8
		var chunk_coord := base_chunk + Vector2i(chunk_index % 4, int(chunk_index / 4))
		var local_x := 0 if within % 2 == 0 else 15
		var local_z := 1 + int(within / 2) * 4
		var lower := Vector3i(
			chunk_coord.x * 16 + local_x,
			floor_y + 1,
			chunk_coord.y * 16 + local_z,
		)
		var support := lower + Vector3i.DOWN
		var lower_id := DoorPolicyScript.variant(door_index % 4, false, door_index % 3 == 0)
		var upper_id := DoorPolicyScript.upper_variant(lower_id)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(mutation_map, lower + Vector3i.UP, upper_id)
		_append_unique_position(support_positions, support_seen, support)
		target_door_cells.append(lower)
		target_door_cells.append(lower + Vector3i.UP)

	for ladder_index in TARGET_LADDER_COUNT:
		var chunk_index := int(ladder_index / 16)
		var within := ladder_index % 16
		var layer := int(within / 8)
		var slot := within % 8
		var chunk_coord := base_chunk + Vector2i(chunk_index % 4, int(chunk_index / 4))
		var local_x := 0
		var local_z := 0
		var block_id := "ladder"
		if slot < 4:
			local_x = 0 if slot % 2 == 0 else 15
			local_z = 2 + int(slot / 2) * 8
			block_id = "ladder_west" if local_x == 0 else "ladder_east"
		else:
			var side_slot := slot - 4
			local_z = 0 if side_slot % 2 == 0 else 15
			local_x = 2 + int(side_slot / 2) * 8
			block_id = "ladder_north" if local_z == 0 else "ladder"
		var ladder_position := Vector3i(
			chunk_coord.x * 16 + local_x,
			floor_y + 4 + layer,
			chunk_coord.y * 16 + local_z,
		)
		var support := ladder_position + LadderPolicyScript.support_offset(block_id)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, block_id)
		_append_unique_position(support_positions, support_seen, support)
		target_ladder_cells.append(ladder_position)

	var gallery_origin := Vector3i(center_chunk.x * 16 + 8, floor_y + 1, (center_chunk.y - 3) * 16 + 8)
	for x_offset in range(-7, 8):
		for z_offset in range(-5, 7):
			_set_mutation(
				mutation_map,
				Vector3i(gallery_origin.x + x_offset, floor_y, gallery_origin.z + z_offset),
				"stone",
			)
			for y_offset in range(1, 8):
				_set_mutation(
					mutation_map,
					Vector3i(gallery_origin.x + x_offset, floor_y + y_offset, gallery_origin.z + z_offset),
					"air",
				)
	for index in 4:
		var lower := Vector3i(gallery_origin.x - 5 + index * 3, floor_y + 1, gallery_origin.z + 2)
		var lower_id := DoorPolicyScript.variant(index, false, index % 2 == 1)
		_set_mutation(mutation_map, lower + Vector3i.DOWN, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(mutation_map, lower + Vector3i.UP, DoorPolicyScript.upper_variant(lower_id))
		control_doors.append({"lower": lower, "lower_id": lower_id})
	var ladder_ids := ["ladder", "ladder_east", "ladder_north", "ladder_west"]
	for index in 4:
		var ladder_id := str(ladder_ids[index])
		var ladder_position := Vector3i(gallery_origin.x - 5 + index * 3, floor_y + 4, gallery_origin.z + 3)
		var support := ladder_position + LadderPolicyScript.support_offset(ladder_id)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, ladder_id)
		control_ladders.append({"position": ladder_position, "block_id": ladder_id})

	return {
		"mutations": _mutation_array(mutation_map),
		"support_positions": support_positions,
		"target_door_cells": target_door_cells,
		"target_ladder_cells": target_ladder_cells,
		"control_doors": control_doors,
		"control_ladders": control_ladders,
		"gallery_origin": gallery_origin,
	}


func _build_fallback_fixture(gallery_origin: Vector3i, floor_y: int) -> Dictionary:
	var mutation_map: Dictionary = {}
	var support_positions: Array[Vector3i] = []
	var support_seen: Dictionary = {}
	var structure_cells: Array[Vector3i] = []
	for index in FALLBACK_DOOR_COUNT:
		var lower := Vector3i(gallery_origin.x - 6 + index * 2, floor_y + 1, gallery_origin.z - 2)
		var support := lower + Vector3i.DOWN
		var lower_id := DoorPolicyScript.variant(index % 4, false, index % 2 == 0)
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, lower, lower_id)
		_set_mutation(mutation_map, lower + Vector3i.UP, DoorPolicyScript.upper_variant(lower_id))
		_append_unique_position(support_positions, support_seen, support)
		structure_cells.append(lower)
		structure_cells.append(lower + Vector3i.UP)
	for index in FALLBACK_LADDER_COUNT:
		var ladder_id := ["ladder", "ladder_east", "ladder_north", "ladder_west"][index % 4]
		var ladder_position := Vector3i(
			gallery_origin.x - 6 + (index % 5) * 3,
			floor_y + 5 + int(index / 5),
			gallery_origin.z - 1,
		)
		var support := ladder_position + LadderPolicyScript.support_offset(str(ladder_id))
		_set_mutation(mutation_map, support, "stone")
		_set_mutation(mutation_map, ladder_position, str(ladder_id))
		_append_unique_position(support_positions, support_seen, support)
		structure_cells.append(ladder_position)
	return {
		"mutations": _mutation_array(mutation_map),
		"support_positions": support_positions,
		"structure_cells": structure_cells,
	}


func _set_mutation(mutation_map: Dictionary, position: Vector3i, block_id: String) -> void:
	mutation_map[_position_key(position)] = {"position": position, "block_id": block_id}


func _mutation_array(mutation_map: Dictionary) -> Array:
	var keys: Array[String] = []
	for raw_key: Variant in mutation_map.keys():
		keys.append(str(raw_key))
	keys.sort()
	var result: Array = []
	for key: String in keys:
		result.append((mutation_map[key] as Dictionary).duplicate(true))
	return result


func _append_unique_position(
	positions: Array[Vector3i],
	seen: Dictionary,
	position: Vector3i
) -> void:
	var key := _position_key(position)
	if seen.has(key):
		return
	seen[key] = true
	positions.append(position)


func _force_load_mutation_chunks(world: Node, mutations: Array) -> void:
	var coords: Dictionary = {}
	for raw_mutation: Variant in mutations:
		if raw_mutation is not Dictionary:
			continue
		var position: Variant = (raw_mutation as Dictionary).get("position", Vector3i.ZERO)
		if position is not Vector3i:
			continue
		var coord: Vector2i = world.call("block_to_chunk", position)
		coords["%d,%d" % [coord.x, coord.y]] = coord
	for raw_coord: Variant in coords.values():
		world.call("force_load_chunk", raw_coord)


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
			and str(hub.get("current_world_id")) == expected_world_id
		):
			return true
	return false


func _wait_for_integrity_idle(integrity: Node) -> bool:
	for _frame in INTEGRITY_SETTLE_FRAMES:
		await process_frame
		if integrity == null or not is_instance_valid(integrity):
			return false
		var snapshot: Dictionary = integrity.call("get_snapshot")
		if (
			int(snapshot.get("pending_candidates", -1)) == 0
			and int(snapshot.get("pending_drop_count", -1)) == 0
			and not bool(snapshot.get("processing", true))
		):
			return true
	return false


func _all_air(world: Node, positions: Array[Vector3i]) -> bool:
	for position: Vector3i in positions:
		if str(world.call("get_block", position)) != "air":
			return false
	return true


func _all_non_air(world: Node, positions: Array[Vector3i]) -> bool:
	for position: Vector3i in positions:
		if str(world.call("get_block", position)) == "air":
			return false
	return true


func _controls_valid(
	world: Node,
	doors: Array[Dictionary],
	ladders: Array[Dictionary]
) -> bool:
	for door: Dictionary in doors:
		var lower: Vector3i = door.get("lower", Vector3i.ZERO)
		var lower_id := str(world.call("get_block", lower))
		var upper_id := str(world.call("get_block", lower + Vector3i.UP))
		if not DoorPolicyScript.is_valid_pair(lower_id, upper_id):
			return false
		if not bool(world.call("get_block", lower + Vector3i.DOWN) != "air"):
			return false
	for ladder: Dictionary in ladders:
		var position: Vector3i = ladder.get("position", Vector3i.ZERO)
		var block_id := str(world.call("get_block", position))
		if block_id != str(ladder.get("block_id", "")):
			return false
		if not LadderPolicyScript.has_support(world, position, block_id):
			return false
	return true


func _pickup_totals(parent: Node3D) -> Dictionary:
	var result: Dictionary = {}
	if parent == null or not is_instance_valid(parent):
		return result
	for child: Node in parent.get_children():
		if not child.has_method("get_pickup_snapshot"):
			continue
		var item_id := str(child.get("item_id"))
		var count := maxi(0, int(child.get("item_count")))
		result[item_id] = int(result.get(item_id, 0)) + count
	return result


func _position_for_capture(
	player: CharacterBody3D,
	world: Node,
	gallery_origin: Vector3i,
	floor_y: int
) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.global_position = Vector3(gallery_origin.x + 0.5, floor_y + 2.05, gallery_origin.z - 8.5)
	player.call("reset_motion")
	var camera: Camera3D = player.call("get_view_camera")
	if camera != null:
		camera.look_at(Vector3(gallery_origin.x + 0.5, floor_y + 3.0, gallery_origin.z + 1.5), Vector3.UP)
	for _frame in 6:
		await physics_frame
		await process_frame
	var ray := player.get_node_or_null("CameraPivot/Camera3D/InteractionRay") as RayCast3D
	if ray != null:
		ray.force_raycast_update()
	player.call("_update_interaction_focus", true)
	await process_frame


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		_check(false, "structural integrity JSON report opens for writing")
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	_check(FileAccess.file_exists(_report_path), "structural integrity JSON report is saved")


func _file_length(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := int(file.get_length())
	file.close()
	return length


func _position_key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]


func _finish(game: Node, hub: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hub != null and is_instance_valid(hub):
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			for _frame in CLEANUP_FRAMES:
				await process_frame
		if not _world_id.is_empty() and hub.get("save_service") != null:
			hub.save_service.delete_world(_world_id)
		var audio: Node = hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print(
			"QA STRUCTURAL INTEGRITY DESKTOP PASS | checks=%d | structures=%d | cleanup_ms=%.3f | capture=%s"
			% [
				checks,
				TARGET_DOOR_COUNT + TARGET_LADDER_COUNT,
				float(_report.get("cleanup_milliseconds", 0.0)),
				_capture_path,
			]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA STRUCTURAL INTEGRITY DESKTOP FAILURE: %s" % failure)
		print(
			"QA STRUCTURAL INTEGRITY DESKTOP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
