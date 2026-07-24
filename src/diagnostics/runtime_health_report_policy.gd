class_name RuntimeHealthReportPolicy
extends RefCounted

const STATUS_HEALTHY := "healthy"
const STATUS_WARNING := "warning"
const STATUS_CRITICAL := "critical"

const MAX_ROWS := 12
const MAX_ISSUES := 8
const DEFAULT_PENDING_CHUNK_BUDGET := 128
const DEFAULT_LOADED_CHUNK_BUDGET := 96
const DEFAULT_MACHINE_BUDGET := 4096
const DEFAULT_MACHINE_DOMAIN_BUDGET := 16

const WARNING_USAGE_RATIO := 0.75
const CRITICAL_USAGE_RATIO := 0.90


static func build(sources: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var streaming := _dictionary(sources.get("streaming", {}))
	var machines := _dictionary(sources.get("machines", {}))
	var agriculture := _dictionary(sources.get("agriculture", {}))
	var husbandry := _dictionary(sources.get("husbandry", {}))
	var attraction := _dictionary(sources.get("animal_attraction", {}))
	var products := _dictionary(sources.get("animal_products", {}))
	var ecology := _dictionary(sources.get("ecology", {}))
	var pickups := _dictionary(sources.get("pickups", {}))
	var structural := _dictionary(sources.get("structural_integrity", {}))
	var catalog := _project_catalog(_dictionary(sources.get("catalog", {})))
	var save := _project_save(_dictionary(sources.get("save", {})))

	rows.append(_usage_row(
		"streaming_pending",
		"Chunk 排队",
		maxi(0, int(streaming.get("pending", 0))),
		_first_positive_int(
			streaming,
			["pending_budget", "max_pending_chunks", "max_pending_chunk_budget"],
			DEFAULT_PENDING_CHUNK_BUDGET
		),
		"待构建 Chunk"
	))
	rows.append(_usage_row(
		"streaming_loaded",
		"Chunk 已加载",
		maxi(0, int(streaming.get("loaded", 0))),
		_first_positive_int(
			streaming,
			["loaded_budget", "max_loaded_chunks", "max_loaded_chunk_budget"],
			DEFAULT_LOADED_CHUNK_BUDGET
		),
		"当前驻留 Chunk"
	))
	rows.append(_usage_row(
		"machines",
		"机器",
		maxi(0, int(machines.get("machine_count", 0))),
		_first_positive_int(
			machines,
			["machine_limit", "max_machine_count", "maximum"],
			DEFAULT_MACHINE_BUDGET
		),
		"持久机器"
	))
	rows.append(_machine_domain_row(machines))
	rows.append(_agriculture_row(agriculture))
	rows.append(_usage_row(
		"husbandry",
		"畜牧",
		maxi(0, int(husbandry.get("managed_animals", 0))),
		maxi(0, int(husbandry.get("maximum", 0))),
		"管理动物"
	))
	rows.append(_ranch_row(attraction, products))
	rows.append(_ecology_row(ecology))
	rows.append(_pickup_row(pickups))
	rows.append(_structural_row(structural))
	rows.append(_catalog_row(catalog))
	rows.append(_save_row(save))

	rows.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_severity := int(first.get("severity", 0))
			var second_severity := int(second.get("severity", 0))
			if first_severity != second_severity:
				return first_severity > second_severity
			var first_ratio := float(first.get("usage_ratio", 0.0))
			var second_ratio := float(second.get("usage_ratio", 0.0))
			if not is_equal_approx(first_ratio, second_ratio):
				return first_ratio > second_ratio
			return str(first.get("id", "")) < str(second.get("id", ""))
	)
	while rows.size() > MAX_ROWS:
		rows.pop_back()

	var severity := 0
	var warning_count := 0
	var critical_count := 0
	var issues: Array[String] = []
	for row: Dictionary in rows:
		var row_severity := clampi(int(row.get("severity", 0)), 0, 2)
		severity = maxi(severity, row_severity)
		if row_severity == 1:
			warning_count += 1
		elif row_severity >= 2:
			critical_count += 1
		var issue := str(row.get("issue", "")).strip_edges()
		if row_severity > 0 and not issue.is_empty() and issues.size() < MAX_ISSUES:
			issues.append(issue)

	var primary := _primary_bottleneck(rows)
	return {
		"schema_version": 1,
		"status": _status_for_severity(severity),
		"severity": severity,
		"healthy": severity == 0,
		"primary_bottleneck": primary,
		"rows": _duplicate_rows(rows),
		"row_count": rows.size(),
		"warning_count": warning_count,
		"critical_count": critical_count,
		"issues": issues,
		"save": save,
		"catalog": catalog,
		"row_limit": MAX_ROWS,
		"issue_limit": MAX_ISSUES,
	}


static func _machine_domain_row(machines: Dictionary) -> Dictionary:
	var current := maxi(0, int(machines.get("domain_count", 0)))
	var detail := "%d 个调度领域 · %d 台机器" % [
		current,
		maxi(0, int(machines.get("machine_count", 0))),
	]
	return _usage_row(
		"machine_domains",
		"机器调度",
		current,
		_first_positive_int(
			machines,
			["domain_limit", "max_domains"],
			DEFAULT_MACHINE_DOMAIN_BUDGET
		),
		detail
	)


static func _agriculture_row(snapshot: Dictionary) -> Dictionary:
	var batch := _dictionary(snapshot.get("world_mutation_batch", {}))
	var rejection_count := maxi(0, int(batch.get("rejection_count", 0)))
	var unsupported_count := maxi(0, int(batch.get("unsupported_count", 0)))
	var severity := 0
	var issue := ""
	if rejection_count > 0:
		severity = 1
		issue = "农业世界批处理出现 %d 次拒绝" % rejection_count
	elif unsupported_count > 0:
		severity = 1
		issue = "农业世界批处理有 %d 次不受支持回退" % unsupported_count
	return _informational_row(
		"agriculture",
		"农业",
		"作物 %d · 成熟 %d · 土壤 %d" % [
			maxi(0, int(snapshot.get("crop_count", 0))),
			maxi(0, int(snapshot.get("mature_crop_count", 0))),
			maxi(0, int(snapshot.get("soil_count", 0))),
		],
		severity,
		issue
	)


static func _ranch_row(attraction: Dictionary, products: Dictionary) -> Dictionary:
	return _informational_row(
		"ranch",
		"牧场",
		"跟随 %d · 产物记录 %d · 待生成 %d" % [
			maxi(0, int(attraction.get("following", 0))),
			maxi(0, int(products.get("tracked_animals", 0))),
			maxi(0, int(products.get("pending_products", 0))),
		]
	)


static func _ecology_row(snapshot: Dictionary) -> Dictionary:
	var current := (
		maxi(0, int(snapshot.get("passive_count", 0)))
		+ maxi(0, int(snapshot.get("hostile_count", 0)))
	)
	var limit := (
		maxi(0, int(snapshot.get("passive_cap", 0)))
		+ maxi(0, int(snapshot.get("hostile_cap", 0)))
	)
	return _usage_row(
		"ecology",
		"生态",
		current,
		limit,
		"被动 %d/%d · 敌对 %d/%d" % [
			maxi(0, int(snapshot.get("passive_count", 0))),
			maxi(0, int(snapshot.get("passive_cap", 0))),
			maxi(0, int(snapshot.get("hostile_count", 0))),
			maxi(0, int(snapshot.get("hostile_cap", 0))),
		]
	)


static func _pickup_row(snapshot: Dictionary) -> Dictionary:
	var row := _usage_row(
		"pickups",
		"物理掉落",
		maxi(0, int(snapshot.get("pickup_node_count", 0))),
		maxi(0, int(snapshot.get("max_pickup_nodes", 0))),
		"可见物品 %d · 待物化 %d" % [
			maxi(0, int(snapshot.get("visible_item_total", 0))),
			maxi(0, int(snapshot.get("pending_item_total", 0))),
		]
	)
	var rejection_count := maxi(0, int(snapshot.get("pending_type_rejection_count", 0)))
	var deferral_count := maxi(0, int(snapshot.get("budget_deferral_count", 0)))
	if rejection_count > 0:
		_apply_override(row, 2, "物理掉落类型队列拒绝 %d 次" % rejection_count)
	elif deferral_count > 0:
		_apply_override(row, 1, "物理掉落因节点预算延后 %d 次" % deferral_count)
	return row


static func _structural_row(snapshot: Dictionary) -> Dictionary:
	var row := _usage_row(
		"structural_integrity",
		"结构完整性",
		maxi(0, int(snapshot.get("pending_candidates", 0))),
		maxi(0, int(snapshot.get("candidate_queue_budget", 0))),
		"已清理 %d · 物品回退 %d" % [
			maxi(0, int(snapshot.get("removed_structure_count", 0))),
			maxi(0, int(snapshot.get("pickup_drop_count", 0))),
		]
	)
	var overflow_count := maxi(0, int(snapshot.get("candidate_overflow_count", 0)))
	var truncated_count := maxi(0, int(snapshot.get("initial_override_truncated_count", 0)))
	if overflow_count > 0:
		_apply_override(row, 2, "结构候选队列溢出 %d 次" % overflow_count)
	elif truncated_count > 0:
		_apply_override(row, 1, "旧世界结构扫描截断 %d 次" % truncated_count)
	return row


static func _catalog_row(catalog: Dictionary) -> Dictionary:
	var severity := 0
	var issue := ""
	var write_failures := maxi(0, int(catalog.get("write_failure_count", 0)))
	var fallback_count := maxi(0, int(catalog.get("last_fallback_count", 0)))
	var repair_count := maxi(0, int(catalog.get("last_repair_count", 0)))
	var deferred_count := maxi(0, int(catalog.get("last_deferred_recovery_count", 0)))
	var repair_budget := maxi(0, int(catalog.get("primary_repair_budget", 0)))
	if write_failures > 0:
		severity = 1
		issue = "轻量世界目录写入失败累计 %d 次" % write_failures
	elif deferred_count > 0:
		severity = 1
		issue = "世界目录仍有 %d 个存档待渐进修复（每次最多 %d）" % [deferred_count, repair_budget]
	elif fallback_count > 0:
		severity = 1
		issue = "世界目录本次回退 %d 个并自愈 %d 个" % [fallback_count, repair_count]
	return _informational_row(
		"catalog",
		"世界目录",
		"命中 %d/%d · 回退 %d · 修复 %d · 待修复 %d · %.2f ms" % [
			maxi(0, int(catalog.get("last_hit_count", 0))),
			maxi(0, int(catalog.get("last_world_count", 0))),
			fallback_count,
			repair_count,
			deferred_count,
			float(catalog.get("last_elapsed_milliseconds", 0.0)),
		],
		severity,
		issue
	)


static func _save_row(save: Dictionary) -> Dictionary:
	var attempts := maxi(0, int(save.get("attempt_count", 0)))
	var recovery_count := maxi(0, int(save.get("recovery_count", 0)))
	var repair_successes := maxi(0, int(save.get("repair_success_count", 0)))
	var repair_failures := maxi(0, int(save.get("repair_failure_count", 0)))
	if attempts <= 0 and recovery_count <= 0:
		return _informational_row("save", "保存", "本会话尚未保存或恢复")
	var detail_parts: Array[String] = []
	if attempts > 0:
		detail_parts.append("%s · %.2f ms · %s" % [
			_format_bytes(maxi(0, int(save.get("last_bytes", 0)))),
			float(save.get("last_elapsed_milliseconds", 0.0)),
			str(save.get("last_world_id", "")),
		])
	if recovery_count > 0:
		detail_parts.append("恢复 %d · 主文件修复 %d/%d · %s · %.2f ms" % [
			recovery_count,
			repair_successes,
			repair_failures,
			str(save.get("last_recovery_source", "unknown")),
			float(save.get("last_recovery_elapsed_milliseconds", 0.0)),
		])
	var detail := " · ".join(detail_parts)
	if repair_failures > 0:
		return _informational_row(
			"save",
			"保存",
			detail,
			2,
			"存档已从恢复候选读取，但主文件重建失败 %d 次" % repair_failures
		)
	if attempts > 0 and not bool(save.get("last_success", false)):
		return _informational_row(
			"save",
			"保存",
			detail,
			2,
			"最近一次世界保存失败"
		)
	if recovery_count > 0:
		var source := str(save.get("last_recovery_source", "恢复候选"))
		var issue := (
			"已从 %s 恢复并重建主存档" % source
			if repair_successes > 0
			else "本会话发生 %d 次存档恢复" % recovery_count
		)
		return _informational_row("save", "保存", detail, 1, issue)
	return _informational_row("save", "保存", detail)


static func _usage_row(
	id: String,
	label: String,
	current: int,
	limit: int,
	detail: String
) -> Dictionary:
	var safe_current := maxi(0, current)
	var safe_limit := maxi(0, limit)
	var ratio := (
		clampf(float(safe_current) / float(safe_limit), 0.0, 99.0)
		if safe_limit > 0
		else 0.0
	)
	var severity := _severity_for_ratio(ratio) if safe_limit > 0 else 0
	var issue := ""
	if severity > 0:
		issue = "%s使用率 %.1f%%（%d/%d）" % [
			label,
			ratio * 100.0,
			safe_current,
			safe_limit,
		]
	return {
		"id": id,
		"label": label,
		"current": safe_current,
		"limit": safe_limit,
		"usage_ratio": ratio,
		"usage_percent": ratio * 100.0,
		"status": _status_for_severity(severity),
		"severity": severity,
		"detail": detail.left(160),
		"issue": issue.left(180),
	}


static func _informational_row(
	id: String,
	label: String,
	detail: String,
	severity: int = 0,
	issue: String = ""
) -> Dictionary:
	var safe_severity := clampi(severity, 0, 2)
	return {
		"id": id,
		"label": label,
		"current": 0,
		"limit": 0,
		"usage_ratio": 0.0,
		"usage_percent": 0.0,
		"status": _status_for_severity(safe_severity),
		"severity": safe_severity,
		"detail": detail.left(160),
		"issue": issue.left(180),
	}


static func _apply_override(row: Dictionary, severity: int, issue: String) -> void:
	var safe_severity := clampi(severity, 0, 2)
	if safe_severity < int(row.get("severity", 0)):
		return
	row["severity"] = safe_severity
	row["status"] = _status_for_severity(safe_severity)
	row["issue"] = issue.left(180)


static func _project_save(snapshot: Dictionary) -> Dictionary:
	return {
		"attempt_count": maxi(0, int(snapshot.get("attempt_count", 0))),
		"success_count": maxi(0, int(snapshot.get("success_count", 0))),
		"failure_count": maxi(0, int(snapshot.get("failure_count", 0))),
		"recovery_count": maxi(0, int(snapshot.get("recovery_count", 0))),
		"repair_attempt_count": maxi(0, int(snapshot.get("repair_attempt_count", 0))),
		"repair_success_count": maxi(0, int(snapshot.get("repair_success_count", 0))),
		"repair_failure_count": maxi(0, int(snapshot.get("repair_failure_count", 0))),
		"primary_rejection_count": maxi(
			0, int(snapshot.get("primary_rejection_count", 0))
		),
		"last_recovery_source": str(snapshot.get("last_recovery_source", "")).left(32),
		"last_recovery_repaired": bool(snapshot.get("last_recovery_repaired", false)),
		"last_recovery_bytes": maxi(0, int(snapshot.get("last_recovery_bytes", 0))),
		"last_recovery_elapsed_milliseconds": maxf(
			0.0, float(snapshot.get("last_recovery_elapsed_milliseconds", 0.0))
		),
		"last_success": bool(snapshot.get("last_success", false)),
		"last_world_id": str(snapshot.get("last_world_id", "")).left(128),
		"last_bytes": maxi(0, int(snapshot.get("last_bytes", 0))),
		"last_elapsed_usec": maxi(0, int(snapshot.get("last_elapsed_usec", 0))),
		"last_elapsed_milliseconds": maxf(
			0.0, float(snapshot.get("last_elapsed_milliseconds", 0.0))
		),
		"last_timestamp_msec": maxi(0, int(snapshot.get("last_timestamp_msec", 0))),
	}


static func _project_catalog(snapshot: Dictionary) -> Dictionary:
	return {
		"list_count": maxi(0, int(snapshot.get("list_count", 0))),
		"hit_count": maxi(0, int(snapshot.get("hit_count", 0))),
		"fallback_count": maxi(0, int(snapshot.get("fallback_count", 0))),
		"repair_count": maxi(0, int(snapshot.get("repair_count", 0))),
		"write_failure_count": maxi(0, int(snapshot.get("write_failure_count", 0))),
		"last_world_count": maxi(0, int(snapshot.get("last_world_count", 0))),
		"last_hit_count": maxi(0, int(snapshot.get("last_hit_count", 0))),
		"last_fallback_count": maxi(0, int(snapshot.get("last_fallback_count", 0))),
		"last_repair_count": maxi(0, int(snapshot.get("last_repair_count", 0))),
		"last_avoided_world_bytes": maxi(
			0, int(snapshot.get("last_avoided_world_bytes", 0))
		),
		"last_elapsed_milliseconds": maxf(
			0.0, float(snapshot.get("last_elapsed_milliseconds", 0.0))
		),
		"last_hit_ratio": clampf(float(snapshot.get("last_hit_ratio", 0.0)), 0.0, 1.0),
		"primary_repair_budget": maxi(0, int(snapshot.get("primary_repair_budget", 0))),
		"last_deferred_recovery_count": maxi(0, int(snapshot.get("last_deferred_recovery_count", 0))),
		"last_repair_budget_used": maxi(0, int(snapshot.get("last_repair_budget_used", 0))),
	}


static func _primary_bottleneck(rows: Array[Dictionary]) -> Dictionary:
	if rows.is_empty():
		return {
			"id": "none",
			"label": "无",
			"status": STATUS_HEALTHY,
			"severity": 0,
			"usage_percent": 0.0,
			"detail": "尚无可用运行数据",
			"message": "尚无可用运行数据",
		}
	var row: Dictionary = rows[0]
	var issue := str(row.get("issue", "")).strip_edges()
	var detail := str(row.get("detail", "")).strip_edges()
	var message := issue if not issue.is_empty() else "%s：%s" % [
		str(row.get("label", "运行域")),
		detail if not detail.is_empty() else "当前占用最高",
	]
	return {
		"id": str(row.get("id", "unknown")),
		"label": str(row.get("label", "运行域")),
		"status": str(row.get("status", STATUS_HEALTHY)),
		"severity": clampi(int(row.get("severity", 0)), 0, 2),
		"usage_percent": maxf(0.0, float(row.get("usage_percent", 0.0))),
		"detail": detail.left(160),
		"message": message.left(200),
	}


static func _duplicate_rows(rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in rows:
		result.append(row.duplicate(true))
	return result


static func _severity_for_ratio(ratio: float) -> int:
	if ratio >= CRITICAL_USAGE_RATIO:
		return 2
	if ratio >= WARNING_USAGE_RATIO:
		return 1
	return 0


static func _status_for_severity(severity: int) -> String:
	if severity >= 2:
		return STATUS_CRITICAL
	if severity == 1:
		return STATUS_WARNING
	return STATUS_HEALTHY


static func _first_positive_int(
	snapshot: Dictionary,
	keys: Array[String],
	fallback: int
) -> int:
	for key: String in keys:
		var value := int(snapshot.get(key, 0))
		if value > 0:
			return value
	return maxi(0, fallback)


static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _format_bytes(value: int) -> String:
	var safe_value := maxi(0, value)
	if safe_value >= 1048576:
		return "%.2f MiB" % (float(safe_value) / 1048576.0)
	if safe_value >= 1024:
		return "%.1f KiB" % (float(safe_value) / 1024.0)
	return "%d B" % safe_value
