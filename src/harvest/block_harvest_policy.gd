class_name BlockHarvestPolicy
extends RefCounted

const MIN_BREAK_SECONDS := 0.08
const MAX_BREAK_SECONDS := 12.0
const HARDNESS_TO_SECONDS := 1.15


func evaluate(block_profile: Dictionary, tool_profile: Dictionary) -> Dictionary:
	if block_profile.is_empty():
		return {"breakable": false, "reason": "unknown_block"}
	var breakable := bool(block_profile.get("breakable", false))
	var required_tool := str(block_profile.get("required_tool", ""))
	var preferred_tool := str(block_profile.get("preferred_tool", required_tool))
	var minimum_power := maxi(0, int(block_profile.get("minimum_power", 0)))
	var tool_type := str(tool_profile.get("tool_type", "hand"))
	var tool_power := maxi(0, int(tool_profile.get("power", 0)))
	var matches_required := required_tool.is_empty() or tool_type == required_tool
	var power_sufficient := tool_power >= minimum_power
	var matches_preferred := preferred_tool.is_empty() or tool_type == preferred_tool
	var collectible := bool(block_profile.get("collectible", false))
	var drop_item := str(block_profile.get("drop_item", ""))
	var drop_requires_tool := bool(block_profile.get("drop_requires_tool", false))
	var can_drop := (
		breakable
		and collectible
		and not drop_item.is_empty()
		and (
			not drop_requires_tool
			or (matches_required and power_sufficient)
		)
	)
	var effective_speed := 1.0
	if not preferred_tool.is_empty():
		if matches_preferred:
			effective_speed = maxf(0.1, float(tool_profile.get("mining_speed", 1.0)))
		else:
			effective_speed = float(block_profile.get("wrong_tool_speed_multiplier", 0.4))
	if not required_tool.is_empty() and matches_required and not power_sufficient:
		effective_speed *= 0.65
	var hardness := maxf(0.0, float(block_profile.get("hardness", 0.0)))
	var duration := clampf(
		hardness * HARDNESS_TO_SECONDS / maxf(0.05, effective_speed),
		MIN_BREAK_SECONDS,
		MAX_BREAK_SECONDS
	)
	var reason := "ok"
	if not breakable:
		reason = "unbreakable"
	elif drop_requires_tool and not matches_required:
		reason = "wrong_tool"
	elif drop_requires_tool and not power_sufficient:
		reason = "insufficient_power"
	return {
		"breakable": breakable,
		"can_drop": can_drop,
		"duration_seconds": duration,
		"effective_speed": effective_speed,
		"required_tool": required_tool,
		"preferred_tool": preferred_tool,
		"minimum_power": minimum_power,
		"matches_required": matches_required,
		"matches_preferred": matches_preferred,
		"power_sufficient": power_sufficient,
		"drop_item": drop_item,
		"drop_count": maxi(0, int(block_profile.get("drop_count", 1))),
		"durability_cost": 1 if bool(tool_profile.get("is_durable", false)) else 0,
		"reason": reason,
	}


static func tool_type_label(tool_type: String) -> String:
	return {
		"pickaxe": "镐",
		"axe": "斧",
		"sword": "剑",
		"hand": "空手",
	}.get(tool_type, tool_type)


static func power_label(power: int) -> String:
	return {
		0: "空手",
		1: "木制",
		2: "石制",
		3: "铁制",
		4: "钻石",
	}.get(power, "等级 %d" % power)
