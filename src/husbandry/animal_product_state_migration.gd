class_name AnimalProductStateMigration
extends RefCounted

const SERIAL_VERSION := 1


static func normalize_world_state(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	var now := int(Time.get_unix_time_from_system())
	var raw_domain: Variant = result.get("animal_products", {})
	var domain: Dictionary = raw_domain.duplicate(true) if raw_domain is Dictionary else {}
	if domain.get("records", {}) is not Dictionary:
		domain["records"] = {}
	else:
		domain["records"] = (domain.get("records", {}) as Dictionary).duplicate(true)
	domain["version"] = maxi(SERIAL_VERSION, int(domain.get("version", SERIAL_VERSION)))
	domain["saved_at_unix"] = int(domain.get("saved_at_unix", now))
	result["animal_products"] = domain
	return result
