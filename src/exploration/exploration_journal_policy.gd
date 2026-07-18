class_name ExplorationJournalPolicy
extends RefCounted

const StateMigrationScript = preload("res://src/exploration/prospecting_state_migration.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")


static func build_snapshot(raw_records: Array, config: Dictionary) -> Dictionary:
	# The records already follow the v3 sequence contract. Passing the version
	# explicitly sanitizes fields and duplicate keys without renumbering valid
	# player-visible discovery IDs.
	var normalized_state := StateMigrationScript.normalize_exploration_state(
		{
			"version": StateMigrationScript.VERSION,
			"records": raw_records,
			"last_result": {},
		}
	)
	var records: Array[Dictionary] = []
	var normalized_records: Variant = normalized_state.get("records", [])
	if normalized_records is Array:
		for raw_record: Variant in normalized_records:
			if raw_record is Dictionary:
				records.append(raw_record.duplicate(true))
	records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("sequence", 0)) > int(b.get("sequence", 0))
	)
	var unique_chunks: Dictionary = {}
	var depth_bands: Dictionary = {}
	var density_ids: Dictionary = {}
	var danger_tiers: Dictionary = {}
	var rich_count := 0
	var highest_danger_score := 0
	var latest_sequence := 0
	for record: Dictionary in records:
		var chunk_key := _chunk_key(record.get("chunk", []))
		if not chunk_key.is_empty():
			unique_chunks[chunk_key] = true
		var depth_id := str(record.get("depth_band_id", "unknown"))
		if depth_id != "unknown" and not depth_id.is_empty():
			depth_bands[depth_id] = true
		var density_id := str(record.get("density_id", "unknown"))
		if density_id != "unknown" and not density_id.is_empty():
			density_ids[density_id] = true
		if density_id == "rich":
			rich_count += 1
		var danger_tier := str(record.get("danger_tier_id", "unknown"))
		if danger_tier != "unknown" and not danger_tier.is_empty():
			danger_tiers[danger_tier] = true
		highest_danger_score = maxi(
			highest_danger_score,
			clampi(int(record.get("danger_score", 0)), 0, 100)
		)
		latest_sequence = maxi(latest_sequence, int(record.get("sequence", 0)))
	var metrics := {
		"record_count": records.size(),
		"unique_chunk_count": unique_chunks.size(),
		"depth_band_count": depth_bands.size(),
		"depth_bands": depth_bands.keys(),
		"density_ids": density_ids.keys(),
		"danger_tiers": danger_tiers.keys(),
		"rich_count": rich_count,
		"highest_danger_score": highest_danger_score,
		"latest_sequence": latest_sequence,
		"records": records,
	}
	var milestones := _evaluate_milestones(config.get("milestones", []), metrics)
	var completed_count := 0
	for milestone: Dictionary in milestones:
		if bool(milestone.get("completed", false)):
			completed_count += 1
	var max_visible := clampi(int(config.get("max_visible_records", 24)), 1, 64)
	var visible_records: Array[Dictionary] = []
	for index in mini(max_visible, records.size()):
		visible_records.append(records[index].duplicate(true))
	return {
		"record_count": records.size(),
		"unique_chunk_count": unique_chunks.size(),
		"depth_band_count": depth_bands.size(),
		"rich_count": rich_count,
		"highest_danger_score": highest_danger_score,
		"latest_sequence": latest_sequence,
		"completed_milestone_count": completed_count,
		"milestone_count": milestones.size(),
		"milestones": milestones,
		"records": visible_records,
		"has_more_records": records.size() > visible_records.size(),
	}


static func map_label(profile_id: String) -> String:
	return MapProfileCatalogScript.label(profile_id)


static func _evaluate_milestones(raw_milestones: Variant, metrics: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_milestones is not Array:
		return result
	for raw_milestone: Variant in raw_milestones:
		if raw_milestone is not Dictionary:
			continue
		var milestone: Dictionary = raw_milestone.duplicate(true)
		var status := _milestone_status(milestone, metrics)
		milestone["completed"] = bool(status.get("completed", false))
		milestone["progress"] = int(status.get("progress", 0))
		milestone["target"] = int(status.get("target", 1))
		for raw_key: Variant in status.keys():
			var key := str(raw_key)
			if key not in ["completed", "progress", "target"]:
				milestone[key] = status[raw_key]
		result.append(milestone)
	return result


static func _milestone_status(milestone: Dictionary, metrics: Dictionary) -> Dictionary:
	var kind := str(milestone.get("kind", ""))
	match kind:
		"record_count":
			return _threshold_status(
				int(metrics.get("record_count", 0)), int(milestone.get("threshold", 1))
			)
		"unique_chunks":
			return _threshold_status(
				int(metrics.get("unique_chunk_count", 0)), int(milestone.get("threshold", 1))
			)
		"depth_band_count":
			return _threshold_status(
				int(metrics.get("depth_band_count", 0)), int(milestone.get("threshold", 1))
			)
		"depth_band":
			var depth_bands: Array = metrics.get("depth_bands", [])
			var completed := str(milestone.get("value", "")) in depth_bands
			return {"completed": completed, "progress": int(completed), "target": 1}
		"density":
			var density_ids: Array = metrics.get("density_ids", [])
			var completed := str(milestone.get("value", "")) in density_ids
			return {"completed": completed, "progress": int(completed), "target": 1}
		"danger_tier":
			var danger_tiers: Array = metrics.get("danger_tiers", [])
			var raw_values: Variant = milestone.get("values", [])
			var completed := false
			if raw_values is Array:
				for raw_value: Variant in raw_values:
					if str(raw_value) in danger_tiers:
						completed = true
						break
			return {"completed": completed, "progress": int(completed), "target": 1}
		"profile_rule":
			return _profile_rule_status(milestone, metrics.get("records", []))
		_:
			return {"completed": false, "progress": 0, "target": 1}


static func _profile_rule_status(milestone: Dictionary, raw_records: Variant) -> Dictionary:
	if raw_records is not Array:
		return {"completed": false, "progress": 0, "target": 1}
	var raw_rules: Variant = milestone.get("rules", {})
	if raw_rules is not Dictionary:
		return {"completed": false, "progress": 0, "target": 1}
	var rules: Dictionary = raw_rules
	for raw_record: Variant in raw_records:
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record
		var profile_id := str(record.get("profile_id", ""))
		var raw_rule: Variant = rules.get(profile_id, {})
		if raw_rule is not Dictionary:
			continue
		if _record_matches_profile_rule(record, raw_rule):
			return {
				"completed": true,
				"progress": 1,
				"target": 1,
				"matched_profile_id": profile_id,
				"matched_sequence": int(record.get("sequence", 0)),
			}
	return {"completed": false, "progress": 0, "target": 1}


static func _record_matches_profile_rule(record: Dictionary, raw_rule: Dictionary) -> bool:
	var depth_ids: Array = raw_rule.get("depth_band_ids", [])
	if not depth_ids.is_empty() and str(record.get("depth_band_id", "")) not in depth_ids:
		return false
	var density_ids: Array = raw_rule.get("density_ids", [])
	if not density_ids.is_empty() and str(record.get("density_id", "")) not in density_ids:
		return false
	var danger_ids: Array = raw_rule.get("danger_tier_ids", [])
	if not danger_ids.is_empty() and str(record.get("danger_tier_id", "")) not in danger_ids:
		return false
	var minimum_danger_score := clampi(int(raw_rule.get("minimum_danger_score", 0)), 0, 100)
	if clampi(int(record.get("danger_score", 0)), 0, 100) < minimum_danger_score:
		return false
	return true


static func _threshold_status(value: int, threshold: int) -> Dictionary:
	var target := maxi(1, threshold)
	return {
		"completed": value >= target,
		"progress": clampi(value, 0, target),
		"target": target,
	}


static func _chunk_key(raw_chunk: Variant) -> String:
	if raw_chunk is not Array or raw_chunk.size() < 2:
		return ""
	return "%d,%d" % [int(raw_chunk[0]), int(raw_chunk[1])]
