extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const AttributeScript = preload("res://src/attribute/attribute_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")
const RegistryScript = preload("res://src/combat/combat_cadence_registry.gd")
const PolicyScript = preload("res://src/combat/combat_cadence_policy.gd")
const CreatureScript = preload("res://src/entity/base_creature.gd")
const OverlayScript = preload("res://src/ui/combat_feedback_overlay.gd")

var checks := 0
var failures: Array[String] = []


class FakeCombatTarget:
	extends Node3D
	var display_name := "测试假人"
	var health := 20.0
	var last_hit: Dictionary = {}

	func is_combat_target_available() -> bool:
		return health > 0.0

	func get_combat_attributes() -> Dictionary:
		return {"defense": 0.0}

	func apply_combat_hit(hit: Dictionary, _attacker: Node3D = null) -> Dictionary:
		var damage := maxf(0.0, float(hit.get("final_damage", 0.0)))
		var before := health
		health = maxf(0.0, health - damage)
		last_hit = hit.duplicate(true)
		return {
			"applied": damage > 0.0,
			"health_before": before,
			"health_after": health,
			"remaining_health": health,
			"defeated": health <= 0.0,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_policy()
	await _test_attack_transaction_and_feedback()
	await _test_creature_hit_capability()
	if failures.is_empty():
		print("QA COMBAT CADENCE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA COMBAT CADENCE FAILURE: %s" % failure)
		print("QA COMBAT CADENCE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = RegistryScript.new()
	_check(registry.load_from_file(), "combat cadence registry loads dedicated data")
	_check(registry.get_profile_count() == 5, "all five swords have explicit cadence profiles")
	var unarmed: Dictionary = registry.get_profile("")
	var iron: Dictionary = registry.get_profile("iron_sword")
	_check(float(unarmed.get("cooldown_seconds", 0.0)) > float(iron.get("cooldown_seconds", 9.0)), "iron sword attacks recover faster than unarmed attacks")
	_check(float(iron.get("knockback_horizontal", 0.0)) >= 3.0, "iron sword profile exposes meaningful knockback")
	var policy = PolicyScript.new()
	var ready: Dictionary = policy.evaluate(iron, 0.0, true)
	_check(bool(ready.get("accepted", false)), "ready attacks are accepted")
	var cooling: Dictionary = policy.evaluate(iron, 0.25, true)
	_check(not bool(cooling.get("accepted", true)) and str(cooling.get("reason", "")) == "cooldown", "cooldown blocks repeated attacks with a stable reason")
	var knockback := policy.build_knockback(Vector3.ZERO, Vector3(0.0, 0.0, -2.0), Vector3.FORWARD, iron)
	_check(knockback.z < -3.0 and knockback.y > 0.0, "knockback points away from the attacker and includes lift")


func _test_attack_transaction_and_feedback() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	var combat = CombatScript.new()
	var overlay = OverlayScript.new()
	var attacker := Node3D.new()
	var target := FakeCombatTarget.new()
	for node in [inventory, equipment, attributes, combat, overlay, attacker, target]:
		host.add_child(node)
	await process_frame
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	combat.setup(attributes, equipment)
	overlay.setup(combat)
	overlay.set_active(true)
	equipment.equip(
		"main_hand",
		{
			"item_id":"iron_sword",
			"count":1,
			"metadata":{"durability":2,"custom_name":"节奏测试剑"},
		}
	)
	attacker.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -2.0)
	var first: Dictionary = combat.try_attack_target(target, attacker)
	_check(bool(first.get("accepted", false)) and str(first.get("status", "")) == "hit", "first entity attack is committed by CombatService")
	_check(is_equal_approx(float(first.get("final_damage", 0.0)), 6.0), "equipped iron sword deals the aggregated attack value")
	_check(is_equal_approx(target.health, 14.0), "accepted attack changes target health exactly once")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("durability", 0)) == 1, "accepted attack consumes one equipped weapon durability")
	_check(float(target.last_hit.get("hit_stun_seconds", 0.0)) > 0.0, "target receives hit-stun context")
	_check(Array(target.last_hit.get("knockback", [])).size() == 3, "target receives a serialized knockback vector")
	var overlay_state: Dictionary = overlay.get_snapshot()
	_check(bool(overlay_state.get("hit_visible", false)), "successful hit produces visible hit feedback")
	_check(bool(overlay_state.get("cooldown_visible", false)), "successful hit starts a visible cooldown indicator")

	var health_after_first := target.health
	var second: Dictionary = combat.try_attack_target(target, attacker)
	_check(not bool(second.get("accepted", true)) and str(second.get("reason", "")) == "cooldown", "immediate repeated click is rejected by cooldown")
	_check(is_equal_approx(target.health, health_after_first), "cooldown rejection cannot deal duplicate damage")
	_check(int(equipment.get_slot("main_hand").get("metadata", {}).get("durability", 0)) == 1, "cooldown rejection cannot consume durability")
	_check(str(overlay.get_snapshot().get("last_result", {}).get("reason", "")) == "cooldown", "feedback overlay exposes the cooldown rejection")

	combat.call("_process", 2.0)
	_check(bool(combat.get_cooldown_snapshot().get("ready", false)), "cooldown deterministically returns to ready")
	var third: Dictionary = combat.try_attack_target(target, attacker)
	_check(bool(third.get("accepted", false)), "attack succeeds again after cooldown")
	_check(is_equal_approx(target.health, 8.0), "second accepted attack applies one additional damage transaction")
	_check(equipment.get_slot("main_hand").is_empty(), "weapon breaks only after its second accepted hit")
	_check(bool(third.get("durability", {}).get("broken", false)), "attack result explains weapon breakage")

	combat.reset_transient_state()
	var unarmed_profile: Dictionary = combat.get_attack_profile()
	_check(str(unarmed_profile.get("id", "")) == "unarmed", "broken weapon falls back to the unarmed cadence profile")
	var invalid: Dictionary = combat.try_attack_target(null, attacker)
	_check(not bool(invalid.get("handled", true)) and str(invalid.get("reason", "")) == "invalid_target", "invalid targets are ignored without starting cooldown")
	overlay.set_blocked(true)
	_check(not bool(overlay.get_snapshot().get("cooldown_visible", true)), "blocking UI hides combat feedback")
	_check(not _tree_has_collision_object(overlay), "combat feedback is a pure non-colliding presentation tree")
	host.queue_free()
	await process_frame
	await process_frame


func _test_creature_hit_capability() -> void:
	var creature = CreatureScript.new()
	root.add_child(creature)
	await process_frame
	creature.global_position = Vector3(0.0, 2.0, -2.0)
	var before := creature.health
	var result: Dictionary = creature.apply_combat_hit(
		{
			"final_damage":2.0,
			"knockback":[0.0, 0.5, -3.0],
			"hit_stun_seconds":0.2,
		},
		null
	)
	var snapshot: Dictionary = creature.get_combat_snapshot()
	_check(bool(result.get("applied", false)) and is_equal_approx(creature.health, before - 2.0), "creature combat capability applies damage")
	_check(float(snapshot.get("hit_stun_remaining", 0.0)) > 0.0, "creature stores transient hit stun")
	var velocity: Array = snapshot.get("velocity", [])
	_check(velocity.size() == 3 and float(velocity[2]) < -2.5, "creature stores the requested horizontal knockback")
	creature.queue_free()
	await process_frame


func _tree_has_collision_object(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _tree_has_collision_object(child):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
