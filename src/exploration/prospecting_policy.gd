class_name ProspectingPolicy
extends RefCounted


static func classify_density(ratio: float, tiers: Array) -> Dictionary:
	var selected: Dictionary = {}
	var normalized_ratio := clampf(ratio, 0.0, 1.0)
	for raw_tier in tiers:
		if raw_tier is not Dictionary:
			continue
		var tier: Dictionary = raw_tier
		if normalized_ratio + 0.000001 < float(tier.get("min_ratio", 0.0)):
			continue
		selected = tier.duplicate(true)
	return selected


static func depth_band(y: int, bands: Array) -> Dictionary:
	var fallback: Dictionary = {}
	for raw_band in bands:
		if raw_band is not Dictionary:
			continue
		var band: Dictionary = raw_band
		fallback = band.duplicate(true)
		if y <= int(band.get("max_y", 63)):
			return fallback
	return fallback


static func dominant_ore(counts: Dictionary, ore_profiles: Array) -> Dictionary:
	var selected: Dictionary = {}
	var selected_count := 0
	var selected_priority := -1
	for raw_profile in ore_profiles:
		if raw_profile is not Dictionary:
			continue
		var profile: Dictionary = raw_profile
		var block_id := str(profile.get("block_id", ""))
		var count := maxi(0, int(counts.get(block_id, 0)))
		var priority := int(profile.get("priority", 0))
		if count < selected_count or (count == selected_count and priority <= selected_priority):
			continue
		selected = profile.duplicate(true)
		selected["count"] = count
		selected_count = count
		selected_priority = priority
	return selected


static func summarize(
	counts: Dictionary,
	geology_samples: int,
	total_samples: int,
	y: int,
	profile_id: String,
	config: Dictionary
) -> Dictionary:
	var ore_total := 0
	for raw_count in counts.values():
		ore_total += maxi(0, int(raw_count))
	var ratio := (
		float(ore_total) / float(geology_samples)
		if geology_samples > 0
		else 0.0
	)
	var density := classify_density(ratio, config.get("density_tiers", []))
	var depth := depth_band(y, config.get("depth_bands", []))
	var dominant := dominant_ore(counts, config.get("ore_blocks", []))
	var depth_label := str(depth.get("label", "当前深度"))
	var density_label := str(density.get("label", "未知"))
	var dominant_label := str(dominant.get("label", ""))
	var message := "%s岩层 · %s" % [depth_label, density_label]
	if int(dominant.get("count", 0)) > 0:
		message += "：%s信号最强" % dominant_label
	else:
		message += "：未发现明显矿物信号"
	message += "；仅显示当前区域的粗粒度趋势"
	return {
		"profile_id": profile_id,
		"depth_band_id": str(depth.get("id", "unknown")),
		"depth_label": depth_label,
		"density_id": str(density.get("id", "unknown")),
		"density_label": density_label,
		"ore_ratio": ratio,
		"ore_samples": ore_total,
		"geology_samples": maxi(0, geology_samples),
		"sample_count": maxi(0, total_samples),
		"dominant_block_id": str(dominant.get("block_id", "")),
		"dominant_label": dominant_label,
		"counts": counts.duplicate(true),
		"message": message,
	}


static func record_key(chunk_coord: Vector2i, depth_band_id: String) -> String:
	return "%d,%d:%s" % [chunk_coord.x, chunk_coord.y, depth_band_id]
