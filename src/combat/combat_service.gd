class_name CombatService
extends Node

signal outgoing_attack_resolved(result: Dictionary)
signal incoming_damage_resolved(result: Dictionary)

const DamageCalculatorScript = preload("res://src/combat/damage_calculator.gd")
const MAIN_HAND_SLOT := "main_hand"

var attribute_service: Node
var equipment_service: Node
var calculator = DamageCalculatorScript.new()


func setup(p_attribute_service: Node, p_equipment_service: Node = null) -> void:
	attribute_service = p_attribute_service
	equipment_service = p_equipment_service


func has_equipped_weapon() -> bool:
	if equipment_service == null or not equipment_service.has_method("get_slot"):
		return false
	return not Dictionary(equipment_service.call("get_slot", MAIN_HAND_SLOT)).is_empty()


func get_attack_damage(fallback_damage: float = 1.0) -> float:
	if attribute_service == null or not attribute_service.has_method("get_value"):
		return maxf(0.0, fallback_damage)
	return maxf(0.0, float(attribute_service.call("get_value", "attack_damage", fallback_damage)))


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


func get_snapshot() -> Dictionary:
	return {
		"attributes": _attribute_snapshot(),
		"has_equipped_weapon": has_equipped_weapon(),
		"attack_damage": get_attack_damage(),
	}


func _attribute_snapshot() -> Dictionary:
	if attribute_service == null:
		return {}
	if attribute_service.has_method("get_snapshot"):
		return attribute_service.call("get_snapshot")
	if attribute_service.has_method("get_values"):
		return attribute_service.call("get_values")
	return {}
