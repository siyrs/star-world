extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const EquipmentServiceScript = preload("res://src/equipment/equipment_service.gd")


func _initialize() -> void:
	var inventory = InventoryScript.new()
	var service = EquipmentServiceScript.new()
	service.setup(inventory.registry)
	inventory.add_item("iron_sword", 1)
	assert(service.equip_from_inventory(inventory, 0))
	assert(str(service.get_slot("main_hand").get("item_id", "")) == "iron_sword")
	assert(float(service.get_attribute_modifiers().get("attack_damage", 0.0)) == 5.0)
	assert(inventory.count_item("iron_sword") == 0)
	assert(service.unequip_to_inventory(inventory, "main_hand"))
	assert(service.get_slot("main_hand").is_empty())
	assert(inventory.count_item("iron_sword") == 1)
	quit(0)
