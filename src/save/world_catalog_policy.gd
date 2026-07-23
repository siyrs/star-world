class_name WorldCatalogPolicy
extends RefCounted

const CATALOG_VERSION := 1
const MAX_TEXT_LENGTH := 128
const METADATA_FIELDS: Array[String] = [
	"id",
	"name",
	"map_id",
	"seed",
	"created_at",
	"updated_at",
	"play_seconds",
]


static func build_entry(world_id: String, state: Dictionary, save_bytes: int) -> Dictionary:
	var raw_metadata: Variant = state.get("metadata", {})
	var metadata := _normalize_metadata(
		raw_metadata if raw_metadata is Dictionary else {},
		world_id
	)
	return {
		"catalog_version": CATALOG_VERSION,
		"save_version": maxi(1, int(state.get("save_version", 1))),
		"save_bytes": maxi(0, save_bytes),
		"metadata": metadata,
	}


static func normalize_entry(
	value: Variant,
	expected_world_id: String,
	expected_save_bytes: int = -1
) -> Dictionary:
	if value is not Dictionary:
		return {}
	var entry: Dictionary = value
	if int(entry.get("catalog_version", 0)) != CATALOG_VERSION:
		return {}
	var raw_metadata: Variant = entry.get("metadata", {})
	if raw_metadata is not Dictionary:
		return {}
	var world_id := str(raw_metadata.get("id", "")).strip_edges()
	if world_id.is_empty() or world_id != expected_world_id:
		return {}
	var save_bytes := maxi(0, int(entry.get("save_bytes", 0)))
	if expected_save_bytes >= 0 and save_bytes != expected_save_bytes:
		return {}
	return {
		"catalog_version": CATALOG_VERSION,
		"save_version": maxi(1, int(entry.get("save_version", 1))),
		"save_bytes": save_bytes,
		"metadata": _normalize_metadata(raw_metadata, world_id),
	}


static func metadata_for_list(entry: Dictionary, source: String) -> Dictionary:
	var raw_metadata: Variant = entry.get("metadata", {})
	var metadata: Dictionary = {}
	if raw_metadata is Dictionary:
		metadata = raw_metadata.duplicate(true)
	metadata["save_bytes"] = maxi(0, int(entry.get("save_bytes", 0)))
	metadata["save_version"] = maxi(1, int(entry.get("save_version", 1)))
	metadata["catalog_version"] = CATALOG_VERSION
	metadata["catalog_source"] = source
	return metadata


static func _normalize_metadata(raw_metadata: Dictionary, world_id: String) -> Dictionary:
	# A catalog row is intentionally smaller than full world metadata. Additional
	# fields such as map_profile remain authoritative in world.json and cannot
	# silently turn this derived sidecar into another unbounded save payload.
	return {
		"id": world_id,
		"name": _bounded_text(raw_metadata.get("name", "新世界"), "新世界"),
		"map_id": _bounded_text(
			raw_metadata.get("map_id", "star_continent"),
			"star_continent"
		),
		"seed": int(raw_metadata.get("seed", 0)),
		"created_at": _bounded_text(raw_metadata.get("created_at", ""), ""),
		"updated_at": _bounded_text(raw_metadata.get("updated_at", ""), ""),
		"play_seconds": maxi(0, int(raw_metadata.get("play_seconds", 0))),
	}


static func _bounded_text(value: Variant, fallback: String) -> String:
	var result := str(value).strip_edges()
	if result.is_empty():
		result = fallback
	return result.left(MAX_TEXT_LENGTH)
