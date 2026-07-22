class_name ExplorationProgressionServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const ExplorationRuntimeParticipantScript = preload(
	"res://src/exploration/exploration_runtime_participant.gd"
)
const JournalRewardParticipantScript = preload(
	"res://src/exploration/exploration_journal_reward_participant.gd"
)
const PickupStackCoordinatorScript = preload(
	"res://src/entity/pickup_stack_coordinator.gd"
)
const EXPLORATION_RUNTIME_FEATURE := &"exploration_runtime"
const JOURNAL_REWARD_FEATURE := &"exploration_journal_rewards"

var prospecting_service: Node
var exploration_danger_service: Node
var exploration_journal_service: Node
var exploration_reward_service: Node
var exploration_runtime_participant: Node
var exploration_journal_reward_participant: Node
var pickup_stack_coordinator: Node


func _ready() -> void:
	super._ready()
	pickup_stack_coordinator = _add_service(
		PickupStackCoordinatorScript.new(), "PickupStackCoordinator"
	)
	pickup_stack_coordinator.call("setup", creature_spawner, inventory)
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
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("clear", true)
	super._begin_world(state)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("activate")


func handle_world_start_failed(reason: String) -> void:
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("clear", true)
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("clear", true)
	super.return_to_menu()


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["ecology"] = (
		creature_spawner.call("get_ecology_snapshot")
		if creature_spawner != null and creature_spawner.has_method("get_ecology_snapshot")
		else {}
	)
	snapshot["pickups"] = (
		pickup_stack_coordinator.call("get_snapshot")
		if pickup_stack_coordinator != null
		and pickup_stack_coordinator.has_method("get_snapshot")
		else {}
	)
	return snapshot


func _exit_tree() -> void:
	if pickup_stack_coordinator != null and pickup_stack_coordinator.has_method("shutdown"):
		pickup_stack_coordinator.call("shutdown")
	super._exit_tree()
