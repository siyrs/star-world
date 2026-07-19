class_name CreatureEcologyPolicy
extends RefCounted


static func hostile_cap(profile: Dictionary, phase: String) -> int:
	return maxi(
		0,
		int(
			profile.get(
				"hostile_cap_night" if phase in ["dusk", "night"] else "hostile_cap_day",
				0
			)
		)
	)


static func hostile_chance(profile: Dictionary, phase: String) -> float:
	var raw_chances: Variant = profile.get("hostile_chance", {})
	if raw_chances is not Dictionary:
		return 0.0
	return clampf(float(raw_chances.get(phase, 0.0)), 0.0, 1.0)


static func choose_species(
	profile: Dictionary,
	phase: String,
	passive_count: int,
	hostile_count: int,
	category_roll: float,
	species_roll: float,
	context: Dictionary = {}
) -> String:
	var passive_cap := maxi(0, int(profile.get("passive_cap", 0)))
	var current_hostile_cap := hostile_cap(profile, phase)
	var can_passive := passive_count < passive_cap
	var can_hostile := hostile_count < current_hostile_cap
	if not can_passive and not can_hostile:
		return ""
	var choose_hostile := false
	if can_hostile and not can_passive:
		choose_hostile = true
	elif can_hostile and can_passive:
		choose_hostile = clampf(category_roll, 0.0, 1.0) < hostile_chance(profile, phase)
	var raw_entries: Variant = profile.get(
		"hostile_species" if choose_hostile else "passive_species", []
	)
	if raw_entries is not Array:
		return ""
	return weighted_species(raw_entries, species_roll, phase, context)


static func weighted_species(
	entries: Array, roll: float, phase: String = "", context: Dictionary = {}
) -> String:
	var eligible: Array[Dictionary] = []
	var total_weight := 0
	for raw_entry: Variant in entries:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if not is_entry_eligible(entry, phase, context):
			continue
		var weight := maxi(0, int(entry.get("weight", 0)))
		if weight <= 0:
			continue
		eligible.append(entry)
		total_weight += weight
	if total_weight <= 0:
		return ""
	var target := clampf(roll, 0.0, 0.999999) * float(total_weight)
	var cursor := 0.0
	for entry: Dictionary in eligible:
		cursor += float(maxi(0, int(entry.get("weight", 0))))
		if target < cursor:
			return str(entry.get("id", ""))
	return str(eligible.back().get("id", "")) if not eligible.is_empty() else ""


static func is_entry_eligible(entry: Dictionary, phase: String, context: Dictionary = {}) -> bool:
	var species_id := str(entry.get("id", ""))
	if species_id.is_empty():
		return false
	var cap := maxi(0, int(entry.get("cap", 0)))
	var raw_counts: Variant = context.get("species_counts", {})
	if cap > 0 and raw_counts is Dictionary and int(raw_counts.get(species_id, 0)) >= cap:
		return false
	var conditions: Array[bool] = []
	var raw_phase_ids: Variant = entry.get("phase_ids", [])
	if raw_phase_ids is Array and not raw_phase_ids.is_empty():
		conditions.append(phase in raw_phase_ids)
	var player_y := float(context.get("player_y", 32.0))
	if entry.has("min_player_y"):
		conditions.append(player_y >= float(entry.get("min_player_y", -64)))
	if entry.has("max_player_y"):
		conditions.append(player_y <= float(entry.get("max_player_y", 128)))
	if conditions.is_empty():
		return true
	var condition_mode := str(entry.get("condition_mode", "all"))
	if condition_mode == "any":
		for condition: bool in conditions:
			if condition:
				return true
		return false
	for condition: bool in conditions:
		if not condition:
			return false
	return true


static func snapshot(
	profile: Dictionary,
	phase: String,
	passive_count: int,
	hostile_count: int,
	context: Dictionary = {}
) -> Dictionary:
	var raw_counts: Variant = context.get("species_counts", {})
	var species_counts: Dictionary = (
		raw_counts.duplicate(true) if raw_counts is Dictionary else {}
	)
	return {
		"profile_id": str(profile.get("id", "star_continent")),
		"profile_name": str(profile.get("name", "生态")),
		"phase": phase,
		"danger_base": clampi(int(profile.get("danger_base", 0)), 0, 60),
		"spawn_interval_seconds": clampf(
			float(profile.get("spawn_interval_seconds", 8.0)), 1.0, 30.0
		),
		"passive_count": maxi(0, passive_count),
		"passive_cap": maxi(0, int(profile.get("passive_cap", 0))),
		"hostile_count": maxi(0, hostile_count),
		"hostile_cap": hostile_cap(profile, phase),
		"hostile_chance": hostile_chance(profile, phase),
		"elite_count": maxi(0, int(context.get("elite_count", 0))),
		"species_counts": species_counts,
	}
