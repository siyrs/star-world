class_name SoilMoisturePolicy
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/soil_moisture.json"

var schema_version: int = 0
var dry_block: String = "farmland"
var wet_block: String = "farmland_wet"
var water_blocks: Array[String] = ["water"]
var horizontal_radius: int = 4
var vertical_radius: int = 1
var manual_hydration_seconds: float = 180.0
var dry_growth_multiplier: float = 0.35
var wet_growth_multiplier: float = 1.0
var refresh_interval_seconds: float = 1.0
var max_refresh_per_tick: int = 8


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Soil moisture policy is missing: %s" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open soil moisture policy: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Invalid soil moisture policy JSON: %s" % path)
		return false
	var data: Dictionary = parsed
	var parsed_dry_block: String = str(data.get("dry_block", dry_block)).strip_edges()
	var parsed_wet_block: String = str(data.get("wet_block", wet_block)).strip_edges()
	if parsed_dry_block.is_empty() or parsed_wet_block.is_empty():
		push_error("Soil moisture policy requires dry and wet block ids")
		return false
	var parsed_water_blocks: Array[String] = []
	var raw_water_blocks: Variant = data.get("water_blocks", [])
	if raw_water_blocks is Array:
		for raw_block: Variant in raw_water_blocks:
			var block_id: String = str(raw_block).strip_edges()
			if not block_id.is_empty() and block_id not in parsed_water_blocks:
				parsed_water_blocks.append(block_id)
	if parsed_water_blocks.is_empty():
		push_error("Soil moisture policy requires at least one water block")
		return false
	schema_version = maxi(1, int(data.get("schema_version", 1)))
	dry_block = parsed_dry_block
	wet_block = parsed_wet_block
	water_blocks = parsed_water_blocks
	horizontal_radius = clampi(int(data.get("horizontal_radius", 4)), 1, 8)
	vertical_radius = clampi(int(data.get("vertical_radius", 1)), 0, 3)
	manual_hydration_seconds = clampf(
		float(data.get("manual_hydration_seconds", 180.0)), 10.0, 3600.0
	)
	dry_growth_multiplier = clampf(
		float(data.get("dry_growth_multiplier", 0.35)), 0.0, 1.0
	)
	wet_growth_multiplier = clampf(
		float(data.get("wet_growth_multiplier", 1.0)), 0.1, 4.0
	)
	refresh_interval_seconds = clampf(
		float(data.get("refresh_interval_seconds", 1.0)), 0.25, 10.0
	)
	max_refresh_per_tick = clampi(int(data.get("max_refresh_per_tick", 8)), 1, 64)
	return true


func is_farmland_block(block_id: String) -> bool:
	return block_id == dry_block or block_id == wet_block


func is_water_block(block_id: String) -> bool:
	return block_id in water_blocks


func block_for_hydration(hydrated: bool) -> String:
	return wet_block if hydrated else dry_block


func growth_multiplier(hydrated: bool) -> float:
	return wet_growth_multiplier if hydrated else dry_growth_multiplier


func get_snapshot() -> Dictionary:
	return {
		"version": schema_version,
		"dry_block": dry_block,
		"wet_block": wet_block,
		"water_blocks": water_blocks.duplicate(),
		"horizontal_radius": horizontal_radius,
		"vertical_radius": vertical_radius,
		"manual_hydration_seconds": manual_hydration_seconds,
		"dry_growth_multiplier": dry_growth_multiplier,
		"wet_growth_multiplier": wet_growth_multiplier,
		"refresh_interval_seconds": refresh_interval_seconds,
		"max_refresh_per_tick": max_refresh_per_tick,
	}
