class_name MachineAutomationService
extends Node

signal automation_cycle_completed(summary: Dictionary)
signal automation_machine_activated(summary: Dictionary)

const PolicyScript = preload("res://src/machine/machine_automation_policy.gd")
const CapabilityPolicyScript = preload("res://src/machine/machine_capability_policy.gd")
const ContainerPortScript = preload("res://src/machine/machine_container_inventory_port.gd")
const InteractionRegistryScript = preload("res://src/interaction/block_interaction_registry.gd")

var router: Node
var container_storage: Node
var world: Node
var _input_port: Node
var _output_port: Node
var _accumulator := 0.0
var _cursor := 0
var _shutdown := false
var _externally_scheduled := false
var _cycle_count := 0
var _total_machine_scans := 0
var _total_container_slot_scans := 0
var _total_transfer_count := 0
var _total_input_items := 0
var _total_output_items := 0
var _max_items_in_cycle := 0
var _announced_machines: Dictionary = {}
var _last_cycle: Dictionary = {}


func setup(p_router: Node, p_container_storage: Node) -> bool:
	if (
		p_router == null
		or not is_instance_valid(p_router)
		or p_container_storage == null
		or not is_instance_valid(p_container_storage)
		or not p_router.has_method("get_machine_capabilities")
		or not p_router.has_method("get_machine_service")
		or not p_router.has_method("insert_transaction")
		or not p_router.has_method("extract_transaction")
		or not p_container_storage.has_method("ensure_container")
		or not p_container_storage.has_method("get_slot_count")
	):
		return false
	router = p_router
	container_storage = p_container_storage
	_input_port = ContainerPortScript.new()
	_input_port.name = "AutomationInputContainerPort"
	add_child(_input_port)
	_output_port = ContainerPortScript.new()
	_output_port.name = "AutomationOutputContainerPort"
	add_child(_output_port)
	_shutdown = false
	return true


func set_external_scheduler(value: bool) -> void:
	_externally_scheduled = value


func is_externally_scheduled() -> bool:
	return _externally_scheduled


func attach_world(p_world: Node) -> void:
	world = p_world
	_accumulator = 0.0
	_cursor = 0
	_announced_machines.clear()


func advance_machine_runtime(seconds: float, emit_events: bool = true) -> Dictionary:
	if _shutdown or world == null or not is_instance_valid(world) or not emit_events:
		return _idle_summary(seconds, "inactive")
	var elapsed := clampf(seconds, 0.0, 1.0) if is_finite(seconds) else 0.0
	if elapsed <= 0.0:
		return _idle_summary(seconds, "invalid_elapsed")
	_accumulator += elapsed
	if not PolicyScript.cycle_due(_accumulator):
		return _idle_summary(elapsed, "interval_pending")
	_accumulator = PolicyScript.normalized_accumulator(_accumulator)
	return _run_cycle(elapsed)


func get_runtime_snapshot() -> Dictionary:
	return {
		"machine_count": 0,
		"active": world != null and is_instance_valid(world) and not _shutdown,
		"shutdown": _shutdown,
		"externally_scheduled": _externally_scheduled,
		"cycle_interval_seconds": PolicyScript.CYCLE_INTERVAL_SECONDS,
		"max_machines_per_cycle": PolicyScript.MAX_MACHINES_PER_CYCLE,
		"max_items_per_cycle": PolicyScript.MAX_ITEMS_PER_CYCLE,
		"max_items_per_transfer": PolicyScript.MAX_ITEMS_PER_TRANSFER,
		"max_container_slots_per_cycle": PolicyScript.MAX_CONTAINER_SLOTS_PER_CYCLE,
		"cycle_count": _cycle_count,
		"total_machine_scans": _total_machine_scans,
		"total_container_slot_scans": _total_container_slot_scans,
		"total_transfer_count": _total_transfer_count,
		"total_input_items": _total_input_items,
		"total_output_items": _total_output_items,
		"max_items_in_cycle": _max_items_in_cycle,
		"announced_machine_count": _announced_machines.size(),
		"last_cycle": _last_cycle.duplicate(true),
	}


func clear() -> void:
	world = null
	_accumulator = 0.0
	_cursor = 0
	_cycle_count = 0
	_total_machine_scans = 0
	_total_container_slot_scans = 0
	_total_transfer_count = 0
	_total_input_items = 0
	_total_output_items = 0
	_max_items_in_cycle = 0
	_announced_machines.clear()
	_last_cycle.clear()
	if _input_port != null and is_instance_valid(_input_port):
		_input_port.call("clear")
	if _output_port != null and is_instance_valid(_output_port):
		_output_port.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear()
	router = null
	container_storage = null


func _run_cycle(elapsed: float) -> Dictionary:
	_cycle_count += 1
	var candidates := _collect_candidates()
	var candidate_count := candidates.size()
	var machine_budget := mini(candidate_count, PolicyScript.MAX_MACHINES_PER_CYCLE)
	var item_budget := PolicyScript.MAX_ITEMS_PER_CYCLE
	var slot_budget := PolicyScript.MAX_CONTAINER_SLOTS_PER_CYCLE
	var changed_machine_keys: Dictionary = {}
	var transfers: Array[Dictionary] = []
	var input_items := 0
	var output_items := 0
	var scanned := 0
	var slots_scanned := 0
	var start := posmod(_cursor, candidate_count) if candidate_count > 0 else 0
	for offset in machine_budget:
		if item_budget <= 0 or slot_budget <= 0:
			break
		var candidate: Dictionary = candidates[(start + offset) % candidate_count]
		var outcome := _process_machine(candidate, item_budget, slot_budget)
		scanned += 1
		var moved := maxi(0, int(outcome.get("items_moved", 0)))
		var inspected_slots := maxi(0, int(outcome.get("slots_scanned", 0)))
		item_budget = maxi(0, item_budget - moved)
		slot_budget = maxi(0, slot_budget - inspected_slots)
		slots_scanned += inspected_slots
		input_items += maxi(0, int(outcome.get("input_items", 0)))
		output_items += maxi(0, int(outcome.get("output_items", 0)))
		var raw_transfers: Variant = outcome.get("transfers", [])
		if raw_transfers is Array:
			for raw_transfer: Variant in raw_transfers:
				if raw_transfer is Dictionary:
					transfers.append(raw_transfer.duplicate(true))
		if moved > 0:
			var machine_key := "%s|%s" % [
				str(candidate.get("machine_type", "")),
				str(candidate.get("machine_id", "")),
			]
			changed_machine_keys[machine_key] = true
			if not _announced_machines.has(machine_key):
				_announced_machines[machine_key] = true
				automation_machine_activated.emit({
					"machine_type": str(candidate.get("machine_type", "")),
					"machine_id": str(candidate.get("machine_id", "")),
					"input_container_id": str(outcome.get("input_container_id", "")),
					"output_container_id": str(outcome.get("output_container_id", "")),
				})
	if candidate_count > 0:
		_cursor = (start + scanned) % candidate_count
	else:
		_cursor = 0
	var moved_total := input_items + output_items
	_total_machine_scans += scanned
	_total_container_slot_scans += slots_scanned
	_total_transfer_count += transfers.size()
	_total_input_items += input_items
	_total_output_items += output_items
	_max_items_in_cycle = maxi(_max_items_in_cycle, moved_total)
	_last_cycle = {
		"elapsed_seconds": elapsed,
		"cycle_index": _cycle_count,
		"candidate_machine_count": candidate_count,
		"scanned_machine_count": scanned,
		"changed_machine_count": changed_machine_keys.size(),
		"slots_scanned": slots_scanned,
		"transfer_count": transfers.size(),
		"input_items": input_items,
		"output_items": output_items,
		"items_moved": moved_total,
		"remaining_item_budget": item_budget,
		"remaining_slot_budget": slot_budget,
		"transfers": transfers.duplicate(true),
	}
	if not transfers.is_empty():
		automation_cycle_completed.emit(_last_cycle.duplicate(true))
	return _last_cycle.duplicate(true)


func _collect_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if router == null or not is_instance_valid(router):
		return result
	var snapshot: Dictionary = router.call("get_snapshot")
	var raw_types: Variant = snapshot.get("machine_types", [])
	if raw_types is not Array:
		return result
	for raw_type: Variant in raw_types:
		var machine_type := StringName(str(raw_type))
		var service: Node = router.call("get_machine_service", machine_type) as Node
		if service == null or not is_instance_valid(service) or not service.has_method("get_machine_ids"):
			continue
		var raw_ids: Variant = service.call("get_machine_ids")
		if raw_ids is not Array:
			continue
		for raw_id: Variant in raw_ids:
			var machine_id := str(raw_id)
			result.append({
				"machine_type": machine_type,
				"machine_id": machine_id,
				"sort_key": "%s|%s" % [str(machine_type), machine_id],
			})
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return result


func _process_machine(candidate: Dictionary, item_budget: int, slot_budget: int) -> Dictionary:
	var result := {
		"items_moved": 0,
		"input_items": 0,
		"output_items": 0,
		"slots_scanned": 0,
		"transfers": [],
		"input_container_id": "",
		"output_container_id": "",
	}
	var machine_type := StringName(str(candidate.get("machine_type", "")))
	var machine_id := str(candidate.get("machine_id", ""))
	var parsed: Dictionary = PolicyScript.parse_machine_position(machine_type, machine_id)
	if not bool(parsed.get("success", false)):
		return result
	var machine_position: Vector3i = parsed.get("position", Vector3i.ZERO)
	var machine_block_id := InteractionRegistryScript.get_machine_block_id(machine_type)
	if (
		machine_block_id.is_empty()
		or world == null
		or not world.has_method("get_block")
		or str(world.call("get_block", machine_position)) != machine_block_id
	):
		return result
	var input_container_id := _resolve_container(PolicyScript.input_position(machine_position))
	var output_container_id := _resolve_container(PolicyScript.output_position(machine_position))
	result["input_container_id"] = input_container_id
	result["output_container_id"] = output_container_id
	if input_container_id.is_empty() and output_container_id.is_empty():
		return result
	var service: Node = router.call("get_machine_service", machine_type) as Node
	if service == null or not is_instance_valid(service):
		return result
	var capabilities: Dictionary = router.call("get_machine_capabilities", machine_type, machine_id)
	var raw_contracts: Variant = capabilities.get("slots", [])
	if raw_contracts is not Array:
		return result
	var remaining_items := maxi(0, item_budget)
	var remaining_slots := maxi(0, slot_budget)
	var transfers: Array[Dictionary] = []
	if not output_container_id.is_empty() and remaining_items > 0:
		_output_port.call("configure", container_storage, output_container_id)
		for raw_contract: Variant in raw_contracts:
			if raw_contract is not Dictionary:
				continue
			var contract: Dictionary = raw_contract
			if not CapabilityPolicyScript.has_direction(contract, CapabilityPolicyScript.DIRECTION_EXTRACT):
				continue
			var slot_name := str(contract.get("id", ""))
			var source: Dictionary = service.call("get_slot", machine_id, slot_name)
			var requested := PolicyScript.transfer_count(
				int(source.get("count", 0)),
				remaining_items,
				int(contract.get("transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS))
			)
			if requested <= 0:
				continue
			var transfer: Dictionary = router.call(
				"extract_transaction",
				machine_type,
				machine_id,
				slot_name,
				_output_port,
				requested
			)
			if not bool(transfer.get("success", false)):
				continue
			transfer["container_id"] = output_container_id
			transfers.append(transfer.duplicate(true))
			var moved := maxi(0, int(transfer.get("count", 0)))
			result["output_items"] = int(result.get("output_items", 0)) + moved
			remaining_items = maxi(0, remaining_items - moved)
			if remaining_items <= 0:
				break
	if not input_container_id.is_empty() and remaining_items > 0 and remaining_slots > 0:
		_input_port.call("configure", container_storage, input_container_id)
		var source_slot_count := mini(
			int(_input_port.call("get_slot_count")), remaining_slots
		)
		for source_index in source_slot_count:
			result["slots_scanned"] = int(result.get("slots_scanned", 0)) + 1
			remaining_slots -= 1
			var source: Dictionary = _input_port.call("get_slot", source_index)
			if source.is_empty():
				continue
			var source_count := maxi(0, int(source.get("count", 0)))
			if source_count <= 0:
				continue
			for raw_contract: Variant in raw_contracts:
				if raw_contract is not Dictionary:
					continue
				var contract: Dictionary = raw_contract
				if not CapabilityPolicyScript.has_direction(contract, CapabilityPolicyScript.DIRECTION_INSERT):
					continue
				var slot_name := str(contract.get("id", ""))
				var probe: Dictionary = router.call(
					"can_insert",
					machine_type,
					machine_id,
					slot_name,
					str(source.get("item_id", "")),
					1,
					source.get("metadata", {})
				)
				if not bool(probe.get("success", false)):
					continue
				var requested := PolicyScript.transfer_count(
					mini(source_count, int(probe.get("capacity", source_count))),
					remaining_items,
					int(contract.get("transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS))
				)
				if requested <= 0:
					continue
				var transfer: Dictionary = router.call(
					"insert_transaction",
					machine_type,
					machine_id,
					slot_name,
					_input_port,
					source_index,
					requested
				)
				if not bool(transfer.get("success", false)):
					continue
				transfer["container_id"] = input_container_id
				transfers.append(transfer.duplicate(true))
				var moved := maxi(0, int(transfer.get("count", 0)))
				result["input_items"] = int(result.get("input_items", 0)) + moved
				remaining_items = maxi(0, remaining_items - moved)
				break
			if remaining_items <= 0 or remaining_slots <= 0:
				break
	result["items_moved"] = (
		int(result.get("input_items", 0)) + int(result.get("output_items", 0))
	)
	result["transfers"] = transfers
	return result


func _resolve_container(position: Vector3i) -> String:
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_method("get_block")
		or str(world.call("get_block", position)) != PolicyScript.CONTAINER_BLOCK_ID
	):
		return ""
	var container_id := PolicyScript.container_id(position)
	var raw: Variant = container_storage.call(
		"ensure_container",
		container_id,
		PolicyScript.CONTAINER_BLOCK_ID,
		PolicyScript.CONTAINER_SLOT_COUNT
	)
	return container_id if raw is Dictionary and not raw.is_empty() else ""


func _idle_summary(elapsed: float, reason: String) -> Dictionary:
	return {
		"elapsed_seconds": elapsed if is_finite(elapsed) else 0.0,
		"machine_count": 0,
		"changed_machine_count": 0,
		"items_moved": 0,
		"reason": reason,
	}
