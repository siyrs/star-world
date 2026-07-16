class_name HusbandryPlayer
extends "res://src/player/character_progression_player.gd"

var entity_interaction_service: Node


func setup_gameplay_services(services: Dictionary) -> void:
	super.setup_gameplay_services(services)
	if services.get("entity_interaction") is Node:
		bind_entity_interaction_service(services["entity_interaction"])


func bind_entity_interaction_service(p_service: Node) -> void:
	entity_interaction_service = p_service


func interact_or_use_selected_item() -> bool:
	if _try_interact_entity():
		return true
	return super.interact_or_use_selected_item()


func _try_interact_entity() -> bool:
	if entity_interaction_service == null or not entity_interaction_service.has_method("interact_entity"):
		return false
	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return false
	var collider: Variant = interaction_ray.get_collider()
	if collider is not Node or not collider.is_in_group("creatures"):
		return false
	var raw_result: Variant = entity_interaction_service.call("interact_entity", collider, inventory)
	if raw_result is not Dictionary:
		return false
	var result: Dictionary = raw_result
	if not bool(result.get("handled", false)):
		return false
	if bool(result.get("success", false)):
		var action := StringName(result.get("action", "interact_entity"))
		_report_player_action(action, result.duplicate(true))
	return true
