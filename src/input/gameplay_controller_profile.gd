class_name GameplayControllerProfile
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/gameplay_controller_profile.json"
const SUPPORTED_SCHEMA_VERSION := 1
const MAX_BINDINGS := 32
const REQUIRED_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_forward", "move_backward",
	"look_left", "look_right", "look_up", "look_down",
	"jump", "sprint", "primary_action", "secondary_action", "reload",
	"hotbar_previous", "hotbar_next", "toggle_inventory", "toggle_crafting",
	"toggle_exploration_journal", "toggle_guidance", "toggle_diagnostics",
	"quick_save", "ui_cancel",
]
const ALLOWED_KINDS: Array[String] = ["button", "axis"]

var schema_version := SUPPORTED_SCHEMA_VERSION
var profile_id := "standard_gamepad"
var profile_name := "标准双摇杆手柄"
var movement_deadzone := 0.22
var look_deadzone := 0.18
var look_response_exponent := 1.55
var look_speed_radians_per_second := 2.8
var trigger_threshold := 0.55
var _bindings: Array[Dictionary] = []
var _validation_errors: Array[String] = []
var _loaded_from_file := false


func _init() -> void:
	if not load_from_file():
		_install_builtin_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_reset()
	if not FileAccess.file_exists(path):
		_record_error("Gameplay controller profile is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open gameplay controller profile: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_record_error("Gameplay controller profile root must be an object")
		return false
	var data: Dictionary = parsed
	if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		_record_error("Unsupported gameplay controller schema version")
		return false
	schema_version = SUPPORTED_SCHEMA_VERSION
	profile_id = str(data.get("profile_id", "")).strip_edges()
	profile_name = str(data.get("name", "")).strip_edges()
	if profile_id.is_empty() or profile_name.is_empty():
		_record_error("Gameplay controller profile identity is incomplete")
		return false
	movement_deadzone = _normalized_float(data.get("movement_deadzone", 0.22), 0.05, 0.6, 0.22, "movement_deadzone")
	look_deadzone = _normalized_float(data.get("look_deadzone", 0.18), 0.05, 0.6, 0.18, "look_deadzone")
	look_response_exponent = _normalized_float(data.get("look_response_exponent", 1.55), 1.0, 3.0, 1.55, "look_response_exponent")
	look_speed_radians_per_second = _normalized_float(data.get("look_speed_radians_per_second", 2.8), 0.5, 8.0, 2.8, "look_speed_radians_per_second")
	trigger_threshold = _normalized_float(data.get("trigger_threshold", 0.55), 0.1, 0.95, 0.55, "trigger_threshold")
	var raw_bindings: Variant = data.get("bindings", [])
	if raw_bindings is not Array:
		_record_error("Gameplay controller bindings must be an array")
		return false
	if raw_bindings.is_empty() or raw_bindings.size() > MAX_BINDINGS:
		_record_error("Gameplay controller binding count is outside the bounded budget")
		return false
	var physical_bindings: Dictionary = {}
	var action_counts: Dictionary = {}
	for raw_binding: Variant in raw_bindings:
		if raw_binding is not Dictionary:
			_record_error("Gameplay controller binding must be an object")
			continue
		var normalized := _normalize_binding(raw_binding)
		if normalized.is_empty():
			continue
		var physical_key := _physical_key(normalized)
		if physical_bindings.has(physical_key):
			_record_error("Duplicate gameplay controller physical binding: %s" % physical_key)
			continue
		physical_bindings[physical_key] = true
		var action := str(normalized.get("action", ""))
		action_counts[action] = int(action_counts.get(action, 0)) + 1
		_bindings.append(normalized)
	for required_action: String in REQUIRED_ACTIONS:
		if int(action_counts.get(required_action, 0)) != 1:
			_record_error("Gameplay controller action must have exactly one binding: %s" % required_action)
	_loaded_from_file = _validation_errors.is_empty()
	return _loaded_from_file


func get_bindings() -> Array[Dictionary]:
	return _bindings.duplicate(true)


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func get_snapshot() -> Dictionary:
	return {
		"schema_version": schema_version,
		"profile_id": profile_id,
		"name": profile_name,
		"loaded_from_file": _loaded_from_file,
		"binding_count": _bindings.size(),
		"binding_budget": MAX_BINDINGS,
		"movement_deadzone": movement_deadzone,
		"look_deadzone": look_deadzone,
		"look_response_exponent": look_response_exponent,
		"look_speed_radians_per_second": look_speed_radians_per_second,
		"trigger_threshold": trigger_threshold,
		"validation_error_count": _validation_errors.size(),
	}


func apply_look_curve(raw_vector: Vector2) -> Vector2:
	var magnitude := raw_vector.length()
	if magnitude <= look_deadzone:
		return Vector2.ZERO
	var normalized_strength := clampf((magnitude - look_deadzone) / maxf(0.001, 1.0 - look_deadzone), 0.0, 1.0)
	return raw_vector.normalized() * pow(normalized_strength, look_response_exponent)


func deadzone_for_action(action: StringName) -> float:
	var action_text := str(action)
	if action_text.begins_with("look_"):
		return look_deadzone
	if action_text in ["primary_action", "secondary_action"]:
		return trigger_threshold
	return movement_deadzone


func _normalize_binding(raw_binding: Dictionary) -> Dictionary:
	var action := str(raw_binding.get("action", "")).strip_edges()
	var kind := str(raw_binding.get("kind", "")).strip_edges()
	if action not in REQUIRED_ACTIONS:
		_record_error("Unknown gameplay controller action: %s" % action)
		return {}
	if kind not in ALLOWED_KINDS:
		_record_error("Unknown gameplay controller binding kind: %s" % kind)
		return {}
	if kind == "button":
		var button := int(raw_binding.get("button", -1))
		if button < 0 or button > 31:
			_record_error("Invalid gameplay controller button for %s" % action)
			return {}
		return {"action": action, "kind": kind, "button": button}
	var axis := int(raw_binding.get("axis", -1))
	var value := float(raw_binding.get("value", 0.0))
	if axis < 0 or axis > 7 or not is_finite(value) or not is_equal_approx(absf(value), 1.0):
		_record_error("Invalid gameplay controller axis for %s" % action)
		return {}
	return {"action": action, "kind": kind, "axis": axis, "value": signf(value)}


func _physical_key(binding: Dictionary) -> String:
	if str(binding.get("kind", "")) == "button":
		return "button:%d" % int(binding.get("button", -1))
	return "axis:%d:%d" % [int(binding.get("axis", -1)), int(signf(float(binding.get("value", 0.0))))]


func _normalized_float(value: Variant, minimum: float, maximum: float, fallback: float, field_name: String) -> float:
	var numeric := float(value)
	if not is_finite(numeric) or numeric < minimum or numeric > maximum:
		_record_error("Invalid gameplay controller field: %s" % field_name)
		return fallback
	return numeric


func _reset() -> void:
	schema_version = SUPPORTED_SCHEMA_VERSION
	profile_id = "standard_gamepad"
	profile_name = "标准双摇杆手柄"
	movement_deadzone = 0.22
	look_deadzone = 0.18
	look_response_exponent = 1.55
	look_speed_radians_per_second = 2.8
	trigger_threshold = 0.55
	_bindings.clear()
	_validation_errors.clear()
	_loaded_from_file = false


func _install_builtin_fallback() -> void:
	_reset()
	_bindings = [
		_axis("move_left", 0, -1.0), _axis("move_right", 0, 1.0),
		_axis("move_forward", 1, -1.0), _axis("move_backward", 1, 1.0),
		_axis("look_left", 2, -1.0), _axis("look_right", 2, 1.0),
		_axis("look_up", 3, -1.0), _axis("look_down", 3, 1.0),
		_axis("secondary_action", 4, 1.0), _axis("primary_action", 5, 1.0),
		_button("jump", 0), _button("toggle_crafting", 2),
		_button("toggle_inventory", 3), _button("toggle_exploration_journal", 4),
		_button("ui_cancel", 6), _button("sprint", 7), _button("reload", 9),
		_button("quick_save", 10), _button("toggle_guidance", 11),
		_button("toggle_diagnostics", 12), _button("hotbar_previous", 13),
		_button("hotbar_next", 14),
	]


func _axis(action: String, axis: int, value: float) -> Dictionary:
	return {"action": action, "kind": "axis", "axis": axis, "value": value}


func _button(action: String, button: int) -> Dictionary:
	return {"action": action, "kind": "button", "button": button}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
