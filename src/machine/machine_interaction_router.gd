class_name MachineInteractionRouter
extends Node

signal machine_type_registered(machine_type: StringName)
signal machine_type_rejected(machine_type: StringName, reason: String)
signal machine_opened(machine_type: StringName, machine_id: String)
signal machine_open_rejected(machine_type: StringName, machine_id: String, reason: String)

const MAX_MACHINE_TYPES := 16
const REQUIRED_SERVICE_METHODS := [
	"ensure_machine",
	"open_machine",
	"close_machine",
	"can_remove_machine",
	"remove_machine",
	"get_slot",
]

var game_ui: Node
var _entries: Dictionary = {}
var _registration_order: Array[StringName] = []
var _open_count := 0
var _open_rejection_count := 0
var _shutdown := false


func setup_ui(p_game_ui: Node) -> void:
	game_ui = p_game_ui


func register_machine_type(
	machine_type: StringName,
	service: Node,
	open_ui_method: StringName,
	slot_names: Array[String],
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
	var normalized_slots: Array[String] = []
	for raw_slot: String in slot_names:
		var slot_name := raw_slot.strip_edges()
		if slot_name.is_empty() or slot_name in normalized_slots:
			continue
		normalized_slots.append(slot_name)
	if normalized_slots.is_empty():
		return _reject_registration(normalized_type, "invalid_slot_contract")
	_entries[normalized_type] = {
		"service": service,
		"open_ui_method": open_ui_method,
		"slot_names": normalized_slots,
		"label": label.strip_edges(),
		"not_empty_message": not_empty_message.strip_edges(),
	}
	_registration_order.append(normalized_type)
	machine_type_registered.emit(normalized_type)
	return {
		"success": true,
		"machine_type": normalized_type,
		"service": service,
	}


func has_machine_type(machine_type: StringName) -> bool:
	return _entries.has(machine_type)


func get_machine_service(machine_type: StringName) -> Node:
	var entry: Dictionary = _entries.get(machine_type, {})
	return entry.get("service") as Node


func get_slot_names(machine_type: StringName) -> Array[String]:
	var entry: Dictionary = _entries.get(machine_type, {})
	var raw_slots: Variant = entry.get("slot_names", [])
	var result: Array[String] = []
	if raw_slots is Array:
		for raw_slot: Variant in raw_slots:
			result.append(str(raw_slot))
	return result


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


func can_remove_machine_type(machine_type: StringName, machine_id: String) -> Dictionary:
	var service := get_machine_service(machine_type)
	if service == null or not is_instance_valid(service):
		return {
			"allowed": false,
			"reason": "machine_service_missing",
			"message": "机器服务暂不可用，为保护内容已阻止拆除",
		}
	var allowed := bool(service.call("can_remove_machine", machine_id))
	return {
		"allowed": allowed,
		"reason": "" if allowed else "machine_not_empty",
		"message": "" if allowed else get_not_empty_message(machine_type),
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
	for machine_type: StringName in _registration_order:
		machine_types.append(str(machine_type))
		var service := get_machine_service(machine_type)
		service_ready[str(machine_type)] = service != null and is_instance_valid(service)
	return {
		"shutdown": _shutdown,
		"machine_type_count": _registration_order.size(),
		"machine_types": machine_types,
		"service_ready": service_ready,
		"open_count": _open_count,
		"open_rejection_count": _open_rejection_count,
	}


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	game_ui = null
	_entries.clear()
	_registration_order.clear()


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
