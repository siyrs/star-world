extends SceneTree

const PolicyScript = preload("res://src/entity/hostile_cover_counter_policy.gd")
const ServiceScript = preload("res://src/entity/lifecycle_bound_hostile_cover_counter_service.gd")
const FactoryScript = preload("res://src/entity/creature_factory.gd")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}
	var block_overrides: Dictionary = {}
	var batch_calls := 0
	var last_reason := ""
	var last_changes: Array = []

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(block_key(position), "air"))

	func set_override(position: Vector3i, block_id: String) -> void:
		var key := block_key(position)
		blocks[key] = block_id
		block_overrides[key] = block_id

	func set_generated(position: Vector3i, block_id: String) -> void:
		blocks[block_key(position)] = block_id

	func apply_block_mutations(changes: Array, reason: String = "test") -> Dictionary:
		batch_calls += 1
		last_reason = reason
		last_changes = changes.duplicate(true)
		var changed := 0
		for raw_change: Variant in changes:
			if raw_change is not Dictionary:
				continue
			var change: Dictionary = raw_change
			var position: Vector3i = change.get("position", Vector3i.ZERO)
			var block_id := str(change.get("block_id", "air"))
			var key := block_key(position)
			if get_block(position) == block_id:
				continue
			changed += 1
			if block_id == "air":
				blocks.erase(key)
				block_overrides.erase(key)
			else:
				blocks[key] = block_id
				block_overrides[key] = block_id
		return {
			"success": true,
			"changed": changed,
			"rejected": 0,
			"truncated": 0,
			"rebuild": {"flush_count": batch_calls, "last_reason": reason},
		}

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, 1.05, candidate.z)


class FakeSpawner:
	extends Node3D
	signal creature_spawned(creature: Node3D)

	func publish(creature: Node3D) -> void:
		add_child(creature)
		creature_spawned.emit(creature)


class FakeHub:
	extends Node
	signal start_world_requested(world_state: Dictionary)
	signal return_to_menu_requested
	var world_node: Node
	var player_node: Node3D
	var creature_spawner: Node
	var current_world_id := "cover-world"
	var game_ui: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_contracts()
	await _test_runtime_break_and_reposition()
	_test_long_session_budgets()
	if failures.is_empty():
		print("QA HOSTILE COVER COUNTER PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE COVER COUNTER FAILURE: %s" % failure)
	print("QA HOSTILE COVER COUNTER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_policy_contracts() -> void:
	_check(PolicyScript.is_breakable_cover("wool"), "wool is explicit temporary breakable cover")
	_check(PolicyScript.is_breakable_cover("glass_pane"), "glass pane is explicit fragile breakable cover")
	_check(not PolicyScript.is_breakable_cover("stone"), "stone permanent base blocks are never breakable")
	_check(not PolicyScript.is_breakable_cover("planks"), "plank permanent base blocks are never breakable")
	_check(not PolicyScript.is_breakable_cover("oak_door"), "doors are never included in hostile destruction")
	_check(not PolicyScript.is_breakable_cover("oak_fence"), "fences are never included in hostile destruction")
	_check(not PolicyScript.is_breakable_cover("stone_slab"), "slabs are never included in hostile destruction")
	_check(PolicyScript.blocks_projectile_lane("oak_door", 0.8), "closed door blocks a hostile projectile lane")
	_check(not PolicyScript.blocks_projectile_lane("oak_door_open", 0.8), "open door exposes a hostile projectile lane")
	_check(PolicyScript.blocks_projectile_lane("oak_fence", 0.8), "fence keeps conservative projectile collision semantics")
	_check(PolicyScript.blocks_projectile_lane("glass_pane", 0.8), "glass pane blocks ballistic fire despite transparency")
	_check(PolicyScript.blocks_projectile_lane("stone_slab", 0.2), "low ray is blocked by a slab")
	_check(not PolicyScript.blocks_projectile_lane("stone_slab", 0.8), "high ray passes over a slab")
	var samples := PolicyScript.line_samples(Vector3.ZERO, Vector3(200.0, 0.0, 0.0))
	_check(samples.size() <= PolicyScript.MAX_LINE_SAMPLE_STEPS, "line sampling remains inside the sixty-four-step hard cap")
	var directions := PolicyScript.reposition_directions(Vector3.FORWARD, 99)
	_check(directions.size() == PolicyScript.MAX_REPOSITION_PROBES, "marksman reposition fan remains inside six probes")
	_check(
		not PolicyScript.can_attempt_reposition(10.0, 0.0, PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET),
		"marksman target lock stops after four bounded reposition attempts"
	)


func _test_runtime_break_and_reposition() -> void:
	var hub := FakeHub.new()
	root.add_child(hub)
	var world := FakeWorld.new()
	var player := Node3D.new()
	var spawner := FakeSpawner.new()
	var service = ServiceScript.new()
	hub.world_node = world
	hub.player_node = player
	hub.creature_spawner = spawner
	hub.add_child(world)
	hub.add_child(player)
	hub.add_child(spawner)
	hub.add_child(service)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	service.call("bind_parent_hub", hub)
	await process_frame
	await process_frame
	_check(bool(service.call("get_snapshot").get("active", false)), "cover counter binds the explicit production-style world boundary")

	var factory = FactoryScript.new()
	var brute: Node3D = factory.create("abyss_brute", Vector3(0.0, 1.0, -3.0), player, null) as Node3D
	var marksman: Node3D = factory.create("abyss_marksman", Vector3(0.0, 1.0, -10.0), player, null) as Node3D
	_check(brute != null and brute.has_method("bind_cover_counter_service"), "factory composes the cover-aware abyss brute")
	_check(marksman != null and marksman.has_method("bind_cover_counter_service"), "factory composes the cover-aware abyss marksman")
	spawner.publish(brute)
	spawner.publish(marksman)
	await process_frame
	brute.set_physics_process(false)
	marksman.set_physics_process(false)
	_check(int(service.call("get_snapshot").get("bound_creature_count", 0)) == 2, "service binds only spawned cover-aware hostile elites")

	var first_cover := Vector3i(0, 2, -2)
	var second_cover := Vector3i(0, 2, -1)
	world.set_override(first_cover, "wool")
	world.set_override(second_cover, "glass_pane")
	var break_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(bool(break_result.get("handled", false)), "brute attack resolves player-placed temporary cover before player damage")
	_check(int(break_result.get("changed_blocks", 0)) == 2, "one brute attack destroys at most two temporary cover blocks")
	_check(world.batch_calls == 1, "one brute cover attack uses exactly one world mutation batch")
	_check(world.last_reason == "hostile_cover_break", "cover destruction publishes the dedicated batch reason")
	_check(world.get_block(first_cover) == "air" and world.get_block(second_cover) == "air", "temporary cover reaches air in the authoritative world")

	world.set_override(first_cover, "stone")
	var permanent_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(not bool(permanent_result.get("handled", false)), "permanent stone base cannot be broken by a brute")
	_check(world.get_block(first_cover) == "stone", "rejected permanent cover remains unchanged")
	world.set_generated(first_cover, "wool")
	world.block_overrides.erase(world.block_key(first_cover))
	var generated_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(not bool(generated_result.get("handled", false)), "generated fragile blocks are not mistaken for player temporary cover")

	world.blocks.erase(world.block_key(first_cover))
	for attack_index in 5:
		world.set_override(first_cover, "wool")
		world.set_override(second_cover, "glass_pane")
		var bounded_result: Dictionary = service.call("resolve_brute_attack", brute, player)
		_check(bool(bounded_result.get("handled", false)), "brute lifetime budget accepts bounded cover attack %d" % (attack_index + 1))
	world.set_override(first_cover, "wool")
	var exhausted_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(str(exhausted_result.get("reason", "")) == "brute_break_budget_exhausted", "brute cannot exceed twelve destroyed blocks per lifetime")
	_check(world.get_block(first_cover) == "wool", "budget exhaustion preserves remaining temporary cover")

	world.blocks.clear()
	world.block_overrides.clear()
	world.set_override(Vector3i(0, 2, -5), "wool")
	var direct_lane := bool(service.call("has_projectile_lane", marksman, player))
	_check(not direct_lane, "temporary wall blocks the marksman ballistic lane")
	var reposition: Dictionary = service.call(
		"find_marksman_reposition_destination",
		marksman,
		player,
		5.5,
		24.0
	)
	_check(bool(reposition.get("success", false)), "blocked marksman finds a bounded lateral firing lane")
	_check(int(reposition.get("probes", 99)) <= PolicyScript.MAX_REPOSITION_PROBES, "marksman lane search never exceeds six probes")
	var destination: Vector3 = reposition.get("destination", Vector3.ZERO)
	_check(destination.distance_to(marksman.global_position) <= PolicyScript.REPOSITION_RADIUS + 0.2, "marksman destination remains inside the local reposition radius")
	_check(
		bool(service.call("_lane_clear", destination + Vector3.UP * 1.48, player.global_position + Vector3.UP * 1.05, true)),
		"selected marksman destination owns a clear projectile lane"
	)

	marksman.set("_blocked_lane_seconds", PolicyScript.REPOSITION_DELAY_SECONDS)
	marksman.set("_reposition_cooldown_remaining", 0.0)
	marksman.call("_choose_direction")
	var attack_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	_check(int(attack_snapshot.get("reposition_attempt_count", 0)) == 1, "cover-aware marksman records one real reposition attempt")
	_check(int(attack_snapshot.get("reposition_success_count", 0)) == 1, "cover-aware marksman accepts the bounded firing lane")
	_check(bool(attack_snapshot.get("cover_destination_active", false)), "cover-aware marksman moves through the existing destination contract")

	hub.current_world_id = ""
	hub.world_node = null
	hub.return_to_menu_requested.emit()
	var cleared: Dictionary = service.call("get_snapshot")
	_check(int(cleared.get("cover_break_block_count", -1)) == 0, "world boundary clears transient cover destruction counters")
	_check(int(cleared.get("marksman_reposition_count", -1)) == 0, "world boundary clears transient marksman reposition counters")
	_check(not bool(cleared.get("active", true)), "return-to-menu signal releases the cover counter world attachment")

	hub.queue_free()
	for _frame in 8:
		await process_frame


func _test_long_session_budgets() -> void:
	var simulated_seconds := 0.0
	var target_sequence := 0
	var attempt_count := 0
	var maximum_attempts := 0
	var total_probes := 0
	var cooldown := 0.0
	var blocked := 0.0
	while simulated_seconds < 3600.0:
		var delta := 0.25
		simulated_seconds += delta
		cooldown = maxf(0.0, cooldown - delta)
		blocked += delta
		if PolicyScript.can_attempt_reposition(blocked, cooldown, attempt_count):
			attempt_count += 1
			maximum_attempts = maxi(maximum_attempts, attempt_count)
			total_probes += PolicyScript.reposition_directions(Vector3.FORWARD).size()
			cooldown = PolicyScript.REPOSITION_COOLDOWN_SECONDS
			blocked = 0.0
		if fmod(simulated_seconds, 30.0) < delta:
			target_sequence += 1
			attempt_count = 0
			cooldown = 0.0
			blocked = 0.0
	_check(target_sequence == 120, "sixty minute simulation rotates exactly one hundred twenty target locks")
	_check(maximum_attempts <= PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET, "sixty minute simulation never exceeds per-target reposition attempts")
	_check(total_probes <= 120 * PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET * PolicyScript.MAX_REPOSITION_PROBES, "sixty minute probe work remains linearly bounded")
	_check(PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE == 12, "long-session brute destruction remains capped at twelve blocks per body")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
