class_name CombatService
extends Node

signal outgoing_attack_resolved(result: Dictionary)
signal incoming_damage_resolved(result: Dictionary)
signal attack_rejected(result: Dictionary)
signal cooldown_changed(snapshot: Dictionary)

const DamageCalculatorScript = preload("res://src/combat/damage_calculator.gd")
const CadenceRegistryScript = preload("res://src/combat/combat_cadence_registry.gd")
const CadencePolicyScript = preload("res://src/combat/combat_cadence_policy.gd")
const MAIN_HAND_SLOT := "main_hand"
const COOLDOWN_SIGNAL_INTERVAL := 0.05

var attribute_service: Node
var equipment_service: Node
var calculator = DamageCalculatorScript.new()
var cadence_registry = CadenceRegistryScript.new()
var cadence_policy = CadencePolicyScript.new()

var _cooldown_remaining := 0.0
var _cooldown_total := 0.0
var _cooldown_signal_accumulator := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	cadence_registry.ensure_loaded()


func _process(delta: float) -> void:
	if _cooldown_remaining <= 0.0:
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - maxf(0.0, delta))
	_cooldown_signal_accumulator += maxf(0.0, delta)
	if _cooldown_remaining <= 0.0 or _cooldown_signal_accumulator >= COOLDOWN_SIGNAL_INTERVAL:
		_emit_cooldown()


func setup(p_attribute_service: Node, p_equipment_service: Node = null) -> void:
	attribute_service = p_attribute_service
	equipment_service = p_equipment_service
	cadence_registry.ensure_loaded()


func has_equipped_weapon() -> bool:
	return not get_equipped_weapon_id().is_empty()


func get_equipped_weapon_id() -> String:
	if equipment_service == null or not equipment_service.has_method("get_slot"):
		return ""
	var raw_slot: Variant = equipment_service.call("get_slot", MAIN_HAND_SLOT)
	if raw_slot is not Dictionary:
		return ""
	return str(raw_slot.get("item_id", ""))


func get_attack_profile() -> Dictionary:
	return cadence_registry.get_profile(get_equipped_weapon_id())


func get_attack_damage(fallback_damage: float = 1.0) -> float:
	if attribute_service == null or not attribute_service.has_method("get_value"):
		return maxf(0.0, fallback_damage)
	return maxf(0.0, float(attribute_service.call("get_value", "attack_damage", fallback_damage)))


func try_attack_target(target: Node, attacker: Node3D) -> Dictionary:
	var profile: Dictionary = get_attack_profile()
	var target_available := _target_available(target)
	var result: Dictionary = cadence_policy.evaluate(
		profile, _cooldown_remaining, target_available
	)
	result["status"] = "rejected"
	result["weapon_item_id"] = get_equipped_weapon_id()
	result["target_id"] = target.get_instance_id() if target_available else 0
	result["target_name"] = _target_name(target) if target_available else ""
	if not bool(result.get("accepted", false)):
		if bool(result.get("handled", false)):
			attack_rejected.emit(result.duplicate(true))
		return result

	var damage_result: Dictionary = calculator.calculate(
		_attribute_snapshot(), _target_attributes(target), "player_attack"
	)
	result.merge(damage_result, true)
	var attacker_forward := Vector3.FORWARD
	if attacker != null and is_instance_valid(attacker):
		attacker_forward = -attacker.global_transform.basis.z
	var knockback := cadence_policy.build_knockback(
		attacker.global_position if attacker != null else Vector3.ZERO,
		target.global_position if target is Node3D else Vector3.ZERO,
		attacker_forward,
		profile
	)
	result["knockback"] = [knockback.x, knockback.y, knockback.z]
	result["hit_stun_seconds"] = float(profile.get("hit_stun_seconds", 0.0))
	var applied: Dictionary = _apply_hit(target, attacker, result)
	if not bool(applied.get("applied", false)):
		result["accepted"] = false
		result["reason"] = "target_rejected"
		result["status"] = "rejected"
		attack_rejected.emit(result.duplicate(true))
		return result
	result.merge(applied, true)
	_cooldown_total = maxf(0.10, float(profile.get("cooldown_seconds", 0.72)))
	_cooldown_remaining = _cooldown_total
	result["status"] = "hit"
	result["reason"] = "ok"
	result["cooldown_seconds"] = _cooldown_total
	result["cooldown_remaining"] = _cooldown_remaining
	result["ready_ratio"] = 0.0
	result["durability"] = consume_attack_durability(1)
	outgoing_attack_resolved.emit(result.duplicate(true))
	_emit_cooldown(true)
	return result


func resolve_outgoing_attack(defender_attributes: Dictionary = {}) -> Dictionary:
	var attacker := _attribute_snapshot()
	var result: Dictionary = calculator.calculate(attacker, defender_attributes, "player_attack")
	outgoing_attack_resolved.emit(result.duplicate(true))
	return result


func resolve_incoming_damage(
	raw_damage: float, source: String = "damage", consume_armor_durability: bool = true
) -> Dictionary:
	var result: Dictionary = calculator.calculate_raw(raw_damage, _attribute_snapshot(), source)
	if (
		consume_armor_durability
		and float(result.get("absorbed", 0.0)) > 0.0
		and equipment_service != null
		and equipment_service.has_method("consume_armor_durability")
	):
		result["armor_durability"] = equipment_service.call(
			"consume_armor_durability", 1, "damage:%s" % source
		)
	incoming_damage_resolved.emit(result.duplicate(true))
	return result


func consume_attack_durability(amount: int = 1) -> Dictionary:
	if equipment_service == null or not equipment_service.has_method("consume_durability"):
		return {"consumed": false, "broken": false}
	return equipment_service.call("consume_durability", MAIN_HAND_SLOT, amount, "attack")


func reset_transient_state() -> void:
	_cooldown_remaining = 0.0
	_cooldown_total = 0.0
	_emit_cooldown(true)


func get_cooldown_snapshot() -> Dictionary:
	return {
		"ready": _cooldown_remaining <= 0.0,
		"remaining_seconds": _cooldown_remaining,
		"total_seconds": _cooldown_total,
		"ready_ratio": cadence_policy.ready_ratio(_cooldown_remaining, _cooldown_total),
		"weapon_item_id": get_equipped_weapon_id(),
	}


func get_snapshot() -> Dictionary:
	return {
		"attributes": _attribute_snapshot(),
		"has_equipped_weapon": has_equipped_weapon(),
		"attack_damage": get_attack_damage(),
		"attack_profile": get_attack_profile(),
		"cooldown": get_cooldown_snapshot(),
	}


func _apply_hit(target: Node, attacker: Node3D, hit: Dictionary) -> Dictionary:
	if target.has_method("apply_combat_hit"):
		var raw_result: Variant = target.call("apply_combat_hit", hit.duplicate(true), attacker)
		if raw_result is Dictionary:
			return raw_result.duplicate(true)
		return {"applied": true}
	if target.has_method("take_damage"):
		target.call("take_damage", float(hit.get("final_damage", 0.0)), attacker)
		return {"applied": true}
	return {"applied": false}


func _target_available(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target.has_method("is_combat_target_available"):
		return bool(target.call("is_combat_target_available"))
	return target.has_method("apply_combat_hit") or target.has_method("take_damage")


func _target_attributes(target: Node) -> Dictionary:
	if target == null:
		return {}
	for method_name in ["get_attribute_snapshot", "get_combat_attributes"]:
		if target.has_method(method_name):
			var raw: Variant = target.call(method_name)
			if raw is Dictionary:
				return raw.duplicate(true)
	return {}


func _target_name(target: Node) -> String:
	if target == null:
		return ""
	for property in target.get_property_list():
		if str(property.get("name", "")) == "display_name":
			return str(target.get("display_name"))
	return target.name


func _emit_cooldown(force: bool = false) -> void:
	if not force and _cooldown_signal_accumulator < COOLDOWN_SIGNAL_INTERVAL:
		return
	_cooldown_signal_accumulator = 0.0
	cooldown_changed.emit(get_cooldown_snapshot())


func _attribute_snapshot() -> Dictionary:
	if attribute_service == null:
		return {}
	if attribute_service.has_method("get_snapshot"):
		return attribute_service.call("get_snapshot")
	if attribute_service.has_method("get_values"):
		return attribute_service.call("get_values")
	return {}
