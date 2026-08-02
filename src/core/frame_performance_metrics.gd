class_name FramePerformanceMetrics
extends RefCounted

const TARGET_60_FPS_FRAME_MS := 1000.0 / 60.0
const TARGET_30_FPS_FRAME_MS := 1000.0 / 30.0
const ONE_PERCENT_FRACTION := 0.01


static func summarize(frame_times_ms: Array, engine_fps_samples: Array = []) -> Dictionary:
	var frame_times := _positive_finite_values(frame_times_ms)
	var engine_fps := _positive_finite_values(engine_fps_samples)
	var average_frame_ms := _average(frame_times)
	return {
		"sample_count": frame_times.size(),
		# Average FPS and 1% Low must be derived from the same real frame-time
		# samples. Engine.get_frames_per_second() is a rolling display statistic and
		# is retained only as a diagnostic field.
		"avg_fps": _fps_from_frame_ms(average_frame_ms),
		"one_percent_low_fps": _slow_tail_fps(frame_times, ONE_PERCENT_FRACTION),
		"frame_ms_avg": average_frame_ms,
		"frame_ms_p95": _percentile(frame_times, 95.0),
		"frame_ms_p99": _percentile(frame_times, 99.0),
		"frame_ms_min": _minimum(frame_times),
		"frame_ms_max": _maximum(frame_times),
		"frame_budget_miss_60fps_percent": _percent_above(
			frame_times, TARGET_60_FPS_FRAME_MS
		),
		"frame_budget_miss_30fps_percent": _percent_above(
			frame_times, TARGET_30_FPS_FRAME_MS
		),
		"engine_fps_avg_diagnostic": _average(engine_fps),
		"engine_fps_sample_count": engine_fps.size(),
	}


static func _slow_tail_fps(frame_times_ms: Array[float], fraction: float) -> float:
	if frame_times_ms.is_empty():
		return 0.0
	var sorted := frame_times_ms.duplicate()
	sorted.sort()
	var tail_count := clampi(
		ceili(float(sorted.size()) * clampf(fraction, 0.0001, 1.0)),
		1,
		sorted.size()
	)
	var tail_total := 0.0
	for index in range(sorted.size() - tail_count, sorted.size()):
		tail_total += sorted[index]
	return _fps_from_frame_ms(tail_total / float(tail_count))


static func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var rank := clampi(
		ceili(clampf(percentile, 0.0, 100.0) / 100.0 * float(sorted.size())) - 1,
		0,
		sorted.size() - 1
	)
	return sorted[rank]


static func _percent_above(values: Array[float], threshold: float) -> float:
	if values.is_empty():
		return 0.0
	var count := 0
	for value: float in values:
		if value > threshold:
			count += 1
	return float(count) / float(values.size()) * 100.0


static func _positive_finite_values(raw_values: Array) -> Array[float]:
	var result: Array[float] = []
	for raw_value: Variant in raw_values:
		var value := float(raw_value)
		if is_finite(value) and value > 0.0:
			result.append(value)
	return result


static func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _minimum(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var result := values[0]
	for value: float in values:
		result = minf(result, value)
	return result


static func _maximum(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var result := values[0]
	for value: float in values:
		result = maxf(result, value)
	return result


static func _fps_from_frame_ms(frame_ms: float) -> float:
	return 1000.0 / frame_ms if frame_ms > 0.0 else 0.0
