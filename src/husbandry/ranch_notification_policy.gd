class_name RanchNotificationPolicy
extends RefCounted

const MAX_PRODUCT_TYPES_IN_MESSAGE := 3


static func following_transition(previous_count: int, current_count: int) -> Dictionary:
	var previous := maxi(0, previous_count)
	var current := maxi(0, current_count)
	if previous == 0 and current > 0:
		return {
			"kind": "started",
			"count": current,
			"message": "%d 只动物被手中饲料吸引" % current,
			"severity": "info",
			"duration": 2.8,
		}
	if previous > 0 and current == 0:
		return {
			"kind": "stopped",
			"count": 0,
			"message": "动物已停止跟随",
			"severity": "info",
			"duration": 2.4,
		}
	return {}


static func product_batch(
	counts: Dictionary,
	names: Dictionary,
	husbandry_ids: Dictionary
) -> Dictionary:
	var item_ids: Array[String] = []
	for raw_id: Variant in counts.keys():
		var item_id := str(raw_id).strip_edges()
		if item_id.is_empty() or int(counts.get(raw_id, 0)) <= 0:
			continue
		item_ids.append(item_id)
	item_ids.sort()
	if item_ids.is_empty():
		return {}
	var products: Array[Dictionary] = []
	var total_count := 0
	for item_id: String in item_ids:
		var count := maxi(0, int(counts.get(item_id, 0)))
		if count <= 0:
			continue
		total_count += count
		products.append({
			"item_id": item_id,
			"name": str(names.get(item_id, item_id)),
			"count": count,
		})
	if products.is_empty():
		return {}
	var animal_count := 0
	for raw_id: Variant in husbandry_ids.keys():
		if not str(raw_id).strip_edges().is_empty():
			animal_count += 1
	var visible_parts: Array[String] = []
	for index in range(mini(products.size(), MAX_PRODUCT_TYPES_IN_MESSAGE)):
		var product: Dictionary = products[index]
		visible_parts.append("%s ×%d" % [product.get("name", "产物"), product.get("count", 0)])
	var product_text := "、".join(visible_parts)
	if products.size() > MAX_PRODUCT_TYPES_IN_MESSAGE:
		product_text += "等 %d 类" % products.size()
	var animal_suffix := ""
	if animal_count > 0:
		animal_suffix = "（%d 只动物）" % animal_count
	return {
		"products": products,
		"product_types": products.size(),
		"total_count": total_count,
		"animal_count": animal_count,
		"message": "牧场产物已生成：%s%s" % [product_text, animal_suffix],
		"severity": "success",
		"duration": 3.2,
	}
