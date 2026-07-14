class_name RepairPolicy
extends RefCounted


func evaluate(
	profile: Dictionary,
	item_definition: Dictionary,
	durability_context: Dictionary,
	material_available: int
) -> Dictionary:
	if profile.is_empty():
		return {"success": false, "reason": "profile_missing"}
	var item_id: String = str(durability_context.get("item_id", ""))
	var maximum: int = maxi(0, int(durability_context.get("maximum_durability", 0)))
	if item_id.is_empty() or item_definition.is_empty() or maximum <= 0:
		return {"success": false, "reason": "not_durable", "item_id": item_id}
	var current: int = clampi(
		int(durability_context.get("remaining_durability", maximum)), 0, maximum
	)
	var missing: int = maximum - current
	if missing <= 0:
		return {
			"success": false,
			"reason": "already_full",
			"item_id": item_id,
			"current": current,
			"maximum": maximum,
		}
	var material_item: String = str(profile.get("material_item", ""))
	var material_count: int = maxi(1, int(profile.get("material_count", 1)))
	if material_item.is_empty():
		return {"success": false, "reason": "material_invalid", "item_id": item_id}
	var restore_ratio: float = clampf(float(profile.get("restore_ratio", 0.0)), 0.0, 1.0)
	var restore_capacity: int = maxi(1, ceili(float(maximum) * restore_ratio))
	var restored: int = mini(missing, restore_capacity)
	if material_available < material_count:
		return {
			"success": false,
			"reason": "material_missing",
			"item_id": item_id,
			"current": current,
			"maximum": maximum,
			"missing": missing,
			"restore_amount": restored,
			"material_item": material_item,
			"material_count": material_count,
			"material_available": maxi(0, material_available),
		}
	return {
		"success": true,
		"reason": "",
		"item_id": item_id,
		"current": current,
		"maximum": maximum,
		"missing": missing,
		"restore_amount": restored,
		"target_durability": current + restored,
		"material_item": material_item,
		"material_count": material_count,
		"material_available": maxi(0, material_available),
		"profile_id": str(profile.get("id", "")),
	}
