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
	species_roll: float
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
	return weighted_species(raw_entries, species_roll)


static func weighted_species(entries: Array, roll: float) -> String:
	var total_weight := 0
	for raw_entry in entries:
		if raw_entry is Dictionary:
			total_weight += maxi(0, int(raw_entry.get("weight", 0)))
	if total_weight <= 0:
		return ""
	var target := clampf(roll, 0.0, 0.999999) * float(total_weight)
	var cursor := 0.0
	for raw_entry in entries:
		if raw_entry is not Dictionary:
			continue
		cursor += float(maxi(0, int(raw_entry.get("weight", 0))))
		if target < cursor:
			return str(raw_entry.get("id", ""))
	return str((entries.back() as Dictionary).get("id", "")) if entries.back() is Dictionary else ""


static func snapshot(
	profile: Dictionary, phase: String, passive_count: int, hostile_count: int
) -> Dictionary:
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
	}
