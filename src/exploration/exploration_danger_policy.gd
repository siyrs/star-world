class_name ExplorationDangerPolicy
extends RefCounted


static func assess(context: Dictionary, config: Dictionary) -> Dictionary:
	var score := clampi(int(context.get("map_base", 0)), 0, 60)
	var reasons: Array[String] = []
	var depth := _depth_score(int(context.get("player_y", 32)), config)
	score += int(depth.get("score", 0))
	if int(depth.get("score", 0)) > 0:
		reasons.append(str(depth.get("label", "深度")))
	var phase := str(context.get("phase", "day"))
	var raw_phase_scores: Variant = config.get("phase_scores", {})
	var phase_score := 0
	if raw_phase_scores is Dictionary:
		phase_score = clampi(int(raw_phase_scores.get(phase, 0)), 0, 40)
	score += phase_score
	if phase_score > 0:
		reasons.append(_phase_label(phase))
	var hostile_count := maxi(0, int(context.get("hostile_count", 0)))
	var hostile_pressure := maxf(
		float(hostile_count), maxf(0.0, float(context.get("hostile_pressure", hostile_count)))
	)
	var hostile_score := mini(
		clampi(int(config.get("hostile_score_cap", 30)), 0, 60),
		roundi(hostile_pressure * float(clampi(int(config.get("hostile_score_each", 12)), 0, 30)))
	)
	score += hostile_score
	if hostile_pressure > float(hostile_count) + 0.01:
		reasons.append("附近精英敌对生物")
	elif hostile_count > 0:
		reasons.append("附近敌对生物 ×%d" % hostile_count)
	var windup_count := maxi(0, int(context.get("windup_count", 0)))
	var elite_windup_count := clampi(
		int(context.get("elite_windup_count", 0)), 0, windup_count
	)
	var soonest_impact_seconds := float(context.get("soonest_impact_seconds", -1.0))
	if not is_finite(soonest_impact_seconds) or soonest_impact_seconds < 0.0:
		soonest_impact_seconds = -1.0
	var urgency_label := _windup_label(
		windup_count, elite_windup_count, soonest_impact_seconds
	)
	var lava_samples := maxi(0, int(context.get("lava_samples", 0)))
	var lava_score := mini(
		clampi(int(config.get("lava_score_cap", 20)), 0, 60),
		lava_samples * clampi(int(config.get("lava_score_each", 5)), 0, 30)
	)
	score += lava_score
	if lava_samples > 0:
		reasons.append("附近岩浆")
	var total_samples := maxi(1, int(context.get("total_samples", 1)))
	var air_ratio := clampf(float(context.get("air_samples", 0)) / float(total_samples), 0.0, 1.0)
	var cave_result := _cave_score(air_ratio, config)
	score += int(cave_result.get("score", 0))
	if int(cave_result.get("score", 0)) > 0:
		reasons.append(str(cave_result.get("label", "洞穴环境")))
	score = clampi(score, 0, 100)
	var tier := _resolve_tier(score, config)
	var message := "危险等级：%s" % str(tier.get("label", "未知"))
	if not urgency_label.is_empty():
		message += " · %s" % urgency_label
	if not reasons.is_empty():
		message += " · %s" % "、".join(reasons.slice(0, 3))
	var raw_source_counts: Variant = context.get("windup_source_counts", {})
	return {
		"score": score,
		"tier_id": str(tier.get("id", "safe")),
		"tier_label": str(tier.get("label", "低")),
		"tone": str(tier.get("tone", "info")),
		"message": message,
		"reasons": reasons,
		"phase": phase,
		"player_y": int(context.get("player_y", 0)),
		"hostile_count": hostile_count,
		"hostile_pressure": hostile_pressure,
		"windup_count": windup_count,
		"elite_windup_count": elite_windup_count,
		"windup_pressure": maxf(0.0, float(context.get("windup_pressure", 0.0))),
		"soonest_impact_seconds": soonest_impact_seconds,
		"windup_urgency_label": urgency_label,
		"windup_source_counts": (
			raw_source_counts.duplicate(true) if raw_source_counts is Dictionary else {}
		),
		"windup_scanned_nodes": maxi(0, int(context.get("windup_scanned_nodes", 0))),
		"windup_query_cap": maxi(0, int(context.get("windup_query_cap", 0))),
		"windup_scan_cap_reached": bool(context.get("windup_scan_cap_reached", false)),
		"lava_samples": lava_samples,
		"air_ratio": air_ratio,
		"sample_count": total_samples,
		"map_id": str(context.get("map_id", "star_continent")),
	}


static func _windup_label(
	windup_count: int, elite_windup_count: int, soonest_impact_seconds: float
) -> String:
	if windup_count <= 0:
		return ""
	var label := "来袭攻击 ×%d" % windup_count
	if elite_windup_count > 0:
		label += "（精英 ×%d）" % elite_windup_count
	if soonest_impact_seconds >= 0.0:
		label += " · 最快 %.1f 秒" % soonest_impact_seconds
	return label


static func _depth_score(player_y: int, config: Dictionary) -> Dictionary:
	var raw_entries: Variant = config.get("depth_scores", [])
	if raw_entries is Array:
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary and player_y <= int(raw_entry.get("max_y", 63)):
				return raw_entry.duplicate(true)
	return {"score":0, "label":"深度"}


static func _cave_score(air_ratio: float, config: Dictionary) -> Dictionary:
	var raw_entries: Variant = config.get("cave_open_thresholds", [])
	if raw_entries is Array:
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary and air_ratio >= float(raw_entry.get("minimum_ratio", 1.0)):
				return raw_entry.duplicate(true)
	return {"score":0, "label":""}


static func _resolve_tier(score: int, config: Dictionary) -> Dictionary:
	var raw_tiers: Variant = config.get("tiers", [])
	if raw_tiers is Array:
		for raw_tier: Variant in raw_tiers:
			if raw_tier is Dictionary and score <= int(raw_tier.get("max_score", 100)):
				return raw_tier.duplicate(true)
	return {"id":"severe", "label":"极高", "tone":"error", "max_score":100}


static func _phase_label(phase: String) -> String:
	match phase:
		"night": return "夜晚"
		"dusk": return "黄昏"
		"dawn": return "黎明"
		_: return "白昼"
