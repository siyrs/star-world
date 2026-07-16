class_name AnimalAttractionPolicy
extends RefCounted


func evaluate(
	profile: Dictionary,
	feed_item_id: String,
	selected_item_id: String,
	distance_to_player: float
) -> Dictionary:
	if profile.is_empty():
		return _reject("profile_missing")
	if feed_item_id.is_empty():
		return _reject("feed_missing")
	if selected_item_id != feed_item_id:
		return _reject("wrong_feed")
	if not is_finite(distance_to_player) or distance_to_player < 0.0:
		return _reject("distance_invalid")
	var follow_radius := maxf(1.0, float(profile.get("follow_radius", 8.0)))
	var stop_distance := clampf(
		float(profile.get("stop_distance", 2.0)), 0.25, follow_radius
	)
	if distance_to_player > follow_radius:
		return {
			"should_follow": false,
			"reason": "out_of_range",
			"follow_radius": follow_radius,
			"stop_distance": stop_distance,
		}
	return {
		"should_follow": true,
		"reason": "follow",
		"follow_radius": follow_radius,
		"stop_distance": stop_distance,
		"hold_position": distance_to_player <= stop_distance,
	}


func _reject(reason: String) -> Dictionary:
	return {
		"should_follow": false,
		"reason": reason,
		"follow_radius": 0.0,
		"stop_distance": 0.0,
		"hold_position": false,
	}
