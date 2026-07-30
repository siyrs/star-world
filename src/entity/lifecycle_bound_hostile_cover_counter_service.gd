class_name LifecycleBoundHostileCoverCounterService
extends "res://src/entity/hostile_cover_counter_service.gd"

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
	var start_callback := Callable(self, "_on_world_start_requested")
	if _lifecycle_hub.has_signal("start_world_requested") and not _lifecycle_hub.is_connected(
		"start_world_requested", start_callback
	):
		_lifecycle_hub.connect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_return_to_menu_requested")
	if _lifecycle_hub.has_signal("return_to_menu_requested") and not _lifecycle_hub.is_connected(
		"return_to_menu_requested", return_callback
	):
		_lifecycle_hub.connect("return_to_menu_requested", return_callback)


func _disconnect_parent_lifecycle() -> void:
	if _lifecycle_hub == null or not is_instance_valid(_lifecycle_hub):
		_lifecycle_hub = null
		return
	var start_callback := Callable(self, "_on_world_start_requested")
	if _lifecycle_hub.has_signal("start_world_requested") and _lifecycle_hub.is_connected(
		"start_world_requested", start_callback
	):
		_lifecycle_hub.disconnect("start_world_requested", start_callback)
	var return_callback := Callable(self, "_on_return_to_menu_requested")
	if _lifecycle_hub.has_signal("return_to_menu_requested") and _lifecycle_hub.is_connected(
		"return_to_menu_requested", return_callback
	):
		_lifecycle_hub.disconnect("return_to_menu_requested", return_callback)
	_lifecycle_hub = null


func _on_world_start_requested(_state: Dictionary) -> void:
	clear("world_start_requested")


func _on_return_to_menu_requested() -> void:
	clear("return_to_menu_requested")
	world = null
	player = null
	_bound_world_id = ""


func _exit_tree() -> void:
	_disconnect_parent_lifecycle()
	super._exit_tree()
