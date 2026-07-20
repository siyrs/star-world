class_name BlockInteractionService
extends Node

signal interaction_opened(action: StringName, block_position: Vector3i, block_id: String)
signal interaction_rejected(reason: String, block_position: Vector3i, block_id: String)

const Registry = preload("res://src/interaction/block_interaction_registry.gd")

var game_ui
var container_storage
var inventory
var machine_access
# Compatibility alias retained for direct tests and older adapters.
var furnace_service
var _extensions: Array[Node] = []


func setup(p_game_ui, p_container_storage, p_inventory, p_machine_access = null) -> void:
	game_ui = p_game_ui
	container_storage = p_container_storage
	inventory = p_inventory
	set_machine_access(p_machine_access)


func set_machine_access(p_machine_access) -> void:
	machine_access = p_machine_access
	furnace_service = null
	if machine_access == null:
		return
	if machine_access.has_method("get_machine_service"):
		furnace_service = machine_access.call(
			"get_machine_service", &"furnace"
		) as Node
	else:
		furnace_service = machine_access


func register_extension(extension: Node) -> bool:
	if extension == null or not is_instance_valid(extension) or extension in _extensions:
		return false
	_extensions.append(extension)
	return true


func unregister_extension(extension: Node) -> bool:
	var index := _extensions.find(extension)
	if index < 0:
		return false
	_extensions.remove_at(index)
	return true


func get_extension_count() -> int:
	_prune_extensions()
	return _extensions.size()


func detach() -> void:
	game_ui = null
	container_storage = null
	inventory = null
	machine_access = null
	furnace_service = null


func interact(world, block_position: Vector3i, block_id: String) -> bool:
	var extension_result := _try_extensions(world, block_position, block_id)
	if bool(extension_result.get("handled", false)):
		var extension_action := StringName(extension_result.get("action", "extension"))
		var succeeded := bool(extension_result.get("success", false))
		var message := str(extension_result.get("message", "")).strip_edges()
		if succeeded:
			interaction_opened.emit(extension_action, block_position, block_id)
			if not message.is_empty():
				_show_message(
					message,
					str(extension_result.get("severity", "success")),
					"interaction:%s:%s" % [extension_action, block_id]
				)
		else:
			var extension_reason := str(
				extension_result.get("reason", "extension_rejected")
			)
			_reject(extension_reason, block_position, block_id)
			if not message.is_empty():
				_show_message(
					message,
					str(extension_result.get("severity", "warning")),
					"interaction_rejected:%s:%s" % [extension_reason, block_id]
				)
		return true
	var definition := Registry.get_interaction(block_id)
	if definition.is_empty() or game_ui == null:
		return false
	var action := StringName(definition.get("action", ""))
	match action:
		Registry.ACTION_CRAFTING:
			var station := str(definition.get("station", "hand"))
			game_ui.call("open_crafting", station)
		Registry.ACTION_CONTAINER:
			if container_storage == null:
				_reject("container_service_missing", block_position, block_id)
				return false
			var container_id := get_container_id(world, block_position, block_id)
			var container_type := str(definition.get("container_type", "chest"))
			var slot_count := int(definition.get("slot_count", 27))
			if not container_storage.open_container(container_id, container_type, slot_count):
				_reject("container_open_failed", block_position, block_id)
				return false
			if not bool(
				game_ui.call(
					"open_container",
					container_id,
					str(definition.get("label", block_id))
				)
			):
				container_storage.close_container()
				_reject("container_ui_failed", block_position, block_id)
				return false
		Registry.ACTION_MACHINE:
			var machine_type := StringName(
				str(definition.get("machine_type", block_id))
			)
			var machine_id := get_machine_id(
				world,
				block_position,
				str(machine_type)
			)
			var open_result := _open_machine(
				machine_type,
				machine_id,
				str(definition.get("label", block_id))
			)
			if not bool(open_result.get("success", false)):
				_reject(
					str(open_result.get("reason", "machine_open_failed")),
					block_position,
					block_id
				)
				return false
		_:
			return false
	interaction_opened.emit(action, block_position, block_id)
	return true


func can_break_block(world, block_position: Vector3i, block_id: String) -> bool:
	_prune_extensions()
	for extension: Node in _extensions:
		if extension.has_method("can_break_block") and not bool(
			extension.call("can_break_block", world, block_position, block_id)
		):
			_reject("extension_protected", block_position, block_id)
			return false
	if Registry.is_container(block_id):
		if container_storage == null:
			return true
		var container_id := get_container_id(world, block_position, block_id)
		if container_storage.is_empty(container_id):
			return true
		_show_message("箱子中还有物品，请先清空后再拆除")
		_reject("container_not_empty", block_position, block_id)
		return false
	if Registry.is_machine(block_id):
		var definition := Registry.get_interaction(block_id)
		var machine_type := StringName(
			str(definition.get("machine_type", block_id))
		)
		var machine_id := get_machine_id(
			world,
			block_position,
			str(machine_type)
		)
		var removal := _can_remove_machine(machine_type, machine_id)
		if bool(removal.get("allowed", false)):
			return true
		var message := str(removal.get("message", "")).strip_edges()
		if message.is_empty():
			message = "机器中仍有物品，请先清空后再拆除"
		_show_message(message)
		_reject(
			str(removal.get("reason", "machine_not_empty")),
			block_position,
			block_id
		)
		return false
	return true


func on_block_removed(world, block_position: Vector3i, block_id: String) -> void:
	if Registry.is_container(block_id) and container_storage != null:
		var container_id := get_container_id(world, block_position, block_id)
		container_storage.remove_container(container_id, true)
	elif Registry.is_machine(block_id):
		var definition := Registry.get_interaction(block_id)
		var machine_type := StringName(
			str(definition.get("machine_type", block_id))
		)
		var machine_id := get_machine_id(
			world,
			block_position,
			str(machine_type)
		)
		_remove_machine(machine_type, machine_id)
	_prune_extensions()
	for extension: Node in _extensions:
		if extension.has_method("on_block_removed"):
			extension.call("on_block_removed", world, block_position, block_id)


func get_container_id(
	world,
	block_position: Vector3i,
	block_id: String = "chest"
) -> String:
	return _stable_position_id(world, block_position, block_id)


func get_machine_id(
	world,
	block_position: Vector3i,
	machine_type: String = "furnace"
) -> String:
	return _stable_position_id(world, block_position, machine_type)


# Stable one-argument contract retained for existing extensions, tests and mods.
func get_interaction_hint(block_id: String) -> String:
	return get_interaction_hint_for_item(block_id, "")


# Context-aware contract used by the current experience layer.
func get_interaction_hint_for_item(
	block_id: String,
	selected_item_id: String = ""
) -> String:
	_prune_extensions()
	for extension: Node in _extensions:
		if not extension.has_method("get_interaction_hint"):
			continue
		var hint := str(
			extension.call("get_interaction_hint", block_id, selected_item_id)
		)
		if not hint.is_empty():
			return hint
	var definition := Registry.get_interaction(block_id)
	if definition.is_empty():
		return ""
	return "右键打开%s" % str(definition.get("label", block_id))


func _open_machine(
	machine_type: StringName,
	machine_id: String,
	label: String
) -> Dictionary:
	if machine_access == null:
		return {"success": false, "reason": "machine_service_missing"}
	if machine_access.has_method("open_machine_type"):
		var raw_result: Variant = machine_access.call(
			"open_machine_type",
			machine_type,
			machine_id,
			label
		)
		return raw_result if raw_result is Dictionary else {
			"success": false,
			"reason": "machine_open_failed",
		}
	# Legacy direct-furnace setup remains supported for isolated tests and mods.
	if str(machine_type) != "furnace":
		return {"success": false, "reason": "unknown_machine_type"}
	if not machine_access.has_method("ensure_machine"):
		return {"success": false, "reason": "machine_service_missing"}
	if not bool(machine_access.call("ensure_machine", machine_id)):
		return {"success": false, "reason": "machine_open_failed"}
	if game_ui == null or not game_ui.has_method("open_furnace"):
		return {"success": false, "reason": "machine_ui_missing"}
	if not bool(game_ui.call("open_furnace", machine_id, label)):
		if machine_access.has_method("close_machine"):
			machine_access.call("close_machine")
		return {"success": false, "reason": "machine_ui_failed"}
	return {"success": true, "machine_id": machine_id}


func _can_remove_machine(
	machine_type: StringName,
	machine_id: String
) -> Dictionary:
	if machine_access == null:
		return {
			"allowed": false,
			"reason": "machine_service_missing",
			"message": "机器服务暂不可用，为保护内容已阻止拆除",
		}
	if machine_access.has_method("can_remove_machine_type"):
		var raw_result: Variant = machine_access.call(
			"can_remove_machine_type",
			machine_type,
			machine_id
		)
		if raw_result is Dictionary:
			return raw_result
	if str(machine_type) == "furnace" and machine_access.has_method("can_remove_machine"):
		var allowed := bool(machine_access.call("can_remove_machine", machine_id))
		return {
			"allowed": allowed,
			"reason": "" if allowed else "machine_not_empty",
			"message": (
				""
				if allowed
				else "熔炉中仍有物品，请先清空三个槽位后再拆除"
			),
		}
	return {
		"allowed": false,
		"reason": "machine_service_missing",
		"message": "机器服务暂不可用，为保护内容已阻止拆除",
	}


func _remove_machine(machine_type: StringName, machine_id: String) -> void:
	if machine_access == null:
		return
	if machine_access.has_method("remove_machine_type"):
		machine_access.call(
			"remove_machine_type",
			machine_type,
			machine_id,
			false
		)
	elif str(machine_type) == "furnace" and machine_access.has_method("remove_machine"):
		machine_access.call("remove_machine", machine_id, false)


func _try_extensions(
	world,
	block_position: Vector3i,
	block_id: String
) -> Dictionary:
	_prune_extensions()
	for extension: Node in _extensions:
		if not extension.has_method("try_interact"):
			continue
		var raw_result: Variant = extension.call(
			"try_interact",
			world,
			inventory,
			block_position,
			block_id
		)
		if raw_result is Dictionary and bool(raw_result.get("handled", false)):
			return raw_result.duplicate(true)
	return {}


func _prune_extensions() -> void:
	for index in range(_extensions.size() - 1, -1, -1):
		if _extensions[index] == null or not is_instance_valid(_extensions[index]):
			_extensions.remove_at(index)


func _stable_position_id(
	world,
	block_position: Vector3i,
	prefix: String
) -> String:
	var position_key := "%d,%d,%d" % [
		block_position.x,
		block_position.y,
		block_position.z,
	]
	if world != null and world.has_method("block_key"):
		position_key = str(world.call("block_key", block_position))
	return "%s@%s" % [prefix, position_key]


func _reject(reason: String, block_position: Vector3i, block_id: String) -> void:
	interaction_rejected.emit(reason, block_position, block_id)


func _show_message(
	message: String,
	severity: String = "warning",
	dedupe_key: String = ""
) -> void:
	if game_ui != null and game_ui.has_method("show_message"):
		game_ui.call(
			"show_message",
			message,
			3.0,
			severity,
			dedupe_key if not dedupe_key.is_empty() else message
		)
