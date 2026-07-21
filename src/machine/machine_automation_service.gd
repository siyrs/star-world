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
var _total_transfer_attempts := 0
var _total_transfer_count := 0
var _total_input_items := 0
var _total_output_items := 0
var _max_items_in_cycle := 0
var _cache_rebuild_count := 0
var _candidate_event_count := 0
var _announced_machines: Dictionary = {}
var _candidates: Dictionary = {}
var _candidate_order: Array[String] = []
var _service_bindings: Array[Dictionary] = []
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
		or not p_container_storage.has_method("can_transact_items")
		or not p_container_storage.has_method("transact_items")
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
	if router.has_signal("machine_type_registered"):
		var callback := Callable(self, "_on_machine_type_registered")
		if not router.is_connected("machine_type_registered", callback):
			router.connect("machine_type_registered", callback)
	_shutdown = false
	_bind_registered_services()
	_rebuild_candidates()
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
	_rebuild_candidates()


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
		"tracked_machine_count": _candidate_order.size(),
		"active": world != null and is_instance_valid(world) and not _shutdown,
		"shutdown": _shutdown,
		"externally_scheduled": _externally_scheduled,
		"cycle_interval_seconds": PolicyScript.CYCLE_INTERVAL_SECONDS,
		"max_machines_per_cycle": PolicyScript.MAX_MACHINES_PER_CYCLE,
		"max_items_per_cycle": PolicyScript.MAX_ITEMS_PER_CYCLE,
		"max_items_per_transfer": PolicyScript.MAX_ITEMS_PER_TRANSFER,
		"max_container_slots_per_cycle": PolicyScript.MAX_CONTAINER_SLOTS_PER_CYCLE,
		"max_transfer_attempts_per_cycle": PolicyScript.MAX_TRANSFER_ATTEMPTS_PER_CYCLE,
		"cycle_count": _cycle_count,
		"total_machine_scans": _total_machine_scans,
		"total_container_slot_scans": _total_container_slot_scans,
		"total_transfer_attempts": _total_transfer_attempts,
		"total_transfer_count": _total_transfer_count,
		"total_input_items": _total_input_items,
		"total_output_items": _total_output_items,
		"max_items_in_cycle": _max_items_in_cycle,
		"cache_rebuild_count": _cache_rebuild_count,
		"candidate_event_count": _candidate_event_count,
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
	_total_transfer_attempts = 0
	_total_transfer_count = 0
	_total_input_items = 0
	_total_output_items = 0
	_max_items_in_cycle = 0
	_announced_machines.clear()
	_candidates.clear()
	_candidate_order.clear()
	_last_cycle.clear()
	if _input_port != null and is_instance_valid(_input_port):
		_input_port.call("clear")
	if _output_port != null and is_instance_valid(_output_port):
		_output_port.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	_disconnect_service_bindings()
	if router != null and is_instance_valid(router) and router.has_signal("machine_type_registered"):
		var callback := Callable(self, "_on_machine_type_registered")
		if router.is_connected("machine_type_registered", callback):
			router.disconnect("machine_type_registered", callback)
	clear()
	router = null
	container_storage = null


func _run_cycle(elapsed: float) -> Dictionary:
	_cycle_count += 1
	var candidate_count := _candidate_order.size()
	var machine_budget := mini(candidate_count, PolicyScript.MAX_MACHINES_PER_CYCLE)
	var item_budget := PolicyScript.MAX_ITEMS_PER_CYCLE
	var slot_budget := PolicyScript.MAX_CONTAINER_SLOTS_PER_CYCLE
	var attempt_budget := PolicyScript.MAX_TRANSFER_ATTEMPTS_PER_CYCLE
	var changed_machine_keys: Dictionary = {}
	var stale_keys: Array[String] = []
	var transfers: Array[Dictionary] = []
	var input_items := 0
	var output_items := 0
	var scanned := 0
	var slots_scanned := 0
	var attempts := 0
	var start := posmod(_cursor, candidate_count) if candidate_count > 0 else 0
	for offset in machine_budget:
		if item_budget <= 0 or slot_budget <= 0 or attempt_budget <= 0:
			break
		var candidate_key := _candidate_order[(start + offset) % candidate_count]
		var candidate: Dictionary = _candidates.get(candidate_key, {})
		if candidate.is_empty():
			stale_keys.append(candidate_key)
			continue
		var outcome := _process_machine(
			candidate, item_budget, slot_budget, attempt_budget
		)
		scanned += 1
		if bool(outcome.get("stale", false)):
			stale_keys.append(candidate_key)
		var moved := maxi(0, int(outcome.get("items_moved", 0)))
		var inspected_slots := maxi(0, int(outcome.get("slots_scanned", 0)))
		var used_attempts := maxi(0, int(outcome.get("transfer_attempts", 0)))
		item_budget = maxi(0, item_budget - moved)
		slot_budget = maxi(0, slot_budget - inspected_slots)
		attempt_budget = maxi(0, attempt_budget - used_attempts)
		slots_scanned += inspected_slots
		attempts += used_attempts
		input_items += maxi(0, int(outcome.get("input_items", 0)))
		output_items += maxi(0, int(outcome.get("output_items", 0)))
		var raw_transfers: Variant = outcome.get("transfers", [])
		if raw_transfers is Array:
			for raw_transfer: Variant in raw_transfers:
				if raw_transfer is Dictionary:
					transfers.append(raw_transfer.duplicate(true))
		if moved > 0:
			changed_machine_keys[candidate_key] = true
			if not _announced_machines.has(candidate_key):
				_announced_machines[candidate_key] = true
				automation_machine_activated.emit({
					"machine_type": str(candidate.get("machine_type", "")),
					"machine_id": str(candidate.get("machine_id", "")),
					"input_container_id": str(outcome.get("input_container_id", "")),
					"output_container_id": str(outcome.get("output_container_id", "")),
				})
	for candidate_key: String in stale_keys:
		_remove_candidate(candidate_key)
	if not _candidate_order.is_empty():
		_cursor = (start + scanned) % _candidate_order.size()
	else:
		_cursor = 0
	var moved_total := input_items + output_items
	_total_machine_scans += scanned
	_total_container_slot_scans += slots_scanned
	_total_transfer_attempts += attempts
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
		"transfer_attempts": attempts,
		"transfer_count": transfers.size(),
		"input_items": input_items,
		"output_items": output_items,
		"items_moved": moved_total,
		"remaining_item_budget": item_budget,
		"remaining_slot_budget": slot_budget,
		"remaining_attempt_budget": attempt_budget,
		"transfers": transfers.duplicate(true),
	}
	if not transfers.is_empty():
		automation_cycle_completed.emit(_last_cycle.duplicate(true))
	return _last_cycle.duplicate(true)


func _process_machine(
	candidate: Dictionary,
	item_budget: int,
	slot_budget: int,
	attempt_budget: int
) -> Dictionary:
	var result := {
		"stale": false,
		"items_moved": 0,
		"input_items": 0,
		"output_items": 0,
		"slots_scanned": 0,
		"transfer_attempts": 0,
		"transfers": [],
		"input_container_id": "",
		"output_container_id": "",
	}
	var machine_type := StringName(str(candidate.get("machine_type", "")))
	var machine_id := str(candidate.get("machine_id", ""))
	var service: Node = router.call("get_machine_service", machine_type) as Node
	if (
		service == null
		or not is_instance_valid(service)
		or not service.has_method("has_machine")
		or not bool(service.call("has_machine", machine_id))
	):
		result["stale"] = true
		return result
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
	var capabilities: Dictionary = router.call(
		"get_machine_capabilities", machine_type, machine_id
	)
	var raw_contracts: Variant = capabilities.get("slots", [])
	if raw_contracts is not Array:
		return result
	var remaining_items := maxi(0, item_budget)
	var remaining_slots := maxi(0, slot_budget)
	var remaining_attempts := maxi(0, attempt_budget)
	var transfers: Array[Dictionary] = []
	if not output_container_id.is_empty() and remaining_items > 0 and remaining_attempts > 0:
		if bool(_output_port.call("configure", container_storage, output_container_id)):
			for raw_contract: Variant in raw_contracts:
				if raw_contract is not Dictionary or remaining_attempts <= 0:
					continue
				var contract: Dictionary = raw_contract
				if not CapabilityPolicyScript.has_direction(
					contract, CapabilityPolicyScript.DIRECTION_EXTRACT
				):
					continue
				var slot_name := str(contract.get("id", ""))
				var source: Dictionary = service.call("get_slot", machine_id, slot_name)
				var requested := PolicyScript.transfer_count(
					int(source.get("count", 0)),
					remaining_items,
					int(contract.get(
						"transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS
					))
				)
				if requested <= 0:
					continue
				remaining_attempts -= 1
				result["transfer_attempts"] = int(result.get("transfer_attempts", 0)) + 1
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
	if (
		not input_container_id.is_empty()
		and remaining_items > 0
		and remaining_slots > 0
		and remaining_attempts > 0
	):
		if bool(_input_port.call("configure", container_storage, input_container_id)):
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
					if raw_contract is not Dictionary or remaining_attempts <= 0:
						continue
					var contract: Dictionary = raw_contract
					if not CapabilityPolicyScript.has_direction(
						contract, CapabilityPolicyScript.DIRECTION_INSERT
					):
						continue
					remaining_attempts -= 1
					result["transfer_attempts"] = int(result.get("transfer_attempts", 0)) + 1
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
					if service.has_method("can_insert_item"):
						var semantic: Variant = service.call(
							"can_insert_item",
							machine_id,
							slot_name,
							str(source.get("item_id", "")),
							1,
							source.get("metadata", {})
						)
						if semantic is Dictionary and not bool(semantic.get("success", false)):
							continue
					var requested := PolicyScript.transfer_count(
						mini(source_count, int(probe.get("capacity", source_count))),
						remaining_items,
						int(contract.get(
							"transaction_limit", CapabilityPolicyScript.MAX_TRANSFER_ITEMS
						))
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
				if remaining_items <= 0 or remaining_slots <= 0 or remaining_attempts <= 0:
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


func _bind_registered_services() -> void:
	if router == null or not is_instance_valid(router):
		return
	var snapshot: Dictionary = router.call("get_snapshot")
	var raw_types: Variant = snapshot.get("machine_types", [])
	if raw_types is not Array:
		return
	for raw_type: Variant in raw_types:
		_bind_machine_service(StringName(str(raw_type)))


func _bind_machine_service(machine_type: StringName) -> void:
	if router == null or not is_instance_valid(router):
		return
	var service: Node = router.call("get_machine_service", machine_type) as Node
	if service == null or not is_instance_valid(service):
		return
	for binding: Dictionary in _service_bindings:
		if binding.get("service") == service:
			return
	var changed_callback := Callable(self, "_on_machine_changed").bind(machine_type)
	var removed_callback := Callable(self, "_on_machine_removed").bind(machine_type)
	if service.has_signal("machine_changed") and not service.is_connected(
		"machine_changed", changed_callback
	):
		service.connect("machine_changed", changed_callback)
	if service.has_signal("machine_removed") and not service.is_connected(
		"machine_removed", removed_callback
	):
		service.connect("machine_removed", removed_callback)
	_service_bindings.append({
		"machine_type": machine_type,
		"service": service,
		"changed_callback": changed_callback,
		"removed_callback": removed_callback,
	})


func _disconnect_service_bindings() -> void:
	for binding: Dictionary in _service_bindings:
		var service: Node = binding.get("service") as Node
		if service == null or not is_instance_valid(service):
			continue
		var changed_callback: Callable = binding.get("changed_callback", Callable())
		var removed_callback: Callable = binding.get("removed_callback", Callable())
		if service.has_signal("machine_changed") and service.is_connected(
			"machine_changed", changed_callback
		):
			service.disconnect("machine_changed", changed_callback)
		if service.has_signal("machine_removed") and service.is_connected(
			"machine_removed", removed_callback
		):
			service.disconnect("machine_removed", removed_callback)
	_service_bindings.clear()


func _rebuild_candidates() -> void:
	_candidates.clear()
	_candidate_order.clear()
	for binding: Dictionary in _service_bindings:
		var machine_type := StringName(str(binding.get("machine_type", "")))
		var service: Node = binding.get("service") as Node
		if service == null or not is_instance_valid(service) or not service.has_method("get_machine_ids"):
			continue
		var raw_ids: Variant = service.call("get_machine_ids")
		if raw_ids is not Array:
			continue
		for raw_id: Variant in raw_ids:
			_add_candidate(machine_type, str(raw_id), false)
	_cache_rebuild_count += 1


func _add_candidate(
	machine_type: StringName, machine_id: String, count_event: bool = true
) -> void:
	if not bool(PolicyScript.parse_machine_position(machine_type, machine_id).get("success", false)):
		return
	var key := "%s|%s" % [str(machine_type), machine_id]
	if _candidates.has(key):
		return
	_candidates[key] = {
		"machine_type": machine_type,
		"machine_id": machine_id,
	}
	_candidate_order.append(key)
	_candidate_order.sort()
	if count_event:
		_candidate_event_count += 1


func _remove_candidate(key: String, count_event: bool = true) -> void:
	if not _candidates.has(key):
		return
	_candidates.erase(key)
	_candidate_order.erase(key)
	_announced_machines.erase(key)
	if count_event:
		_candidate_event_count += 1
	if _candidate_order.is_empty():
		_cursor = 0
	else:
		_cursor = posmod(_cursor, _candidate_order.size())


func _on_machine_type_registered(machine_type: StringName) -> void:
	_bind_machine_service(machine_type)
	_rebuild_candidates()


func _on_machine_changed(
	machine_id: String, _snapshot: Dictionary, machine_type: StringName
) -> void:
	_add_candidate(machine_type, machine_id)


func _on_machine_removed(machine_id: String, machine_type: StringName) -> void:
	_remove_candidate("%s|%s" % [str(machine_type), machine_id])


func _idle_summary(elapsed: float, reason: String) -> Dictionary:
	return {
		"elapsed_seconds": elapsed if is_finite(elapsed) else 0.0,
		"machine_count": 0,
		"changed_machine_count": 0,
		"items_moved": 0,
		"reason": reason,
	}
