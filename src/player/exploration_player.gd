class_name ExplorationPlayer
extends "res://src/player/ladder_climbing_player.gd"

var prospecting_service: Node


func bind_prospecting_service(p_service: Node) -> void:
	prospecting_service = p_service


func use_selected_item() -> bool:
	var item_id := _get_selected_item_id()
	if prospecting_service != null and prospecting_service.has_method("use_item"):
		var raw_result: Variant = prospecting_service.call("use_item", item_id)
		if raw_result is Dictionary:
			var result: Dictionary = raw_result
			if bool(result.get("handled", false)):
				if bool(result.get("success", false)):
					_report_player_action(&"prospect", result)
				return true
	return super.use_selected_item()
