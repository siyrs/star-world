class_name HostileEncounterPolicy
extends RefCounted

const MAX_ACTIVE_ENCOUNTERS := 2
const MAX_TRACKED_MEMBERS := 12
const LOW_HEALTH_SUPPRESSION_RATIO := 0.35
const FORMATION_ARC_RADIANS := 1.9


static func select_profile(
	profiles: Array[Dictionary],
	context: Dictionary,
	roll: float
) -> Dictionary:
	var eligible: Array[Dictionary] = []
	var total_weight := 0
	for profile: Dictionary in profiles:
		if not is_profile_eligible(profile, context):
			continue
		eligible.append(profile)
		total_weight += maxi(0, int(profile.get("weight", 0)))
	if eligible.is_empty() or total_weight <= 0:
		return {}
	var cursor := clampf(roll, 0.0, 0.999999) * float(total_weight)
	for profile: Dictionary in eligible:
		cursor -= float(maxi(0, int(profile.get("weight", 0))))
		if cursor < 0.0:
			return profile.duplicate(true)
	return eligible.back().duplicate(true)


static func is_profile_eligible(profile: Dictionary, context: Dictionary) -> bool:
	var map_id := str(context.get("map_id", ""))
	var phase_id := str(context.get("phase_id", "day"))
	var player_y := float(context.get("player_y", 0.0))
	var health_ratio := clampf(float(context.get("health_ratio", 1.0)), 0.0, 1.0)
	var existing_pressure := maxf(0.0, float(context.get("existing_pressure", 0.0)))
	var existing_count := maxi(0, int(context.get("existing_count", 0)))
	var hostile_cap := maxi(0, int(context.get("hostile_cap", 0)))
	var active_encounters := maxi(0, int(context.get("active_encounters", 0)))
	var tracked_members := maxi(0, int(context.get("tracked_members", 0)))
	var cooldown_remaining := maxf(0.0, float(context.get("cooldown_remaining", 0.0)))
	if active_encounters >= MAX_ACTIVE_ENCOUNTERS or cooldown_remaining > 0.0:
		return false
	if health_ratio < LOW_HEALTH_SUPPRESSION_RATIO:
		return false
	if map_id not in profile.get("map_ids", []):
		return false
	if phase_id not in profile.get("phase_ids", []):
		return false
	if player_y < float(profile.get("minimum_player_y", -INF)):
		return false
	if player_y > float(profile.get("maximum_player_y", INF)):
		return false
	if health_ratio < float(profile.get("minimum_health_ratio", 0.0)):
		return false
	if existing_pressure < float(profile.get("minimum_existing_pressure", 0.0)):
		return false
	var intensity_profile: Dictionary = context.get("intensity_profile", {})
	if existing_pressure > effective_pressure_limit(
		float(profile.get("maximum_existing_pressure", INF)), intensity_profile
	):
		return false
	var member_count := maxi(0, int(profile.get("member_count", 0)))
	if member_count <= 0 or existing_count + member_count > hostile_cap:
		return false
	if tracked_members + member_count > MAX_TRACKED_MEMBERS:
		return false
	var encounter_pressure := estimate_pressure(profile)
	return existing_pressure + encounter_pressure <= effective_pressure_limit(
		float(profile.get("maximum_total_pressure", 0.0)), intensity_profile
	) + 0.0001


static func effective_cooldown_seconds(
	profile: Dictionary, intensity_profile: Dictionary
) -> float:
	var base_seconds := maxf(0.1, float(profile.get("cooldown_seconds", 30.0)))
	var multiplier := clampf(
		float(intensity_profile.get("cooldown_multiplier", 1.0)), 0.5, 2.0
	)
	return base_seconds * multiplier


static func effective_pressure_limit(
	base_limit: float, intensity_profile: Dictionary
) -> float:
	if not is_finite(base_limit):
		return base_limit
	var multiplier := clampf(
		float(intensity_profile.get("danger_pressure_multiplier", 1.0)), 0.5, 1.5
	)
	return maxf(0.0, base_limit) * multiplier


static func expand_members(profile: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_members: Variant = profile.get("members", [])
	if raw_members is not Array:
		return result
	for raw_member: Variant in raw_members:
		if raw_member is not Dictionary:
			continue
		var species_id := str(raw_member.get("species_id", ""))
		var role := str(raw_member.get("role", "vanguard"))
		var count := clampi(int(raw_member.get("count", 0)), 0, 3)
		for _index in count:
			result.append({"species_id": species_id, "role": role})
			if result.size() >= 5:
				return result
	return result


static func formation_requests(
	profile: Dictionary,
	player_position: Vector3,
	base_angle: float
) -> Array[Dictionary]:
	var members := expand_members(profile)
	var result: Array[Dictionary] = []
	if members.is_empty():
		return result
	var minimum_radius := float(profile.get("minimum_spawn_radius", 20.0))
	var maximum_radius := float(profile.get("maximum_spawn_radius", minimum_radius))
	var denominator := maxf(1.0, float(members.size() - 1))
	for index in members.size():
		var member: Dictionary = members[index]
		var t := float(index) / denominator if members.size() > 1 else 0.5
		var angle_offset := lerpf(-FORMATION_ARC_RADIANS * 0.5, FORMATION_ARC_RADIANS * 0.5, t)
		var role := str(member.get("role", "vanguard"))
		var radius_ratio := 0.35
		if role == "support":
			radius_ratio = 1.0
		elif role == "finisher":
			radius_ratio = 0.62
		var radius := lerpf(minimum_radius, maximum_radius, radius_ratio)
		var angle := base_angle + angle_offset
		var offset := Vector3(sin(angle) * radius, 2.0, cos(angle) * radius)
		result.append({
			"species_id": str(member.get("species_id", "")),
			"role": role,
			"member_index": index,
			"requested_position": player_position + offset,
			"radius": radius,
			"angle": angle,
		})
	return result


static func estimate_pressure(profile: Dictionary) -> float:
	var species_pressure := {
		"zombie": 1.0,
		"abyss_marksman": 1.6,
		"abyss_brute": 2.0,
	}
	var total := 0.0
	for member: Dictionary in expand_members(profile):
		total += float(species_pressure.get(str(member.get("species_id", "")), 1.0))
	return total


static func rejection_reason(profiles: Array[Dictionary], context: Dictionary) -> String:
	if maxf(0.0, float(context.get("cooldown_remaining", 0.0))) > 0.0:
		return "cooldown"
	if int(context.get("active_encounters", 0)) >= MAX_ACTIVE_ENCOUNTERS:
		return "active_encounter_limit"
	if float(context.get("health_ratio", 1.0)) < LOW_HEALTH_SUPPRESSION_RATIO:
		return "low_health"
	if int(context.get("existing_count", 0)) >= int(context.get("hostile_cap", 0)):
		return "hostile_cap"
	for profile: Dictionary in profiles:
		if is_profile_eligible(profile, context):
			return "eligible"
	return "no_eligible_profile"
