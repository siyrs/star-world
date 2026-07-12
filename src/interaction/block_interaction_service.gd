class_name BlockInteractionService
extends Node

signal interaction_opened(action: StringName, block_position: Vector3i, block_id: String)
signal interaction_rejected(reason: String, block_position: Vector3i, block_id: String)

const Registry = preload("res://src/interaction/block_interaction_registry.gd")

var game_ui
var container_storage
var inventory


func setup(p_game_ui, p_container_storage, p_inventory) -> void:
	game_ui = p_game_ui
	container_storage = p_container_storage
	inventory = p_inventory


func detach() -> void:
	game_ui = null
	container_storage = null
	inventory = null


func interact(world, block_position: Vector3i, block_id: String) -> bool:
	var definition := Registry.get_interaction(block_id)
	if definition.is_empty() or game_ui == null:
		return false
	var action := StringName(definition.get("action", ""))
	match action:
		Registry.ACTION_CRAFTING:
			var station := str(definition.get("station", "hand"))
			game_ui.call("open_crafting", station)
		Registry.ACTION_CONTAINER:
			if container_storage == null:
				_reject("container_service_missing", block_position, block_id)
				return false
			var container_id := get_container_id(world, block_position, block_id)
			var container_type := str(definition.get("container_type", "chest"))
			var slot_count := int(definition.get("slot_count", 27))
			if not container_storage.open_container(container_id, container_type, slot_count):
				_reject("container_open_failed", block_position, block_id)
				return false
			game_ui.call("open_container", container_id, str(definition.get("label", block_id)))
		_:
			return false
	interaction_opened.emit(action, block_position, block_id)
	return true


func can_break_block(world, block_position: Vector3i, block_id: String) -> bool:
	if not Registry.is_container(block_id) or container_storage == null:
		return true
	var container_id := get_container_id(world, block_position, block_id)
	if container_storage.is_empty(container_id):
		return true
	_show_message("箱子中还有物品，请先清空后再拆除")
	_reject("container_not_empty", block_position, block_id)
	return false


func on_block_removed(world, block_position: Vector3i, block_id: String) -> void:
	if not Registry.is_container(block_id) or container_storage == null:
		return
	var container_id := get_container_id(world, block_position, block_id)
	container_storage.remove_container(container_id, true)


func get_container_id(world, block_position: Vector3i, block_id: String = "chest") -> String:
	var position_key := "%d,%d,%d" % [block_position.x, block_position.y, block_position.z]
	if world != null and world.has_method("block_key"):
		position_key = str(world.call("block_key", block_position))
	return "%s@%s" % [block_id, position_key]


func get_interaction_hint(block_id: String) -> String:
	var definition := Registry.get_interaction(block_id)
	if definition.is_empty():
		return ""
	return "右键打开%s" % str(definition.get("label", block_id))


func _reject(reason: String, block_position: Vector3i, block_id: String) -> void:
	interaction_rejected.emit(reason, block_position, block_id)


func _show_message(message: String) -> void:
	if game_ui != null and game_ui.has_method("show_message"):
		game_ui.call("show_message", message, 3.0)
