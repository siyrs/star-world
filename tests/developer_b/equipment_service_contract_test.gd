extends SceneTree

const EquipmentServiceScript = preload("res://src/equipment/equipment_service.gd")

func _initialize() -> void:
	var service = EquipmentServiceScript.new()
	var ok := service.equip("main_hand", {"attack_damage": 5.0})
	assert(ok)
	assert(float(service.get_snapshot()["attributes"]["attack_damage"]) == 5.0)
	var removed := service.unequip("main_hand")
	assert(not removed.is_empty())
	quit()
