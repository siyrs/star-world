class_name AnimalHusbandryService
extends "res://src/husbandry/animal_husbandry_service_impl.gd"


func is_ready() -> bool:
	return (
		item_registry != null
		and inventory != null
		and spawner != null
		and bool(registry.call("ensure_loaded"))
	)


func get_managed_records() -> Dictionary:
	_sync_live_records()
	return records.duplicate(true)


func get_live_entity(husbandry_id: String) -> Node3D:
	return _live_entity(husbandry_id)


func detach_world() -> void:
	_disconnect_live_creature_signals()
	super.detach_world()


func shutdown() -> void:
	clear()
	item_registry = null
	inventory = null
	spawner = null
	world = null
	player = null


func _disconnect_live_creature_signals() -> void:
	for raw_id: Variant in _live.keys():
		var husbandry_id := str(raw_id)
		var raw_entity: Variant = _live.get(husbandry_id)
		if raw_entity is not Node or not is_instance_valid(raw_entity):
			continue
		var entity: Node = raw_entity
		if not entity.has_signal("died"):
			continue
		var callback := Callable(self, "_on_creature_died").bind(husbandry_id)
		if entity.is_connected("died", callback):
			entity.disconnect("died", callback)
