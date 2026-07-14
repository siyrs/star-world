class_name PrecisionInteractionPlayer
extends "res://src/player/husbandry_player.gd"

const PrecisionBlockRegistry = preload("res://src/block/block_registry.gd")
const VoxelTargetResolverScript = preload("res://src/interaction/voxel_target_resolver.gd")
const PlacementPreviewPolicyScript = preload(
	"res://src/interaction/placement_preview_policy.gd"
)

var _precision_target_resolver = VoxelTargetResolverScript.new()
var _placement_preview_policy = PlacementPreviewPolicyScript.new()

@onready var interaction_preview: Node = get_node_or_null("InteractionPreview")


func _ready() -> void:
	super._ready()
	if interaction_preview != null:
		interaction_preview.call("setup", self)
		interaction_preview.call("set_active", input_enabled)


func set_input_enabled(enabled: bool) -> void:
	super.set_input_enabled(enabled)
	if is_instance_valid(interaction_preview):
		interaction_preview.call("set_active", enabled)


func get_placement_preview_state() -> Dictionary:
	var raw_preview: Variant = _interaction_focus.get("placement_preview", {})
	return raw_preview.duplicate(true) if raw_preview is Dictionary else {}


func get_interaction_preview() -> Node:
	return interaction_preview


func _update_interaction_focus(force: bool = false) -> void:
	var next_focus: Dictionary = _focus_resolver.resolve(interaction_ray, world)
	if str(next_focus.get("type", "")) == "block":
		next_focus["placement_preview"] = _placement_preview_policy.evaluate(
			next_focus,
			get_selected_block_id(),
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
	return {"position":block_position, "block_id":block_id}


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
	var interacted := bool(interaction_service.call("interact", world, block_position, block_id))
	if interacted:
		_report_player_action(
			&"interact",
			{
				"block_id":block_id,
				"display_name":str(
					PrecisionBlockRegistry.get_definition(block_id).get("name", block_id)
				),
				"position":[block_position.x, block_position.y, block_position.z],
			}
		)
	return interacted


func _resolve_placement_target() -> Dictionary:
	if world == null:
		return {}
	var target: Dictionary = _precision_target_resolver.resolve(interaction_ray, world)
	if str(target.get("type", "")) != "block":
		return {}
	var hit_position: Vector3i = target.get("hit_position", Vector3i.ZERO)
	var placement_position: Vector3i = target.get("placement_position", Vector3i.ZERO)
	var previous_block := str(target.get("placement_block_id", PrecisionBlockRegistry.AIR))
	var preview_focus := {
		"type":"block",
		"hit_position":[hit_position.x, hit_position.y, hit_position.z],
		"placement_position":[
			placement_position.x, placement_position.y, placement_position.z
		],
		"placement_target_block_id":previous_block,
	}
	var evaluation: Dictionary = _placement_preview_policy.evaluate(
		preview_focus,
		get_selected_block_id(),
		_player_bounds()
	)
	if not bool(evaluation.get("valid", false)):
		return {}
	var face_normal: Vector3 = target.get("collision_normal", Vector3.ZERO)
	return {
		"position":placement_position,
		"previous_block":previous_block,
		"hit_position":hit_position,
		"face_normal":face_normal,
	}


func _player_bounds() -> AABB:
	return AABB(
		global_position + Vector3(-0.32, 0.0, -0.32),
		Vector3(0.64, 1.82, 0.64)
	)
