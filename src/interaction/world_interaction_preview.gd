class_name WorldInteractionPreview
extends Node3D

signal preview_changed(snapshot: Dictionary)

const TARGET_COLOR := Color("#F6FAFFDD")
const VALID_COLOR := Color("#64E59ECC")
const INVALID_COLOR := Color("#FF6B6BCC")
const VALID_FILL := Color("#64E59E2E")
const INVALID_FILL := Color("#FF6B6B2E")
const BLOCK_CENTER_OFFSET := Vector3(0.5, 0.5, 0.5)

var _player: Node
var _active := false
var _snapshot: Dictionary = {}
var _target_outline: MeshInstance3D
var _placement_outline: MeshInstance3D
var _placement_fill: MeshInstance3D
var _placement_outline_material: StandardMaterial3D
var _placement_fill_material: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_visuals()
	_hide_all()


func setup(player: Node) -> void:
	_disconnect_player()
	_player = player
	if _player != null and _player.has_signal("interaction_focus_changed"):
		_player.connect(
			"interaction_focus_changed", Callable(self, "_on_interaction_focus_changed")
		)
	_refresh_from_player()


func set_active(value: bool) -> void:
	_active = value
	if not _active:
		_hide_all()
		return
	_refresh_from_player()


func clear() -> void:
	_snapshot.clear()
	_hide_all()
	preview_changed.emit({})


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _exit_tree() -> void:
	_disconnect_player()


func _on_interaction_focus_changed(focus: Dictionary) -> void:
	_apply_focus(focus)


func _refresh_from_player() -> void:
	if not _active or _player == null or not _player.has_method("get_interaction_focus"):
		_hide_all()
		return
	var focus: Dictionary = _player.call("get_interaction_focus")
	_apply_focus(focus)


func _apply_focus(focus: Dictionary) -> void:
	if not _active:
		_hide_all()
		return
	var raw_preview: Variant = focus.get("placement_preview", {})
	if raw_preview is not Dictionary:
		clear()
		return
	_snapshot = raw_preview.duplicate(true)
	_render_snapshot()
	preview_changed.emit(_snapshot.duplicate(true))


func _render_snapshot() -> void:
	var target_position := _position_from(_snapshot.get("target_position", []))
	var target_visible := bool(_snapshot.get("target_visible", false)) and target_position != null
	_target_outline.visible = target_visible
	if target_visible:
		_target_outline.position = Vector3(target_position) + BLOCK_CENTER_OFFSET

	var placement_position := _position_from(_snapshot.get("placement_position", []))
	var placement_visible := (
		bool(_snapshot.get("placement_visible", false)) and placement_position != null
	)
	_placement_outline.visible = placement_visible
	_placement_fill.visible = placement_visible
	if not placement_visible:
		return
	var world_position := Vector3(placement_position) + BLOCK_CENTER_OFFSET
	_placement_outline.position = world_position
	_placement_fill.position = world_position
	var valid := bool(_snapshot.get("valid", false))
	_placement_outline_material.albedo_color = VALID_COLOR if valid else INVALID_COLOR
	_placement_outline_material.emission = VALID_COLOR if valid else INVALID_COLOR
	_placement_fill_material.albedo_color = VALID_FILL if valid else INVALID_FILL
	_placement_fill_material.emission = VALID_FILL if valid else INVALID_FILL


func _build_visuals() -> void:
	var target_material := _line_material(TARGET_COLOR)
	_target_outline = _wire_box("TargetOutline", 1.018, target_material)
	add_child(_target_outline)

	_placement_outline_material = _line_material(VALID_COLOR)
	_placement_outline = _wire_box("PlacementOutline", 1.035, _placement_outline_material)
	add_child(_placement_outline)

	_placement_fill_material = StandardMaterial3D.new()
	_placement_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placement_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_placement_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_placement_fill_material.albedo_color = VALID_FILL
	_placement_fill_material.emission_enabled = true
	_placement_fill_material.emission = VALID_FILL
	_placement_fill_material.render_priority = 1
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.94, 0.94, 0.94)
	_placement_fill = MeshInstance3D.new()
	_placement_fill.name = "PlacementFill"
	_placement_fill.mesh = fill_mesh
	_placement_fill.material_override = _placement_fill_material
	_placement_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_placement_fill)


func _wire_box(
	node_name: String, extent: float, material: StandardMaterial3D
) -> MeshInstance3D:
	var half := extent * 0.5
	var corners := [
		Vector3(-half, -half, -half),
		Vector3(half, -half, -half),
		Vector3(half, half, -half),
		Vector3(-half, half, -half),
		Vector3(-half, -half, half),
		Vector3(half, -half, half),
		Vector3(half, half, half),
		Vector3(-half, half, half),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Array in edges:
		mesh.surface_add_vertex(corners[int(edge[0])])
		mesh.surface_add_vertex(corners[int(edge[1])])
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.render_priority = 2
	return material


func _hide_all() -> void:
	if _target_outline != null:
		_target_outline.visible = false
	if _placement_outline != null:
		_placement_outline.visible = false
	if _placement_fill != null:
		_placement_fill.visible = false


func _disconnect_player() -> void:
	if _player == null or not _player.has_signal("interaction_focus_changed"):
		_player = null
		return
	var callback := Callable(self, "_on_interaction_focus_changed")
	if _player.is_connected("interaction_focus_changed", callback):
		_player.disconnect("interaction_focus_changed", callback)
	_player = null


func _position_from(value: Variant) -> Variant:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return null
