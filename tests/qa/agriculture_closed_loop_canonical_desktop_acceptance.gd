extends "res://tests/qa/agriculture_closed_loop_desktop_acceptance.gd"

# Keep the production journey unchanged while making the full-inventory fixture
# structurally stable across JSON. Unknown numeric metadata is intentionally not
# coerced by InventoryService, so fixture identity uses strings instead of relying
# on JSON's int/float representation.


func _fill_full_harvest_inventory(inventory: Node) -> void:
	inventory.clear()
	inventory.call("add_item", "wheat_seeds", 1)
	for index in 35:
		inventory.call(
			"add_item",
			"wooden_pickaxe",
			1,
			{"fixture_slot":"agriculture_%02d" % index},
		)
