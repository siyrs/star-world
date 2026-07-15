class_name MiningCrackOverlay
extends Node3D

const PolicyScript = preload("res://src/harvest/mining_feedback_policy.gd")
const TextureFactoryScript = preload("res://src/harvest/mining_crack_texture_factory.gd")
const REFRESH_INTERVAL := 0.25
const OVERLAY_SCALE := 1.006

var player: Node
var harvest_service: Node
var policy = PolicyScript.new()
var active := true
var _state: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _materials: Dictionary = {}
var _refresh_remaining := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	_build_mesh()
	_resolve_player()
	_refresh_bindings()
	_hide_overlay("ready")


func setup(p_player: Node, p_harvest_service: Node = null) -> void:
	_bind_player(p_player)
	_bind_harvest_service(p_harvest_service)
	if harvest_service != null and harvest_service.has_method("get_active_snapshot"):
		_apply_progress(harvest_service.call("get_active_snapshot"))


func set_active(value: bool) -> void:
	active = value
	if not active:
		_hide_overlay("inactive")


func get_snapshot() -> Dictionary:
	var result := _state.duplicate(true)
	result["active"] = active
	result["visible"] = visible
	result["global_position"] = [global_position.x, global_position.y, global_position.z]
	result["has_collision"] = _tree_has_collision(self)
	return result


func refresh_for_test() -> void:
	_refresh_bindings()
	if harvest_service != null and harvest_service.has_method("get_active_snapshot"):
		_apply_progress(harvest_service.call("get_active_snapshot"))


func _process(delta: float) -> void:
	_refresh_remaining -= maxf(0.0, delta)
	if _refresh_remaining <= 0.0:
		_refresh_remaining = REFRESH_INTERVAL
		_refresh_bindings()
	if visible and not _player_accepts_feedback():
		_hide_overlay("input_blocked")


func _build_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CrackMesh"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mesh_instance.mesh = box
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 1.0
	add_child(_mesh_instance)
	scale = Vector3.ONE * OVERLAY_SCALE


func _resolve_player() -> void:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("get_view_camera") and cursor.has_signal("gameplay_action_reported"):
			_bind_player(cursor)
			return
		cursor = cursor.get_parent()


func _bind_player(value: Node) -> void:
	player = value


func _refresh_bindings() -> void:
	if player == null or not is_instance_valid(player):
		_resolve_player()
	if player == null:
		return
	var next_harvest: Variant = player.get("harvest_service")
	if next_harvest is Node:
		_bind_harvest_service(next_harvest)


func _bind_harvest_service(value: Node) -> void:
	if harvest_service == value:
		return
	_disconnect_harvest_service()
	harvest_service = value
	if harvest_service == null:
		_hide_overlay("service_missing")
		return
	if harvest_service.has_signal("harvest_progress_changed"):
		harvest_service.connect(
			"harvest_progress_changed", Callable(self, "_on_harvest_progress_changed")
		)
	if harvest_service.has_signal("harvest_cancelled"):
		harvest_service.connect("harvest_cancelled", Callable(self, "_on_harvest_cancelled"))
	if harvest_service.has_signal("harvest_completed"):
		harvest_service.connect("harvest_completed", Callable(self, "_on_harvest_completed"))
	if harvest_service.has_signal("harvest_rejected"):
		harvest_service.connect("harvest_rejected", Callable(self, "_on_harvest_rejected"))


func _on_harvest_progress_changed(snapshot: Dictionary) -> void:
	_apply_progress(snapshot)


func _on_harvest_cancelled(_reason: String) -> void:
	_hide_overlay("cancelled")


func _on_harvest_completed(_result: Dictionary) -> void:
	_hide_overlay("completed")


func _on_harvest_rejected(reason: String, _snapshot: Dictionary) -> void:
	_hide_overlay(reason)


func _apply_progress(snapshot: Dictionary) -> void:
	var evaluation: Dictionary = policy.evaluate(snapshot, active and _player_accepts_feedback())
	_state = evaluation.duplicate(true)
	if not bool(evaluation.get("visible", false)):
		visible = false
		return
	var block_position: Vector3i = evaluation.get("block_position", Vector3i.ZERO)
	global_position = Vector3(block_position) + Vector3.ONE * 0.5
	var stage := int(evaluation.get("stage", 0))
	_mesh_instance.material_override = _material_for_stage(stage)
	visible = true


func _hide_overlay(reason: String) -> void:
	_state = policy.evaluate({}, false)
	_state["reason"] = reason
	visible = false


func _material_for_stage(stage: int) -> StandardMaterial3D:
	var normalized := clampi(stage, 0, TextureFactoryScript.STAGE_COUNT - 1)
	if _materials.has(normalized):
		return _materials[normalized]
	var material := StandardMaterial3D.new()
	material.albedo_texture = TextureFactoryScript.get_texture(normalized)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.render_priority = 110
	_materials[normalized] = material
	return material


func _player_accepts_feedback() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return bool(player.get("input_enabled")) and player.visible


func _disconnect_harvest_service() -> void:
	if harvest_service == null:
		return
	for pair in [
		["harvest_progress_changed", "_on_harvest_progress_changed"],
		["harvest_cancelled", "_on_harvest_cancelled"],
		["harvest_completed", "_on_harvest_completed"],
		["harvest_rejected", "_on_harvest_rejected"],
	]:
		var signal_name := str(pair[0])
		var callback := Callable(self, str(pair[1]))
		if harvest_service.has_signal(signal_name) and harvest_service.is_connected(signal_name, callback):
			harvest_service.disconnect(signal_name, callback)


func _tree_has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _tree_has_collision(child):
			return true
	return false


func _exit_tree() -> void:
	_disconnect_harvest_service()
