class_name PickupAwareExplorationRuntimeParticipant
extends "res://src/exploration/exploration_runtime_participant.gd"

const PickupStackCoordinatorScript = preload(
	"res://src/entity/bounded_pickup_stack_coordinator.gd"
)

var pickup_stack_coordinator: Node


func install(p_hub: Node) -> bool:
	if not super.install(p_hub):
		return false
	pickup_stack_coordinator = hub.call(
		"_add_service", PickupStackCoordinatorScript.new(), "PickupStackCoordinator"
	) as Node
	if (
		pickup_stack_coordinator == null
		or not pickup_stack_coordinator.has_method("setup")
		or not bool(
			pickup_stack_coordinator.call(
				"setup", hub.get("creature_spawner") as Node3D, hub.get("inventory")
			)
		)
	):
		if pickup_stack_coordinator != null:
			_dispose_service(pickup_stack_coordinator)
		pickup_stack_coordinator = null
		return false
	hub.set("pickup_stack_coordinator", pickup_stack_coordinator)
	return true


func begin_world(state: Dictionary) -> void:
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("clear", true)
	super.begin_world(state)


func activate() -> void:
	super.activate()
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("activate")


func snapshot_into(snapshot: Dictionary) -> void:
	super.snapshot_into(snapshot)
	snapshot["pickups"] = (
		pickup_stack_coordinator.call("get_snapshot")
		if pickup_stack_coordinator != null
		and pickup_stack_coordinator.has_method("get_snapshot")
		else {}
	)


func clear(reason: StringName = &"clear") -> void:
	if pickup_stack_coordinator != null:
		pickup_stack_coordinator.call("clear", true)
	super.clear(reason)


func shutdown() -> void:
	if _shutdown:
		return
	if pickup_stack_coordinator != null and pickup_stack_coordinator.has_method("shutdown"):
		pickup_stack_coordinator.call("shutdown")
	super.shutdown()


func get_pickup_coordinator() -> Node:
	return pickup_stack_coordinator


func get_lifecycle_snapshot() -> Dictionary:
	var result: Dictionary = super.get_lifecycle_snapshot()
	result["pickup_runtime"] = (
		pickup_stack_coordinator.call("get_snapshot")
		if pickup_stack_coordinator != null
		and pickup_stack_coordinator.has_method("get_snapshot")
		else {}
	)
	return result
