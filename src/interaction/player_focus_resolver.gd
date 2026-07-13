class_name PlayerFocusResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")


func resolve(ray: RayCast3D, world: Node) -> Dictionary:
	if ray == null or not is_instance_valid(ray):
		return {}
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var collider = ray.get_collider()
	if collider is Node and (collider.is_in_group("creatures") or collider.has_method("take_damage")):
		return _entity_focus(collider)
	if world == null or not world.has_method("world_to_block") or not world.has_method("get_block"):
		return {}
	var point := ray.get_collision_point()
	var normal := ray.get_collision_normal()
	var block_position: Vector3i = world.call("world_to_block", point - normal * 0.01)
	var block_id := str(world.call("get_block", block_position))
	if block_id == BlockRegistryScript.AIR:
		return {}
	var definition := BlockRegistryScript.get_definition(block_id)
	return {
		"type": "block",
		"target_key": "%s@%d,%d,%d" % [
			block_id, block_position.x, block_position.y, block_position.z
		],
		"block_id": block_id,
		"display_name": str(definition.get("name", block_id)),
		"collectible": BlockRegistryScript.is_collectible(block_id),
		"solid": BlockRegistryScript.is_solid(block_id),
		"position": [block_position.x, block_position.y, block_position.z],
	}


func _entity_focus(collider: Node) -> Dictionary:
	var display_name := str(_property_value(collider, "display_name", collider.name))
	var species_id := str(_property_value(collider, "species_id", "creature"))
	var health_value = _property_value(collider, "health", null)
	var maximum_value = _property_value(collider, "max_health", null)
	var result := {
		"type": "entity",
		"target_key": "entity:%d" % collider.get_instance_id(),
		"entity_id": collider.get_instance_id(),
		"species_id": species_id,
		"display_name": display_name,
	}
	if health_value != null and maximum_value != null:
		result["health"] = float(health_value)
		result["max_health"] = float(maximum_value)
	return result


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback
