class_name SaveCheckpointTimelineFormatter
extends RefCounted

const PolicyScript = preload("res://src/save/save_checkpoint_timeline_policy.gd")


static func format_f3(raw_timeline: Variant) -> Array[String]:
	var timeline := PolicyScript.project_timeline(raw_timeline)
	var counts: Dictionary = timeline.get("reason_counts", {})
	var lines: Array[String] = [
		"保存来源：手动 %d · 自动 %d · 返回 %d · 系统 %d" % [
			maxi(0, int(counts.get("manual", 0))),
			maxi(0, int(counts.get("autosave", 0))),
			maxi(0, int(counts.get("return_to_menu", 0))),
			maxi(0, int(counts.get("system", 0))),
		],
		"检查点历史：%d/%d · 已丢弃 %d" % [
			maxi(0, int(timeline.get("history_count", 0))),
			maxi(0, int(timeline.get("history_limit", PolicyScript.MAX_EVENTS))),
			maxi(0, int(timeline.get("history_dropped_count", 0))),
		],
	]
	var event: Dictionary = timeline.get("last_current_world_event", {})
	if event.is_empty():
		event = timeline.get("last_event", {})
	if event.is_empty():
		lines.append("最近检查点：本会话尚无保存记录")
	else:
		var outcome := "成功" if bool(event.get("success", false)) else "失败"
		var age_seconds := _age_seconds(
			maxi(0, int(timeline.get("captured_at_msec", 0))),
			maxi(0, int(event.get("timestamp_msec", 0)))
		)
		lines.append(
			"最近检查点：%s%s · %s · %.2f ms · %s前" % [
				str(event.get("reason_label", PolicyScript.reason_label(event.get("reason", "")))),
				outcome,
				_format_bytes(maxi(0, int(event.get("bytes", 0)))),
				maxf(0.0, float(event.get("elapsed_milliseconds", 0.0))),
				_format_duration(age_seconds),
			]
		)
	lines.append(_format_autosave(timeline.get("autosave", {})))
	return lines


static func _format_autosave(raw_snapshot: Variant) -> String:
	var snapshot := PolicyScript.project_autosave(raw_snapshot)
	if not bool(snapshot.get("enabled", false)):
		return "自动保存：已关闭"
	if bool(snapshot.get("saving", false)):
		return "自动保存：正在写入权威存档"
	if bool(snapshot.get("pending", false)):
		return "自动保存：已到期，等待本帧检查点"
	var next_seconds := maxf(0.0, float(snapshot.get("next_in_seconds", 0.0)))
	var suffix := "（暂停期间不计时）" if bool(snapshot.get("paused", false)) else ""
	return "自动保存：%s后%s" % [_format_duration(next_seconds), suffix]


static func _age_seconds(captured_at_msec: int, event_msec: int) -> float:
	if captured_at_msec <= 0 or event_msec <= 0:
		return 0.0
	return maxf(0.0, float(captured_at_msec - event_msec) / 1000.0)


static func _format_duration(seconds: float) -> String:
	var total := maxi(0, int(ceil(seconds)))
	if total >= 3600:
		return "%d小时%02d分" % [total / 3600, (total % 3600) / 60]
	if total >= 60:
		return "%d分%02d秒" % [total / 60, total % 60]
	return "%d秒" % total


static func _format_bytes(bytes: int) -> String:
	var safe_bytes := maxi(0, bytes)
	if safe_bytes >= 1024 * 1024:
		return "%.2f MiB" % (float(safe_bytes) / float(1024 * 1024))
	if safe_bytes >= 1024:
		return "%.1f KiB" % (float(safe_bytes) / 1024.0)
	return "%d B" % safe_bytes
