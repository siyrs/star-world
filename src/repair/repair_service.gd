class_name RepairService
extends Node

signal repair_completed(result: Dictionary)
signal repair_rejected(reason: String, context: Dictionary)

const RepairRegistryScript = preload("res://src/repair/repair_registry.gd")
const RepairPolicyScript = preload("res://src/repair/repair_policy.gd")
const TARGET_INVENTORY := "inventory"
const TARGET_EQUIPMENT := "equipment"

var item_registry
var inventory: Node
var equipment: Node
var tool_service: Node
var registry = RepairRegistryScript.new()
var policy = RepairPolicyScript.new()


func setup(
	p_item_registry,
	p_inventory: Node,
	p_equipment: Node,
	p_tool_service: Node
) -> void:
	item_registry = p_item_registry
	inventory = p_inventory
	equipment = p_equipment
	tool_service = p_tool_service
	registry.ensure_loaded()


func get_station_block() -> String:
	return registry.get_station_block()


func get_snapshot() -> Dictionary:
	return {
		"station_block": get_station_block(),
		"profile_count": registry.profile_count(),
		"target_count": get_all_previews().size(),
	}


func get_all_previews() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory != null and inventory.has_method("get_slot"):
		var count: int = maxi(0, int(inventory.get("slot_count")))
		for index in count:
			var target: Dictionary = {
				"kind": TARGET_INVENTORY,
				"slot_index": index,
				"target_id": "inventory:%d" % index,
			}
			var preview: Dictionary = get_preview(target)
			if bool(preview.get("listed", false)):
				result.append(preview)
	if equipment != null and equipment.has_method("get_slot_definitions"):
		var slot_definitions: Array = equipment.call("get_slot_definitions")
		for raw_definition in slot_definitions:
			if raw_definition is not Dictionary:
				continue
			var definition: Dictionary = raw_definition
			var slot_id: String = str(definition.get("id", ""))
			if slot_id.is_empty():
				continue
			var target: Dictionary = {
				"kind": TARGET_EQUIPMENT,
				"slot_id": slot_id,
				"target_id": "equipment:%s" % slot_id,
			}
			var preview: Dictionary = get_preview(target)
			if bool(preview.get("listed", false)):
				result.append(preview)
	return result


func get_preview(target: Dictionary) -> Dictionary:
	var item: Dictionary = _read_target(target)
	if item.is_empty():
		return {"listed": false, "target": target.duplicate(true), "reason": "target_empty"}
	var item_id: String = str(item.get("item_id", ""))
	var profile: Dictionary = registry.get_profile_for_item(item_id)
	if profile.is_empty():
		return {
			"listed": false,
			"target": target.duplicate(true),
			"item_id": item_id,
			"reason": "profile_missing",
		}
	var item_definition: Dictionary = _item_definition(item_id)
	var durability_context: Dictionary = _durability_context(item)
	var material_item: String = str(profile.get("material_item", ""))
	var material_available: int = _material_count(material_item)
	var evaluation: Dictionary = policy.evaluate(
		profile, item_definition, durability_context, material_available
	)
	var preview: Dictionary = evaluation.duplicate(true)
	preview["listed"] = true
	preview["target"] = target.duplicate(true)
	preview["target_id"] = str(target.get("target_id", ""))
	preview["target_label"] = _target_label(target)
	preview["item"] = item.duplicate(true)
	preview["item_id"] = item_id
	preview["display_name"] = str(item_definition.get("name", item_id))
	preview["material_name"] = _display_name(material_item)
	preview["color"] = str(item_definition.get("color", "#FFFFFF"))
	return preview


func repair_target(target: Dictionary) -> Dictionary:
	var preview: Dictionary = get_preview(target)
	if not bool(preview.get("listed", false)):
		return _reject(str(preview.get("reason", "target_invalid")), preview)
	if not bool(preview.get("success", false)):
		return _reject(str(preview.get("reason", "repair_rejected")), preview)
	var before_item: Dictionary = _read_target(target)
	var material_item: String = str(preview.get("material_item", ""))
	var material_count: int = maxi(1, int(preview.get("material_count", 1)))
	if inventory == null or not inventory.has_method("remove_item"):
		return _reject("inventory_contract_missing", preview)
	var removed: int = int(inventory.call("remove_item", material_item, material_count))
	if removed != material_count:
		if removed > 0:
			_restore_material(material_item, removed)
		return _reject("material_missing", get_preview(target))
	var current_item: Dictionary = _read_target(target)
	if not _same_target_item(before_item, current_item):
		_restore_material(material_item, material_count)
		return _reject("target_changed", get_preview(target))
	var metadata: Dictionary = current_item.get("metadata", {}).duplicate(true)
	metadata["durability"] = int(preview.get("target_durability", 0))
	if not _write_target_metadata(target, metadata):
		_restore_material(material_item, material_count)
		return _reject("durability_update_failed", get_preview(target))
	var result: Dictionary = get_preview(target)
	result["success"] = true
	result["action"] = &"repair_item"
	result["repaired_amount"] = int(preview.get("restore_amount", 0))
	result["before_durability"] = int(preview.get("current", 0))
	result["after_durability"] = int(preview.get("target_durability", 0))
	result["maximum"] = int(preview.get("maximum", 0))
	result["material_item"] = material_item
	result["material_count"] = material_count
	result["message"] = "%s 已恢复 %d 点耐久" % [
		str(preview.get("display_name", "物品")),
		int(preview.get("restore_amount", 0)),
	]
	repair_completed.emit(result.duplicate(true))
	return result


func _read_target(target: Dictionary) -> Dictionary:
	var kind: String = str(target.get("kind", ""))
	if kind == TARGET_INVENTORY:
		if inventory == null or not inventory.has_method("get_slot"):
			return {}
		return inventory.call("get_slot", int(target.get("slot_index", -1)))
	if kind == TARGET_EQUIPMENT:
		if equipment == null or not equipment.has_method("get_slot"):
			return {}
		return equipment.call("get_slot", str(target.get("slot_id", "")))
	return {}


func _write_target_metadata(target: Dictionary, metadata: Dictionary) -> bool:
	var kind: String = str(target.get("kind", ""))
	if kind == TARGET_INVENTORY:
		return (
			inventory != null
			and inventory.has_method("update_slot_metadata")
			and bool(
				inventory.call(
					"update_slot_metadata", int(target.get("slot_index", -1)), metadata
				)
			)
		)
	if kind == TARGET_EQUIPMENT:
		return (
			equipment != null
			and equipment.has_method("update_slot_metadata")
			and bool(
				equipment.call(
					"update_slot_metadata", str(target.get("slot_id", "")), metadata
				)
			)
		)
	return false


func _durability_context(item: Dictionary) -> Dictionary:
	if tool_service != null and tool_service.has_method("get_slot_context"):
		return tool_service.call("get_slot_context", item)
	var item_id: String = str(item.get("item_id", ""))
	var definition: Dictionary = _item_definition(item_id)
	var maximum: int = maxi(0, int(definition.get("durability", 0)))
	var metadata: Dictionary = item.get("metadata", {})
	return {
		"item_id": item_id,
		"maximum_durability": maximum,
		"remaining_durability": clampi(int(metadata.get("durability", maximum)), 0, maximum),
	}


func _target_label(target: Dictionary) -> String:
	if str(target.get("kind", "")) == TARGET_INVENTORY:
		return "背包槽 %d" % (int(target.get("slot_index", 0)) + 1)
	var slot_id: String = str(target.get("slot_id", ""))
	if equipment != null and equipment.has_method("get_slot_definition"):
		var definition: Dictionary = equipment.call("get_slot_definition", slot_id)
		return "已装备 · %s" % str(definition.get("name", slot_id))
	return "已装备 · %s" % slot_id


func _material_count(item_id: String) -> int:
	if item_id.is_empty() or inventory == null or not inventory.has_method("count_item"):
		return 0
	return int(inventory.call("count_item", item_id))


func _item_definition(item_id: String) -> Dictionary:
	if item_registry == null or not item_registry.has_method("get_item"):
		return {}
	return item_registry.call("get_item", item_id)


func _display_name(item_id: String) -> String:
	if item_registry != null and item_registry.has_method("get_display_name"):
		return str(item_registry.call("get_display_name", item_id))
	return item_id


func _same_target_item(before: Dictionary, after: Dictionary) -> bool:
	return (
		not before.is_empty()
		and not after.is_empty()
		and str(before.get("item_id", "")) == str(after.get("item_id", ""))
		and int(before.get("count", 0)) == int(after.get("count", 0))
		and before.get("metadata", {}) == after.get("metadata", {})
	)


func _restore_material(item_id: String, count: int) -> void:
	if count <= 0 or inventory == null or not inventory.has_method("add_item"):
		return
	var remaining: int = int(inventory.call("add_item", item_id, count))
	if remaining > 0:
		push_error("Repair rollback could not restore %d x %s" % [remaining, item_id])


func _reject(reason: String, context: Dictionary) -> Dictionary:
	var result: Dictionary = context.duplicate(true)
	result["success"] = false
	result["reason"] = reason
	result["message"] = _message_for_reason(reason, result)
	repair_rejected.emit(reason, result.duplicate(true))
	return result


func _message_for_reason(reason: String, context: Dictionary) -> String:
	match reason:
		"already_full":
			return "%s 的耐久已经是满值" % str(context.get("display_name", "该物品"))
		"material_missing":
			return "缺少 %d 个%s" % [
				int(context.get("material_count", 1)),
				str(context.get("material_name", "修理材料")),
			]
		"profile_missing":
			return "该物品没有可用的修理方案"
		"not_durable":
			return "该物品不具有耐久"
		"target_changed":
			return "目标物品发生变化，本次修理已取消"
		"durability_update_failed":
			return "耐久写入失败，修理材料已退回"
		"inventory_contract_missing":
			return "背包服务暂不可用"
		_:
			return "无法修理该物品"
