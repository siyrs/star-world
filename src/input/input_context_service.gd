class_name InputContextService
extends Node

signal context_changed(context: StringName)
signal gameplay_input_changed(enabled: bool)

const CONTEXT_MENU: StringName = &"menu"
const CONTEXT_LOADING: StringName = &"loading"
const CONTEXT_GAMEPLAY: StringName = &"gameplay"
const CONTEXT_INVENTORY: StringName = &"inventory"
const CONTEXT_CRAFTING: StringName = &"crafting"
const CONTEXT_CONTAINER: StringName = &"container"
const CONTEXT_MACHINE: StringName = &"machine"
const CONTEXT_PAUSE: StringName = &"pause"
const CONTEXT_DEATH: StringName = &"death"
const Actions = preload("res://src/input/gameplay_input_actions.gd")
const VALID_CONTEXTS := [
	CONTEXT_MENU,
	CONTEXT_LOADING,
	CONTEXT_GAMEPLAY,
	CONTEXT_INVENTORY,
	CONTEXT_CRAFTING,
	CONTEXT_CONTAINER,
	CONTEXT_MACHINE,
	CONTEXT_PAUSE,
	CONTEXT_DEATH,
]

var _context: StringName = CONTEXT_MENU
var _player: Node
var _last_gameplay_enabled := false
var _application_focused := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_context(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_application_focused = false
			_apply_context()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_application_focused = true
			_apply_context()


func _input(event: InputEvent) -> void:
	if not is_gameplay_context() or not _application_focused:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		_apply_mouse_mode()
		get_viewport().set_input_as_handled()


func bind_player(player: Node) -> void:
	if _player == player:
		_apply_context()
		return
	unbind_player()
	_player = player
	_apply_context()


func unbind_player(player: Node = null) -> void:
	if player != null and player != _player:
		return
	if is_instance_valid(_player) and _player.has_method("set_input_enabled"):
		_player.call("set_input_enabled", false)
	_player = null
	_last_gameplay_enabled = false
	_release_action_state()


func set_context(context: StringName) -> bool:
	if not VALID_CONTEXTS.has(context):
		push_warning("Unknown input context: %s" % context)
		return false
	var changed := context != _context
	_context = context
	_apply_context(changed)
	return true


func get_context() -> StringName:
	return _context


func is_gameplay_context() -> bool:
	return _context == CONTEXT_GAMEPLAY


func is_gameplay_input_enabled() -> bool:
	return is_gameplay_context() and _application_focused


func reapply() -> void:
	_apply_context()


func _apply_context(emit_context_change: bool = false) -> void:
	var gameplay_enabled := is_gameplay_input_enabled()
	if _last_gameplay_enabled and not gameplay_enabled:
		_release_action_state()
	_apply_player_state(gameplay_enabled)
	_apply_mouse_mode()
	if gameplay_enabled:
		_release_gui_focus()
	if gameplay_enabled != _last_gameplay_enabled:
		_last_gameplay_enabled = gameplay_enabled
		gameplay_input_changed.emit(gameplay_enabled)
	if emit_context_change:
		context_changed.emit(_context)


func _apply_player_state(gameplay_enabled: bool) -> void:
	if not is_instance_valid(_player):
		_player = null
		return
	if _player.has_method("set_input_enabled"):
		_player.call("set_input_enabled", gameplay_enabled)


func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if is_gameplay_input_enabled() else Input.MOUSE_MODE_VISIBLE
	)


func _release_gui_focus() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func _release_action_state() -> void:
	for raw_action in Actions.DEFAULT_KEY_BINDINGS:
		Input.action_release(StringName(raw_action))
