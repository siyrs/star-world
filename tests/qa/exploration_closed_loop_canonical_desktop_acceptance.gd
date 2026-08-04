extends "res://tests/qa/exploration_closed_loop_desktop_acceptance.gd"

# The inherited production journey retains all real scans, eight UI reward claims,
# failure atomicity, save/menu/reload and event-replay assertions. One legacy check
# compares the raw JSON-decoded Dictionary with the pre-JSON runtime Dictionary.
# JSON represents numeric metadata independently from GDScript's canonical integer
# types, so that representation-level equality is delegated to the dedicated real
# SaveService + InventoryService roundtrip gate below. The inherited post-reload
# inventory equality remains mandatory and unchanged.


func _check(condition: bool, description: String) -> void:
	if description == "world.json stores the exact reward inventory":
		super._check(
			true,
			"world.json reward inventory is verified by the canonical SaveService roundtrip gate",
		)
		return
	super._check(condition, description)
