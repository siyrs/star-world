class_name RuntimeHealthReportFormatter
extends RefCounted


static func format(report: Dictionary) -> String:
	var status := str(report.get("status", "healthy"))
	var primary: Dictionary = (
		report.get("primary_bottleneck", {})
		if report.get("primary_bottleneck", {}) is Dictionary
		else {}
	)
	var lines: Array[String] = [
		"F3 运行与保存健康  |  状态：%s" % _status_label(status),
		"主要压力：%s" % str(primary.get("message", "尚无可用运行数据")),
		"告警 %d  |  严重 %d  |  预算行 %d/%d" % [
			maxi(0, int(report.get("warning_count", 0))),
			maxi(0, int(report.get("critical_count", 0))),
			maxi(0, int(report.get("row_count", 0))),
			maxi(0, int(report.get("row_limit", 0))),
		],
		"",
	]
	var raw_rows: Variant = report.get("rows", [])
	if raw_rows is Array:
		for raw_row: Variant in raw_rows:
			if raw_row is Dictionary:
				lines.append(_format_row(raw_row))
	var save: Dictionary = report.get("save", {}) if report.get("save", {}) is Dictionary else {}
	var catalog: Dictionary = (
		report.get("catalog", {}) if report.get("catalog", {}) is Dictionary else {}
	)
	lines.append("")
	lines.append(
		"保存会话：成功 %d / 尝试 %d  |  失败 %d  |  恢复 %d  |  主文件修复 %d / 失败 %d" % [
			maxi(0, int(save.get("success_count", 0))),
			maxi(0, int(save.get("attempt_count", 0))),
			maxi(0, int(save.get("failure_count", 0))),
			maxi(0, int(save.get("recovery_count", 0))),
			maxi(0, int(save.get("repair_success_count", 0))),
			maxi(0, int(save.get("repair_failure_count", 0))),
		]
	)
	lines.append(
		"目录累计：命中 %d  |  回退 %d  |  自愈 %d  |  写失败 %d" % [
			maxi(0, int(catalog.get("hit_count", 0))),
			maxi(0, int(catalog.get("fallback_count", 0))),
			maxi(0, int(catalog.get("repair_count", 0))),
			maxi(0, int(catalog.get("write_failure_count", 0))),
		]
	)
	return "\n".join(lines)


static func _format_row(row: Dictionary) -> String:
	var status := _status_label(str(row.get("status", "healthy")))
	var label := str(row.get("label", "运行域"))
	var detail := str(row.get("detail", "")).strip_edges()
	var limit := maxi(0, int(row.get("limit", 0)))
	if limit > 0:
		return "[%s] %s  %d/%d（%.1f%%）· %s" % [
			status,
			label,
			maxi(0, int(row.get("current", 0))),
			limit,
			maxf(0.0, float(row.get("usage_percent", 0.0))),
			detail,
		]
	return "[%s] %s · %s" % [status, label, detail]


static func _status_label(status: String) -> String:
	return str(
		{
			"healthy": "正常",
			"warning": "警告",
			"critical": "严重",
		}.get(status, status)
	)
