class_name RuntimeHealthPolicy
extends RefCounted

const STATUS_HEALTHY := "healthy"
const STATUS_WARNING := "warning"
const STATUS_CRITICAL := "critical"
const MAX_OPERATION_ISSUES := 8

var minimum_frame_samples := 10
var warning_average_frame_ms := 25.0
var critical_average_frame_ms := 40.0
var warning_peak_frame_ms := 45.0
var critical_peak_frame_ms := 80.0
var warning_stutters_per_window := 3
var critical_stutters_per_window := 8
var warning_pending_chunks := 48
var critical_pending_chunks := 96
var warning_memory_mib := 1024.0
var critical_memory_mib := 1536.0
var warning_node_count := 5000
var critical_node_count := 9000


func evaluate(snapshot: Dictionary) -> Dictionary:
	var runtime_severity := 0
	var issues: Array[String] = []
	var frame_sample_count := int(snapshot.get("frame_sample_count", 0))
	var frame_metrics_ready: bool = frame_sample_count >= maxi(1, minimum_frame_samples)
	if frame_metrics_ready:
		runtime_severity = maxi(
			runtime_severity,
			_evaluate_upper_bound(
				float(snapshot.get("frame_ms_avg", 0.0)),
				warning_average_frame_ms,
				critical_average_frame_ms,
				"平均帧时间偏高",
				issues
			)
		)
		runtime_severity = maxi(
			runtime_severity,
			_evaluate_upper_bound(
				float(snapshot.get("frame_ms_peak", 0.0)),
				warning_peak_frame_ms,
				critical_peak_frame_ms,
				"峰值帧时间偏高",
				issues
			)
		)
		runtime_severity = maxi(
			runtime_severity,
			_evaluate_upper_bound(
				float(snapshot.get("stutter_count", 0)),
				float(warning_stutters_per_window),
				float(critical_stutters_per_window),
				"采样窗口内卡顿次数偏多",
				issues
			)
		)
	var streaming: Dictionary = snapshot.get("streaming", {})
	runtime_severity = maxi(
		runtime_severity,
		_evaluate_upper_bound(
			float(streaming.get("pending", 0)),
			float(warning_pending_chunks),
			float(critical_pending_chunks),
			"区块构建队列积压",
			issues
		)
	)
	runtime_severity = maxi(
		runtime_severity,
		_evaluate_upper_bound(
			float(snapshot.get("memory_mib", 0.0)),
			warning_memory_mib,
			critical_memory_mib,
			"静态内存占用偏高",
			issues
		)
	)
	runtime_severity = maxi(
		runtime_severity,
		_evaluate_upper_bound(
			float(snapshot.get("node_count", 0)),
			float(warning_node_count),
			critical_node_count,
			"场景节点数量偏高",
			issues
		)
	)
	var operations: Dictionary = (
		snapshot.get("operations", {})
		if snapshot.get("operations", {}) is Dictionary
		else {}
	)
	var operations_severity := clampi(int(operations.get("severity", 0)), 0, 2)
	var operation_issue_count := 0
	var raw_operation_issues: Variant = operations.get("issues", [])
	if raw_operation_issues is Array:
		for raw_issue: Variant in raw_operation_issues:
			if operation_issue_count >= MAX_OPERATION_ISSUES:
				break
			var issue := str(raw_issue).strip_edges()
			if issue.is_empty():
				continue
			issues.append("运行与保存：%s" % issue)
			operation_issue_count += 1
	var severity := maxi(runtime_severity, operations_severity)
	return {
		"status": _status_for_severity(severity),
		"severity": severity,
		"healthy": severity == 0,
		"issues": issues,
		"frame_metrics_ready": frame_metrics_ready,
		"frame_sample_count": frame_sample_count,
		"runtime_status": _status_for_severity(runtime_severity),
		"runtime_severity": runtime_severity,
		"operations_status": _status_for_severity(operations_severity),
		"operations_severity": operations_severity,
		"operations_issue_count": operation_issue_count,
	}


func _evaluate_upper_bound(
	value: float,
	warning_threshold: float,
	critical_threshold: float,
	description: String,
	issues: Array[String]
) -> int:
	if value >= critical_threshold:
		issues.append("%s：%.1f（严重阈值 %.1f）" % [description, value, critical_threshold])
		return 2
	if value >= warning_threshold:
		issues.append("%s：%.1f（警告阈值 %.1f）" % [description, value, warning_threshold])
		return 1
	return 0


func _status_for_severity(severity: int) -> String:
	if severity >= 2:
		return STATUS_CRITICAL
	if severity == 1:
		return STATUS_WARNING
	return STATUS_HEALTHY
