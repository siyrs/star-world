class_name SaveBrowserQueryPolicy
extends RefCounted

const MAX_QUERY_LENGTH := 64
const MAX_QUERY_TOKENS := 8
const SORT_UPDATED_DESC := "updated_desc"
const SORT_NAME_ASC := "name_asc"
const SORT_SIZE_DESC := "size_desc"
const SUPPORTED_SORT_MODES := [
	SORT_UPDATED_DESC,
	SORT_NAME_ASC,
	SORT_SIZE_DESC,
]


static func normalize_query(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized.length() > MAX_QUERY_LENGTH:
		normalized = normalized.substr(0, MAX_QUERY_LENGTH)
	return normalized


static func query_tokens(value: String) -> Array[String]:
	var result: Array[String] = []
	for raw_token: String in normalize_query(value).split(" ", false):
		var token := raw_token.strip_edges()
		if token.is_empty() or result.has(token):
			continue
		result.append(token)
		if result.size() >= MAX_QUERY_TOKENS:
			break
	return result


static func normalize_sort_mode(value: String) -> String:
	return value if value in SUPPORTED_SORT_MODES else SORT_UPDATED_DESC


static func select_world_ids(
	worlds: Array,
	query: String,
	sort_mode: String = SORT_UPDATED_DESC
) -> Array[String]:
	var tokens := query_tokens(query)
	var safe_sort_mode := normalize_sort_mode(sort_mode)
	var matched: Array[Dictionary] = []
	for raw_metadata: Variant in worlds:
		if not raw_metadata is Dictionary:
			continue
		var metadata := raw_metadata as Dictionary
		var world_id := str(metadata.get("id", ""))
		if world_id.is_empty() or not _matches_tokens(metadata, tokens):
			continue
		matched.append(metadata)
	matched.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return _comes_before(left, right, safe_sort_mode)
	)
	var result: Array[String] = []
	for metadata: Dictionary in matched:
		result.append(str(metadata.get("id", "")))
	return result


static func _matches_tokens(
	metadata: Dictionary,
	tokens: Array[String]
) -> bool:
	if tokens.is_empty():
		return true
	var searchable := " ".join([
		str(metadata.get("name", "")),
		str(metadata.get("id", "")),
		str(metadata.get("map_id", "")),
		str(metadata.get("seed", "")),
	]).to_lower()
	for token: String in tokens:
		if not searchable.contains(token):
			return false
	return true


static func _comes_before(
	left: Dictionary,
	right: Dictionary,
	sort_mode: String
) -> bool:
	var left_id := str(left.get("id", ""))
	var right_id := str(right.get("id", ""))
	match sort_mode:
		SORT_NAME_ASC:
			var name_order := str(left.get("name", "")).naturalnocasecmp_to(
				str(right.get("name", ""))
			)
			if name_order != 0:
				return name_order < 0
		SORT_SIZE_DESC:
			var left_bytes := maxi(0, int(left.get("save_bytes", 0)))
			var right_bytes := maxi(0, int(right.get("save_bytes", 0)))
			if left_bytes != right_bytes:
				return left_bytes > right_bytes
		_:
			var left_updated := str(left.get("updated_at", ""))
			var right_updated := str(right.get("updated_at", ""))
			if left_updated != right_updated:
				return left_updated > right_updated
	return left_id.naturalnocasecmp_to(right_id) < 0
