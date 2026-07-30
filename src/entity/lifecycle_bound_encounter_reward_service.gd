class_name LifecycleBoundEncounterRewardService
extends "res://src/entity/encounter_reward_service.gd"

var _lifecycle_hub: Node


func _ready() -> void:
	super._ready()
	call_deferred("_bind_parent_lifecycle")


func bind_parent_hub(p_parent_hub: Node) -> void:
	_disconnect_parent_lifecycle()
	_lifecycle_hub = p_parent_hub
	super.bind_parent_hub(p_parent_hub)
	_connect_parent_lifecycle()


func _bind_parent_lifecycle() -> void:
	var parent_hub := get_parent()
	if parent_hub == null or not is_instance_valid(parent_hub):
		return
	bind_parent_hub(parent_hub)


func _connect_parent_lifecycle() -> void:
	if _lifecycle_hub == null or not is_instance_valid(_lifecycle_hub):
		return
	var start_callback := Callable(self, "_on_parent_start_world")
	if (
		_lifecycle_hub.has_signal("start_world_requested")
		and not _lifecycle_hub.is_connected("start_world_requested", start_callback)
	):
		_lifecycle_hub.connect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_parent_return_to_menu")
	if (
		_lifecycle_hub.has_signal("return_to_menu_requested")
		and not _lifecycle_hub.is_connected("return_to_menu_requested", return_callback)
	):
		_lifecycle_hub.connect("return_to_menu_requested", return_callback)


func _disconnect_parent_lifecycle() -> void:
	if _lifecycle_hub == null or not is_instance_valid(_lifecycle_hub):
		return
	var start_callback := Callable(self, "_on_parent_start_world")
	if (
		_lifecycle_hub.has_signal("start_world_requested")
		and _lifecycle_hub.is_connected("start_world_requested", start_callback)
	):
		_lifecycle_hub.disconnect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_parent_return_to_menu")
	if (
		_lifecycle_hub.has_signal("return_to_menu_requested")
		and _lifecycle_hub.is_connected("return_to_menu_requested", return_callback)
	):
		_lifecycle_hub.disconnect("return_to_menu_requested", return_callback)


func _on_parent_start_world(state: Dictionary) -> void:
	var metadata: Dictionary = state.get("metadata", {})
	clear("start_world_signal")
	_bound_world_id = str(metadata.get("id", ""))


func _on_parent_return_to_menu() -> void:
	clear("return_to_menu_signal")
	_bound_world_id = ""


func _exit_tree() -> void:
	_disconnect_parent_lifecycle()
	super._exit_tree()
