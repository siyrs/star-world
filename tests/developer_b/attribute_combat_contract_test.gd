extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentScript = preload("res://src/equipment/equipment_service.gd")
const AttributeScript = preload("res://src/attribute/attribute_service.gd")
const CombatScript = preload("res://src/combat/combat_service.gd")


func _initialize() -> void:
	var inventory = InventoryScript.new()
	var equipment = EquipmentScript.new()
	var attributes = AttributeScript.new()
	var combat = CombatScript.new()
	equipment.setup(inventory.registry)
	attributes.setup(equipment)
	combat.setup(attributes, equipment)
	assert(equipment.equip("main_hand", {"item_id":"iron_sword","count":1}))
	assert(equipment.equip("helmet", {"item_id":"iron_helmet","count":1}))
	assert(float(attributes.get_value("attack_damage")) == 6.0)
	assert(float(attributes.get_value("defense")) == 2.0)
	var result: Dictionary = combat.resolve_incoming_damage(10.0, "contract", false)
	assert(float(result.get("final_damage", 10.0)) < 10.0)
	assert(float(result.get("mitigation_ratio", 0.0)) > 0.0)
	quit(0)
