class_name EncounterAwareCreatureSpawner
extends "res://src/entity/creature_spawner.gd"

const MAX_ENCOUNTER_METADATA_KEYS := 8


func get_hostile_population_snapshot() -> Dictionary:
	var phase := _current_phase()
	var cap := EcologyPolicyScript.hostile_cap(_ecology_profile, phase)
	return {
		"count": _count_group(&"hostile"),
		"cap": cap,
		"pressure": get_nearby_hostile_pressure(
			player.global_position if player != null and is_instance_valid(player) else global_position,
			despawn_radius
		),
		"species_counts": _species_counts(),
		"phase_id": phase,
		"map_id": map_id,
	}


func resolve_spawn_candidate(candidate: Vector3) -> Vector3:
	var resolved := candidate
	if ground_resolver.is_valid():
		var raw_result: Variant = ground_resolver.call(candidate)
		if raw_result is Vector3:
			resolved = raw_result
		elif raw_result is float or raw_result is int:
			resolved.y = float(raw_result) + 1.0
	return resolved


func spawn_encounter_member(
	species_id: String,
	spawn_position: Vector3,
	encounter_id: String,
	role: String,
	shared_target: Node3D,
	member_index: int
):
	if encounter_id.is_empty() or role not in ["vanguard", "support", "finisher"]:
		return null
	var population := get_hostile_population_snapshot()
	if int(population.get("count", 0)) >= int(population.get("cap", 0)):
		return null
	var species_cap := _encounter_species_cap(species_id)
	if species_cap >= 0 and get_species_count(species_id) >= species_cap:
		return null
	var creature = spawn_creature(species_id, spawn_position)
	if creature == null or creature is not Node3D:
		return null
	creature.add_to_group("encounter_hostile")
	creature.set_meta("encounter_id", encounter_id)
	creature.set_meta("encounter_role", role)
	creature.set_meta("encounter_member_index", clampi(member_index, 0, 7))
	creature.set_meta("encounter_spawned", true)
	if shared_target != null and is_instance_valid(shared_target):
		creature.set("target", shared_target)
	return creature


func remove_creature(creature: Node, emit_event: bool = true) -> bool:
	if creature == null or not is_instance_valid(creature) or creature.get_parent() != self:
		return false
	_dispose_child(creature, emit_event)
	return true


func get_encounter_member_snapshot(creature: Node) -> Dictionary:
	if creature == null or not is_instance_valid(creature):
		return {}
	var metadata: Dictionary = {}
	for key: String in [
		"encounter_id", "encounter_role", "encounter_member_index", "encounter_spawned"
	]:
		if creature.has_meta(key):
			metadata[key] = creature.get_meta(key)
		if metadata.size() >= MAX_ENCOUNTER_METADATA_KEYS:
			break
	metadata["species_id"] = str(_property_value(creature, "species_id", ""))
	metadata["target_id"] = (
		int(creature.get("target").get_instance_id())
		if creature.get("target") is Node and is_instance_valid(creature.get("target"))
		else 0
	)
	metadata["instance_id"] = int(creature.get_instance_id())
	return metadata


func _encounter_species_cap(species_id: String) -> int:
	var raw_species: Variant = _ecology_profile.get("hostile_species", [])
	if raw_species is not Array:
		return -1
	for raw_entry: Variant in raw_species:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if str(entry.get("id", "")) != species_id:
			continue
		return int(entry.get("cap", -1))
	return -1
