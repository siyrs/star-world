class_name PlayerFocusResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const VoxelTargetResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")

var _voxel_target_resolver = VoxelTargetResolverScript.new()


func resolve(ray: RayCast3D, world: Node) -> Dictionary:
	var target: Dictionary = _voxel_target_resolver.resolve(ray, world)
	if target.is_empty():
		return {}
	if str(target.get("type", "")) == "entity":
		var collider: Variant = target.get("collider")
		return _entity_focus(collider) if collider is Node else {}
	if str(target.get("type", "")) != "block":
		return {}
	var raw_hit_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var raw_hit_block_id := str(target.get("hit_block_id", BlockRegistryScript.AIR))
	if raw_hit_block_id == BlockRegistryScript.AIR:
		return {}
	var block_position := raw_hit_position
	var block_id := raw_hit_block_id
	var proxy: Dictionary = _resolve_visual_proxy(world, block_position, block_id)
	if not proxy.is_empty():
		block_position = proxy.get("position", block_position)
		block_id = str(proxy.get("block_id", block_id))
	var definition := BlockRegistryScript.get_definition(block_id)
	var placement_position: Vector3i = target.get("placement_position", Vector3i.ZERO)
	var face_normal: Vector3 = target.get("collision_normal", Vector3.ZERO)
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
		"hit_position": [
			raw_hit_position.x, raw_hit_position.y, raw_hit_position.z
		],
		"hit_block_id": raw_hit_block_id,
		"placement_position": [
			placement_position.x, placement_position.y, placement_position.z
		],
		"placement_target_block_id": str(
			target.get("placement_block_id", BlockRegistryScript.AIR)
		),
		"face_normal": [face_normal.x, face_normal.y, face_normal.z],
		"interaction_proxy": bool(proxy.get("proxied", false)),
	}


func _resolve_visual_proxy(
	world: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if block_id not in ["farmland", "farmland_wet"]:
		return {}
	var crop_position := block_position + Vector3i.UP
	var crop_id := str(world.call("get_block", crop_position))
	var definition: Dictionary = BlockRegistryScript.get_definition(crop_id)
	if str(definition.get("shape", "")) != "crop":
		return {}
	return {
		"proxied": true,
		"position": crop_position,
		"block_id": crop_id,
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
		"elite": bool(_property_value(collider, "elite", false)),
		"danger_weight": maxf(0.0, float(_property_value(collider, "danger_weight", 1.0))),
	}
	if health_value != null and maximum_value != null:
		result["health"] = float(health_value)
		result["max_health"] = float(maximum_value)
	if collider.has_method("get_hostile_attack_snapshot"):
		var raw_attack: Variant = collider.call("get_hostile_attack_snapshot")
		if raw_attack is Dictionary and not raw_attack.is_empty():
			result["hostile_attack"] = raw_attack.duplicate(true)
	return result


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback
