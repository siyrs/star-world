class_name AttributeService
extends Node

## Owns calculated character attributes.
## Equipment, combat and UI consume snapshots only.

signal attributes_changed(snapshot: Dictionary)

const DEFAULT_ATTRIBUTES := {
	"health": 20.0,
	"attack_damage": 1.0,
	"defense": 0.0,
	"movement_speed": 1.0,
	"mining_speed": 1.0,
}

var base_attributes: Dictionary = DEFAULT_ATTRIBUTES.duplicate(true)
var modifiers: Array[Dictionary] = []
var current: Dictionary = DEFAULT_ATTRIBUTES.duplicate(true)

func set_base(values: Dictionary) -> void:
	base_attributes = DEFAULT_ATTRIBUTES.duplicate(true)
	base_attributes.merge(values, true)
	_recalculate()

func add_modifier(modifier: Dictionary) -> void:
	if modifier.is_empty():
		return
	modifiers.append(modifier.duplicate(true))
	_recalculate()

func clear_modifiers() -> void:
	modifiers.clear()
	_recalculate()

func get_snapshot() -> Dictionary:
	return current.duplicate(true)

func serialize() -> Dictionary:
	return {
		"base": base_attributes.duplicate(true),
		"modifiers": modifiers.duplicate(true),
	}

func deserialize(data: Dictionary) -> void:
	base_attributes = data.get("base", DEFAULT_ATTRIBUTES).duplicate(true)
	modifiers = data.get("modifiers", []).duplicate(true)
	_recalculate()

func _recalculate() -> void:
	current = DEFAULT_ATTRIBUTES.duplicate(true)
	current.merge(base_attributes, true)
	for modifier in modifiers:
		for key in modifier.keys():
			current[key] = float(current.get(key, 0.0)) + float(modifier[key])
	attributes_changed.emit(get_snapshot())
