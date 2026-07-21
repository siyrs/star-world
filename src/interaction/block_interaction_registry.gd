class_name BlockInteractionRegistry
extends RefCounted

const ACTION_CRAFTING: StringName = &"crafting"
const ACTION_CONTAINER: StringName = &"container"
const ACTION_MACHINE: StringName = &"machine"

const INTERACTIONS := {
	"crafting_table":
	{
		"action": ACTION_CRAFTING,
		"station": "workbench",
		"label": "工作台",
	},
	"furnace":
	{
		"action": ACTION_MACHINE,
		"machine_type": "furnace",
		"label": "熔炉",
	},
	"stonecutter":
	{
		"action": ACTION_MACHINE,
		"machine_type": "stonecutter",
		"label": "石材切割机",
	},
	"chest":
	{
		"action": ACTION_CONTAINER,
		"container_type": "chest",
		"label": "箱子",
		"slot_count": 27,
	},
}


static func has_interaction(block_id: String) -> bool:
	return INTERACTIONS.has(block_id)


static func get_interaction(block_id: String) -> Dictionary:
	return INTERACTIONS.get(block_id, {}).duplicate(true)


static func is_container(block_id: String) -> bool:
	return str(get_interaction(block_id).get("action", "")) == ACTION_CONTAINER


static func is_machine(block_id: String) -> bool:
	return str(get_interaction(block_id).get("action", "")) == ACTION_MACHINE


static func get_machine_block_id(machine_type: StringName) -> String:
	var normalized_type := str(machine_type).strip_edges()
	if normalized_type.is_empty():
		return ""
	for raw_block_id: Variant in INTERACTIONS.keys():
		var block_id := str(raw_block_id)
		var definition: Dictionary = INTERACTIONS.get(block_id, {})
		if (
			str(definition.get("action", "")) == str(ACTION_MACHINE)
			and str(definition.get("machine_type", "")) == normalized_type
		):
			return block_id
	return ""
