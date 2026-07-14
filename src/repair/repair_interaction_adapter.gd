class_name RepairInteractionAdapter
extends Node

var game_ui: Node
var repair_service: Node


func setup(p_game_ui: Node, p_repair_service: Node) -> void:
	game_ui = p_game_ui
	repair_service = p_repair_service


func try_interact(
	_world: Node,
	_inventory: Node,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	if not _is_repair_station(block_id):
		return {"handled": false}
	if game_ui == null or not game_ui.has_method("open_repair"):
		return _reject(block_position, block_id, "修理界面暂不可用")
	if not bool(game_ui.call("open_repair")):
		return _reject(block_position, block_id, "当前状态无法打开修理台")
	return {
		"handled": true,
		"success": true,
		"action": &"open_repair",
		"position": block_position,
		"message": "已打开修理台",
		"severity": "info",
	}


func get_interaction_hint(block_id: String, _selected_item_id: String = "") -> String:
	return "右键打开修理台" if _is_repair_station(block_id) else ""


func can_break_block(_world: Node, _block_position: Vector3i, _block_id: String) -> bool:
	return true


func on_block_removed(_world: Node, _block_position: Vector3i, _block_id: String) -> void:
	return


func _is_repair_station(block_id: String) -> bool:
	return (
		repair_service != null
		and repair_service.has_method("get_station_block")
		and block_id == str(repair_service.call("get_station_block"))
	)


func _reject(position: Vector3i, block_id: String, message: String) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"action": &"open_repair",
		"reason": "repair_ui_unavailable",
		"position": position,
		"block_id": block_id,
		"message": message,
		"severity": "warning",
	}
