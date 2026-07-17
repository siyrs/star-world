class_name ResourceDistributionPolicy
extends RefCounted

const ROLL_SCALE := 10000
const DEFAULT_FALLBACK_BLOCK := "stone"


static func resolve_block(profile: Dictionary, y: int, roll: int) -> String:
	var fallback_block := str(profile.get("fallback_block", DEFAULT_FALLBACK_BLOCK)).strip_edges()
	if fallback_block.is_empty():
		fallback_block = DEFAULT_FALLBACK_BLOCK
	var normalized_roll := clampi(roll, 0, ROLL_SCALE - 1)
	var raw_entries: Variant = profile.get("entries", [])
	if raw_entries is not Array:
		return fallback_block
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var min_y := int(entry.get("min_y", 1))
		var max_y := int(entry.get("max_y", 0))
		if y < min_y or y > max_y:
			continue
		if normalized_roll >= int(entry.get("cumulative_threshold", 0)):
			continue
		var block_id := str(entry.get("block_id", "")).strip_edges()
		return block_id if not block_id.is_empty() else fallback_block
	return fallback_block


static func active_entries(profile: Dictionary, y: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_entries: Variant = profile.get("entries", [])
	if raw_entries is not Array:
		return result
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if y < int(entry.get("min_y", 1)) or y > int(entry.get("max_y", 0)):
			continue
		result.append(entry.duplicate(true))
	return result
