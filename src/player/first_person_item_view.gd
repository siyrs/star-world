class_name FirstPersonItemView
extends Node3D

const CONFIG_PATH := "res://data/first_person_viewmodel.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const PolicyScript = preload("res://src/player/held_item_visual_policy.gd")
const MeshFactoryScript = preload("res://src/player/held_item_mesh_factory.gd")

var player: Node
var inventory: Node
var harvest_service: Node
var policy = PolicyScript.new()
var mesh_factory = MeshFactoryScript.new()
var config: Dictionary = {}
var active := true
var current_item_id := ""
var current_block_id := ""
var current_model_kind := "empty"
var mining_active := false
var _model: Node3D
var _elapsed := 0.0
var _swing_remaining := 0.0
var _use_remaining := 0.0
var _switch_remaining := 0.0
var _service_refresh_remaining := 0.0
var _base_position := Vector3.ZERO
var _base_rotation_degrees := Vector3.ZERO
var _base_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_resolve_player()
	_refresh_bindings()
	_refresh_selected_item()


func setup(p_player: Node, p_inventory: Node = null, p_harvest_service: Node = null) -> void:
	_bind_player(p_player)
	_bind_inventory(p_inventory)
	_bind_harvest_service(p_harvest_service)
	_refresh_selected_item()


func set_active(value: bool) -> void:
	active = value
	_refresh_visibility()


func trigger_action(action: StringName) -> void:
	match policy.action_kind(action):
		PolicyScript.ACTION_SWING:
			_swing_remaining = maxf(0.05, float(config.get("swing_seconds", 0.28)))
		PolicyScript.ACTION_USE:
			_use_remaining = maxf(0.05, float(config.get("use_seconds", 0.24)))


func get_snapshot() -> Dictionary:
	return {
		"active": active,
		"visible": visible,
		"item_id": current_item_id,
		"block_id": current_block_id,
		"model_kind": current_model_kind,
		"part_count": int(_model.get_meta("part_count", 0)) if _model != null else 0,
		"mining_active": mining_active,
		"swing_remaining": _swing_remaining,
		"use_remaining": _use_remaining,
		"switch_remaining": _switch_remaining,
		"position": [position.x, position.y, position.z],
		"rotation_degrees": [rotation_degrees.x, rotation_degrees.y, rotation_degrees.z],
		"scale": [scale.x, scale.y, scale.z],
	}


func refresh_for_test() -> void:
	_refresh_bindings()
	_refresh_selected_item()
	_update_transform(0.0)


func _process(delta: float) -> void:
	var safe_delta := maxf(0.0, delta)
	_elapsed += safe_delta
	_swing_remaining = maxf(0.0, _swing_remaining - safe_delta)
	_use_remaining = maxf(0.0, _use_remaining - safe_delta)
	_switch_remaining = maxf(0.0, _switch_remaining - safe_delta)
	_service_refresh_remaining -= safe_delta
	if _service_refresh_remaining <= 0.0:
		_service_refresh_remaining = 0.25
		_refresh_bindings()
	_refresh_visibility()
	if visible:
		_update_transform(safe_delta)


func _load_config() -> void:
	config = {
		"base_position":[0.62, -0.52, -1.05],
		"base_rotation_degrees":[-18.0, -24.0, 8.0],
		"base_scale":0.72,
		"block_scale":0.72,
		"tool_scale":0.82,
		"item_scale":0.68,
		"switch_seconds":0.18,
		"swing_seconds":0.28,
		"use_seconds":0.24,
	}
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				config.merge(parsed, true)
	_base_position = _vector3_from(config.get("base_position", [0.62, -0.52, -1.05]))
	_base_rotation_degrees = _vector3_from(
		config.get("base_rotation_degrees", [-18.0, -24.0, 8.0])
	)
	_base_scale = maxf(0.05, float(config.get("base_scale", 0.72)))


func _resolve_player() -> void:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_signal("gameplay_action_reported") and cursor.has_method("get_selected_block_id"):
			_bind_player(cursor)
			return
		cursor = cursor.get_parent()


func _bind_player(value: Node) -> void:
	if player == value:
		return
	_disconnect_player()
	player = value
	if player != null and player.has_signal("gameplay_action_reported"):
		player.connect("gameplay_action_reported", Callable(self, "_on_gameplay_action_reported"))


func _bind_inventory(value: Node) -> void:
	if inventory == value:
		return
	_disconnect_inventory()
	inventory = value
	if inventory != null and inventory.has_signal("selected_slot_changed"):
		inventory.connect("selected_slot_changed", Callable(self, "_on_selected_slot_changed"))
	_refresh_selected_item()


func _bind_harvest_service(value: Node) -> void:
	if harvest_service == value:
		return
	_disconnect_harvest()
	harvest_service = value
	if harvest_service == null:
		return
	if harvest_service.has_signal("harvest_progress_changed"):
		harvest_service.connect(
			"harvest_progress_changed", Callable(self, "_on_harvest_progress_changed")
		)
	if harvest_service.has_signal("harvest_cancelled"):
		harvest_service.connect("harvest_cancelled", Callable(self, "_on_harvest_cancelled"))
	if harvest_service.has_signal("harvest_completed"):
		harvest_service.connect("harvest_completed", Callable(self, "_on_harvest_completed"))


func _refresh_bindings() -> void:
	if player == null or not is_instance_valid(player):
		_resolve_player()
	if player == null:
		return
	var next_inventory: Variant = player.get("inventory")
	if next_inventory is Node:
		_bind_inventory(next_inventory)
	var next_harvest: Variant = player.get("harvest_service")
	if next_harvest is Node:
		_bind_harvest_service(next_harvest)


func _refresh_selected_item() -> void:
	var slot: Dictionary = {}
	if inventory != null and inventory.has_method("get_selected_item"):
		var raw_slot: Variant = inventory.call("get_selected_item")
		if raw_slot is Dictionary:
			slot = raw_slot
	var item_id := str(slot.get("item_id", ""))
	if item_id == current_item_id and _model != null:
		return
	current_item_id = item_id
	var definition: Dictionary = {}
	if not item_id.is_empty() and inventory != null:
		var registry: Variant = inventory.get("registry")
		if registry != null and registry.has_method("get_item"):
			var raw_definition: Variant = registry.call("get_item", item_id)
			if raw_definition is Dictionary:
				definition = raw_definition
	current_block_id = str(definition.get("block_id", ""))
	if current_block_id.is_empty() and not item_id.is_empty():
		current_block_id = BlockRegistryScript.get_block_for_item(item_id)
	_rebuild_model(definition)


func _rebuild_model(definition: Dictionary) -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	current_model_kind = policy.classify(definition, current_block_id)
	if current_item_id.is_empty():
		_refresh_visibility()
		return
	_model = mesh_factory.build_model(current_item_id, definition, current_block_id)
	_model.name = "Model"
	add_child(_model)
	_switch_remaining = maxf(0.01, float(config.get("switch_seconds", 0.18)))
	_refresh_visibility()


func _update_transform(_delta: float) -> void:
	var movement_speed := 0.0
	var on_floor := false
	if player is CharacterBody3D:
		movement_speed = Vector2(player.velocity.x, player.velocity.z).length()
		on_floor = player.is_on_floor()
	var swing_duration := maxf(0.05, float(config.get("swing_seconds", 0.28)))
	var use_duration := maxf(0.05, float(config.get("use_seconds", 0.24)))
	var switch_duration := maxf(0.01, float(config.get("switch_seconds", 0.18)))
	var swing_ratio := -1.0 if _swing_remaining <= 0.0 else 1.0 - _swing_remaining / swing_duration
	var use_ratio := -1.0 if _use_remaining <= 0.0 else 1.0 - _use_remaining / use_duration
	var switch_ratio := 1.0 if _switch_remaining <= 0.0 else 1.0 - _switch_remaining / switch_duration
	var sample: Dictionary = policy.sample_transform(
		config,
		_elapsed,
		movement_speed,
		on_floor,
		swing_ratio,
		use_ratio,
		switch_ratio,
		mining_active
	)
	position = _base_position + sample.get("position_offset", Vector3.ZERO)
	rotation_degrees = _base_rotation_degrees + sample.get("rotation_degrees", Vector3.ZERO)
	var kind_scale := float(config.get("item_scale", _base_scale))
	match current_model_kind:
		"block":
			kind_scale = float(config.get("block_scale", _base_scale))
		"tool":
			kind_scale = float(config.get("tool_scale", _base_scale))
	var final_scale := maxf(0.05, kind_scale * float(sample.get("scale_multiplier", 1.0)))
	scale = Vector3.ONE * final_scale


func _refresh_visibility() -> void:
	var player_active := true
	if player != null and is_instance_valid(player):
		player_active = bool(player.get("input_enabled")) and player.visible
	visible = active and player_active and not current_item_id.is_empty() and _model != null


func _on_selected_slot_changed(_index: int, _slot: Dictionary) -> void:
	_refresh_selected_item()


func _on_gameplay_action_reported(action: StringName, _payload: Dictionary) -> void:
	trigger_action(action)


func _on_harvest_progress_changed(snapshot: Dictionary) -> void:
	mining_active = not snapshot.is_empty() and str(snapshot.get("status", "progress")) == "progress"


func _on_harvest_cancelled(_reason: String) -> void:
	mining_active = false


func _on_harvest_completed(_result: Dictionary) -> void:
	mining_active = false
	trigger_action(&"mine")


func _disconnect_player() -> void:
	if player == null or not player.has_signal("gameplay_action_reported"):
		return
	var callback := Callable(self, "_on_gameplay_action_reported")
	if player.is_connected("gameplay_action_reported", callback):
		player.disconnect("gameplay_action_reported", callback)


func _disconnect_inventory() -> void:
	if inventory == null or not inventory.has_signal("selected_slot_changed"):
		return
	var callback := Callable(self, "_on_selected_slot_changed")
	if inventory.is_connected("selected_slot_changed", callback):
		inventory.disconnect("selected_slot_changed", callback)


func _disconnect_harvest() -> void:
	if harvest_service == null:
		return
	for pair in [
		["harvest_progress_changed", "_on_harvest_progress_changed"],
		["harvest_cancelled", "_on_harvest_cancelled"],
		["harvest_completed", "_on_harvest_completed"],
	]:
		var signal_name := str(pair[0])
		var callback := Callable(self, str(pair[1]))
		if harvest_service.has_signal(signal_name) and harvest_service.is_connected(signal_name, callback):
			harvest_service.disconnect(signal_name, callback)


func _exit_tree() -> void:
	_disconnect_player()
	_disconnect_inventory()
	_disconnect_harvest()


func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
