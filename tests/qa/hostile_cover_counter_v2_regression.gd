extends SceneTree

const PolicyScript = preload("res://src/entity/hostile_cover_counter_policy.gd")
const ServiceScript = preload("res://src/entity/hostile_cover_counter_service.gd")
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
	var fail_mutations := false
	var partial_mutations := false

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]

	func get_block(position: Vector3i) -> String:
		var key := block_key(position)
		if blocks.has(key):
			return str(blocks[key])
		# A deterministic flat floor at y=1 gives the production local-ground search
		# real support while leaving the body/head and combat lanes empty.
		return "stone" if position.y == 1 else "air"

	func set_override(position: Vector3i, block_id: String) -> void:
		var key := block_key(position)
		blocks[key] = block_id
		block_overrides[key] = block_id

	func set_generated(position: Vector3i, block_id: String) -> void:
		var key := block_key(position)
		blocks[key] = block_id
		block_overrides.erase(key)

	func erase(position: Vector3i) -> void:
		var key := block_key(position)
		blocks.erase(key)
		block_overrides.erase(key)

	func clear_explicit() -> void:
		blocks.clear()
		block_overrides.clear()
		last_changes.clear()
		last_reason = ""
		fail_mutations = false
		partial_mutations = false

	func apply_block_mutations(changes: Array, reason: String = "test") -> Dictionary:
		batch_calls += 1
		last_reason = reason
		last_changes = changes.duplicate(true)
		if fail_mutations:
			return {
				"success": false,
				"changed": 0,
				"rejected": changes.size(),
				"truncated": 0,
				"reason": "forced_failure",
			}
		var changed := 0
		for raw_change: Variant in changes:
			if raw_change is not Dictionary:
				continue
			if partial_mutations and changed >= 1:
				break
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
			"rejected": maxi(0, changes.size() - changed),
			"truncated": 0,
			"rebuild": {"flush_count": batch_calls, "last_reason": reason},
		}


class FakeSpawner:
	extends Node3D

	signal creature_spawned(creature: Node3D)

	func publish(creature: Node3D) -> void:
		add_child(creature)
		creature_spawned.emit(creature)


class FakeDamageTarget:
	extends Node3D

	var damage_calls := 0
	var total_damage := 0.0
	var last_source := ""
	var last_attacker_id := 0

	func take_hostile_damage(
		amount: float,
		source_id: String,
		attacker_id: int
	) -> Dictionary:
		damage_calls += 1
		total_damage += amount
		last_source = source_id
		last_attacker_id = attacker_id
		return {"applied": true, "accepted": true}

	func reset_damage() -> void:
		damage_calls = 0
		total_damage = 0.0
		last_source = ""
		last_attacker_id = 0


class FakeHub:
	extends Node

	signal start_world_requested(world_state: Dictionary)
	signal return_to_menu_requested

	var world_node: Node
	var player_node: Node3D
	var creature_spawner: Node
	var current_world_id := "cover-world-v2"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_policy_contracts()
	await _test_runtime_safety_and_reposition()
	_test_long_session_budgets()
	if failures.is_empty():
		print("QA HOSTILE COVER COUNTER V2 PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE COVER COUNTER V2 FAILURE: %s" % failure)
	print(
		"QA HOSTILE COVER COUNTER V2 FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_policy_contracts() -> void:
	_check(PolicyScript.is_breakable_cover("wool"), "wool is explicit temporary breakable cover")
	_check(PolicyScript.is_breakable_cover("glass_pane"), "glass pane is explicit fragile breakable cover")
	_check(not PolicyScript.is_breakable_cover("stone"), "stone permanent bases are protected")
	_check(not PolicyScript.is_breakable_cover("planks"), "plank permanent bases are protected")
	_check(not PolicyScript.is_breakable_cover("oak_door"), "doors are protected")
	_check(not PolicyScript.is_breakable_cover("oak_fence"), "fences are protected")
	_check(not PolicyScript.is_breakable_cover("stone_slab"), "slabs are protected")
	_check(PolicyScript.blocks_projectile_lane("oak_door", 0.8), "closed door blocks projectiles")
	_check(not PolicyScript.blocks_projectile_lane("oak_door_open", 0.8), "open door exposes projectile lane")
	_check(PolicyScript.blocks_projectile_lane("oak_fence", 0.8), "fence conservatively blocks projectiles")
	_check(PolicyScript.blocks_projectile_lane("glass_pane", 0.8), "glass blocks hostile projectiles")
	_check(PolicyScript.blocks_projectile_lane("stone_slab", 0.2), "low projectile is blocked by slab")
	_check(not PolicyScript.blocks_projectile_lane("stone_slab", 0.8), "high projectile passes over slab")
	_check(not PolicyScript.blocks_projectile_lane("water", 0.5), "water does not block a projectile lane")
	_check(not PolicyScript.blocks_projectile_lane("lava", 0.5), "lava does not block a projectile lane")
	_check(PolicyScript.blocks_walk_lane("water", 0.5), "water is rejected as marksman walk lane")
	_check(PolicyScript.blocks_walk_lane("lava", 0.5), "lava is rejected as marksman walk lane")
	_check(PolicyScript.blocks_walk_lane("cactus", 0.5), "cactus is rejected as marksman walk lane")
	_check(not PolicyScript.is_safe_reposition_support("leaves"), "leaf canopy cannot become hostile footing")
	_check(not PolicyScript.is_safe_reposition_support("glow_crystal"), "decorative crystal cannot become hostile footing")
	var samples := PolicyScript.line_samples(Vector3.ZERO, Vector3(200.0, 0.0, 0.0))
	_check(
		samples.size() <= PolicyScript.MAX_LINE_SAMPLE_STEPS,
		"line sampling remains inside the sixty-four-step hard cap"
	)
	var directions := PolicyScript.reposition_directions(Vector3.FORWARD, 99)
	_check(
		directions.size() == PolicyScript.MAX_REPOSITION_PROBES,
		"marksman reposition fan remains inside six probes"
	)
	_check(
		not PolicyScript.can_attempt_reposition(
			10.0,
			0.0,
			PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET
		),
		"one target lock stops after four bounded reposition attempts"
	)


func _test_runtime_safety_and_reposition() -> void:
	var hub := FakeHub.new()
	root.add_child(hub)
	var world := FakeWorld.new()
	var player := FakeDamageTarget.new()
	var spawner := FakeSpawner.new()
	var service = ServiceScript.new()
	hub.world_node = world
	hub.player_node = player
	hub.creature_spawner = spawner
	hub.add_child(world)
	hub.add_child(player)
	hub.add_child(spawner)
	hub.add_child(service)
	player.global_position = Vector3(0.0, 2.05, 0.0)
	service.call("bind_parent_hub", hub)
	for _frame in 3:
		await process_frame
	_check(
		bool(service.call("get_snapshot").get("active", false)),
		"cover counter binds a production-style world lifecycle"
	)

	var factory = FactoryScript.new()
	var brute: Node3D = factory.create(
		"abyss_brute",
		Vector3(0.0, 2.05, -3.0),
		player,
		null
	) as Node3D
	var marksman: Node3D = factory.create(
		"abyss_marksman",
		Vector3(0.0, 2.05, -10.0),
		player,
		null
	) as Node3D
	_check(
		brute != null and brute.has_method("bind_cover_counter_service"),
		"factory composes the cover-aware abyss brute"
	)
	_check(
		marksman != null and marksman.has_method("bind_cover_counter_service"),
		"factory composes the cover-aware abyss marksman"
	)
	if brute == null or marksman == null:
		hub.queue_free()
		for _frame in 8:
			await process_frame
		return
	brute.set_physics_process(false)
	marksman.set_physics_process(false)
	spawner.publish(brute)
	spawner.publish(marksman)
	for _frame in 3:
		await process_frame
	brute.set_physics_process(false)
	marksman.set_physics_process(false)
	brute.call("bind_cover_counter_service", service)
	marksman.call("bind_cover_counter_service", service)
	_check(
		int(service.call("get_snapshot").get("bound_creature_count", 0)) == 2,
		"service binds spawned cover-aware hostile elites"
	)

	var first_cover := Vector3i(0, 3, -2)
	var second_cover := Vector3i(0, 3, -1)
	world.set_override(first_cover, "wool")
	world.set_override(second_cover, "glass_pane")
	var break_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(bool(break_result.get("handled", false)), "brute consumes an attack to break temporary cover")
	_check(bool(break_result.get("blocks_damage", false)), "cover break explicitly blocks same-frame player damage")
	_check(int(break_result.get("changed_blocks", 0)) == 2, "one attack breaks at most two temporary blocks")
	_check(world.batch_calls == 1, "one cover attack uses one world mutation batch")
	_check(world.last_reason == "hostile_cover_break", "cover mutation owns an auditable reason")
	_check(
		world.get_block(first_cover) == "air" and world.get_block(second_cover) == "air",
		"temporary cover reaches air in authoritative world state"
	)

	world.clear_explicit()
	world.set_generated(first_cover, "stone")
	var permanent_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(not bool(permanent_result.get("handled", true)), "permanent stone is never broken")
	_check(bool(permanent_result.get("blocks_damage", false)), "permanent stone explicitly blocks brute damage")
	_check(str(permanent_result.get("reason", "")) == "permanent_cover_blocked", "permanent wall reports bounded block reason")
	_check(world.get_block(first_cover) == "stone", "permanent stone remains unchanged")

	world.clear_explicit()
	world.set_generated(first_cover, "wool")
	var generated_result: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(not bool(generated_result.get("handled", true)), "generated fragile terrain is not mistaken for player cover")
	_check(bool(generated_result.get("blocks_damage", false)), "generated fragile terrain blocks damage")
	_check(world.get_block(first_cover) == "wool", "generated fragile terrain remains unchanged")

	world.clear_explicit()
	world.set_generated(first_cover, "stone")
	world.set_override(second_cover, "wool")
	var behind_permanent: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(bool(behind_permanent.get("blocks_damage", false)), "permanent wall blocks attack before later temporary material")
	_check(world.get_block(second_cover) == "wool", "scan never destroys temporary cover behind permanent wall")

	world.clear_explicit()
	world.set_override(first_cover, "wool")
	world.fail_mutations = true
	var failed_mutation: Dictionary = service.call("resolve_brute_attack", brute, player)
	_check(not bool(failed_mutation.get("handled", true)), "failed world mutation is not reported as a successful break")
	_check(bool(failed_mutation.get("blocks_damage", false)), "failed mutation still blocks same-frame damage")
	_check(str(failed_mutation.get("reason", "")) == "mutation_failed", "failed mutation has explicit telemetry")
	_check(world.get_block(first_cover) == "wool", "failed mutation preserves player cover")

	# Verify the production brute caller, not only the service return dictionary.
	world.clear_explicit()
	player.reset_damage()
	world.set_generated(first_cover, "stone")
	brute.call("_commit_attack")
	_check(player.damage_calls == 0, "production brute cannot damage through permanent wall")

	world.clear_explicit()
	player.reset_damage()
	var exhausted_counts: Dictionary = {}
	exhausted_counts[int(brute.get_instance_id())] = PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE
	service.set("_brute_break_counts", exhausted_counts)
	world.set_override(first_cover, "wool")
	brute.call("_commit_attack")
	var exhausted_snapshot: Dictionary = brute.call("get_hostile_attack_snapshot")
	var exhausted_last: Dictionary = exhausted_snapshot.get("last_cover_result", {})
	_check(player.damage_calls == 0, "production brute cannot damage through cover after lifetime budget exhaustion")
	_check(str(exhausted_last.get("reason", "")) == "brute_break_budget_exhausted", "production brute records exhausted lifetime budget")
	_check(world.get_block(first_cover) == "wool", "budget exhaustion preserves remaining player cover")

	world.clear_explicit()
	player.reset_damage()
	service.set("_brute_break_counts", {})
	world.set_override(first_cover, "wool")
	world.fail_mutations = true
	brute.call("_commit_attack")
	var failed_snapshot: Dictionary = brute.call("get_hostile_attack_snapshot")
	var failed_last: Dictionary = failed_snapshot.get("last_cover_result", {})
	_check(player.damage_calls == 0, "production brute cannot damage through cover when mutation fails")
	_check(str(failed_last.get("reason", "")) == "mutation_failed", "production brute exposes mutation failure reason")

	world.clear_explicit()
	player.reset_damage()
	service.set("_brute_break_counts", {})
	brute.call("_commit_attack")
	_check(player.damage_calls == 1, "clear lane still reaches the existing production melee attack")
	_check(player.total_damage > 0.0, "clear-lane melee applies configured positive damage")

	world.clear_explicit()
	world.set_override(Vector3i(0, 3, -5), "wool")
	_check(not bool(service.call("has_projectile_lane", marksman, player)), "temporary wall blocks marksman projectile lane")
	var directions: Array[Vector3] = PolicyScript.reposition_directions(
		player.global_position - marksman.global_position
	)
	var first_raw := marksman.global_position + directions[0] * PolicyScript.REPOSITION_RADIUS
	var first_support := Vector3i(floori(first_raw.x), 1, floori(first_raw.z))
	world.set_generated(first_support, "lava")
	var reposition: Dictionary = service.call(
		"find_marksman_reposition_destination",
		marksman,
		player,
		5.5,
		24.0
	)
	_check(bool(reposition.get("success", false)), "blocked marksman finds another bounded lateral lane")
	_check(int(reposition.get("probes", 99)) <= PolicyScript.MAX_REPOSITION_PROBES, "reposition never exceeds six probes")
	var destination: Vector3 = reposition.get("destination", Vector3.ZERO)
	_check(
		destination.distance_to(marksman.global_position) <= PolicyScript.REPOSITION_RADIUS + 0.2,
		"destination remains local instead of teleporting across the map"
	)
	_check(
		world.get_block(Vector3i(floori(destination.x), 1, floori(destination.z))) != "lava",
		"selected destination rejects lava support"
	)
	var service_snapshot: Dictionary = service.call("get_snapshot")
	_check(int(service_snapshot.get("marksman_hazard_rejection_count", 0)) >= 1, "hazard rejection is observable")

	world.clear_explicit()
	world.set_override(Vector3i(0, 3, -5), "wool")
	for direction: Vector3 in directions:
		var raw_candidate := marksman.global_position + direction * PolicyScript.REPOSITION_RADIUS
		world.set_generated(
			Vector3i(floori(raw_candidate.x), 1, floori(raw_candidate.z)),
			"lava"
		)
	var no_lane: Dictionary = service.call(
		"find_marksman_reposition_destination",
		marksman,
		player,
		5.5,
		24.0
	)
	_check(not bool(no_lane.get("success", true)), "fully hazardous ring yields no unsafe reposition")
	_check(str(no_lane.get("reason", "")) == "no_safe_lane", "hazard exhaustion returns explicit no-safe-lane reason")
	_check(int(no_lane.get("probes", 99)) <= PolicyScript.MAX_REPOSITION_PROBES, "failed search is still bounded")

	world.clear_explicit()
	world.set_override(Vector3i(0, 3, -5), "wool")
	marksman.set("_blocked_lane_seconds", PolicyScript.REPOSITION_DELAY_SECONDS)
	marksman.set("_reposition_cooldown_remaining", 0.0)
	marksman.call("_choose_direction")
	var marksman_snapshot: Dictionary = marksman.call("get_hostile_attack_snapshot")
	_check(int(marksman_snapshot.get("reposition_attempt_count", 0)) == 1, "cover-aware marksman records a real attempt")
	_check(int(marksman_snapshot.get("reposition_success_count", 0)) == 1, "cover-aware marksman accepts safe lane")
	_check(bool(marksman_snapshot.get("cover_destination_active", false)), "marksman moves through existing destination contract")

	hub.current_world_id = ""
	hub.world_node = null
	hub.return_to_menu_requested.emit()
	var cleared: Dictionary = service.call("get_snapshot")
	_check(int(cleared.get("cover_break_block_count", -1)) == 0, "return to menu clears cover counters")
	_check(int(cleared.get("marksman_reposition_count", -1)) == 0, "return to menu clears reposition counters")
	_check(not bool(cleared.get("active", true)), "return to menu releases world attachment")

	hub.queue_free()
	for _frame in 12:
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
	_check(target_sequence == 120, "sixty-minute simulation rotates exactly one hundred twenty target locks")
	_check(
		maximum_attempts <= PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET,
		"sixty-minute simulation never exceeds per-target attempts"
	)
	_check(
		total_probes <= (
			120
			* PolicyScript.MAX_REPOSITION_ATTEMPTS_PER_TARGET
			* PolicyScript.MAX_REPOSITION_PROBES
		),
		"sixty-minute probe work remains linearly bounded"
	)
	_check(
		PolicyScript.MAX_BREAK_BLOCKS_PER_BRUTE == 12,
		"long-session brute destruction remains capped at twelve blocks per body"
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
