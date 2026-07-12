class_name SimulationPauseService
extends Node

signal pause_changed(paused: bool)

var _paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_paused(false)


func _exit_tree() -> void:
	if _paused and get_tree() != null:
		get_tree().paused = false
	_paused = false


func set_paused(value: bool) -> void:
	var tree := get_tree()
	if tree == null:
		_paused = value
		return
	if _paused == value and tree.paused == value:
		return
	_paused = value
	tree.paused = value
	pause_changed.emit(_paused)


func reset() -> void:
	set_paused(false)


func is_paused() -> bool:
	return _paused
