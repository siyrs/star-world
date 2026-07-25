extends SceneTree

const Policy = preload("res://src/ui/save_browser_query_policy.gd")
const WORLD_COUNT := 256

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var worlds := _build_worlds()
	worlds.append(worlds[0])
	worlds.append({})
	worlds.append("invalid")

	var normalized := Policy.normalize_query(
		"  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-extra  "
	)
	_check(
		normalized.length() == Policy.MAX_QUERY_LENGTH
		and normalized == normalized.to_lower(),
		"query normalization trims, lowercases and enforces the sixty-four-character limit"
	)
	var tokens: Array[String] = Policy.query_tokens(
		"one two one three four five six seven eight nine ten"
	)
	_check(
		tokens.size() == Policy.MAX_QUERY_TOKENS
		and tokens[0] == "one"
		and tokens[1] == "two"
		and tokens.count("one") == 1,
		"query tokens are unique and capped at eight"
	)

	var updated := Policy.select_world_ids(
		worlds,
		"",
		Policy.SORT_UPDATED_DESC
	)
	_check(
		updated.size() == WORLD_COUNT
		and updated[0] == "world-255"
		and updated[WORLD_COUNT - 1] == "world-000",
		"default sorting is deterministic newest-first and removes duplicate ids"
	)
	var invalid_sort := Policy.select_world_ids(worlds, "", "unknown")
	_check(
		invalid_sort == updated,
		"unknown sort modes normalize to newest-first"
	)

	var names := Policy.select_world_ids(worlds, "", Policy.SORT_NAME_ASC)
	_check(
		names[0] == "world-000"
		and names[1] == "world-004"
		and names[WORLD_COUNT - 1] == "world-254",
		"name sorting is natural, case-insensitive and id-stable"
	)
	var sizes := Policy.select_world_ids(worlds, "", Policy.SORT_SIZE_DESC)
	_check(
		sizes[0] == "world-255"
		and sizes[WORLD_COUNT - 1] == "world-000",
		"save-size sorting is deterministic largest-first"
	)

	var gamma := Policy.select_world_ids(worlds, "gamma")
	_check(
		gamma.size() == 64,
		"name search returns all sixty-four matching worlds"
	)
	var exact_tokens := Policy.select_world_ids(
		worlds,
		"gamma 122",
		Policy.SORT_NAME_ASC
	)
	_check(
		exact_tokens == ["world-122"],
		"all search tokens must match the same world"
	)
	var by_id := Policy.select_world_ids(worlds, "world-123")
	_check(by_id == ["world-123"], "world id is searchable")
	var by_map := Policy.select_world_ids(worlds, "snowfield")
	_check(
		by_map.size() == 51,
		"map id is searchable without reading world payloads"
	)
	var by_seed := Policy.select_world_ids(worlds, "1200123")
	_check(by_seed == ["world-123"], "seed is searchable as exact text")
	var no_matches := Policy.select_world_ids(worlds, "missing-world")
	_check(no_matches.is_empty(), "unknown queries return an empty result")

	var tied := [
		{
			"id": "world-b",
			"name": "Same",
			"updated_at": "2026-07-25T00:00:00",
			"save_bytes": 100,
		},
		{
			"id": "world-a",
			"name": "same",
			"updated_at": "2026-07-25T00:00:00",
			"save_bytes": 100,
		},
	]
	_check(
		Policy.select_world_ids(tied, "", Policy.SORT_NAME_ASC)
		== ["world-a", "world-b"],
		"sort ties always fall back to stable natural world ids"
	)

	if failures.is_empty():
		print(
			"QA SAVE BROWSER QUERY POLICY PASS | checks=%d | worlds=%d"
			% [checks, WORLD_COUNT]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SAVE BROWSER QUERY POLICY FAILURE: %s" % failure)
		print(
			"QA SAVE BROWSER QUERY POLICY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _build_worlds() -> Array:
	var groups := ["Alpha", "Beta", "Gamma", "Delta"]
	var maps := [
		"star_continent",
		"snowfield",
		"desert",
		"floating_islands",
		"abyss",
	]
	var result: Array = []
	for index in WORLD_COUNT:
		result.append({
			"id": "world-%03d" % index,
			"name": "Archive %s %03d" % [groups[index % groups.size()], index],
			"map_id": maps[index % maps.size()],
			"seed": 1200000 + index,
			"updated_at": "2026-07-25T00:%02d:%02d" % [
				index / 60,
				index % 60,
			],
			"save_bytes": 4096 + index * 17,
		})
	return result


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
