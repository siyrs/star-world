extends SceneTree

const RegistryScript = preload("res://src/world/resource_distribution_registry.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const MapSelectionPanelScript = preload("res://src/ui/map_selection_panel.gd")
const PROFILE_IDS: Array[String] = ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands", "abyss_world"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_contract()
	_test_threshold_boundaries()
	_test_generator_delegation()
	_test_map_density_ordering()
	await _test_map_selection_contract()
	if failures.is_empty():
		print("QA RESOURCE DISTRIBUTION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RESOURCE DISTRIBUTION FAILURE: %s" % failure)
		print("QA RESOURCE DISTRIBUTION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_contract() -> void:
	var registry = RegistryScript.new()
	_check(registry.schema_version == 1, "resource distribution schema version is stable")
	_check(registry.get_validation_errors().is_empty(), "production resource distribution data has no validation errors")
	_check(
		registry.get_profile_ids() == ["abyss_world", "desert_ruins", "frozen_wastes", "sky_islands", "star_continent"],
		"all five production maps expose resource profiles"
	)
	for profile_id: String in registry.get_profile_ids():
		var profile: Dictionary = registry.get_profile(profile_id)
		var entries: Array = profile.get("entries", [])
		_check(str(profile.get("id", "")) == profile_id, "%s returns its own profile" % profile_id)
		_check(not str(profile.get("summary", "")).is_empty(), "%s exposes a player-facing resource summary" % profile_id)
		_check(str(profile.get("fallback_block", "")) == "stone", "%s falls back to stone" % profile_id)
		_check(entries.size() == 4, "%s defines four ordered ore bands" % profile_id)
	_check(registry.get_profile("unknown").get("id", "") == "star_continent", "unknown maps fall back to the balanced profile")


func _test_threshold_boundaries() -> void:
	var registry = RegistryScript.new()
	var cases: Array[Dictionary] = [
		{"profile":"star_continent", "y":5, "roll":21, "expected":"diamond_ore"},
		{"profile":"star_continent", "y":5, "roll":22, "expected":"gold_ore"},
		{"profile":"star_continent", "y":5, "roll":69, "expected":"gold_ore"},
		{"profile":"star_continent", "y":5, "roll":70, "expected":"iron_ore"},
		{"profile":"star_continent", "y":5, "roll":204, "expected":"iron_ore"},
		{"profile":"star_continent", "y":5, "roll":205, "expected":"coal_ore"},
		{"profile":"star_continent", "y":5, "roll":499, "expected":"coal_ore"},
		{"profile":"star_continent", "y":5, "roll":500, "expected":"stone"},
		{"profile":"star_continent", "y":15, "roll":21, "expected":"gold_ore"},
		{"profile":"star_continent", "y":25, "roll":69, "expected":"iron_ore"},
		{"profile":"star_continent", "y":40, "roll":204, "expected":"coal_ore"},
		{"profile":"star_continent", "y":0, "roll":0, "expected":"stone"},
		{"profile":"desert_ruins", "y":5, "roll":28, "expected":"diamond_ore"},
		{"profile":"desert_ruins", "y":5, "roll":29, "expected":"gold_ore"},
		{"profile":"desert_ruins", "y":5, "roll":93, "expected":"gold_ore"},
		{"profile":"desert_ruins", "y":5, "roll":94, "expected":"iron_ore"},
		{"profile":"desert_ruins", "y":5, "roll":275, "expected":"iron_ore"},
		{"profile":"desert_ruins", "y":5, "roll":276, "expected":"coal_ore"},
		{"profile":"desert_ruins", "y":5, "roll":674, "expected":"coal_ore"},
		{"profile":"desert_ruins", "y":5, "roll":675, "expected":"stone"},
		{"profile":"sky_islands", "y":5, "roll":14, "expected":"diamond_ore"},
		{"profile":"sky_islands", "y":5, "roll":15, "expected":"gold_ore"},
		{"profile":"sky_islands", "y":5, "roll":48, "expected":"gold_ore"},
		{"profile":"sky_islands", "y":5, "roll":49, "expected":"iron_ore"},
		{"profile":"sky_islands", "y":5, "roll":142, "expected":"iron_ore"},
		{"profile":"sky_islands", "y":5, "roll":143, "expected":"coal_ore"},
		{"profile":"sky_islands", "y":5, "roll":349, "expected":"coal_ore"},
		{"profile":"sky_islands", "y":5, "roll":350, "expected":"stone"},
		{"profile":"abyss_world", "y":5, "roll":35, "expected":"diamond_ore"},
		{"profile":"abyss_world", "y":5, "roll":36, "expected":"gold_ore"},
		{"profile":"abyss_world", "y":5, "roll":114, "expected":"gold_ore"},
		{"profile":"abyss_world", "y":5, "roll":115, "expected":"iron_ore"},
		{"profile":"abyss_world", "y":5, "roll":337, "expected":"iron_ore"},
		{"profile":"abyss_world", "y":5, "roll":338, "expected":"coal_ore"},
		{"profile":"abyss_world", "y":5, "roll":824, "expected":"coal_ore"},
		{"profile":"abyss_world", "y":5, "roll":825, "expected":"stone"},
	]
	for test_case: Dictionary in cases:
		var actual := registry.resolve_block(
			str(test_case.get("profile", "")),
			int(test_case.get("y", 0)),
			int(test_case.get("roll", 0))
		)
		_check(
			actual == str(test_case.get("expected", "")),
			"%s y=%d roll=%d resolves to %s"
			% [test_case.get("profile", ""), test_case.get("y", 0), test_case.get("roll", 0), test_case.get("expected", "")]
		)


func _test_generator_delegation() -> void:
	var registry = RegistryScript.new()
	var generator = GeneratorScript.new()
	generator.configure("desert", 73190462)
	_check(generator.profile_id == "desert_ruins", "legacy desert alias normalizes before resource lookup")
	var positions: Array[Vector3i] = [
		Vector3i(-31, 5, 17),
		Vector3i(0, 8, 0),
		Vector3i(27, 15, -42),
		Vector3i(51, 25, 19),
		Vector3i(-13, 40, -7),
	]
	for position: Vector3i in positions:
		var roll := int(generator.call("_hash_roll", position.x, position.y, position.z, GeneratorScript.RESOURCE_ROLL_SALT))
		var expected := registry.resolve_block("desert_ruins", position.y, roll)
		var actual := str(generator.call("_ore_or_stone", position))
		_check(actual == expected, "world generator delegates %s to the resource registry" % position)
	generator.configure("unknown-profile", 73190462)
	_check(generator.profile_id == "star_continent", "unknown generator profile preserves the balanced fallback")


func _test_map_density_ordering() -> void:
	var counts: Dictionary = {}
	for profile_id: String in PROFILE_IDS:
		var generator = GeneratorScript.new()
		generator.configure(profile_id, 8451397)
		var ore_count := 0
		for x in range(-48, 49):
			for z in range(-48, 49):
				if str(generator.call("_ore_or_stone", Vector3i(x, 8, z))) != "stone":
					ore_count += 1
		counts[profile_id] = ore_count
	_check(int(counts["abyss_world"]) > int(counts["desert_ruins"]), "abyss resource density exceeds desert density for the same seed")
	_check(int(counts["desert_ruins"]) > int(counts["star_continent"]), "desert resource density exceeds balanced density for the same seed")
	_check(int(counts["star_continent"]) == int(counts["frozen_wastes"]), "frozen and balanced maps preserve their identical resource probability")
	_check(int(counts["star_continent"]) > int(counts["sky_islands"]), "balanced resource density exceeds sky island density for the same seed")
	print("QA RESOURCE DENSITY | %s" % counts)


func _test_map_selection_contract() -> void:
	var panel = MapSelectionPanelScript.new()
	root.add_child(panel)
	await process_frame
	await process_frame
	for profile_id: String in PROFILE_IDS:
		panel.call("_select_profile", profile_id)
		var summary := str(panel.call("get_resource_summary", profile_id))
		var details := str(panel.call("get_details_text"))
		_check(not summary.is_empty(), "%s resource summary is available to the map selection UI" % profile_id)
		_check(details.contains("资源特点"), "%s map details label the resource strategy" % profile_id)
		_check(details.contains(summary), "%s map details display the authoritative resource summary" % profile_id)
	panel.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
