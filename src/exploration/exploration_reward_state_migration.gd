class_name ExplorationRewardStateMigration
extends RefCounted

const VERSION := 1
const MAX_CLAIMED_IDS := 64
const MAX_ID_LENGTH := 80


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	normalized["exploration_rewards"] = normalize_reward_state(
		state.get("exploration_rewards", {})
	)
	return normalized


static func normalize_reward_state(raw_state: Variant) -> Dictionary:
	var claimed: Array[String] = []
	if raw_state is Dictionary:
		var raw_claimed: Variant = raw_state.get("claimed", [])
		if raw_claimed is Array:
			for raw_id: Variant in raw_claimed:
				var milestone_id := str(raw_id).strip_edges().substr(0, MAX_ID_LENGTH)
				if milestone_id.is_empty() or milestone_id in claimed:
					continue
				claimed.append(milestone_id)
				if claimed.size() >= MAX_CLAIMED_IDS:
					break
	return {
		"version": VERSION,
		"claimed": claimed,
	}
