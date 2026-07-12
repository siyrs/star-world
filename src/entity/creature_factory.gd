class_name CreatureFactory
extends RefCounted

const DATA_PATH := "res://data/creatures.json"
const SCRIPTS := {
	"chicken": preload("res://src/entity/chicken.gd"),
	"cow": preload("res://src/entity/cow.gd"),
	"pig": preload("res://src/entity/pig.gd"),
	"zombie": preload("res://src/entity/zombie.gd")
}

var profiles: Dictionary = {}


func _init() -> void:
	load_profiles()


func load_profiles(path: String = DATA_PATH) -> bool:
	profiles.clear()
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		profiles = parsed.get("creatures", {}).duplicate(true)
	return not profiles.is_empty()


func create(species_id: String, world_position: Vector3, target: Node3D = null, inventory = null):
	if not SCRIPTS.has(species_id):
		push_warning("Unknown creature species: %s" % species_id)
		return null
	var creature = SCRIPTS[species_id].new()
	creature.apply_profile(profiles.get(species_id, {}))
	creature.position = world_position
	creature.target = target
	creature.inventory_service = inventory
	return creature
