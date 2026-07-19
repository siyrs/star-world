extends SceneTree

const AttackRegistryScript = preload("res://src/entity/hostile_attack_registry.gd")
const AttackPolicyScript = preload("res://src/entity/hostile_attack_policy.gd")
const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")

var checks := 0
var failures: Array[String] = []


class FakeTarget:
	extends Node3D
	var health := 20.0
	var last_source := ""
	var damage_events := 0

	func _ready() -> void:
		add_to_group("player")

	func is_combat_target_available() -> bool:
		return health > 0.0

	func take_damage(amount: float, source: String = "world") -> void:
		if amount <= 0.0:
			return
		health = maxf(0.0, health - amount)
		last_source = source
		damage_events += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_policy()
	await _test_factory_and_state_machine()
	_test_prompt_contract()
	if failures.is_empty():
		print("QA HOSTILE ATTACK WINDUP PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA HOSTILE ATTACK WINDUP FAILURE: %s" % failure)
		print("QA HOSTILE ATTACK WINDUP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = AttackRegistryScript.new()
	_check(registry.schema_version == 1, "hostile attack schema version is stable")
	_check(registry.get_validation_errors().is_empty(), "production hostile attack data has no validation errors")
	_check(registry.get_profile_ids() == ["zombie"], "only the production hostile species owns an attack profile")
	var zombie: Dictionary = registry.get_profile("zombie")
	_check(is_equal_approx(float(zombie.get("windup_seconds", 0.0)), 0.8), "zombie exposes a readable windup")
	_check(float(zombie.get("cooldown_seconds", 0.0)) >= 4.5, "zombie cadence does not outrun the player hostile-damage cooldown")
	_check(float(zombie.get("detection_range", 0.0)) > float(zombie.get("attack_range", 99.0)), "detection range exceeds the committed attack range")
	_check(
		AttackPolicyScript.can_begin(1.65, 1.65, 0.0, 0.0),
		"windup can begin at the inclusive attack boundary"
	)
	_check(
		not AttackPolicyScript.can_begin(1.65, 1.65, 0.1, 0.0),
		"cooldown blocks a new windup"
	)
	_check(
		AttackPolicyScript.cancellation_reason(true, 2.1, 1.65, 1.35, 0.0).is_empty(),
		"brief movement inside the cancel radius does not cancel prematurely"
	)
	_check(
		AttackPolicyScript.cancellation_reason(true, 2.3, 1.65, 1.35, 0.0) == "target_evaded",
		"leaving the cancel radius produces a stable dodge reason"
	)
	_check(
		AttackPolicyScript.cancellation_reason(true, 1.0, 1.65, 1.35, 0.2) == "interrupted",
		"hit stun interrupts a hostile windup"
	)
	_check(
		not AttackPolicyScript.can_commit(true, 1.7, 1.65, 0.0),
		"the final hit only commits inside the real attack range"
	)
	_check(
		is_equal_approx(AttackPolicyScript.progress_ratio(0.4, 0.8), 0.5),
		"windup progress is deterministic"
	)


func _test_factory_and_state_machine() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var target := FakeTarget.new()
	host.add_child(target)
	target.global_position = Vector3(0.0, 2.0, 1.3)
	var factory = CreatureFactoryScript.new()
	_check(factory.get_hostile_attack_validation_errors().is_empty(), "CreatureFactory composes valid hostile attack data")
	var creature_variant: Variant = factory.create("zombie", Vector3(0.0, 2.0, 0.0), target, null)
	_check(creature_variant is Node3D, "factory creates the production zombie")
	if creature_variant is not Node3D:
		host.queue_free()
		await process_frame
		return
	var zombie = creature_variant
	host.add_child(zombie)
	await process_frame
	zombie.set_physics_process(false)
	zombie.set("move_speed", 0.0)
	zombie.set("target", target)
	var profile: Dictionary = factory.get_hostile_attack_profile("zombie")
	_check(is_equal_approx(float(zombie.get("attack_windup_seconds")), float(profile.get("windup_seconds", 0.0))), "factory injects the authoritative windup")
	_check(str(zombie.get("attack_source_id")) == "zombie", "damage source comes from the attack profile")
	_check(is_equal_approx(float(zombie.get("attack_damage")), 1.0), "production and fallback zombie damage remain aligned")
	var telegraph := zombie.get_node_or_null("AttackTelegraph")
	_check(telegraph is MeshInstance3D, "hostile creature creates a non-colliding visual telegraph")
	_check(not _tree_has_collision_object(telegraph), "attack telegraph cannot affect physics or ray targeting")

	var events := {
		"started": 0,
		"cancelled": 0,
		"landed": 0,
		"cancel_reason": "",
	}
	zombie.connect(
		"attack_windup_started",
		func(_target: Node, _snapshot: Dictionary) -> void:
			events["started"] = int(events["started"]) + 1
	)
	zombie.connect(
		"attack_windup_cancelled",
		func(reason: String, _snapshot: Dictionary) -> void:
			events["cancelled"] = int(events["cancelled"]) + 1
			events["cancel_reason"] = reason
	)
	zombie.connect(
		"attack_landed",
		func(_target: Node, _damage: float) -> void:
			events["landed"] = int(events["landed"]) + 1
	)

	_check(bool(zombie.call("_begin_attack_windup")), "hostile begins a windup instead of dealing instant damage")
	var snapshot: Dictionary = zombie.call("get_hostile_attack_snapshot")
	_check(str(snapshot.get("state", "")) == "windup", "windup state is externally diagnosable")
	_check(bool(snapshot.get("telegraph_visible", false)), "red warning telegraph is visible during windup")
	_check(target.damage_events == 0 and is_equal_approx(target.health, 20.0), "starting a windup never deals early damage")
	zombie.call("_advance_attack_windup", 0.35)
	_check(target.damage_events == 0, "partial windup remains non-damaging")
	target.global_position = Vector3(0.0, 2.0, 3.0)
	zombie.call("_advance_attack_windup", 0.1)
	snapshot = zombie.call("get_hostile_attack_snapshot")
	_check(int(events["cancelled"]) == 1 and str(events["cancel_reason"]) == "target_evaded", "moving out of the warning radius cancels the attack")
	_check(str(snapshot.get("state", "")) == "cooldown", "cancelled attack enters a bounded recovery")
	_check(not bool(snapshot.get("telegraph_visible", true)), "cancelled attack immediately hides the telegraph")
	_check(target.damage_events == 0, "successful dodge prevents all damage")

	zombie.call("_physics_process", 0.7)
	target.global_position = Vector3(0.0, 2.0, 1.3)
	zombie.set("target", target)
	_check(bool(zombie.call("_begin_attack_windup")), "attack can begin again after cancel recovery")
	zombie.call("_advance_attack_windup", 0.81)
	snapshot = zombie.call("get_hostile_attack_snapshot")
	_check(int(events["landed"]) == 1 and target.damage_events == 1, "completed windup commits exactly one damage event")
	_check(is_equal_approx(target.health, 19.0), "committed attack uses the production zombie damage")
	_check(target.last_source == "zombie", "committed attack preserves the stable damage source")
	_check(str(snapshot.get("state", "")) == "cooldown", "successful attack enters data-driven cooldown")
	_check(not bool(zombie.call("_begin_attack_windup")), "cooldown rejects immediate repeat attacks")

	zombie.set("_attack_timer", 0.0)
	zombie.call("_set_attack_state", AttackPolicyScript.STATE_IDLE)
	_check(bool(zombie.call("_begin_attack_windup")), "third windup begins for interruption coverage")
	var creature_health_before := float(zombie.get("health"))
	var hit_result: Dictionary = zombie.call(
		"apply_combat_hit",
		{
			"final_damage": 2.0,
			"knockback": [0.0, 0.2, -1.0],
			"hit_stun_seconds": 0.25,
		},
		null
	)
	snapshot = zombie.call("get_hostile_attack_snapshot")
	_check(bool(hit_result.get("applied", false)), "player combat hit reaches the production creature capability")
	_check(is_equal_approx(float(zombie.get("health")), creature_health_before - 2.0), "interrupting hit still applies its own damage")
	_check(str(snapshot.get("last_cancel_reason", "")) == "interrupted", "combat interruption records a stable reason")
	_check(target.damage_events == 1, "interrupted windup cannot leak an additional player hit")
	_check(int(events["started"]) == 3 and int(events["cancelled"]) == 2 and int(events["landed"]) == 1, "windup lifecycle signals fire exactly once per transition")

	host.queue_free()
	await process_frame
	await process_frame


func _test_prompt_contract() -> void:
	var resolver = PromptResolverScript.new()
	var prompt: Dictionary = resolver.resolve(
		{
			"type": "entity",
			"display_name": "僵尸",
			"health": 20.0,
			"max_health": 20.0,
			"hostile_attack": {
				"enabled": true,
				"state": "windup",
				"windup_remaining": 0.4,
			},
		},
		null,
		null,
		null
	)
	_check(str(prompt.get("subtitle", "")).contains("正在蓄力"), "focus prompt explains the incoming attack")
	_check(str(prompt.get("primary", "")).contains("打断"), "focus prompt explains the interruption response")
	_check(str(prompt.get("secondary", "")).contains("离开红色预警圈"), "focus prompt explains the dodge response")
	_check(str(prompt.get("tone", "")) == "error", "windup prompt uses urgent presentation tone")


func _tree_has_collision_object(node: Node) -> bool:
	if node == null:
		return false
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _tree_has_collision_object(child):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
