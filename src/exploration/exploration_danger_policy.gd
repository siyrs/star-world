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
	var hostile_score := mini(
		clampi(int(config.get("hostile_score_cap", 30)), 0, 60),
		hostile_count * clampi(int(config.get("hostile_score_each", 12)), 0, 30)
	)
	score += hostile_score
	if hostile_count > 0:
		reasons.append("附近敌对生物 ×%d" % hostile_count)
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
	if not reasons.is_empty():
		message += " · %s" % "、".join(reasons.slice(0, 3))
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
		"lava_samples": lava_samples,
		"air_ratio": air_ratio,
		"sample_count": total_samples,
		"map_id": str(context.get("map_id", "star_continent")),
	}


static func _depth_score(player_y: int, config: Dictionary) -> Dictionary:
	var raw_entries: Variant = config.get("depth_scores", [])
	if raw_entries is Array:
		for raw_entry in raw_entries:
			if raw_entry is Dictionary and player_y <= int(raw_entry.get("max_y", 63)):
				return raw_entry.duplicate(true)
	return {"score":0, "label":"深度"}


static func _cave_score(air_ratio: float, config: Dictionary) -> Dictionary:
	var raw_entries: Variant = config.get("cave_open_thresholds", [])
	if raw_entries is Array:
		for raw_entry in raw_entries:
			if raw_entry is Dictionary and air_ratio >= float(raw_entry.get("minimum_ratio", 1.0)):
				return raw_entry.duplicate(true)
	return {"score":0, "label":""}


static func _resolve_tier(score: int, config: Dictionary) -> Dictionary:
	var raw_tiers: Variant = config.get("tiers", [])
	if raw_tiers is Array:
		for raw_tier in raw_tiers:
			if raw_tier is Dictionary and score <= int(raw_tier.get("max_score", 100)):
				return raw_tier.duplicate(true)
	return {"id":"severe", "label":"极高", "tone":"error", "max_score":100}


static func _phase_label(phase: String) -> String:
	match phase:
		"night": return "夜晚"
		"dusk": return "黄昏"
		"dawn": return "黎明"
		_: return "白昼"
