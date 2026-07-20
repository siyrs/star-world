class_name MachineCapabilityPolicy
extends RefCounted

const DIRECTION_INSERT := "insert"
const DIRECTION_EXTRACT := "extract"
const VALID_DIRECTIONS := [DIRECTION_INSERT, DIRECTION_EXTRACT]
const MAX_TRANSFER_ITEMS := 64


static func normalize_slot_contracts(raw_contracts: Array) -> Dictionary:
	var slots: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for raw_contract: Variant in raw_contracts:
		var contract := _normalize_slot_contract(raw_contract)
		if not bool(contract.get("success", false)):
			return contract
		var slot: Dictionary = contract.get("slot", {})
		var slot_id := str(slot.get("id", ""))
		if by_id.has(slot_id):
			return failure("duplicate_slot", {"slot_id": slot_id})
		by_id[slot_id] = slot.duplicate(true)
		slots.append(slot)
	if slots.is_empty():
		return failure("invalid_slot_contract")
	return {
		"success": true,
		"reason": "",
		"slots": slots,
		"slots_by_id": by_id,
	}


static func get_slot_contract(slots_by_id: Dictionary, slot_name: String) -> Dictionary:
	return slots_by_id.get(slot_name, {}).duplicate(true)


static func has_direction(slot_contract: Dictionary, direction: String) -> bool:
	var raw_directions: Variant = slot_contract.get("directions", [])
	return raw_directions is Array and direction in raw_directions


static func normalize_requested_count(count: int, available: int, limit: int) -> Dictionary:
	var normalized_limit := clampi(limit, 1, MAX_TRANSFER_ITEMS)
	var requested := available if count <= 0 else count
	if requested <= 0:
		return failure("empty_source")
	if requested > normalized_limit:
		return failure(
			"transaction_limit",
			{"requested": requested, "limit": normalized_limit}
		)
	if requested > available:
		return failure(
			"source_insufficient",
			{"requested": requested, "available": available}
		)
	return {
		"success": true,
		"reason": "",
		"count": requested,
		"limit": normalized_limit,
	}


static func slot_capacity(
	current_slot: Dictionary,
	item_id: String,
	metadata: Dictionary,
	max_stack: int
) -> int:
	if item_id.is_empty() or max_stack <= 0:
		return 0
	if current_slot.is_empty():
		return max_stack
	if (
		str(current_slot.get("item_id", "")) != item_id
		or current_slot.get("metadata", {}) != metadata
	):
		return 0
	return maxi(0, max_stack - int(current_slot.get("count", 0)))


static func capability_snapshot(
	machine_type: StringName,
	machine_id: String,
	slots: Array,
	service_ready: bool
) -> Dictionary:
	var normalized_slots: Array[Dictionary] = []
	for raw_slot: Variant in slots:
		if raw_slot is Dictionary:
			normalized_slots.append(raw_slot.duplicate(true))
	return {
		"schema_version": 1,
		"machine_type": str(machine_type),
		"machine_id": machine_id,
		"service_ready": service_ready,
		"max_transfer_items": MAX_TRANSFER_ITEMS,
		"slots": normalized_slots,
	}


static func failure(reason: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "reason": reason}
	result.merge(extra, true)
	return result


static func _normalize_slot_contract(raw_contract: Variant) -> Dictionary:
	var slot_id := ""
	var raw_directions: Variant = []
	var transaction_limit := MAX_TRANSFER_ITEMS
	var allow_metadata := false
	if raw_contract is Dictionary:
		slot_id = str(raw_contract.get("id", raw_contract.get("slot_id", ""))).strip_edges()
		raw_directions = raw_contract.get(
			"directions",
			[raw_contract.get("direction", raw_contract.get("mode", ""))]
		)
		transaction_limit = int(raw_contract.get("transaction_limit", MAX_TRANSFER_ITEMS))
		allow_metadata = bool(raw_contract.get("allow_metadata", false))
	else:
		slot_id = str(raw_contract).strip_edges()
		raw_directions = [
			DIRECTION_EXTRACT if slot_id == "output" else DIRECTION_INSERT
		]
	if slot_id.is_empty() or "\n" in slot_id or "\r" in slot_id:
		return failure("invalid_slot_id", {"slot_id": slot_id})
	var directions: Array[String] = []
	if raw_directions is Array:
		for raw_direction: Variant in raw_directions:
			var direction := str(raw_direction).strip_edges()
			if direction.is_empty() or direction in directions:
				continue
			if direction not in VALID_DIRECTIONS:
				return failure(
					"invalid_direction",
					{"slot_id": slot_id, "direction": direction}
				)
			directions.append(direction)
	if directions.is_empty():
		return failure("missing_direction", {"slot_id": slot_id})
	if transaction_limit < 1 or transaction_limit > MAX_TRANSFER_ITEMS:
		return failure(
			"invalid_transaction_limit",
			{"slot_id": slot_id, "limit": transaction_limit}
		)
	return {
		"success": true,
		"slot": {
			"id": slot_id,
			"directions": directions,
			"transaction_limit": transaction_limit,
			"allow_metadata": allow_metadata,
		},
	}
