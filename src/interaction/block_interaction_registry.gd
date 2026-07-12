class_name BlockInteractionRegistry
extends RefCounted

const ACTION_CRAFTING: StringName = &"crafting"
const ACTION_CONTAINER: StringName = &"container"

const INTERACTIONS := {
	"crafting_table":
	{
		"action": ACTION_CRAFTING,
		"station": "workbench",
		"label": "工作台",
	},
	"furnace":
	{
		"action": ACTION_CRAFTING,
		"station": "furnace",
		"label": "熔炉",
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
