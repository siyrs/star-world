class_name PrecisionInteractionPlayer
extends "res://src/player/husbandry_player.gd"

const PrecisionBlockRegistry = preload("res://src/block/block_registry.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const VoxelTargetResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")
const PlacementPreviewPolicyScript = preload(
	"res://src/interaction/placement_preview_policy.gd"
)
const INVALID_CONNECTION_POSITION := Vector3i(2147483647,2147483647,2147483647)

var block_structure_service: Node
var _precision_target_resolver = VoxelTargetResolverScript.new()
var _placement_preview_policy = PlacementPreviewPolicyScript.new()
var _last_placement_evaluation: Dictionary = {
	"valid":false,
	"reason":"no_focus",
}

@onready var interaction_preview: Node = get_node_or_null("InteractionPreview")


func _ready() -> void:
	super._ready()
	if interaction_preview != null:
		interaction_preview.call("setup", self)
		interaction_preview.call("set_active", input_enabled)


func bind_block_structure_service(service: Node) -> void:
	block_structure_service = service


func set_input_enabled(enabled: bool) -> void:
	super.set_input_enabled(enabled)
	if is_instance_valid(interaction_preview):
		interaction_preview.call("set_active", enabled)


func get_placement_preview_state() -> Dictionary:
	var raw_preview: Variant = _interaction_focus.get("placement_preview", {})
	return raw_preview.duplicate(true) if raw_preview is Dictionary else {}


func get_interaction_preview() -> Node:
	return interaction_preview


func get_resolved_placement_block_id() -> String:
	return _resolve_directional_block_id(get_selected_block_id())


func _update_interaction_focus(force: bool = false) -> void:
	var next_focus: Dictionary = _focus_resolver.resolve(interaction_ray, world)
	if str(next_focus.get("type", "")) == "block":
		var selected_block_id := get_resolved_placement_block_id()
		_append_connection_context(next_focus)
		_append_door_context(next_focus, selected_block_id)
		next_focus["placement_preview"] = _placement_preview_policy.evaluate(
			next_focus,
			selected_block_id,
			_player_bounds()
		)
	if not force and next_focus == _interaction_focus:
		return
	_interaction_focus = next_focus.duplicate(true)
	interaction_focus_changed.emit(_interaction_focus.duplicate(true))


func _on_inventory_selection_changed(index: int, slot: Dictionary) -> void:
	super._on_inventory_selection_changed(index, slot)
	_update_interaction_focus(true)


func _resolve_harvest_target() -> Dictionary:
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return {}
	var block_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var block_id := str(target.get("hit_block_id", PrecisionBlockRegistry.AIR))
	if block_id == PrecisionBlockRegistry.AIR:
		return {}
	return {"position":block_position,"block_id":block_id}


func _try_interact_target() -> bool:
	if interaction_service == null or world == null or not interaction_service.has_method("interact"):
		return false
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return false
	var block_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var block_id := str(target.get("hit_block_id", PrecisionBlockRegistry.AIR))
	if block_id == PrecisionBlockRegistry.AIR:
		return false
	var interacted := bool(interaction_service.call("interact",world,block_position,block_id))
	if interacted:
		_report_player_action(
			&"interact",
			{
				"block_id":block_id,
				"display_name":str(
					PrecisionBlockRegistry.get_definition(block_id).get("name",block_id)
				),
				"position":[block_position.x,block_position.y,block_position.z],
			}
		)
	return interacted


func _place_block(block_id: String) -> bool:
	var resolved_block_id := _resolve_directional_block_id(block_id)
	if world == null:
		_report_placement_failure("placement_unavailable",resolved_block_id)
		return false
	if inventory != null and _get_selected_item_id().is_empty():
		_report_placement_failure("no_block_selected",resolved_block_id)
		return false
	var target := _resolve_placement_target()
	if target.is_empty():
		_report_placement_failure(
			str(_last_placement_evaluation.get("reason","no_focus")),
			resolved_block_id
		)
		return false
	var placed := _commit_block_placement(resolved_block_id,target)
	if not placed:
		_report_placement_failure(
			str(_last_placement_evaluation.get("reason","placement_unavailable")),
			resolved_block_id
		)
	return placed


func _resolve_placement_target() -> Dictionary:
	var selected_block_id := get_resolved_placement_block_id()
	if world == null:
		_last_placement_evaluation = {
			"valid":false,
			"reason":"placement_unavailable",
		}
		return {}
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray,world)
	if str(target.get("type","")) != "block":
		_last_placement_evaluation = _placement_preview_policy.evaluate(
			{},
			selected_block_id,
			_player_bounds()
		)
		return {}
	var hit_position: Vector3i = target.get("hit_position",Vector3i.ZERO)
	var placement_position: Vector3i = target.get("placement_position",Vector3i.ZERO)
	var previous_block := str(target.get("placement_block_id",PrecisionBlockRegistry.AIR))
	var hit_block_id := str(target.get("hit_block_id",PrecisionBlockRegistry.AIR))
	var preview_focus := {
		"type":"block",
		"hit_position":[hit_position.x,hit_position.y,hit_position.z],
		"hit_block_id":hit_block_id,
		"target_neighbor_ids":_connection_neighbors_for(hit_position),
		"placement_position":[placement_position.x,placement_position.y,placement_position.z],
		"placement_target_block_id":previous_block,
		"placement_neighbor_ids":_connection_neighbors_for(placement_position),
	}
	_append_door_context(preview_focus, selected_block_id)
	var evaluation: Dictionary = _placement_preview_policy.evaluate(
		preview_focus,
		selected_block_id,
		_player_bounds()
	)
	_last_placement_evaluation = evaluation.duplicate(true)
	if not bool(evaluation.get("valid",false)):
		return {}
	var face_normal: Vector3 = target.get("collision_normal",Vector3.ZERO)
	return {
		"position":placement_position,
		"previous_block":previous_block,
		"hit_position":hit_position,
		"face_normal":face_normal,
		"connection_mask":int(evaluation.get("placement_connection_mask",0)),
	}


func _commit_block_placement(block_id: String, target: Dictionary) -> bool:
	if (
		block_structure_service != null
		and block_structure_service.has_method("try_place_block")
	):
		var raw_result: Variant = block_structure_service.call(
			"try_place_block",
			world,
			inventory,
			target.get("position", Vector3i.ZERO),
			block_id,
			str(target.get("previous_block", PrecisionBlockRegistry.AIR))
		)
		if raw_result is Dictionary:
			var result: Dictionary = raw_result
			if bool(result.get("handled", false)):
				if not bool(result.get("success", false)):
					_last_placement_evaluation["reason"] = str(
						result.get("reason", "placement_unavailable")
					)
					return false
				var block_position: Vector3i = target.get("position", Vector3i.ZERO)
				var display_name := str(
					PrecisionBlockRegistry.get_definition(block_id).get("name", block_id)
				)
				_report_player_action(
					&"place",
					{
						"block_id":block_id,
						"display_name":display_name,
						"position":[block_position.x,block_position.y,block_position.z],
					}
				)
				block_placed.emit(block_position, block_id)
				_update_interaction_focus(true)
				return true
	return super._commit_block_placement(block_id, target)


func _append_connection_context(focus: Dictionary) -> void:
	if world == null:
		return
	var hit_position := _focus_position(focus.get("hit_position",[]))
	if hit_position != INVALID_CONNECTION_POSITION:
		focus["target_neighbor_ids"] = _connection_neighbors_for(hit_position)
	var placement_position := _focus_position(focus.get("placement_position",[]))
	if placement_position != INVALID_CONNECTION_POSITION:
		focus["placement_neighbor_ids"] = _connection_neighbors_for(placement_position)


func _append_door_context(focus: Dictionary, selected_block_id: String) -> void:
	if world == null or not DoorPolicyScript.supports(selected_block_id):
		return
	var placement_position := _focus_position(focus.get("placement_position", []))
	if placement_position == INVALID_CONNECTION_POSITION:
		return
	focus["placement_upper_block_id"] = str(
		world.call("get_block", placement_position + Vector3i.UP)
	)
	focus["placement_support_block_id"] = str(
		world.call("get_block", placement_position + Vector3i.DOWN)
	)


func _connection_neighbors_for(block_position: Vector3i) -> Dictionary:
	return ConnectionPolicyScript.read_neighbors(world,block_position)


func _focus_position(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]),int(value[1]),int(value[2]))
	return INVALID_CONNECTION_POSITION


func _report_placement_failure(reason: String, block_id: String) -> void:
	var occupied_id := str(_last_placement_evaluation.get("occupied_block_id",""))
	var occupied_name := ""
	if not occupied_id.is_empty() and occupied_id != PrecisionBlockRegistry.AIR:
		occupied_name = str(
			PrecisionBlockRegistry.get_definition(occupied_id).get("name",occupied_id)
		)
	var detail := PlacementPreviewPolicyScript.reason_text(reason,occupied_name)
	var message := ""
	match reason:
		"no_focus":
			message = "准星没有对准方块表面；先退开一点，看到绿色预览格后再按右键"
		"player_overlap":
			message = "你离得太近了；后退一步，看到绿色预览格后再按右键"
		"occupied", "door_upper_occupied", "door_support_missing":
			message = "%s；请换一个绿色预览位置" % detail
		"no_block_selected":
			message = "先用数字键选中快捷栏里的方块"
		_:
			message = "%s；重新瞄准，看到绿色预览格后再按右键" % detail
	_report_player_action(
		&"place_failed",
		{
			"block_id":block_id,
			"reason":reason,
			"message":message,
		}
	)


func _resolve_directional_block_id(block_id: String) -> String:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	return OrientationPolicyScript.resolve_for_forward(block_id,forward)


func _player_bounds() -> AABB:
	return AABB(
		global_position+Vector3(-0.32,0.0,-0.32),
		Vector3(0.64,1.82,0.64)
	)
