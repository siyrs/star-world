class_name HusbandryPolicy
extends RefCounted

const STAGE_ADULT := "adult"
const STAGE_BABY := "baby"


func evaluate_feed(
	profile: Dictionary,
	state: Dictionary,
	selected_item_id: String,
	managed_count: int,
	maximum_managed: int
) -> Dictionary:
	if profile.is_empty():
		return {"success": false, "reason": "unsupported_species"}
	var expected_item := str(profile.get("feed_item", ""))
	if selected_item_id != expected_item:
		return {
			"success": false,
			"reason": "wrong_feed",
			"feed_item": expected_item,
		}
	var stage := str(state.get("stage", STAGE_ADULT))
	if stage == STAGE_BABY:
		var remaining := maxf(0.0, float(state.get("growth_remaining_seconds", 0.0)))
		if remaining <= 0.0:
			return {"success": false, "reason": "already_adult", "feed_item": expected_item}
		var reduction := maxf(
			1.0,
			float(profile.get("growth_seconds", remaining))
			* float(profile.get("baby_growth_reduction_ratio", 0.2))
		)
		return {
			"success": true,
			"action": &"accelerate_growth",
			"feed_item": expected_item,
			"growth_reduction_seconds": minf(remaining, reduction),
			"target_growth_remaining_seconds": maxf(0.0, remaining - reduction),
		}
	if float(state.get("breed_cooldown_seconds", 0.0)) > 0.0:
		return {
			"success": false,
			"reason": "breed_cooldown",
			"feed_item": expected_item,
			"remaining_seconds": float(state.get("breed_cooldown_seconds", 0.0)),
		}
	if float(state.get("love_remaining_seconds", 0.0)) > 0.0:
		return {
			"success": false,
			"reason": "already_ready",
			"feed_item": expected_item,
			"remaining_seconds": float(state.get("love_remaining_seconds", 0.0)),
		}
	if managed_count >= maximum_managed:
		return {
			"success": false,
			"reason": "population_cap",
			"feed_item": expected_item,
			"maximum": maximum_managed,
		}
	return {
		"success": true,
		"action": &"enter_love",
		"feed_item": expected_item,
		"love_seconds": float(profile.get("love_seconds", 30.0)),
	}


func can_pair(
	first_state: Dictionary,
	second_state: Dictionary,
	distance: float,
	pair_radius: float
) -> bool:
	return (
		str(first_state.get("species_id", "")) == str(second_state.get("species_id", ""))
		and str(first_state.get("stage", STAGE_ADULT)) == STAGE_ADULT
		and str(second_state.get("stage", STAGE_ADULT)) == STAGE_ADULT
		and float(first_state.get("love_remaining_seconds", 0.0)) > 0.0
		and float(second_state.get("love_remaining_seconds", 0.0)) > 0.0
		and float(first_state.get("breed_cooldown_seconds", 0.0)) <= 0.0
		and float(second_state.get("breed_cooldown_seconds", 0.0)) <= 0.0
		and distance <= maxf(0.1, pair_radius)
	)


func format_duration(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	if total < 60:
		return "%d 秒" % total
	return "%d 分 %02d 秒" % [total / 60, total % 60]
