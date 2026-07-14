class_name PrecisionInteractionPlayer
extends "res://src/player/husbandry_player.gd"

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const VoxelTargetResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")

var _precision_target_resolver = VoxelTargetResolverScript.new()


func _resolve_harvest_target() -> Dictionary:
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return {}
	var block_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var block_id := str(target.get("hit_block_id", BlockRegistryScript.AIR))
	if block_id == BlockRegistryScript.AIR:
		return {}
	return {"position":block_position, "block_id":block_id}


func _try_interact_target() -> bool:
	if interaction_service == null or world == null or not interaction_service.has_method("interact"):
		return false
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return false
	var block_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var block_id := str(target.get("hit_block_id", BlockRegistryScript.AIR))
	if block_id == BlockRegistryScript.AIR:
		return false
	var interacted := bool(interaction_service.call("interact", world, block_position, block_id))
	if interacted:
		_report_player_action(
			&"interact",
			{
				"block_id":block_id,
				"display_name":str(
					BlockRegistryScript.get_definition(block_id).get("name", block_id)
				),
				"position":[block_position.x, block_position.y, block_position.z],
			}
		)
	return interacted


func _resolve_placement_target() -> Dictionary:
	if world == null:
		return {}
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return {}
	var block_position: Vector3i = target.get("placement_position", Vector3i.ZERO)
	var previous_block := str(target.get("placement_block_id", BlockRegistryScript.AIR))
	# Ordinary building blocks must never replace an occupied voxel. The visible
	# hit block and its adjacent face are now one atomic placement contract.
	if previous_block != BlockRegistryScript.AIR:
		return {}
	var player_bounds := AABB(
		global_position + Vector3(-0.32, 0.0, -0.32), Vector3(0.64, 1.82, 0.64)
	)
	if player_bounds.intersects(AABB(Vector3(block_position), Vector3.ONE)):
		return {}
	var hit_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var face_normal: Vector3 = target.get("collision_normal", Vector3.ZERO)
	return {
		"position":block_position,
		"previous_block":previous_block,
		"hit_position":hit_position,
		"face_normal":face_normal,
	}
