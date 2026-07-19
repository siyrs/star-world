class_name ExplorationProgressionServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const FeatureCoordinatorScript = preload(
	"res://src/core/service_hub_feature_coordinator.gd"
)
const ExplorationRuntimeParticipantScript = preload(
	"res://src/exploration/exploration_runtime_participant.gd"
)
const JournalRewardParticipantScript = preload(
	"res://src/exploration/exploration_journal_reward_participant.gd"
)
const EXPLORATION_RUNTIME_FEATURE := &"exploration_runtime"
const JOURNAL_REWARD_FEATURE := &"exploration_journal_rewards"

var prospecting_service: Node
var exploration_danger_service: Node
var exploration_journal_service: Node
var exploration_reward_service: Node
var feature_lifecycle: Node
var exploration_runtime_participant: Node
var exploration_journal_reward_participant: Node


func _ready() -> void:
	super._ready()
	feature_lifecycle = _add_service(
		FeatureCoordinatorScript.new(), "FeatureLifecycle"
	)
	feature_lifecycle.call("setup", self)
	exploration_runtime_participant = _register_feature_participant(
		EXPLORATION_RUNTIME_FEATURE,
		ExplorationRuntimeParticipantScript.new(),
		"exploration runtime"
	)
	if exploration_runtime_participant != null:
		prospecting_service = exploration_runtime_participant.call(
			"get_prospecting_service"
		) as Node
		exploration_danger_service = exploration_runtime_participant.call(
			"get_danger_service"
		) as Node
		exploration_journal_reward_participant = _register_feature_participant(
			JOURNAL_REWARD_FEATURE,
			JournalRewardParticipantScript.new(),
			"exploration journal/reward"
		)
	if exploration_journal_reward_participant != null:
		exploration_journal_service = exploration_journal_reward_participant.call(
			"get_journal_service"
		) as Node
		exploration_reward_service = exploration_journal_reward_participant.call(
			"get_reward_service"
		) as Node


func _begin_world(state: Dictionary) -> void:
	var migrated_state := state.duplicate(true)
	if (
		exploration_runtime_participant != null
		and exploration_runtime_participant.has_method("normalize_world_state")
	):
		var raw_migrated: Variant = exploration_runtime_participant.call(
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
	snapshot["ecology"] = (
		creature_spawner.call("get_ecology_snapshot")
		if creature_spawner != null and creature_spawner.has_method("get_ecology_snapshot")
		else {}
	)
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
