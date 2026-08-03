extends SceneTree

const MetricsScript = preload("res://src/core/frame_performance_metrics.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_one_percent_tail()
	_test_two_frame_tail()
	_test_invalid_and_empty_samples()
	if failures.is_empty():
		print("QA FRAME PERFORMANCE METRICS PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA FRAME PERFORMANCE METRICS FAILURE: %s" % failure)
	print(
		"QA FRAME PERFORMANCE METRICS FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_one_percent_tail() -> void:
	var frames: Array[float] = []
	for _index in 99:
		frames.append(10.0)
	frames.append(100.0)
	var result := MetricsScript.summarize(frames, [1.0, 240.0])
	_check(int(result.get("sample_count", 0)) == 100, "one-percent fixture retains one hundred real frames")
	_check(_near(float(result.get("frame_ms_avg", 0.0)), 10.9), "average frame time uses real samples")
	_check(_near(float(result.get("avg_fps", 0.0)), 1000.0 / 10.9), "average FPS is derived from average frame time")
	_check(_near(float(result.get("one_percent_low_fps", 0.0)), 10.0), "one-percent low uses the slowest one-percent frame tail")
	_check(_near(float(result.get("frame_ms_p95", 0.0)), 10.0), "p95 remains an independent frame-time percentile")
	_check(_near(float(result.get("frame_ms_p99", 0.0)), 10.0), "p99 does not masquerade as one-percent tail average")
	_check(_near(float(result.get("frame_ms_max", 0.0)), 100.0), "maximum frame time preserves the outlier")
	_check(_near(float(result.get("frame_budget_miss_60fps_percent", 0.0)), 1.0), "sixty-FPS budget miss ratio counts the outlier")
	_check(_near(float(result.get("frame_budget_miss_30fps_percent", 0.0)), 1.0), "thirty-FPS budget miss ratio counts the outlier")
	_check(_near(float(result.get("engine_fps_avg_diagnostic", 0.0)), 120.5), "rolling engine FPS remains diagnostic only")
	_check(not _near(float(result.get("avg_fps", 0.0)), 120.5), "rolling engine FPS cannot overwrite real average FPS")


func _test_two_frame_tail() -> void:
	var frames: Array[float] = []
	for _index in 198:
		frames.append(16.0)
	frames.append(40.0)
	frames.append(60.0)
	var result := MetricsScript.summarize(frames)
	_check(int(result.get("sample_count", 0)) == 200, "two-hundred-frame fixture is complete")
	_check(_near(float(result.get("one_percent_low_fps", 0.0)), 20.0), "one-percent low averages the two slowest frames")
	_check(_near(float(result.get("frame_ms_min", 0.0)), 16.0), "minimum frame time is retained")
	_check(_near(float(result.get("frame_ms_max", 0.0)), 60.0), "maximum frame time is retained")
	_check(_near(float(result.get("frame_budget_miss_60fps_percent", 0.0)), 1.0), "only two frames miss the sixty-FPS budget")
	_check(_near(float(result.get("frame_budget_miss_30fps_percent", 0.0)), 1.0), "only two frames miss the thirty-FPS budget")


func _test_invalid_and_empty_samples() -> void:
	var filtered := MetricsScript.summarize([0.0, -4.0, INF, NAN, 20.0], [0.0, INF, 50.0])
	_check(int(filtered.get("sample_count", 0)) == 1, "non-positive and non-finite frame samples are rejected")
	_check(_near(float(filtered.get("avg_fps", 0.0)), 50.0), "remaining valid frame controls FPS")
	_check(int(filtered.get("engine_fps_sample_count", 0)) == 1, "invalid rolling FPS diagnostics are rejected")
	var empty := MetricsScript.summarize([])
	_check(int(empty.get("sample_count", -1)) == 0, "empty capture remains explicitly empty")
	_check(_near(float(empty.get("avg_fps", -1.0)), 0.0), "empty capture does not invent average FPS")
	_check(_near(float(empty.get("one_percent_low_fps", -1.0)), 0.0), "empty capture does not invent one-percent low")


func _near(actual: float, expected: float, tolerance: float = 0.001) -> bool:
	return absf(actual - expected) <= tolerance


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
