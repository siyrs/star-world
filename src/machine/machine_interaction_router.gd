class_name MachineInteractionRouter
extends Node

signal machine_type_registered(machine_type: StringName)
signal machine_type_rejected(machine_type: StringName, reason: String)
signal machine_opened(machine_type: StringName, machine_id: String)
signal machine_open_rejected(machine_type: StringName, machine_id: String, reason: String)
signal machine_transfer_completed(summary: Dictionary)
signal machine_transfer_rejected(summary: Dictionary)

const CapabilityPolicyScript = preload("res://src/machine/machine_capability_policy.gd")
const TransferProxyScript = preload("res://src/machine/machine_transfer_inventory_proxy.gd")
const MAX_MACHINE_TYPES := 16
const REQUIRED_SERVICE_METHODS := [
	"ensure_machine",
	"has_machine",
	"open_machine",
	"close_machine",
	"can_remove_machine",
	"remove_machine",
	"get_slot",
	"transfer_from_inventory",
	"transfer_to_inventory",
]

var game_ui: Node
var _entries: Dictionary = {}
var _registration_order: Array[StringName] = []
var _open_count := 0
var _open_rejection_count := 0
var _transfer_attempt_count := 0
var _transfer_success_count := 0
var _transfer_rejection_count := 0
var _inserted_item_count := 0
var _extracted_item_count := 0
var _last_transfer: Dictionary = {}
var _shutdown := false


func setup_ui(p_game_ui: Node) -> void:
	game_ui = p_game_ui


func register_machine_type(
	machine_type: StringName,
	service: Node,
	open_ui_method: StringName,
	slot_contracts: Array,
	label: String,
	not_empty_message: String
) -> Dictionary:
	if _shutdown:
		return _reject_registration(machine_type, "router_shutdown")
	var normalized_type := StringName(str(machine_type).strip_edges())
	if str(normalized_type).is_empty():
		return _reject_registration(machine_type, "invalid_machine_type")
	if _entries.has(normalized_type):
		return _reject_registration(normalized_type, "duplicate_machine_type")
	if _entries.size() >= MAX_MACHINE_TYPES:
		return _reject_registration(normalized_type, "machine_type_capacity")
	if service == null or not is_instance_valid(service):
		return _reject_registration(normalized_type, "invalid_service")
	for required_method: String in REQUIRED_SERVICE_METHODS:
		if not service.has_method(required_method):
			return _reject_registration(
				normalized_type,
				"service_contract:%s" % required_method
			)
	if str(open_ui_method).strip_edges().is_empty():
		return _reject_registration(normalized_type, "invalid_ui_method")
	var normalized_contracts: Dictionary = CapabilityPolicyScript.normalize_slot_contracts(
		slot_contracts
	)
	if not bool(normalized_contracts.get("success", false)):
		return _reject_registration(
			normalized_type,
			"slot_contract:%s" % str(normalized_contracts.get("reason", "invalid"))
		)
	_entries[normalized_type] = {
		"service": service,
		"open_ui_method": open_ui_method,
		"slot_contracts": normalized_contracts.get("slots", []).duplicate(true),
		"slot_contracts_by_id": normalized_contracts.get("slots_by_id", {}).duplicate(true),
		"label": label.strip_edges(),
		"not_empty_message": not_empty_message.strip_edges(),
	}
	_registration_order.append(normalized_type)
	machine_type_registered.emit(normalized_type)
	return {
		"success": true,
		"machine_type": normalized_type,
		"service": service,
		"capabilities": get_machine_capabilities(normalized_type),
	}


func has_machine_type(machine_type: StringName) -> bool:
	return _entries.has(machine_type)


func get_machine_service(machine_type: StringName) -> Node:
	var entry: Dictionary = _entries.get(machine_type, {})
	return entry.get("service") as Node


func get_slot_names(machine_type: StringName) -> Array[String]:
	var entry: Dictionary = _entries.get(machine_type, {})
	var raw_slots: Variant = entry.get("slot_contracts", [])
	var result: Array[String] = []
	if raw_slots is Array:
		for raw_slot: Variant in raw_slots:
			if raw_slot is Dictionary:
				result.append(str(raw_slot.get("id", "")))
	return result


func get_machine_capabilities(
	machine_type: StringName,
	machine_id: String = ""
) -> Dictionary:
	var entry: Dictionary = _entries.get(machine_type, {})
	if entry.is_empty():
		return {}
	var service: Node = entry.get("service") as Node
	return CapabilityPolicyScript.capability_snapshot(
		machine_type,
		machine_id,
		entry.get("slot_contracts", []),
		service != null and is_instance_valid(service)
	)


func get_slot_contract(machine_type: StringName, slot_name: String) -> Dictionary:
	var entry: Dictionary = _entries.get(machine_type, {})
	var raw_contracts: Variant = entry.get("slot_contracts_by_id", {})
	if raw_contracts is not Dictionary:
		return {}
	return CapabilityPolicyScript.get_slot_contract(raw_contracts, slot_name)


func get_not_empty_message(machine_type: StringName) -> String:
	var entry: Dictionary = _entries.get(machine_type, {})
	return str(entry.get("not_empty_message", "机器中仍有物品，请先清空后再拆除"))


func open_machine_type(
	machine_type: StringName,
	machine_id: String,
	label: String = ""
) -> Dictionary:
	if _shutdown:
		return _reject_open(machine_type, machine_id, "router_shutdown")
	var entry: Dictionary = _entries.get(machine_type, {})
	if entry.is_empty():
		return _reject_open(machine_type, machine_id, "unknown_machine_type")
	var service: Node = entry.get("service") as Node
	if service == null or not is_instance_valid(service):
		return _reject_open(machine_type, machine_id, "machine_service_missing")
	if not bool(service.call("ensure_machine", machine_id)):
		return _reject_open(machine_type, machine_id, "machine_open_failed")
	if game_ui == null or not is_instance_valid(game_ui):
		return _reject_open(machine_type, machine_id, "machine_ui_missing")
	var open_ui_method := StringName(entry.get("open_ui_method", &""))
	if str(open_ui_method).is_empty() or not game_ui.has_method(open_ui_method):
		return _reject_open(machine_type, machine_id, "machine_ui_contract")
	var resolved_label := label.strip_edges()
	if resolved_label.is_empty():
		resolved_label = str(entry.get("label", str(machine_type)))
	var opened := bool(game_ui.call(open_ui_method, machine_id, resolved_label))
	if not opened:
		service.call("close_machine")
		return _reject_open(machine_type, machine_id, "machine_ui_failed")
	_open_count += 1
	machine_opened.emit(machine_type, machine_id)
	return {
		"success": true,
		"machine_type": machine_type,
		"machine_id": machine_id,
	}


func can_insert(
	machine_type: StringName,
	machine_id: String,
	slot_name: String,
	item_id: String,
	count: int,
	metadata: Dictionary = {}
) -> Dictionary:
	var context := _transfer_context(machine_type, machine_id, slot_name)
	if not bool(context.get("success", false)):
		return context
	var slot_contract: Dictionary = context.get("slot_contract", {})
	if not CapabilityPolicyScript.has_direction(
		slot_contract, CapabilityPolicyScript.DIRECTION_INSERT
	):
		return CapabilityPolicyScript.failure(
			"direction_not_allowed", {"direction": "insert", "slot_name": slot_name}
		)
	if not bool(slot_contract.get("allow_metadata", false)) and not metadata.is_empty():
		return CapabilityPolicyScript.failure("metadata_not_supported")
	var item_registry: Variant = _get_item_registry(context.get("service") as Node)
	if item_registry == null or not bool(item_registry.call("has_item", item_id)):
		return CapabilityPolicyScript.failure("unknown_item", {"item_id": item_id})
	var count_result: Dictionary = CapabilityPolicyScript.normalize_requested_count(
		count,
		count,
		int(slot_contract.get("transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS))
	)
	if not bool(count_result.get("success", false)):
		return count_result
	var service: Node = context.get("service") as Node
	var current_slot: Dictionary = service.call("get_slot", machine_id, slot_name)
	var capacity := CapabilityPolicyScript.slot_capacity(
		current_slot,
		item_id,
		metadata,
		int(item_registry.call("get_max_stack", item_id))
	)
	if capacity < count:
		return CapabilityPolicyScript.failure(
			"slot_capacity",
			{"requested": count, "capacity": capacity, "slot_name": slot_name}
		)
	return {
		"success": true,
		"reason": "",
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"slot_name": slot_name,
		"item_id": item_id,
		"count": count,
		"capacity": capacity,
	}


func can_extract(
	machine_type: StringName,
	machine_id: String,
	slot_name: String,
	count: int = 0
) -> Dictionary:
	var context := _transfer_context(machine_type, machine_id, slot_name)
	if not bool(context.get("success", false)):
		return context
	var slot_contract: Dictionary = context.get("slot_contract", {})
	if not CapabilityPolicyScript.has_direction(
		slot_contract, CapabilityPolicyScript.DIRECTION_EXTRACT
	):
		return CapabilityPolicyScript.failure(
			"direction_not_allowed", {"direction": "extract", "slot_name": slot_name}
		)
	var service: Node = context.get("service") as Node
	var source: Dictionary = service.call("get_slot", machine_id, slot_name)
	if source.is_empty():
		return CapabilityPolicyScript.failure("empty_source")
	var available := maxi(0, int(source.get("count", 0)))
	var count_result: Dictionary = CapabilityPolicyScript.normalize_requested_count(
		count,
		available,
		int(slot_contract.get("transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS))
	)
	if not bool(count_result.get("success", false)):
		return count_result
	return {
		"success": true,
		"reason": "",
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"slot_name": slot_name,
		"item_id": str(source.get("item_id", "")),
		"metadata": source.get("metadata", {}).duplicate(true),
		"count": int(count_result.get("count", 0)),
		"available": available,
	}


func insert_transaction(
	machine_type: StringName,
	machine_id: String,
	slot_name: String,
	inventory: Node,
	inventory_index: int,
	count: int = 0
) -> Dictionary:
	_transfer_attempt_count += 1
	if inventory == null or not is_instance_valid(inventory) or not inventory.has_method("get_slot"):
		return _reject_transfer(
			machine_type, machine_id, slot_name, "insert", "inventory_unavailable"
		)
	var source: Dictionary = inventory.call("get_slot", inventory_index)
	if source.is_empty():
		return _reject_transfer(
			machine_type, machine_id, slot_name, "insert", "empty_source"
		)
	var available := maxi(0, int(source.get("count", 0)))
	var slot_contract := get_slot_contract(machine_type, slot_name)
	if slot_contract.is_empty():
		return _reject_transfer(
			machine_type, machine_id, slot_name, "insert", "unknown_slot"
		)
	var count_result: Dictionary = CapabilityPolicyScript.normalize_requested_count(
		count,
		available,
		int(slot_contract.get("transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS))
	)
	if not bool(count_result.get("success", false)):
		return _reject_transfer(
			machine_type,
			machine_id,
			slot_name,
			"insert",
			str(count_result.get("reason", "invalid_count")),
			count_result
		)
	var requested := int(count_result.get("count", 0))
	var validation := can_insert(
		machine_type,
		machine_id,
		slot_name,
		str(source.get("item_id", "")),
		requested,
		source.get("metadata", {})
	)
	if not bool(validation.get("success", false)):
		return _reject_transfer(
			machine_type,
			machine_id,
			slot_name,
			"insert",
			str(validation.get("reason", "insert_rejected")),
			validation
		)
	var proxy = TransferProxyScript.new()
	if not proxy.setup_insert(inventory, inventory_index, requested, source):
		return _reject_transfer(
			machine_type, machine_id, slot_name, "insert", proxy.failure_reason
		)
	var service := get_machine_service(machine_type)
	var accepted := bool(service.call(
		"transfer_from_inventory", proxy, 0, slot_name, machine_id
	))
	if not accepted or proxy.get_moved_count() != requested:
		return _reject_transfer(
			machine_type,
			machine_id,
			slot_name,
			"insert",
			proxy.failure_reason if not proxy.failure_reason.is_empty() else "service_rejected"
		)
	return _complete_transfer({
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"slot_name": slot_name,
		"direction": "insert",
		"item_id": str(source.get("item_id", "")),
		"count": requested,
	})


func extract_transaction(
	machine_type: StringName,
	machine_id: String,
	slot_name: String,
	inventory: Node,
	count: int = 0
) -> Dictionary:
	_transfer_attempt_count += 1
	if (
		inventory == null
		or not is_instance_valid(inventory)
		or not inventory.has_method("can_transact_items")
		or not inventory.has_method("transact_items")
	):
		return _reject_transfer(
			machine_type, machine_id, slot_name, "extract", "inventory_contract"
		)
	var validation := can_extract(machine_type, machine_id, slot_name, count)
	if not bool(validation.get("success", false)):
		return _reject_transfer(
			machine_type,
			machine_id,
			slot_name,
			"extract",
			str(validation.get("reason", "extract_rejected")),
			validation
		)
	var requested := int(validation.get("count", 0))
	var source := {
		"item_id": str(validation.get("item_id", "")),
		"count": int(validation.get("available", requested)),
		"metadata": validation.get("metadata", {}).duplicate(true),
	}
	var addition := [{
		"item_id": str(source.get("item_id", "")),
		"count": requested,
		"metadata": source.get("metadata", {}).duplicate(true),
	}]
	if not bool(inventory.call("can_transact_items", {}, addition)):
		return _reject_transfer(
			machine_type, machine_id, slot_name, "extract", "inventory_full"
		)
	var proxy = TransferProxyScript.new()
	if not proxy.setup_extract(inventory, requested, source):
		return _reject_transfer(
			machine_type, machine_id, slot_name, "extract", proxy.failure_reason
		)
	var service := get_machine_service(machine_type)
	var extracted := bool(service.call(
		"transfer_to_inventory", proxy, slot_name, machine_id
	))
	if not extracted or proxy.get_moved_count() != requested:
		return _reject_transfer(
			machine_type,
			machine_id,
			slot_name,
			"extract",
			proxy.failure_reason if not proxy.failure_reason.is_empty() else "service_rejected"
		)
	return _complete_transfer({
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"slot_name": slot_name,
		"direction": "extract",
		"item_id": str(source.get("item_id", "")),
		"count": requested,
	})


func can_remove_machine_type(machine_type: StringName, machine_id: String) -> Dictionary:
	var entry: Dictionary = _entries.get(machine_type, {})
	var service: Node = entry.get("service") as Node
	if service == null or not is_instance_valid(service):
		return {
			"allowed": false,
			"reason": "machine_service_missing",
			"message": "机器服务暂不可用，为保护内容已阻止拆除",
		}
	# Registered slots are the persistent player-owned contents. Runtime heat,
	# animation and other transient state may be discarded with an empty machine.
	for slot_name: String in get_slot_names(machine_type):
		var raw_slot: Variant = service.call("get_slot", machine_id, slot_name)
		if raw_slot is Dictionary and int(raw_slot.get("count", 0)) > 0:
			return {
				"allowed": false,
				"reason": "machine_not_empty",
				"message": get_not_empty_message(machine_type),
			}
	return {
		"allowed": true,
		"reason": "",
		"message": "",
	}


func remove_machine_type(
	machine_type: StringName,
	machine_id: String,
	require_empty: bool = false
) -> bool:
	var service := get_machine_service(machine_type)
	if service == null or not is_instance_valid(service):
		return false
	return bool(service.call("remove_machine", machine_id, require_empty))


func close_machine_type(machine_type: StringName) -> void:
	var service := get_machine_service(machine_type)
	if service != null and is_instance_valid(service):
		service.call("close_machine")


func get_snapshot() -> Dictionary:
	var machine_types: Array[String] = []
	var service_ready: Dictionary = {}
	var capabilities: Dictionary = {}
	for machine_type: StringName in _registration_order:
		machine_types.append(str(machine_type))
		var service := get_machine_service(machine_type)
		service_ready[str(machine_type)] = service != null and is_instance_valid(service)
		capabilities[str(machine_type)] = get_machine_capabilities(machine_type)
	return {
		"shutdown": _shutdown,
		"machine_type_count": _registration_order.size(),
		"machine_types": machine_types,
		"service_ready": service_ready,
		"capabilities": capabilities,
		"open_count": _open_count,
		"open_rejection_count": _open_rejection_count,
		"transfer_attempt_count": _transfer_attempt_count,
		"transfer_success_count": _transfer_success_count,
		"transfer_rejection_count": _transfer_rejection_count,
		"inserted_item_count": _inserted_item_count,
		"extracted_item_count": _extracted_item_count,
		"last_transfer": _last_transfer.duplicate(true),
	}


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	game_ui = null
	_entries.clear()
	_registration_order.clear()
	_last_transfer.clear()


func _transfer_context(
	machine_type: StringName,
	machine_id: String,
	slot_name: String
) -> Dictionary:
	if _shutdown:
		return CapabilityPolicyScript.failure("router_shutdown")
	var entry: Dictionary = _entries.get(machine_type, {})
	if entry.is_empty():
		return CapabilityPolicyScript.failure("unknown_machine_type")
	var service: Node = entry.get("service") as Node
	if service == null or not is_instance_valid(service):
		return CapabilityPolicyScript.failure("machine_service_missing")
	if machine_id.is_empty() or not bool(service.call("has_machine", machine_id)):
		return CapabilityPolicyScript.failure("machine_missing")
	var slot_contract := get_slot_contract(machine_type, slot_name)
	if slot_contract.is_empty():
		return CapabilityPolicyScript.failure("unknown_slot", {"slot_name": slot_name})
	return {
		"success": true,
		"reason": "",
		"entry": entry,
		"service": service,
		"slot_contract": slot_contract,
	}


func _get_item_registry(service: Node) -> Variant:
	if service == null or not is_instance_valid(service):
		return null
	return service.get("item_registry")


func _complete_transfer(summary: Dictionary) -> Dictionary:
	_transfer_success_count += 1
	var count := maxi(0, int(summary.get("count", 0)))
	if str(summary.get("direction", "")) == "insert":
		_inserted_item_count += count
	else:
		_extracted_item_count += count
	var result := summary.duplicate(true)
	result["success"] = true
	result["reason"] = ""
	result["transfer_index"] = _transfer_success_count
	_last_transfer = result.duplicate(true)
	machine_transfer_completed.emit(result.duplicate(true))
	return result


func _reject_transfer(
	machine_type: StringName,
	machine_id: String,
	slot_name: String,
	direction: String,
	reason: String,
	extra: Dictionary = {}
) -> Dictionary:
	_transfer_rejection_count += 1
	var result := {
		"success": false,
		"reason": reason,
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"slot_name": slot_name,
		"direction": direction,
	}
	for raw_key: Variant in extra.keys():
		var key := str(raw_key)
		if key in ["success", "reason"]:
			continue
		result[key] = extra[raw_key]
	_last_transfer = result.duplicate(true)
	machine_transfer_rejected.emit(result.duplicate(true))
	return result


func _reject_registration(machine_type: StringName, reason: String) -> Dictionary:
	machine_type_rejected.emit(machine_type, reason)
	return {
		"success": false,
		"reason": reason,
		"machine_type": machine_type,
	}


func _reject_open(
	machine_type: StringName,
	machine_id: String,
	reason: String
) -> Dictionary:
	_open_rejection_count += 1
	machine_open_rejected.emit(machine_type, machine_id, reason)
	return {
		"success": false,
		"reason": reason,
		"machine_type": machine_type,
		"machine_id": machine_id,
	}
