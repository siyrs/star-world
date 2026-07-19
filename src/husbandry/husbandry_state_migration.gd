class_name HusbandryStateMigration
extends RefCounted

const RegistryScript = preload("res://src/husbandry/husbandry_registry.gd")
const VERSION := 1
const MAX_ID_LENGTH := 128
const MAX_TIMER_SECONDS := 86400.0
const MAX_HEALTH := 10000.0


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	normalized["husbandry"] = normalize_husbandry_state(state.get("husbandry", {}))
	return normalized


static func normalize_husbandry_state(raw_state: Variant) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var result := {
		"version": VERSION,
		"saved_at_unix": now,
		"animals": {},
	}
	if raw_state is not Dictionary:
		return result
	var state: Dictionary = raw_state
	result["saved_at_unix"] = maxi(0, int(state.get("saved_at_unix", now)))
	var raw_animals: Variant = state.get("animals", {})
	if raw_animals is not Dictionary:
		return result
	var registry = RegistryScript.new()
	if not registry.ensure_loaded():
		return result
	var normalized_animals: Dictionary = {}
	var ids: Array[String] = []
	for raw_id: Variant in raw_animals.keys():
		var husbandry_id := str(raw_id).strip_edges()
		if not husbandry_id.is_empty():
			ids.append(husbandry_id)
	ids.sort()
	for husbandry_id: String in ids:
		if husbandry_id.length() > MAX_ID_LENGTH:
			continue
		var raw_record: Variant = raw_animals.get(husbandry_id, {})
		if raw_record is not Dictionary:
			continue
		var record := _normalize_record(husbandry_id, raw_record, registry)
		if not record.is_empty():
			normalized_animals[husbandry_id] = record
	result["animals"] = normalized_animals
	return result


static func _normalize_record(
	husbandry_id: String, raw_record: Dictionary, registry: RefCounted
) -> Dictionary:
	var species_id := str(raw_record.get("species_id", "")).strip_edges()
	if species_id.is_empty() or not bool(registry.call("supports_species", species_id)):
		return {}
	var position := _normalize_position(raw_record.get("position", []))
	if position.is_empty():
		return {}
	var stage := str(raw_record.get("stage", "adult"))
	if stage not in ["adult", "baby"]:
		stage = "adult"
	var growth_remaining := _bounded_timer(raw_record.get("growth_remaining_seconds", 0.0))
	if stage == "adult":
		growth_remaining = 0.0
	return {
		"species_id": species_id,
		"position": position,
		"stage": stage,
		"growth_remaining_seconds": growth_remaining,
		"breed_cooldown_seconds": _bounded_timer(
			raw_record.get("breed_cooldown_seconds", 0.0)
		),
		"love_remaining_seconds": _bounded_timer(
			raw_record.get("love_remaining_seconds", 0.0)
		),
		"health": clampf(float(raw_record.get("health", 1.0)), 0.1, MAX_HEALTH),
	}


static func _normalize_position(raw_value: Variant) -> Array:
	if raw_value is not Array or raw_value.size() < 3:
		return []
	var position := Vector3(
		float(raw_value[0]), float(raw_value[1]), float(raw_value[2])
	)
	if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
		return []
	return [position.x, position.y, position.z]


static func _bounded_timer(raw_value: Variant) -> float:
	var value := float(raw_value)
	return clampf(value if is_finite(value) else 0.0, 0.0, MAX_TIMER_SECONDS)
