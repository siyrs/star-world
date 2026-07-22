class_name ScalableMachineServiceHub
extends "res://src/ui/exploration_progression_service_hub.gd"

const ScalableFurnaceScript = preload(
	"res://src/machine/scalable_furnace_service.gd"
)
const ScalableStonecutterScript = preload(
	"res://src/machine/scalable_stonecutter_service.gd"
)
const ScalableAutomationScript = preload(
	"res://src/machine/scalable_machine_automation_service.gd"
)
const ScalableParticipantScript = preload(
	"res://src/machine/scalable_machine_runtime_participant.gd"
)


func _add_service(service: Node, service_name: String) -> Node:
	match service_name:
		"FurnaceService":
			_dispose_unparented(service)
			service = ScalableFurnaceScript.new()
		"StonecutterService":
			_dispose_unparented(service)
			service = ScalableStonecutterScript.new()
		"MachineAutomationService":
			_dispose_unparented(service)
			service = ScalableAutomationScript.new()
	return super._add_service(service, service_name)


func _register_feature_participant(
	participant_id: StringName, participant: Node, label: String
) -> Node:
	if participant_id == &"machine_runtime":
		_dispose_unparented(participant)
		participant = ScalableParticipantScript.new()
	return super._register_feature_participant(participant_id, participant, label)


func _dispose_unparented(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() == null:
		node.free()
	else:
		node.queue_free()
