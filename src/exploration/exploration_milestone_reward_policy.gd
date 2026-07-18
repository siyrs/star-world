class_name ExplorationMilestoneRewardPolicy
extends RefCounted


static func build_snapshot(
	journal_snapshot: Dictionary,
	reward_registry: Variant,
	claimed_ids: Array[String],
	profile_id: String
) -> Dictionary:
	var claimed_set: Dictionary = {}
	for milestone_id: String in claimed_ids:
		claimed_set[milestone_id] = true
	var reward_entries: Array[Dictionary] = []
	var claimable_count := 0
	var claimed_count := 0
	var locked_count := 0
	var raw_milestones: Variant = journal_snapshot.get("milestones", [])
	if raw_milestones is Array:
		for raw_milestone: Variant in raw_milestones:
			if raw_milestone is not Dictionary:
				continue
			var milestone: Dictionary = raw_milestone
			var milestone_id := str(milestone.get("id", ""))
			if milestone_id.is_empty() or reward_registry == null or not reward_registry.has_method("get_reward"):
				continue
			var raw_reward: Variant = reward_registry.call("get_reward", milestone_id, profile_id)
			if raw_reward is not Dictionary or raw_reward.is_empty():
				continue
			var reward: Dictionary = raw_reward
			var completed := bool(milestone.get("completed", false))
			var claimed := claimed_set.has(milestone_id)
			var status := "locked"
			if claimed:
				status = "claimed"
				claimed_count += 1
			elif completed:
				status = "claimable"
				claimable_count += 1
			else:
				locked_count += 1
			var entry := milestone.duplicate(true)
			entry["milestone_id"] = milestone_id
			entry["status"] = status
			entry["claimed"] = claimed
			entry["claimable"] = status == "claimable"
			entry["reward_description"] = str(reward.get("description", ""))
			entry["reward_label"] = str(reward.get("reward_label", ""))
			entry["reward_items"] = reward.get("items", []).duplicate(true)
			entry["has_profile_bonus"] = bool(reward.get("has_profile_bonus", false))
			reward_entries.append(entry)
	return {
		"version": 1,
		"profile_id": profile_id,
		"reward_count": reward_entries.size(),
		"claimable_count": claimable_count,
		"claimed_count": claimed_count,
		"locked_count": locked_count,
		"rewards": reward_entries,
	}


static func find_reward(snapshot: Dictionary, milestone_id: String) -> Dictionary:
	var raw_rewards: Variant = snapshot.get("rewards", [])
	if raw_rewards is not Array:
		return {}
	for raw_reward: Variant in raw_rewards:
		if raw_reward is Dictionary and str(raw_reward.get("milestone_id", "")) == milestone_id:
			return raw_reward.duplicate(true)
	return {}
