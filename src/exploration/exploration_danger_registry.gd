class_name ExplorationDangerRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/exploration_danger.json"

var schema_version := 0
var _config: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_config.clear()
	_validation_errors.clear()
	schema_version = 0
	if not FileAccess.file_exists(path):
		_record_error("Exploration danger data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open exploration danger data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Exploration danger root must be an object")
		return false
	var raw: Dictionary = parsed
	schema_version = int(raw.get("schema_version", 0))
	if schema_version != 1:
		_record_error("Unsupported exploration danger schema_version: %d" % schema_version)
	_config = _normalize(raw)
	return _validation_errors.is_empty()


func get_config() -> Dictionary:
	return _config.duplicate(true)


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize(raw: Dictionary) -> Dictionary:
	var horizontal_radius := clampi(int(raw.get("horizontal_radius", 4)), 1, 12)
	var vertical_radius := clampi(int(raw.get("vertical_radius", 4)), 1, 12)
	var horizontal_step := clampi(int(raw.get("horizontal_step", 2)), 1, 6)
	var vertical_step := clampi(int(raw.get("vertical_step", 2)), 1, 6)
	var maximum_samples := clampi(int(raw.get("max_samples", 125)), 1, 512)
	var theoretical := (
		(ceili(float(horizontal_radius * 2 + 1) / float(horizontal_step)))
		* (ceili(float(horizontal_radius * 2 + 1) / float(horizontal_step)))
		* (ceili(float(vertical_radius * 2 + 1) / float(vertical_step)))
	)
	if theoretical > maximum_samples:
		_record_error(
			"Danger sampling contract exceeds max_samples: %d > %d" % [theoretical, maximum_samples]
		)
	var depth_scores := _normalize_depth_scores(raw.get("depth_scores", []))
	var cave_thresholds := _normalize_cave_thresholds(raw.get("cave_open_thresholds", []))
	var tiers := _normalize_tiers(raw.get("tiers", []))
	var phases := {"day":0, "dawn":0, "dusk":0, "night":0}
	var raw_phases: Variant = raw.get("phase_scores", {})
	if raw_phases is Dictionary:
		for phase: String in phases.keys():
			phases[phase] = clampi(int(raw_phases.get(phase, 0)), 0, 40)
	return {
		"assessment_interval_seconds": clampf(
			float(raw.get("assessment_interval_seconds", 0.75)), 0.25, 5.0
		),
		"horizontal_radius": horizontal_radius,
		"vertical_radius": vertical_radius,
		"horizontal_step": horizontal_step,
		"vertical_step": vertical_step,
		"max_samples": maximum_samples,
		"hostile_radius": clampf(float(raw.get("hostile_radius", 18.0)), 4.0, 48.0),
		"depth_scores": depth_scores,
		"phase_scores": phases,
		"hostile_score_each": clampi(int(raw.get("hostile_score_each", 12)), 0, 30),
		"hostile_score_cap": clampi(int(raw.get("hostile_score_cap", 30)), 0, 60),
		"lava_score_each": clampi(int(raw.get("lava_score_each", 5)), 0, 30),
		"lava_score_cap": clampi(int(raw.get("lava_score_cap", 20)), 0, 60),
		"cave_open_thresholds": cave_thresholds,
		"tiers": tiers,
	}


func _normalize_depth_scores(raw_entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_entries is not Array:
		_record_error("Danger depth_scores must be an array")
		return result
	var previous_max := -1
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			continue
		var maximum_y := clampi(int(raw_entry.get("max_y", -1)), 0, 63)
		if maximum_y <= previous_max:
			_record_error("Danger depth_scores must be ordered by max_y")
			continue
		previous_max = maximum_y
		result.append({
			"max_y": maximum_y,
			"score": clampi(int(raw_entry.get("score", 0)), 0, 50),
			"label": str(raw_entry.get("label", "深度")),
		})
	if result.is_empty() or int(result.back().get("max_y", -1)) < 63:
		_record_error("Danger depth_scores must cover world height through Y63")
	return result


func _normalize_cave_thresholds(raw_entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_entries is not Array:
		_record_error("Danger cave thresholds must be an array")
		return result
	var previous_ratio := 2.0
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			continue
		var ratio := clampf(float(raw_entry.get("minimum_ratio", 0.0)), 0.0, 1.0)
		if ratio >= previous_ratio:
			_record_error("Danger cave thresholds must be ordered from high to low ratio")
			continue
		previous_ratio = ratio
		result.append({
			"minimum_ratio":ratio,
			"score":clampi(int(raw_entry.get("score", 0)), 0, 40),
			"label":str(raw_entry.get("label", "洞穴")),
		})
	return result


func _normalize_tiers(raw_entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_entries is not Array:
		_record_error("Danger tiers must be an array")
		return result
	var previous_max := -1
	var seen: Dictionary = {}
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			continue
		var tier_id := str(raw_entry.get("id", "")).strip_edges()
		var maximum := clampi(int(raw_entry.get("max_score", 0)), 0, 100)
		if tier_id.is_empty() or seen.has(tier_id):
			_record_error("Danger tier id is empty or duplicated")
			continue
		if maximum <= previous_max:
			_record_error("Danger tiers must have increasing max_score")
			continue
		seen[tier_id] = true
		previous_max = maximum
		result.append({
			"id":tier_id,
			"label":str(raw_entry.get("label", tier_id)),
			"max_score":maximum,
			"tone":str(raw_entry.get("tone", "info")),
		})
	if result.is_empty() or int(result.back().get("max_score", 0)) < 100:
		_record_error("Danger tiers must cover score 100")
	return result


func _install_fallback() -> void:
	schema_version = 1
	_config = {
		"assessment_interval_seconds":0.75,
		"horizontal_radius":4,
		"vertical_radius":4,
		"horizontal_step":2,
		"vertical_step":2,
		"max_samples":125,
		"hostile_radius":18.0,
		"depth_scores":[{"max_y":10,"score":28,"label":"极深层"},{"max_y":20,"score":20,"label":"深层"},{"max_y":32,"score":12,"label":"下层"},{"max_y":63,"score":4,"label":"浅层"}],
		"phase_scores":{"day":0,"dawn":4,"dusk":10,"night":18},
		"hostile_score_each":12,
		"hostile_score_cap":30,
		"lava_score_each":5,
		"lava_score_cap":20,
		"cave_open_thresholds":[{"minimum_ratio":0.45,"score":15,"label":"大型空洞"},{"minimum_ratio":0.25,"score":8,"label":"洞穴环境"}],
		"tiers":[{"id":"safe","label":"低","max_score":19,"tone":"success"},{"id":"guarded","label":"警戒","max_score":39,"tone":"info"},{"id":"dangerous","label":"危险","max_score":64,"tone":"warning"},{"id":"severe","label":"极高","max_score":100,"tone":"error"}],
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
