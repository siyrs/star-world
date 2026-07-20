class_name HusbandryProgressionServiceHub
extends "res://src/ui/repair_progression_service_hub.gd"

const HusbandryRuntimeParticipantScript = preload(
	"res://src/husbandry/husbandry_runtime_participant.gd"
)
const HUSBANDRY_RUNTIME_FEATURE := &"husbandry_runtime"

var husbandry_service: Node
var husbandry_interaction: Node
var husbandry_runtime_participant: Node


func _ready() -> void:
	super._ready()
	husbandry_runtime_participant = _register_feature_participant(
		HUSBANDRY_RUNTIME_FEATURE,
		HusbandryRuntimeParticipantScript.new(),
		"husbandry runtime"
	)
	if husbandry_runtime_participant != null:
		husbandry_service = husbandry_runtime_participant.call(
			"get_husbandry_service"
		) as Node
		husbandry_interaction = husbandry_runtime_participant.call(
			"get_interaction_service"
		) as Node
