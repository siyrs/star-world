class_name AnimalHusbandryService
extends "res://src/husbandry/animal_husbandry_service_impl.gd"


func get_managed_records() -> Dictionary:
	_sync_live_records()
	return records.duplicate(true)


func get_live_entity(husbandry_id: String) -> Node3D:
	return _live_entity(husbandry_id)
