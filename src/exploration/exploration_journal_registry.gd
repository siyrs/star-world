class_name ExplorationJournalRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/exploration_journal.json"
const ALLOWED_KINDS: Array[String] = [
	"record_count",
	"unique_chunks",
	"depth_band",
	"density",
	"danger_tier",
	"depth_band_count",
]

var schema_version := 0
var max_visible_records := 24
var _milestones: Array[Dictionary] = []
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	schema_version = 0
	max_visible_records = 24
	_milestones.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_record_error("Exploration journal data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open exploration journal data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Exploration journal data must be an object: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = int(data.get("schema_version", 0))
	max_visible_records = clampi(int(data.get("max_visible_records", 24)), 1, 64)
	if schema_version != 1:
		_record_error("Unsupported exploration journal schema_version: %d" % schema_version)
	var raw_milestones: Variant = data.get("milestones", [])
	if raw_milestones is not Array:
		_record_error("Exploration journal milestones must be an array")
		return false
	var seen_ids: Dictionary = {}
	for raw_milestone: Variant in raw_milestones:
		if raw_milestone is not Dictionary:
			_record_error("Exploration journal milestone must be an object")
			continue
		var milestone: Dictionary = raw_milestone
		var milestone_id := str(milestone.get("id", "")).strip_edges()
		var milestone_name := str(milestone.get("name", "")).strip_edges()
		var description := str(milestone.get("description", "")).strip_edges()
		var kind := str(milestone.get("kind", "")).strip_edges()
		if milestone_id.is_empty() or milestone_name.is_empty() or description.is_empty():
			_record_error("Exploration journal milestone has empty identity text")
			continue
		if seen_ids.has(milestone_id):
			_record_error("Duplicate exploration journal milestone: %s" % milestone_id)
			continue
		if kind not in ALLOWED_KINDS:
			_record_error("Unsupported exploration journal milestone kind '%s': %s" % [kind, milestone_id])
			continue
		var normalized := {
			"id": milestone_id,
			"name": milestone_name,
			"description": description,
			"kind": kind,
		}
		match kind:
			"record_count", "unique_chunks", "depth_band_count":
				var threshold := int(milestone.get("threshold", 0))
				if threshold < 1 or threshold > 64:
					_record_error("Invalid exploration journal threshold for %s" % milestone_id)
					continue
				normalized["threshold"] = threshold
			"depth_band", "density":
				var value := str(milestone.get("value", "")).strip_edges()
				if value.is_empty():
					_record_error("Exploration journal milestone value is empty: %s" % milestone_id)
					continue
				normalized["value"] = value
			"danger_tier":
				var raw_values: Variant = milestone.get("values", [])
				var values: Array[String] = []
				if raw_values is Array:
					for raw_value: Variant in raw_values:
						var value := str(raw_value).strip_edges()
						if not value.is_empty() and value not in values:
							values.append(value)
				if values.is_empty():
					_record_error("Exploration journal danger milestone has no tiers: %s" % milestone_id)
					continue
				normalized["values"] = values
		seen_ids[milestone_id] = true
		_milestones.append(normalized)
	if _milestones.is_empty():
		_record_error("Exploration journal contains no valid milestones")
	return _validation_errors.is_empty()


func get_config() -> Dictionary:
	return {
		"schema_version": schema_version,
		"max_visible_records": max_visible_records,
		"milestones": get_milestones(),
	}


func get_milestones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for milestone: Dictionary in _milestones:
		result.append(milestone.duplicate(true))
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _install_fallback() -> void:
	schema_version = 1
	max_visible_records = 24
	_milestones = [
		{
			"id":"first_discovery",
			"name":"初次勘探",
			"description":"保存第一条区域发现。",
			"kind":"record_count",
			"threshold":1,
		},
		{
			"id":"three_regions",
			"name":"踏勘者",
			"description":"记录三个不同区块。",
			"kind":"unique_chunks",
			"threshold":3,
		},
	]


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
