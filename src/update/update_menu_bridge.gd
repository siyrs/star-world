class_name UpdateMenuBridge
extends Node

const MAX_BIND_FRAMES := 240

var _frames := 0
var _bound := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	if _bound:
		set_process(false)
		return
	_frames += 1
	var service := get_node_or_null("/root/StarWorldUpdateService")
	var menu := get_tree().root.find_child("MainMenu", true, false)
	if service != null and menu != null:
		menu.set("update_service", service)
		if menu.has_method("_setup_update_service"):
			menu.call("_setup_update_service")
		_bound = true
		set_process(false)
	elif _frames >= MAX_BIND_FRAMES:
		set_process(false)
