class_name BlockInteractionService
extends Node

signal interaction_opened(action: StringName, block_position: Vector3i, block_id: String)
signal interaction_rejected(reason: String, block_position: Vector3i, block_id: String)

const Registry = preload("res://src/interaction/block_interaction_registry.gd")
const MACHINE_SLOTS := ["input", "fuel", "output"]

var game_ui
var container_storage
var inventory
var furnace_service
var _extensions: Array[Node] = []


func setup(p_game_ui, p_container_storage, p_inventory, p_furnace_service = null) -> void:
	game_ui = p_game_ui
	container_storage = p_container_storage
	inventory = p_inventory
	furnace_service = p_furnace_service


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
	furnace_service = null


func interact(world, block_position: Vector3i, block_id: String) -> bool:
	var extension_result := _try_extensions(world, block_position, block_id)
	if bool(extension_result.get("handled", false)):
		var action := StringName(extension_result.get("action", "extension"))
		var succeeded := bool(extension_result.get("success", false))
		var message := str(extension_result.get("message", "")).strip_edges()
		if succeeded:
			interaction_opened.emit(action, block_position, block_id)
			if not message.is_empty():
				_show_message(
					message,
					str(extension_result.get("severity", "success")),
					"interaction:%s:%s" % [action, block_id]
				)
		else:
			var reason := str(extension_result.get("reason", "extension_rejected"))
			_reject(reason, block_position, block_id)
			if not message.is_empty():
				_show_message(
					message,
					str(extension_result.get("severity", "warning")),
					"interaction_rejected:%s:%s" % [reason, block_id]
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
					"open_container", container_id, str(definition.get("label", block_id))
				)
			):
				container_storage.close_container()
				_reject("container_ui_failed", block_position, block_id)
				return false
		Registry.ACTION_MACHINE:
			if furnace_service == null:
				_reject("machine_service_missing", block_position, block_id)
				return false
			var machine_type := str(definition.get("machine_type", block_id))
			var machine_id := get_machine_id(world, block_position, machine_type)
			if not furnace_service.ensure_machine(machine_id):
				_reject("machine_open_failed", block_position, block_id)
				return false
			if not bool(
				game_ui.call(
					"open_furnace", machine_id, str(definition.get("label", block_id))
				)
			):
				furnace_service.close_machine()
				_reject("machine_ui_failed", block_position, block_id)
				return false
		_:
			return false
	interaction_opened.emit(action, block_position, block_id)
	return true


func can_break_block(world, block_position: Vector3i, block_id: String) -> bool:
	_prune_extensions()
	for extension in _extensions:
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
		if furnace_service == null:
			_show_message("熔炉服务暂不可用，为保护内容已阻止拆除")
			_reject("machine_service_missing", block_position, block_id)
			return false
		var machine_id := get_machine_id(world, block_position, block_id)
		if _machine_slots_are_empty(machine_id):
			return true
		_show_message("熔炉中仍有物品，请先清空三个槽位后再拆除")
		_reject("machine_not_empty", block_position, block_id)
		return false
	return true


func on_block_removed(world, block_position: Vector3i, block_id: String) -> void:
	if Registry.is_container(block_id) and container_storage != null:
		var container_id := get_container_id(world, block_position, block_id)
		container_storage.remove_container(container_id, true)
	elif Registry.is_machine(block_id) and furnace_service != null:
		var machine_id := get_machine_id(world, block_position, block_id)
		# Empty furnaces may be dismantled even if a consumed fuel item left residual
		# heat. Removing the block intentionally discards that transient heat only.
		furnace_service.remove_machine(machine_id, false)
	_prune_extensions()
	for extension in _extensions:
		if extension.has_method("on_block_removed"):
			extension.call("on_block_removed", world, block_position, block_id)


func get_container_id(world, block_position: Vector3i, block_id: String = "chest") -> String:
	return _stable_position_id(world, block_position, block_id)


func get_machine_id(world, block_position: Vector3i, machine_type: String = "furnace") -> String:
	return _stable_position_id(world, block_position, machine_type)


func get_interaction_hint(block_id: String, selected_item_id: String = "") -> String:
	_prune_extensions()
	for extension in _extensions:
		if not extension.has_method("get_interaction_hint"):
			continue
		var hint := str(extension.call("get_interaction_hint", block_id, selected_item_id))
		if not hint.is_empty():
			return hint
	var definition := Registry.get_interaction(block_id)
	if definition.is_empty():
		return ""
	return "右键打开%s" % str(definition.get("label", block_id))


func _try_extensions(world, block_position: Vector3i, block_id: String) -> Dictionary:
	_prune_extensions()
	for extension in _extensions:
		if not extension.has_method("try_interact"):
			continue
		var raw_result = extension.call(
			"try_interact", world, inventory, block_position, block_id
		)
		if raw_result is Dictionary and bool(raw_result.get("handled", false)):
			return raw_result.duplicate(true)
	return {}


func _prune_extensions() -> void:
	for index in range(_extensions.size() - 1, -1, -1):
		if _extensions[index] == null or not is_instance_valid(_extensions[index]):
			_extensions.remove_at(index)


func _machine_slots_are_empty(machine_id: String) -> bool:
	if furnace_service == null or not furnace_service.has_machine(machine_id):
		return true
	for slot_name in MACHINE_SLOTS:
		var slot: Dictionary = furnace_service.get_slot(machine_id, slot_name)
		if not slot.is_empty() and int(slot.get("count", 0)) > 0:
			return false
	return true


func _stable_position_id(world, block_position: Vector3i, prefix: String) -> String:
	var position_key := "%d,%d,%d" % [block_position.x, block_position.y, block_position.z]
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
