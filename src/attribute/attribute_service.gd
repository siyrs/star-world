class_name AttributeService
extends Node

signal attributes_changed(snapshot: Dictionary)

const SERIAL_VERSION := 1
const EQUIPMENT_SOURCE := "equipment"
const DEFAULT_BASE := {
	"max_health": 20.0,
	"attack_damage": 1.0,
	"defense": 0.0,
	"movement_speed": 1.0,
	"mining_speed": 1.0,
}

var equipment_service: Node
var base_attributes: Dictionary = DEFAULT_BASE.duplicate(true)
var modifier_sources: Dictionary = {}
var persistent_sources: Dictionary = {}
var current: Dictionary = DEFAULT_BASE.duplicate(true)


func setup(p_equipment_service: Node = null) -> void:
	_disconnect_equipment()
	equipment_service = p_equipment_service
	if equipment_service != null and equipment_service.has_signal("equipment_changed"):
		equipment_service.connect("equipment_changed", Callable(self, "_on_equipment_changed"))
	_sync_equipment_source()


func reset() -> void:
	base_attributes = DEFAULT_BASE.duplicate(true)
	modifier_sources.clear()
	persistent_sources.clear()
	_sync_equipment_source()


func set_base(values: Dictionary) -> void:
	base_attributes = DEFAULT_BASE.duplicate(true)
	base_attributes.merge(_numeric_values(values), true)
	_recalculate()


func set_modifier_source(source_id: String, values: Dictionary, persistent: bool = false) -> void:
	var normalized_id := source_id.strip_edges()
	if normalized_id.is_empty():
		return
	var normalized_values := _numeric_values(values)
	if normalized_values.is_empty():
		remove_modifier_source(normalized_id)
		return
	modifier_sources[normalized_id] = normalized_values
	if persistent and normalized_id != EQUIPMENT_SOURCE:
		persistent_sources[normalized_id] = true
	else:
		persistent_sources.erase(normalized_id)
	_recalculate()


func remove_modifier_source(source_id: String) -> void:
	var normalized_id := source_id.strip_edges()
	if not modifier_sources.has(normalized_id) and not persistent_sources.has(normalized_id):
		return
	modifier_sources.erase(normalized_id)
	persistent_sources.erase(normalized_id)
	_recalculate()


# Compatibility helper. New integrations should use named modifier sources so updates
# replace one source instead of accumulating duplicate modifiers.
func add_modifier(modifier: Dictionary) -> void:
	var source_id := "legacy:%d" % Time.get_ticks_usec()
	set_modifier_source(source_id, modifier, true)


func clear_modifiers() -> void:
	modifier_sources.clear()
	persistent_sources.clear()
	_sync_equipment_source()


func get_value(attribute_id: String, fallback: float = 0.0) -> float:
	return float(current.get(attribute_id, fallback))


func get_values() -> Dictionary:
	return current.duplicate(true)


func get_snapshot() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"base": base_attributes.duplicate(true),
		"modifiers": modifier_sources.duplicate(true),
		"final": current.duplicate(true),
		"attributes": current.duplicate(true),
	}


func serialize() -> Dictionary:
	var persisted: Dictionary = {}
	for raw_source_id in persistent_sources:
		var source_id := str(raw_source_id)
		if modifier_sources.has(source_id):
			persisted[source_id] = modifier_sources[source_id].duplicate(true)
	return {
		"version": SERIAL_VERSION,
		"base": base_attributes.duplicate(true),
		"sources": persisted,
	}


func deserialize(data: Dictionary) -> bool:
	base_attributes = DEFAULT_BASE.duplicate(true)
	modifier_sources.clear()
	persistent_sources.clear()
	var raw_base = data.get("base", {})
	if raw_base is Dictionary:
		base_attributes.merge(_numeric_values(raw_base), true)
	var raw_sources = data.get("sources", {})
	if raw_sources is Dictionary:
		for raw_source_id in raw_sources:
			var source_id := str(raw_source_id).strip_edges()
			var values = raw_sources[raw_source_id]
			if source_id.is_empty() or source_id == EQUIPMENT_SOURCE or values is not Dictionary:
				continue
			var normalized := _numeric_values(values)
			if normalized.is_empty():
				continue
			modifier_sources[source_id] = normalized
			persistent_sources[source_id] = true
	elif data.get("modifiers", null) is Array:
		var legacy_modifiers: Array = data.get("modifiers", [])
		for index in legacy_modifiers.size():
			var modifier = legacy_modifiers[index]
			if modifier is Dictionary:
				var source_id := "legacy:%d" % index
				modifier_sources[source_id] = _numeric_values(modifier)
				persistent_sources[source_id] = true
	_sync_equipment_source()
	return true


func refresh_equipment() -> void:
	_sync_equipment_source()


func _sync_equipment_source() -> void:
	if equipment_service != null and equipment_service.has_method("get_attribute_modifiers"):
		var modifiers: Dictionary = equipment_service.call("get_attribute_modifiers")
		if modifiers.is_empty():
			modifier_sources.erase(EQUIPMENT_SOURCE)
		else:
			modifier_sources[EQUIPMENT_SOURCE] = _numeric_values(modifiers)
	else:
		modifier_sources.erase(EQUIPMENT_SOURCE)
	persistent_sources.erase(EQUIPMENT_SOURCE)
	_recalculate()


func _on_equipment_changed(_snapshot: Dictionary) -> void:
	_sync_equipment_source()


func _recalculate() -> void:
	current = DEFAULT_BASE.duplicate(true)
	current.merge(_numeric_values(base_attributes), true)
	for raw_source_id in modifier_sources:
		var source_values = modifier_sources[raw_source_id]
		if source_values is not Dictionary:
			continue
		for raw_key in source_values:
			var key := str(raw_key)
			current[key] = float(current.get(key, 0.0)) + float(source_values[raw_key])
	current["max_health"] = maxf(1.0, float(current.get("max_health", 20.0)))
	current["attack_damage"] = maxf(0.0, float(current.get("attack_damage", 1.0)))
	current["defense"] = maxf(0.0, float(current.get("defense", 0.0)))
	current["movement_speed"] = maxf(0.1, float(current.get("movement_speed", 1.0)))
	current["mining_speed"] = maxf(0.1, float(current.get("mining_speed", 1.0)))
	attributes_changed.emit(get_snapshot())


func _numeric_values(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in values:
		var value = values[raw_key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		result[str(raw_key)] = float(value)
	return result


func _disconnect_equipment() -> void:
	if equipment_service == null or not equipment_service.has_signal("equipment_changed"):
		return
	var callback := Callable(self, "_on_equipment_changed")
	if equipment_service.is_connected("equipment_changed", callback):
		equipment_service.disconnect("equipment_changed", callback)
