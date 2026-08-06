extends SceneTree

const RewardServiceScript = preload("res://src/entity/encounter_reward_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const PickupCoordinatorScript = preload(
	"res://src/entity/bounded_pickup_stack_coordinator.gd"
)
const PickupScript = preload("res://src/entity/item_pickup.gd")
const CachedChunkScript = preload("res://src/chunk/cached_voxel_chunk.gd")
const CachedWorldScript = preload("res://src/world/cached_batched_voxel_world.gd")
const RecentChunkSnapshotCacheScript = preload(
	"res://src/world/recent_chunk_snapshot_cache.gd"
)
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const StructuralServiceScript = preload(
	"res://src/interaction/batched_block_structure_integrity_service.gd"
)

const CAMPAIGN_CYCLES := 8
const HOSTILES_PER_CYCLE := 3
const EXPECTED_DEATHS := CAMPAIGN_CYCLES * HOSTILES_PER_CYCLE
const EXPECTED_HOT_RETURNS := CAMPAIGN_CYCLES * 2

var checks := 0
var failures: Array[String] = []
var death_count := 0
var physical_drop_count := 0


class FakeDirector:
	extends Node
	signal encounter_started(snapshot: Dictionary)
	signal encounter_completed(snapshot: Dictionary)


class FakeRangedCombat:
	extends Node
	signal shot_fired(result: Dictionary)


class FakeMember:
	extends Node3D
	signal died(species_id: String, drops: Dictionary, world_position: Vector3)
	var species_id := "zombie"
	var _dead := false

	func defeat(drops: Dictionary, position: Vector3) -> void:
		if _dead:
			return
		_dead = true
		died.emit(species_id, drops.duplicate(true), position)


class StructuralWorld:
	extends Node
	signal block_changed(block_position: Vector3i, old_block: String, new_block: String)
	signal block_mutation_batch_pre_flush(reason: String, summary: Dictionary)
	var blocks: Dictionary = {}
	var block_overrides: Dictionary = {}
	var apply_call_count := 0

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var old_block := get_block(position)
		if old_block == block_id:
			return false
		blocks[_key(position)] = block_id
		if block_id == "air":
			block_overrides.erase(_key(position))
		else:
			block_overrides[_key(position)] = block_id
		block_changed.emit(position, old_block, block_id)
		return true

	func apply_block_mutations(changes: Array, reason: String = "campaign") -> Dictionary:
		apply_call_count += 1
		var changed := 0
		for raw_change: Variant in changes:
			if raw_change is not Dictionary:
				continue
			var change: Dictionary = raw_change
			var position: Variant = change.get("position", Vector3i.ZERO)
			if position is Vector3i and set_block(
				position, str(change.get("block_id", "air"))
			):
				changed += 1
		var result := {
			"success":true,
			"requested":changes.size(),
			"accepted":changes.size(),
			"changed":changed,
			"unchanged":changes.size() - changed,
			"rejected":0,
			"truncated":0,
			"rebuild":{"execution_count":1 if changed > 0 else 0, "pending_chunks":0, "batch_depth":0},
		}
		block_mutation_batch_pre_flush.emit(reason, result.duplicate(true))
		return result

	func block_key(position: Vector3i) -> String:
		return _key(position)

	func block_to_world(position: Vector3i) -> Vector3:
		return Vector3(position) + Vector3(0.5, 0.5, 0.5)

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_children := root.get_child_count()
	var host := Node3D.new()
	root.add_child(host)
	var director := FakeDirector.new()
	var ranged := FakeRangedCombat.new()
	var reward_inventory = InventoryScript.new(36, 9)
	var drop_parent := Node3D.new()
	var reward_service = RewardServiceScript.new()
	reward_service.auto_bind_parent = false
	var pickup_coordinator = PickupCoordinatorScript.new()
	var cached_world = CachedWorldScript.new()
	var structural_world := StructuralWorld.new()
	var structural_inventory = InventoryScript.new()
	var structural_pickup_parent := Node3D.new()
	var structural_service = StructuralServiceScript.new()
	for node: Node in [
		director, ranged, reward_inventory, drop_parent, reward_service,
		pickup_coordinator, cached_world, structural_world, structural_inventory,
		structural_pickup_parent, structural_service,
	]:
		host.add_child(node)
	reward_service.setup(director, reward_inventory, ranged, drop_parent)
	_check(
		pickup_coordinator.setup(drop_parent, null),
		"continuous campaign binds one shared bounded pickup runtime"
	)
	pickup_coordinator.activate()
	_check(
		structural_service.setup(structural_inventory, structural_pickup_parent)
		and structural_service.bind_world(structural_world),
		"continuous campaign binds one event-driven structural queue"
	)
	await process_frame

	for cycle in CAMPAIGN_CYCLES:
		await _run_hostile_reward_drop_cycle(
			cycle, director, ranged, reward_service, drop_parent, pickup_coordinator
		)
		await _run_chunk_connection_cycle(cycle, cached_world)
		_run_structural_cycle(cycle, structural_world, structural_service)

	var reward_snapshot: Dictionary = reward_service.get_snapshot()
	var pickup_snapshot: Dictionary = pickup_coordinator.get_snapshot()
	var cache_snapshot: Dictionary = cached_world.get_recent_chunk_cache_stats()
	var structural_snapshot: Dictionary = structural_service.get_snapshot()
	_check(
		death_count == EXPECTED_DEATHS,
		"campaign records the exact multi-hostile death count"
	)
	_check(
		int(reward_snapshot.get("reward_grant_count", 0)) == CAMPAIGN_CYCLES
		and int(reward_snapshot.get("duplicate_completion_count", 0)) == CAMPAIGN_CYCLES,
		"every encounter grants once and every duplicate completion is rejected"
	)
	_check(
		physical_drop_count == EXPECTED_DEATHS
		and int(pickup_snapshot.get("expired_pickup_count", 0)) == EXPECTED_DEATHS
		and int(pickup_snapshot.get("pickup_node_count", -1)) == 0,
		"each hostile death materializes exactly one physical drop and leaves zero residue"
	)
	_check(
		int(cache_snapshot.get("hit_count", 0)) == EXPECTED_HOT_RETURNS
		and int(cache_snapshot.get("entry_count", 0)) <= 64,
		"chunk hot return hits exactly twice per cycle inside the fixed cache capacity"
	)
	_check(
		int(structural_snapshot.get("door_cleanup_count", 0)) == CAMPAIGN_CYCLES
		and int(structural_snapshot.get("ladder_cleanup_count", 0)) == CAMPAIGN_CYCLES
		and int(structural_snapshot.get("pending_candidates", -1)) == 0,
		"structural queue converges after every combat and streaming cycle"
	)
	_check(
		int(pickup_snapshot.get("max_runtime_nodes_observed", 0))
		<= PickupCoordinatorScript.MAX_RUNTIME_NODES,
		"continuous physical drops never exceed the shared runtime hard cap"
	)

	reward_service.clear("campaign_cleanup")
	pickup_coordinator.shutdown()
	structural_service.shutdown()
	cached_world.clear_world()
	host.queue_free()
	for _frame in 20:
		await process_frame
	_check(
		root.get_child_count() == baseline_children,
		"campaign teardown releases every hostile, pickup, chunk and structural node"
	)
	if failures.is_empty():
		print(
			"QA RELEASE INTEGRITY CONTINUOUS CAMPAIGN PASS | checks=%d | deaths=%d | cycles=%d"
			% [checks, death_count, CAMPAIGN_CYCLES]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA RELEASE INTEGRITY CONTINUOUS CAMPAIGN FAILURE: %s" % failure)
	print(
		"QA RELEASE INTEGRITY CONTINUOUS CAMPAIGN FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _run_hostile_reward_drop_cycle(
	cycle: int,
	director: FakeDirector,
	ranged: FakeRangedCombat,
	reward_service: Node,
	drop_parent: Node3D,
	pickup_coordinator: Node
) -> void:
	var members: Array[FakeMember] = []
	for index in HOSTILES_PER_CYCLE:
		var member := FakeMember.new()
		member.name = "CampaignMember_%02d_%02d" % [cycle, index]
		drop_parent.add_child(member)
		member.global_position = Vector3(float(cycle * 12 + index * 3), 3.0, 0.0)
		member.died.connect(
			func(_species_id: String, drops: Dictionary, position: Vector3) -> void:
				death_count += 1
				_materialize_death_drops(drop_parent, drops, position)
		)
		members.append(member)
	var member_ids: Array[int] = []
	for member: FakeMember in members:
		member_ids.append(int(member.get_instance_id()))
	var encounter_id := "release-integrity-%02d" % cycle
	director.encounter_started.emit({
		"id":encounter_id,
		"profile_id":"continent_night_patrol",
		"display_name":"Release Integrity Patrol",
		"living_member_ids":member_ids,
	})
	for shot_index in 4:
		ranged.shot_fired.emit({
			"accepted":true,
			"status":"fired",
			"ammo_item_id":"light_round",
			"accepted_target_count":1,
			"target_results":[{
				"target_id":member_ids[mini(shot_index, member_ids.size() - 1)],
				"accepted":true,
				"applied":true,
			}],
		})
	for member: FakeMember in members:
		member.defeat({"rotten_flesh":1}, member.global_position)
		member.defeat({"rotten_flesh":1}, member.global_position)
	var reward_ready := func() -> bool:
		return int(
			reward_service.get_snapshot().get("reward_grant_count", 0)
		) == cycle + 1
	var rewarded := await _wait_until(reward_ready, 2000)
	_check(
		rewarded,
		"combat cycle %02d resolves one formal reward after the last death" % (cycle + 1)
	)
	director.encounter_completed.emit({
		"id":encounter_id,
		"profile_id":"continent_night_patrol",
		"completion_reason":"members_cleared",
	})
	director.encounter_completed.emit({
		"id":encounter_id,
		"profile_id":"continent_night_patrol",
		"completion_reason":"members_cleared",
	})
	for _frame in 4:
		await process_frame
	var live: Dictionary = pickup_coordinator.get_snapshot()
	_check(
		int(live.get("visible_item_total", 0)) == HOSTILES_PER_CYCLE,
		"combat cycle %02d exposes one unique physical item per hostile death" % (cycle + 1)
	)
	for child: Node in drop_parent.get_children():
		if child.has_method("advance_runtime"):
			child.set("life_seconds", 0.01)
	var step: Dictionary = pickup_coordinator.advance_shared_runtime(0.25)
	_check(
		int(step.get("expired_pickup_count", 0)) == HOSTILES_PER_CYCLE,
		"combat cycle %02d expires each bounded drop exactly once" % (cycle + 1)
	)
	for member: FakeMember in members:
		member.queue_free()
	for _frame in 6:
		await process_frame
	_check(
		int(pickup_coordinator.get_snapshot().get("pickup_node_count", -1)) == 0,
		"combat cycle %02d returns the physical-drop runtime to zero" % (cycle + 1)
	)


func _materialize_death_drops(
	parent: Node3D, drops: Dictionary, position: Vector3
) -> void:
	var item_ids: Array[String] = []
	for raw_id: Variant in drops.keys():
		item_ids.append(str(raw_id))
	item_ids.sort()
	for item_id: String in item_ids:
		var count := maxi(0, int(drops.get(item_id, 0)))
		if count <= 0:
			continue
		var pickup = PickupScript.new()
		pickup.setup(item_id, count, null)
		parent.add_child(pickup)
		pickup.global_position = position
		physical_drop_count += 1


func _run_chunk_connection_cycle(cycle: int, world: Node) -> void:
	var left_coord := Vector2i(cycle * 2, 0)
	var right_coord := left_coord + Vector2i.RIGHT
	var left_local := Vector3i(15, 40, 4)
	var right_local := Vector3i(0, 40, 4)
	var block_id := "glass_pane" if cycle % 2 == 0 else "oak_fence"
	var left_snapshot := _empty_snapshot()
	var right_snapshot := _empty_snapshot()
	left_snapshot[CachedChunkScript.local_cell_index(left_local)] = (
		BlockRegistryScript.get_numeric_id(block_id)
	)
	right_snapshot[CachedChunkScript.local_cell_index(right_local)] = (
		BlockRegistryScript.get_numeric_id("stone")
	)
	var left = CachedChunkScript.new()
	var right = CachedChunkScript.new()
	world.add_child(left)
	world.add_child(right)
	left.begin_initialize_from_snapshot(left_coord, world, left_snapshot)
	right.begin_initialize_from_snapshot(right_coord, world, right_snapshot)
	world.chunks[left_coord] = left
	world.chunks[right_coord] = right
	var global_position := Vector3i(
		left_coord.x * int(world.CHUNK_SIZE) + left_local.x,
		left_local.y,
		left_coord.y * int(world.CHUNK_SIZE) + left_local.z
	)
	var neighbor_position := global_position + Vector3i.RIGHT
	_check(
		ConnectionPolicyScript.resolve_mask(
			block_id, _connection_neighbors(world, global_position)
		) & ConnectionPolicyScript.EAST != 0,
		"stream cycle %02d resolves the cross-chunk east connection" % (cycle + 1)
	)
	world.call("_unload_chunk", left_coord)
	await process_frame
	var first_return: Node = world.call("_load_chunk_synchronously", left_coord)
	_check(
		first_return != null
		and bool(first_return.call("was_hydrated_from_snapshot"))
		and str(first_return.call("get_local_block", left_local)) == block_id,
		"stream cycle %02d hot-returns the connected block from cache" % (cycle + 1)
	)
	_check(
		ConnectionPolicyScript.resolve_mask(
			block_id, _connection_neighbors(world, global_position)
		) & ConnectionPolicyScript.EAST != 0,
		"stream cycle %02d preserves adjacency after the first hot return" % (cycle + 1)
	)
	world.call("_unload_chunk", left_coord)
	await process_frame
	_check(
		bool(world.call("set_block", neighbor_position, "air")),
		"stream cycle %02d mutates the loaded neighbor while the owner chunk is cold"
		% (cycle + 1)
	)
	var second_return: Node = world.call("_load_chunk_synchronously", left_coord)
	_check(
		second_return != null
		and bool(second_return.call("was_hydrated_from_snapshot")),
		"stream cycle %02d performs a second bounded hot return" % (cycle + 1)
	)
	var rebuilt_neighbors := _connection_neighbors(world, global_position)
	var rebuilt_mask := ConnectionPolicyScript.resolve_mask(
		block_id, rebuilt_neighbors
	)
	_check(
		not ConnectionPolicyScript.connected_face(
			block_id,
			rebuilt_mask,
			0,
			str(rebuilt_neighbors.get("east", "air"))
		),
		"stream cycle %02d rebuild removes the stale cross-chunk connection"
		% (cycle + 1)
	)
	world.call("_unload_chunk", left_coord)
	world.call("_unload_chunk", right_coord)
	await process_frame


func _run_structural_cycle(
	cycle: int, world: StructuralWorld, service: Node
) -> void:
	var base := Vector3i(cycle * 6, 20, 12)
	var door_support := base + Vector3i.DOWN
	var ladder_position := base + Vector3i(2, 0, 0)
	var ladder_support := ladder_position + Vector3i.LEFT
	world.set_test_block(door_support, "stone")
	world.set_test_block(base, "oak_door")
	world.set_test_block(base + Vector3i.UP, "oak_door_upper")
	world.set_test_block(ladder_support, "stone")
	world.set_test_block(ladder_position, "ladder_west")
	var result: Dictionary = world.apply_block_mutations(
		[
			{"position":door_support, "block_id":"air"},
			{"position":ladder_support, "block_id":"air"},
		],
		"release_integrity_cycle_%02d" % cycle
	)
	var snapshot: Dictionary = service.get_snapshot()
	_check(
		bool(result.get("success", false))
		and int(snapshot.get("pending_candidates", -1)) == 0
		and not bool(snapshot.get("processing", true)),
		"structure cycle %02d drains its queue before the outer batch returns"
		% (cycle + 1)
	)
	_check(
		str(world.get_block(base)) == "air"
		and str(world.get_block(base + Vector3i.UP)) == "air"
		and str(world.get_block(ladder_position)) == "air",
		"structure cycle %02d removes one unsupported door and ladder exactly once"
		% (cycle + 1)
	)


func _connection_neighbors(world: Node, position: Vector3i) -> Dictionary:
	var result := ConnectionPolicyScript.empty_neighbors()
	result["east"] = str(world.call("get_block", position + Vector3i.RIGHT))
	result["west"] = str(world.call("get_block", position + Vector3i.LEFT))
	result["south"] = str(world.call("get_block", position + Vector3i.BACK))
	result["north"] = str(world.call("get_block", position + Vector3i.FORWARD))
	return result


func _empty_snapshot() -> PackedInt32Array:
	var snapshot := PackedInt32Array()
	snapshot.resize(RecentChunkSnapshotCacheScript.CHUNK_CELL_COUNT)
	snapshot.fill(BlockRegistryScript.get_numeric_id("air"))
	return snapshot


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
