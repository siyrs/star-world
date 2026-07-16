class_name WorldInteractionPreview
extends Node3D

signal preview_changed(snapshot: Dictionary)

const TARGET_COLOR := Color("#F6FAFFDD")
const VALID_COLOR := Color("#64E59ECC")
const INVALID_COLOR := Color("#FF6B6BCC")
const VALID_FILL := Color("#64E59E2E")
const INVALID_FILL := Color("#FF6B6B2E")

var _player: Node
var _active := false
var _snapshot: Dictionary = {}
var _target_outlines: Array[MeshInstance3D] = []
var _placement_outlines: Array[MeshInstance3D] = []
var _placement_fills: Array[MeshInstance3D] = []
var _target_material: StandardMaterial3D
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
	var target_position: Variant = _position_from(_snapshot.get("target_position", []))
	var target_visible := bool(_snapshot.get("target_visible", false)) and target_position != null
	var target_boxes := _boxes_from(_snapshot.get("target_boxes", []))
	_render_outline_group(
		_target_outlines,
		"TargetOutline",
		Vector3(target_position) if target_position != null else Vector3.ZERO,
		target_boxes,
		target_visible,
		1.018,
		_target_material
	)

	var placement_position: Variant = _position_from(
		_snapshot.get("placement_position", [])
	)
	var placement_visible := (
		bool(_snapshot.get("placement_visible", false)) and placement_position != null
	)
	var valid := bool(_snapshot.get("valid", false))
	_placement_outline_material.albedo_color = VALID_COLOR if valid else INVALID_COLOR
	_placement_outline_material.emission = VALID_COLOR if valid else INVALID_COLOR
	_placement_fill_material.albedo_color = VALID_FILL if valid else INVALID_FILL
	_placement_fill_material.emission = VALID_FILL if valid else INVALID_FILL
	var placement_boxes := _boxes_from(_snapshot.get("placement_boxes", []))
	var cell_origin := Vector3(placement_position) if placement_position != null else Vector3.ZERO
	_render_outline_group(
		_placement_outlines,
		"PlacementOutline",
		cell_origin,
		placement_boxes,
		placement_visible,
		1.035,
		_placement_outline_material
	)
	_render_fill_group(cell_origin, placement_boxes, placement_visible)


func _build_visuals() -> void:
	_target_material = _line_material(TARGET_COLOR)
	_placement_outline_material = _line_material(VALID_COLOR)
	_placement_fill_material = StandardMaterial3D.new()
	_placement_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placement_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_placement_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_placement_fill_material.albedo_color = VALID_FILL
	_placement_fill_material.emission_enabled = true
	_placement_fill_material.emission = VALID_FILL
	_placement_fill_material.render_priority = 1
	_ensure_outline_count(_target_outlines, 1, "TargetOutline", _target_material)
	_ensure_outline_count(
		_placement_outlines, 1, "PlacementOutline", _placement_outline_material
	)
	_ensure_fill_count(1)


func _render_outline_group(
	nodes: Array[MeshInstance3D],
	prefix: String,
	cell_origin: Vector3,
	boxes: Array[AABB],
	visible: bool,
	inflation: float,
	material: StandardMaterial3D
) -> void:
	var normalized := boxes if not boxes.is_empty() else [AABB(Vector3.ZERO, Vector3.ONE)]
	_ensure_outline_count(nodes, normalized.size(), prefix, material)
	for index in nodes.size():
		var node := nodes[index]
		var should_show := visible and index < normalized.size()
		node.visible = should_show
		if not should_show:
			continue
		var box: AABB = normalized[index]
		node.position = cell_origin + box.position + box.size * 0.5
		node.scale = box.size * inflation


func _render_fill_group(cell_origin: Vector3, boxes: Array[AABB], visible: bool) -> void:
	var normalized := boxes if not boxes.is_empty() else [AABB(Vector3.ZERO, Vector3.ONE)]
	_ensure_fill_count(normalized.size())
	for index in _placement_fills.size():
		var node := _placement_fills[index]
		var should_show := visible and index < normalized.size()
		node.visible = should_show
		if not should_show:
			continue
		var box: AABB = normalized[index]
		node.position = cell_origin + box.position + box.size * 0.5
		node.scale = box.size * 0.94


func _ensure_outline_count(
	nodes: Array[MeshInstance3D],
	count: int,
	prefix: String,
	material: StandardMaterial3D
) -> void:
	while nodes.size() < maxi(1, count):
		var index := nodes.size()
		var node := _wire_box(prefix if index == 0 else "%s_%d" % [prefix, index], material)
		add_child(node)
		nodes.append(node)


func _ensure_fill_count(count: int) -> void:
	while _placement_fills.size() < maxi(1, count):
		var index := _placement_fills.size()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var node := MeshInstance3D.new()
		node.name = "PlacementFill" if index == 0 else "PlacementFill_%d" % index
		node.mesh = mesh
		node.material_override = _placement_fill_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_placement_fills.append(node)


func _wire_box(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var half := 0.5
	var corners: Array[Vector3] = [
		Vector3(-half,-half,-half), Vector3(half,-half,-half),
		Vector3(half,half,-half), Vector3(-half,half,-half),
		Vector3(-half,-half,half), Vector3(half,-half,half),
		Vector3(half,half,half), Vector3(-half,half,half),
	]
	var edges: Array[Array] = [
		[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
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


func _boxes_from(value: Variant) -> Array[AABB]:
	var result: Array[AABB] = []
	if value is not Array:
		return result
	for raw_box: Variant in value:
		if raw_box is not Dictionary:
			continue
		var box_data: Dictionary = raw_box
		var position_value: Variant = _vector3_from(box_data.get("position", []))
		var size_value: Variant = _vector3_from(box_data.get("size", []))
		if position_value == null or size_value == null:
			continue
		var size: Vector3 = size_value
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			continue
		result.append(AABB(position_value, size))
	return result


func _hide_all() -> void:
	for node: MeshInstance3D in _target_outlines:
		node.visible = false
	for node: MeshInstance3D in _placement_outlines:
		node.visible = false
	for node: MeshInstance3D in _placement_fills:
		node.visible = false


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


func _vector3_from(value: Variant) -> Variant:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null
