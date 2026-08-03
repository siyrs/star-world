extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original = InventoryScript.new(12, 4)
	var restored = InventoryScript.new(12, 4)
	root.add_child(original)
	root.add_child(restored)

	_check(
		int(original.add_item("oak_log", 2)) == 0,
		"canonical fixture adds one plain stack",
	)
	_check(
		int(original.add_item(
			"iron_pickaxe",
			1,
			{
				"durability": 87,
				"custom_name": "Canonical Pickaxe",
			},
		)) == 0,
		"canonical fixture adds one metadata-bearing item",
	)
	original.select_slot(1)
	var serialized: Dictionary = original.serialize()
	var plain_slot: Dictionary = serialized.get("slots", [])[0]
	var metadata_slot: Dictionary = serialized.get("slots", [])[1]
	_check(
		not plain_slot.has("metadata"),
		"plain runtime stack serializes without an empty metadata field",
	)
	_check(
		metadata_slot.get("metadata", {}).get("durability", 0) == 87,
		"meaningful metadata is serialized",
	)

	_check(
		bool(restored.deserialize(serialized)),
		"canonical payload deserializes",
	)
	var roundtrip: Dictionary = restored.serialize()
	_check(
		roundtrip == serialized,
		"serialize-deserialize-serialize preserves exact canonical shape",
	)
	_check(
		restored.count_item("oak_log") == 2
		and restored.count_item("iron_pickaxe") == 1,
		"roundtrip preserves item counts",
	)
	_check(
		int(roundtrip.get("selected_slot", -1)) == 1,
		"roundtrip preserves the selected hotbar slot",
	)

	var legacy_empty_metadata: Dictionary = serialized.duplicate(true)
	legacy_empty_metadata["slots"][0]["metadata"] = {}
	_check(
		bool(restored.deserialize(legacy_empty_metadata)),
		"legacy empty-metadata payload remains readable",
	)
	var normalized_legacy: Dictionary = restored.serialize()
	_check(
		not normalized_legacy["slots"][0].has("metadata"),
		"legacy empty metadata is normalized away on the next save",
	)

	var malformed_metadata: Dictionary = serialized.duplicate(true)
	malformed_metadata["slots"][0]["metadata"] = "invalid"
	_check(
		bool(restored.deserialize(malformed_metadata)),
		"malformed optional metadata cannot make the whole inventory unreadable",
	)
	var normalized_malformed: Dictionary = restored.serialize()
	_check(
		not normalized_malformed["slots"][0].has("metadata"),
		"malformed metadata is rejected instead of entering runtime state",
	)
	_check(
		normalized_malformed["slots"][1].get("metadata", {}).get(
			"custom_name",
			"",
		) == "Canonical Pickaxe",
		"valid metadata in another slot survives malformed-neighbour recovery",
	)

	original.queue_free()
	restored.queue_free()
	for _frame in 8:
		await process_frame
	if failures.is_empty():
		print("QA INVENTORY CANONICAL ROUNDTRIP PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA INVENTORY CANONICAL ROUNDTRIP FAILURE: %s" % failure)
	print(
		"QA INVENTORY CANONICAL ROUNDTRIP FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
