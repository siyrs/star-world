class_name AgricultureInteractionAdapter
extends Node

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var agriculture_service: Node


func setup(p_agriculture_service: Node) -> void:
	agriculture_service = p_agriculture_service


func try_interact(
	world: Node,
	inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return {"handled": false}
	var target_position: Vector3i = block_position
	var target_block: String = block_id
	if _is_farmland(block_id) and world != null and world.has_method("get_block"):
		var crop_position: Vector3i = block_position + Vector3i.UP
		var crop_block: String = str(world.call("get_block", crop_position))
		if _is_crop_block(crop_block):
			target_position = crop_position
			target_block = crop_block
	var raw_result: Variant = agriculture_service.call(
		"try_interact", world, inventory, target_position, target_block
	)
	return raw_result.duplicate(true) if raw_result is Dictionary else {"handled": false}


func get_interaction_hint(block_id: String, selected_item_id: String = "") -> String:
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return ""
	return str(
		agriculture_service.call(
			"get_interaction_hint", block_id, selected_item_id
		)
	)


func can_break_block(world: Node, block_position: Vector3i, block_id: String) -> bool:
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return true
	if agriculture_service.has_method("can_break_block"):
		return bool(
			agriculture_service.call(
				"can_break_block", world, block_position, block_id
			)
		)
	return true


func on_block_removed(world: Node, block_position: Vector3i, block_id: String) -> void:
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return
	if agriculture_service.has_method("on_block_removed"):
		agriculture_service.call(
			"on_block_removed", world, block_position, block_id
		)


func _is_farmland(block_id: String) -> bool:
	return block_id in ["farmland", "farmland_wet"]


func _is_crop_block(block_id: String) -> bool:
	return str(BlockRegistryScript.get_definition(block_id).get("shape", "")) == "crop"
