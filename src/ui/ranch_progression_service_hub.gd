class_name RanchProgressionServiceHub
extends "res://src/ui/husbandry_progression_service_hub.gd"

const RanchRuntimeParticipantScript = preload(
	"res://src/husbandry/ranch_runtime_participant.gd"
)
const RANCH_RUNTIME_FEATURE := &"ranch_runtime"

var animal_attraction_service: Node
var animal_product_service: Node
var ranch_runtime_participant: Node


func _ready() -> void:
	super._ready()
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
