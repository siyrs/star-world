class_name AdaptiveStreamingPolicy
extends RefCounted

const LEVEL_CONSERVATIVE := 0
const LEVEL_GUARDED := 1
const LEVEL_BALANCED := 2
const LEVEL_THROUGHPUT := 3
const MIN_LEVEL := LEVEL_CONSERVATIVE
const MAX_LEVEL := LEVEL_THROUGHPUT

var minimum_frame_samples := 10
var warning_average_frame_ms := 23.0
var critical_average_frame_ms := 35.0
var warning_peak_frame_ms := 45.0
var critical_peak_frame_ms := 75.0
var warning_stutters_per_window := 2
var critical_stutters_per_window := 5
var healthy_average_frame_ms := 17.5
var healthy_peak_frame_ms := 30.0
var backlog_for_boost := 10
var backlog_for_aggressive_boost := 28


func recommend(snapshot: Dictionary, current_level: int) -> Dictionary:
	var normalized_level := clampi(current_level, MIN_LEVEL, MAX_LEVEL)
	if not bool(snapshot.get("world_attached", false)):
		return _recommendation(normalized_level, "detached", "世界未连接")
	if bool(snapshot.get("paused", false)):
		return _recommendation(normalized_level, "paused", "暂停期间保持预算")
	if str(snapshot.get("input_context", "unknown")) != "gameplay":
		return _recommendation(normalized_level, "inactive", "非游戏输入上下文保持预算")
	var frame_sample_count := int(snapshot.get("frame_sample_count", 0))
	if frame_sample_count < maxi(1, minimum_frame_samples):
		return _recommendation(normalized_level, "warmup", "帧样本不足")
	var average_frame_ms := float(snapshot.get("frame_ms_avg", 0.0))
	var peak_frame_ms := float(snapshot.get("frame_ms_peak", 0.0))
	var stutter_count := int(snapshot.get("stutter_count", 0))
	var streaming: Dictionary = snapshot.get("streaming", {})
	var pending_chunks := int(streaming.get("pending", 0))
	var critical_pressure := (
		average_frame_ms >= critical_average_frame_ms
		or peak_frame_ms >= critical_peak_frame_ms
		or stutter_count >= critical_stutters_per_window
	)
	if critical_pressure:
		return _recommendation(
			maxi(MIN_LEVEL, normalized_level - 2),
			"critical_pressure",
			"严重帧压力，快速降低区块构建负载"
		)
	var warning_pressure := (
		average_frame_ms >= warning_average_frame_ms
		or peak_frame_ms >= warning_peak_frame_ms
		or stutter_count >= warning_stutters_per_window
	)
	if warning_pressure:
		return _recommendation(
			maxi(MIN_LEVEL, normalized_level - 1),
			"frame_pressure",
			"帧时间压力升高，降低区块构建负载"
		)
	var has_headroom := (
		average_frame_ms <= healthy_average_frame_ms
		and peak_frame_ms <= healthy_peak_frame_ms
		and stutter_count == 0
	)
	if pending_chunks <= 0:
		if has_headroom and normalized_level < LEVEL_BALANCED:
			return _recommendation(
				normalized_level + 1,
				"recover_baseline",
				"帧时间恢复，逐步回到均衡预算"
			)
		if normalized_level > LEVEL_BALANCED:
			return _recommendation(
				normalized_level - 1,
				"queue_drained",
				"区块队列已清空，回收额外吞吐预算"
			)
		return _recommendation(normalized_level, "idle", "区块队列为空")
	if has_headroom:
		if normalized_level < LEVEL_BALANCED:
			return _recommendation(
				normalized_level + 1,
				"recover_headroom",
				"帧时间稳定，恢复区块构建预算"
			)
		if pending_chunks >= backlog_for_aggressive_boost:
			return _recommendation(
				mini(MAX_LEVEL, normalized_level + 1),
				"large_backlog",
				"帧时间充足且区块队列较长，提高构建吞吐"
			)
		if pending_chunks >= backlog_for_boost and normalized_level < LEVEL_THROUGHPUT:
			return _recommendation(
				normalized_level + 1,
				"healthy_backlog",
				"帧时间稳定且存在区块积压，适度提高吞吐"
			)
	return _recommendation(normalized_level, "balanced", "维持当前区块构建预算")


func profile_for_level(baseline: Dictionary, level: int) -> Dictionary:
	var normalized_level := clampi(level, MIN_LEVEL, MAX_LEVEL)
	var base_budget_ms := clampf(float(baseline.get("budget_ms", 4.0)), 0.5, 12.0)
	var base_cells := clampi(int(baseline.get("cells_per_step", 2048)), 256, 8192)
	var base_steps := clampi(int(baseline.get("max_steps_per_frame", 2)), 1, 8)
	var base_chunks := clampi(int(baseline.get("chunks_per_frame", 1)), 1, 4)
	var budget_ms := base_budget_ms
	var cells_per_step := base_cells
	var max_steps_per_frame := base_steps
	var chunks_per_frame := base_chunks
	match normalized_level:
		LEVEL_CONSERVATIVE:
			budget_ms = clampf(base_budget_ms * 0.4, 0.75, 2.0)
			cells_per_step = _quantize_cells(int(round(float(base_cells) * 0.5)))
			max_steps_per_frame = 1
			chunks_per_frame = 1
		LEVEL_GUARDED:
			budget_ms = clampf(base_budget_ms * 0.7, 1.0, 3.5)
			cells_per_step = _quantize_cells(int(round(float(base_cells) * 0.75)))
			max_steps_per_frame = 1
			chunks_per_frame = 1
		LEVEL_THROUGHPUT:
			budget_ms = clampf(base_budget_ms * 1.25, base_budget_ms, 6.0)
			cells_per_step = _quantize_cells(int(round(float(base_cells) * 1.5)))
			max_steps_per_frame = clampi(base_steps + 1, base_steps, 4)
			chunks_per_frame = clampi(base_chunks + 1, base_chunks, 2)
		_:
			pass
	return {
		"level": normalized_level,
		"level_name": level_name(normalized_level),
		"budget_ms": budget_ms,
		"cells_per_step": cells_per_step,
		"max_steps_per_frame": max_steps_per_frame,
		"chunks_per_frame": chunks_per_frame,
	}


func level_name(level: int) -> String:
	match clampi(level, MIN_LEVEL, MAX_LEVEL):
		LEVEL_CONSERVATIVE:
			return "conservative"
		LEVEL_GUARDED:
			return "guarded"
		LEVEL_THROUGHPUT:
			return "throughput"
		_:
			return "balanced"


func _recommendation(target_level: int, code: String, reason: String) -> Dictionary:
	return {
		"target_level": clampi(target_level, MIN_LEVEL, MAX_LEVEL),
		"code": code,
		"reason": reason,
		"critical": code == "critical_pressure",
	}


func _quantize_cells(value: int) -> int:
	var quantized := int(round(float(value) / 256.0)) * 256
	return clampi(quantized, 256, 8192)
