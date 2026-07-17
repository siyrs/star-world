class_name ProspectingService
extends Node

signal scan_completed(result: Dictionary)
signal scan_rejected(reason: String, context: Dictionary)

const RegistryScript = preload("res://src/exploration/prospecting_registry.gd")
const PolicyScript = preload("res://src/exploration/prospecting_policy.gd")
const StateMigrationScript = preload("res://src/exploration/prospecting_state_migration.gd")

var registry = RegistryScript.new()
var item_registry: Variant
var danger_service: Node
var world: Node
var player: Node3D
var _records: Dictionary = {}
var _record_order: Array[String] = []
var _last_result: Dictionary = {}
var _last_scan_msec := -1


func setup(p_item_registry: Variant, p_danger_service: Node = null) -> bool:
	item_registry = p_item_registry
	danger_service = p_danger_service
	return registry.get_validation_errors().is_empty() and registry.validate_item_registry(item_registry)


func set_danger_service(service: Node) -> void:
	danger_service = service


func attach_world(p_world: Node, p_player: Node3D) -> void:
	world = p_world
	player = p_player
	_last_scan_msec = -1


func use_item(item_id: String, now_msec: int = -1) -> Dictionary:
	if item_id != registry.get_tool_item_id():
		return {"handled": false, "success": false}
	if world == null or player == null or not is_instance_valid(world) or not is_instance_valid(player):
		return _reject("runtime_unavailable", "当前世界还没有准备好，暂时无法勘探")
	var current_msec := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var config := registry.get_config()
	var cooldown_msec := roundi(maxf(0.0, float(config.get("cooldown_seconds", 0.0))) * 1000.0)
	if _last_scan_msec >= 0 and current_msec - _last_scan_msec < cooldown_msec:
		var remaining := float(cooldown_msec - (current_msec - _last_scan_msec)) / 1000.0
		return _reject(
			"cooldown",
			"探矿仪正在校准，请等待 %.1f 秒" % maxf(0.1, remaining),
			{"remaining_seconds": remaining}
		)
	var result := _scan(config, current_msec)
	if not bool(result.get("success", false)):
		return result
	_last_scan_msec = current_msec
	_store_record(result)
	_last_result = result.duplicate(true)
	scan_completed.emit(result.duplicate(true))
	return result


func serialize() -> Dictionary:
	var records: Array[Dictionary] = []
	for record_key: String in _record_order:
		var raw_record: Variant = _records.get(record_key, {})
		if raw_record is Dictionary and not raw_record.is_empty():
			records.append(raw_record.duplicate(true))
	return {
		"version": StateMigrationScript.VERSION,
		"records": records,
		"last_result": _last_result.duplicate(true),
	}


func deserialize(raw_state: Variant) -> void:
	_records.clear()
	_record_order.clear()
	_last_result.clear()
	_last_scan_msec = -1
	var state := StateMigrationScript.normalize_exploration_state(raw_state)
	var max_records := maxi(1, int(registry.get_config().get("max_records", 64)))
	var raw_records: Variant = state.get("records", [])
	if raw_records is Array:
		var start_index := maxi(0, raw_records.size() - max_records)
		for index in range(start_index, raw_records.size()):
			var raw_record: Variant = raw_records[index]
			if raw_record is not Dictionary:
				continue
			var record: Dictionary = raw_record
			var record_key := str(record.get("record_key", ""))
			if record_key.is_empty():
				continue
			_records[record_key] = record.duplicate(true)
			_record_order.append(record_key)
	var raw_last: Variant = state.get("last_result", {})
	if raw_last is Dictionary:
		_last_result = raw_last.duplicate(true)


func clear() -> void:
	world = null
	player = null
	_records.clear()
	_record_order.clear()
	_last_result.clear()
	_last_scan_msec = -1


func get_snapshot() -> Dictionary:
	return {
		"record_count": _record_order.size(),
		"record_keys": _record_order.duplicate(),
		"last_result": _last_result.duplicate(true),
		"tool_item_id": registry.get_tool_item_id(),
	}


func get_record(record_key: String) -> Dictionary:
	var raw_record: Variant = _records.get(record_key, {})
	return raw_record.duplicate(true) if raw_record is Dictionary else {}


func get_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record_key: String in _record_order:
		var record := get_record(record_key)
		if not record.is_empty():
			result.append(record)
	return result


func _scan(config: Dictionary, current_msec: int) -> Dictionary:
	if not world.has_method("world_to_block") or not world.has_method("get_initial_block"):
		return _reject("world_contract", "当前世界不支持区域勘探")
	var center: Vector3i = world.call("world_to_block", player.global_position)
	var horizontal_radius := maxi(1, int(config.get("horizontal_radius", 6)))
	var vertical_radius := maxi(1, int(config.get("vertical_radius", 12)))
	var horizontal_step := maxi(1, int(config.get("horizontal_step", 2)))
	var vertical_step := maxi(1, int(config.get("vertical_step", 2)))
	var max_samples := maxi(1, int(config.get("max_samples", 700)))
	var geology_blocks: Array = config.get("geology_blocks", [])
	var ore_profiles: Array = config.get("ore_blocks", [])
	var ore_ids: Array[String] = []
	var counts: Dictionary = {}
	for raw_profile in ore_profiles:
		if raw_profile is not Dictionary:
			continue
		var block_id := str(raw_profile.get("block_id", ""))
		if block_id.is_empty():
			continue
		ore_ids.append(block_id)
		counts[block_id] = 0
	var total_samples := 0
	var geology_samples := 0
	var exhausted := false
	var minimum_y := maxi(1, center.y - vertical_radius)
	var maximum_y := mini(63, center.y + vertical_radius)
	for x in range(center.x - horizontal_radius, center.x + horizontal_radius + 1, horizontal_step):
		for z in range(center.z - horizontal_radius, center.z + horizontal_radius + 1, horizontal_step):
			for y in range(minimum_y, maximum_y + 1, vertical_step):
				if total_samples >= max_samples:
					exhausted = true
					break
				var block_id := str(world.call("get_initial_block", Vector3i(x, y, z)))
				total_samples += 1
				if block_id not in geology_blocks:
					continue
				geology_samples += 1
				if block_id in ore_ids:
					counts[block_id] = int(counts.get(block_id, 0)) + 1
			if exhausted:
				break
		if exhausted:
			break
	var minimum_geology := maxi(1, int(config.get("minimum_geology_samples", 24)))
	if geology_samples < minimum_geology:
		return _reject(
			"insufficient_geology",
			"岩层样本不足；请靠近地面、洞穴或更低深度后重试",
			{
				"sample_count": total_samples,
				"geology_samples": geology_samples,
			}
		)
	var profile_id := str(world.get("profile_id"))
	var summary := PolicyScript.summarize(
		counts,
		geology_samples,
		total_samples,
		center.y,
		profile_id,
		config
	)
	_apply_danger_snapshot(summary)
	var chunk_coord := _resolve_chunk_coord(center)
	var record_key := PolicyScript.record_key(
		chunk_coord, str(summary.get("depth_band_id", "unknown"))
	)
	summary["handled"] = true
	summary["success"] = true
	summary["record_key"] = record_key
	summary["chunk"] = [chunk_coord.x, chunk_coord.y]
	summary["scanned_at_msec"] = maxi(0, current_msec)
	return summary


func _apply_danger_snapshot(summary: Dictionary) -> void:
	if danger_service == null or not danger_service.has_method("get_snapshot"):
		return
	var raw_danger: Variant = danger_service.call("get_snapshot")
	if raw_danger is not Dictionary or raw_danger.is_empty():
		if danger_service.has_method("refresh_now"):
			raw_danger = danger_service.call("refresh_now")
	if raw_danger is not Dictionary or raw_danger.is_empty():
		return
	var danger: Dictionary = raw_danger
	summary["danger_tier_id"] = str(danger.get("tier_id", "safe"))
	summary["danger_label"] = str(danger.get("tier_label", "低"))
	summary["danger_score"] = clampi(int(danger.get("score", 0)), 0, 100)
	var raw_reasons: Variant = danger.get("reasons", [])
	summary["danger_reasons"] = raw_reasons.duplicate() if raw_reasons is Array else []
	summary["message"] = "%s · 当前危险：%s" % [
		str(summary.get("message", "区域勘探完成")),
		str(danger.get("tier_label", "低")),
	]


func _resolve_chunk_coord(center: Vector3i) -> Vector2i:
	if world != null and world.has_method("block_to_chunk"):
		return world.call("block_to_chunk", center)
	return Vector2i(floori(float(center.x) / 16.0), floori(float(center.z) / 16.0))


func _store_record(result: Dictionary) -> void:
	var record_key := str(result.get("record_key", ""))
	if record_key.is_empty():
		return
	if record_key in _record_order:
		_record_order.erase(record_key)
	_records[record_key] = _record_from_result(result)
	_record_order.append(record_key)
	var max_records := maxi(1, int(registry.get_config().get("max_records", 64)))
	while _record_order.size() > max_records:
		var expired_key := str(_record_order.pop_front())
		_records.erase(expired_key)


func _record_from_result(result: Dictionary) -> Dictionary:
	var raw_chunk: Variant = result.get("chunk", [])
	var chunk: Array = raw_chunk.duplicate() if raw_chunk is Array else []
	var raw_reasons: Variant = result.get("danger_reasons", [])
	var danger_reasons: Array = raw_reasons.duplicate() if raw_reasons is Array else []
	return {
		"record_key": str(result.get("record_key", "")),
		"chunk": chunk,
		"profile_id": str(result.get("profile_id", "star_continent")),
		"depth_band_id": str(result.get("depth_band_id", "unknown")),
		"depth_label": str(result.get("depth_label", "未知")),
		"density_id": str(result.get("density_id", "unknown")),
		"density_label": str(result.get("density_label", "未知")),
		"ore_ratio": clampf(float(result.get("ore_ratio", 0.0)), 0.0, 1.0),
		"dominant_block_id": str(result.get("dominant_block_id", "")),
		"dominant_label": str(result.get("dominant_label", "")),
		"danger_tier_id": str(result.get("danger_tier_id", "unknown")),
		"danger_label": str(result.get("danger_label", "未知")),
		"danger_score": clampi(int(result.get("danger_score", 0)), 0, 100),
		"danger_reasons": danger_reasons,
		"message": str(result.get("message", "")),
		"scanned_at_msec": maxi(0, int(result.get("scanned_at_msec", 0))),
	}


func _reject(reason: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var context := extra.duplicate(true)
	context["handled"] = true
	context["success"] = false
	context["reason"] = reason
	context["message"] = message
	scan_rejected.emit(reason, context.duplicate(true))
	return context
