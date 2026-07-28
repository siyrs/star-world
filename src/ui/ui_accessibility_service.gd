class_name UiAccessibilityService
extends Node

signal input_mode_changed(mode: StringName)
signal ui_scale_changed(scale: float)

const Policy = preload("res://src/settings/ui_accessibility_policy.gd")

var _input_mode: StringName = Policy.MODE_KEYBOARD
var _ui_scale := Policy.DEFAULT_SCALE
var _mode_change_count := 0
var _scale_change_count := 0
var _disposed := false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)


func setup(settings: Dictionary) -> void:
	_disposed = false
	apply_settings(settings)


func _input(event: InputEvent) -> void:
	if _disposed:
		return
	var next_mode := Policy.classify_event(event, _input_mode)
	if next_mode == _input_mode:
		return
	_input_mode = next_mode
	_mode_change_count += 1
	input_mode_changed.emit(_input_mode)


func apply_settings(settings: Dictionary) -> void:
	if _disposed:
		return
	var next_scale := Policy.normalize_scale(settings.get("ui_scale", Policy.DEFAULT_SCALE))
	var changed := not is_equal_approx(next_scale, _ui_scale)
	_ui_scale = next_scale
	ThemeDB.fallback_base_scale = _ui_scale
	if changed:
		_scale_change_count += 1
		ui_scale_changed.emit(_ui_scale)


func get_input_mode() -> StringName:
	return _input_mode


func get_ui_scale() -> float:
	return _ui_scale


func prefers_focus_navigation() -> bool:
	return _input_mode != Policy.MODE_MOUSE


func get_snapshot() -> Dictionary:
	return {
		"input_mode": _input_mode,
		"ui_scale": _ui_scale,
		"ui_scale_label": Policy.scale_label(_ui_scale),
		"focus_navigation": prefers_focus_navigation(),
		"mode_change_count": _mode_change_count,
		"scale_change_count": _scale_change_count,
		"disposed": _disposed,
	}


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	set_process_input(false)
	ThemeDB.fallback_base_scale = Policy.DEFAULT_SCALE
