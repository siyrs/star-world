class_name RanchProgressionServiceHub
extends "res://src/ui/husbandry_progression_service_hub.gd"

const FeatureCoordinatorScript = preload(
	"res://src/core/service_hub_feature_coordinator.gd"
)
const RanchRuntimeParticipantScript = preload(
	"res://src/husbandry/ranch_runtime_participant.gd"
)
const RANCH_RUNTIME_FEATURE := &"ranch_runtime"

var animal_attraction_service: Node
var animal_product_service: Node
var feature_lifecycle: Node
var ranch_runtime_participant: Node


func _ready() -> void:
	super._ready()
	feature_lifecycle = _add_service(
		FeatureCoordinatorScript.new(), "FeatureLifecycle"
	)
	feature_lifecycle.call("setup", self)
	ranch_runtime_participant = _register_feature_participant(
		RANCH_RUNTIME_FEATURE,
		RanchRuntimeParticipantScript.new(),
		"ranch runtime"
	)
	if ranch_runtime_participant != null:
		animal_attraction_service = ranch_runtime_participant.call(
			"get_attraction_service"
		) as Node
		animal_product_service = ranch_runtime_participant.call(
			"get_product_service"
		) as Node


func _begin_world(state: Dictionary) -> void:
	var migrated_state := state.duplicate(true)
	if feature_lifecycle != null and feature_lifecycle.has_method("normalize_world_state"):
		var raw_migrated: Variant = feature_lifecycle.call(
			"normalize_world_state", state
		)
		if raw_migrated is Dictionary:
			migrated_state = raw_migrated
	if feature_lifecycle != null:
		feature_lifecycle.call("begin_world", migrated_state)
	super._begin_world(migrated_state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if feature_lifecycle != null:
		feature_lifecycle.call(
			"attach_game", world, player, sun, environment, ground_resolver
		)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if feature_lifecycle != null:
		feature_lifecycle.call("activate")


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if feature_lifecycle != null:
		feature_lifecycle.call("save_into", current_state)
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	if feature_lifecycle != null:
		feature_lifecycle.call("clear", &"world_start_failed")
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty() and feature_lifecycle != null:
		feature_lifecycle.call("clear", &"return_to_menu")


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	if feature_lifecycle != null:
		feature_lifecycle.call("snapshot_into", snapshot)
		snapshot["feature_lifecycle"] = feature_lifecycle.call("get_snapshot")
	return snapshot


func _exit_tree() -> void:
	if feature_lifecycle != null and feature_lifecycle.has_method("shutdown"):
		feature_lifecycle.call("shutdown")
	super._exit_tree()


func _register_feature_participant(
	participant_id: StringName, participant: Node, label: String
) -> Node:
	if feature_lifecycle == null:
		return null
	var registration: Dictionary = feature_lifecycle.call(
		"register_participant", participant_id, participant
	)
	if bool(registration.get("success", false)):
		return registration.get("participant") as Node
	push_error(
		"Unable to install %s lifecycle participant: %s"
		% [label, str(registration.get("reason", "unknown"))]
	)
	return null
