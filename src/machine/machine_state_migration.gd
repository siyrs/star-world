class_name MachineStateMigration
extends RefCounted

const VERSION := 1
const MAX_MACHINE_COUNT := 4096
const MAX_MACHINE_ID_LENGTH := 128
const MAX_RECIPE_ID_LENGTH := 128
const MAX_SLOT_COUNT := 4096
const MAX_RUNTIME_SECONDS := 4.0 * 60.0 * 60.0


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	normalized["machines"] = normalize_machine_state(state.get("machines", {}))
	return normalized


static func normalize_machine_state(raw_state: Variant) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var result := {
		"version": VERSION,
		"saved_at_unix": now,
		"furnaces": {},
		"stonecutters": {},
	}
	if raw_state is not Dictionary:
		return result
	var state: Dictionary = raw_state
	result["saved_at_unix"] = maxi(0, int(state.get("saved_at_unix", now)))
	var raw_furnaces: Variant = state.get("furnaces", state.get("machines", {}))
	var furnaces := _normalize_domain(raw_furnaces, "furnace", MAX_MACHINE_COUNT)
	result["furnaces"] = furnaces
	var remaining_capacity := maxi(0, MAX_MACHINE_COUNT - furnaces.size())
	result["stonecutters"] = _normalize_domain(
		state.get("stonecutters", {}),
		"stonecutter",
		remaining_capacity
	)
	return result


static func _normalize_domain(
	raw_domain: Variant,
	machine_type: String,
	capacity: int
) -> Dictionary:
	var result: Dictionary = {}
	if raw_domain is not Dictionary or capacity <= 0:
		return result
	var ids: Array[String] = []
	for raw_id: Variant in raw_domain.keys():
		var machine_id := str(raw_id).strip_edges()
		if _is_valid_machine_id(machine_id):
			ids.append(machine_id)
	ids.sort()
	for machine_id: String in ids:
		if result.size() >= capacity:
			break
		var raw_machine: Variant = raw_domain.get(machine_id, {})
		if raw_machine is not Dictionary:
			continue
		match machine_type:
			"furnace":
				result[machine_id] = _normalize_furnace_state(raw_machine)
			"stonecutter":
				result[machine_id] = _normalize_stonecutter_state(raw_machine)
	return result


static func _normalize_furnace_state(raw_state: Dictionary) -> Dictionary:
	var recipe_id := _normalize_recipe_id(raw_state.get("active_recipe_id", ""))
	var burn_remaining := _bounded_seconds(raw_state.get("burn_remaining_seconds", 0.0))
	return {
		"type": "furnace",
		"input": _normalize_slot(raw_state.get("input", {})),
		"fuel": _normalize_slot(raw_state.get("fuel", {})),
		"output": _normalize_slot(raw_state.get("output", {})),
		"active_recipe_id": recipe_id,
		"progress_seconds": _bounded_seconds(raw_state.get("progress_seconds", 0.0)),
		"burn_remaining_seconds": burn_remaining,
		"burn_total_seconds": maxf(
			burn_remaining,
			_bounded_seconds(raw_state.get("burn_total_seconds", burn_remaining))
		),
	}


static func _normalize_stonecutter_state(raw_state: Dictionary) -> Dictionary:
	return {
		"type": "stonecutter",
		"input": _normalize_slot(raw_state.get("input", {})),
		"output": _normalize_slot(raw_state.get("output", {})),
		"active_recipe_id": _normalize_recipe_id(
			raw_state.get("active_recipe_id", "")
		),
		"progress_seconds": _bounded_seconds(
			raw_state.get("progress_seconds", 0.0)
		),
	}


static func _normalize_recipe_id(raw_value: Variant) -> String:
	var recipe_id := str(raw_value).strip_edges()
	if (
		recipe_id.length() > MAX_RECIPE_ID_LENGTH
		or "\n" in recipe_id
		or "\r" in recipe_id
	):
		return ""
	return recipe_id


static func _normalize_slot(raw_slot: Variant) -> Dictionary:
	if raw_slot is not Dictionary:
		return {}
	var item_id := str(raw_slot.get("item_id", "")).strip_edges()
	var count := clampi(int(raw_slot.get("count", 0)), 0, MAX_SLOT_COUNT)
	if item_id.is_empty() or count <= 0 or item_id.length() > MAX_MACHINE_ID_LENGTH:
		return {}
	if "\n" in item_id or "\r" in item_id:
		return {}
	var metadata: Dictionary = {}
	var raw_metadata: Variant = raw_slot.get("metadata", {})
	if raw_metadata is Dictionary:
		metadata = raw_metadata.duplicate(true)
	return {
		"item_id": item_id,
		"count": count,
		"metadata": metadata,
	}


static func _bounded_seconds(raw_value: Variant) -> float:
	var value := float(raw_value)
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, MAX_RUNTIME_SECONDS)


static func _is_valid_machine_id(machine_id: String) -> bool:
	return (
		not machine_id.is_empty()
		and machine_id.length() <= MAX_MACHINE_ID_LENGTH
		and "\n" not in machine_id
		and "\r" not in machine_id
	)
