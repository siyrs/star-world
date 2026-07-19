class_name CreatureFactory
extends RefCounted

const DATA_PATH := "res://data/creatures.json"
const PhysicsPolicy = preload("res://src/core/physics_interaction_policy.gd")
const HostileAttackRegistryScript = preload(
	"res://src/entity/hostile_attack_registry.gd"
)
const SCRIPTS := {
	"chicken": preload("res://src/entity/chicken.gd"),
	"cow": preload("res://src/entity/cow.gd"),
	"pig": preload("res://src/entity/pig.gd"),
	"zombie": preload("res://src/entity/zombie.gd"),
	"abyss_brute": preload("res://src/entity/abyss_brute.gd"),
}

var profiles: Dictionary = {}
var hostile_attack_registry = HostileAttackRegistryScript.new()
var _validation_errors: Array[String] = []


func _init() -> void:
	load_profiles()


func load_profiles(path: String = DATA_PATH) -> bool:
	profiles.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_validation_errors.append("Creature data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_validation_errors.append("Unable to open creature data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var raw_profiles: Variant = parsed.get("creatures", {})
		if raw_profiles is Dictionary:
			profiles = raw_profiles.duplicate(true)
	for raw_species_id: Variant in profiles.keys():
		var species_id := str(raw_species_id)
		if not SCRIPTS.has(species_id):
			_validation_errors.append("Creature profile has no production script: %s" % species_id)
	for raw_species_id: Variant in SCRIPTS.keys():
		var species_id := str(raw_species_id)
		if not profiles.has(species_id):
			_validation_errors.append("Production creature script has no profile: %s" % species_id)
	return not profiles.is_empty() and _validation_errors.is_empty()


func get_profile(species_id: String) -> Dictionary:
	var raw_profile: Variant = profiles.get(species_id, {})
	return raw_profile.duplicate(true) if raw_profile is Dictionary else {}


func get_species_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_species_id: Variant in SCRIPTS.keys():
		result.append(str(raw_species_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func get_hostile_attack_profile(species_id: String) -> Dictionary:
	return hostile_attack_registry.get_profile(species_id)


func get_hostile_attack_validation_errors() -> Array[String]:
	return hostile_attack_registry.get_validation_errors()


func is_hostile_species(species_id: String) -> bool:
	return not get_hostile_attack_profile(species_id).is_empty()


func create(species_id: String, world_position: Vector3, target: Node3D = null, inventory = null):
	if not SCRIPTS.has(species_id):
		push_warning("Unknown creature species: %s" % species_id)
		return null
	var creature = SCRIPTS[species_id].new()
	PhysicsPolicy.configure_creature(creature)
	creature.died.connect(
		func(_species_id: String, _drops: Dictionary, _position: Vector3) -> void:
			PhysicsPolicy.disable_body_collision(creature)
	)
	var profile := get_profile(species_id)
	var hostile_attack := hostile_attack_registry.get_profile(species_id)
	if not hostile_attack.is_empty():
		profile["hostile_attack"] = hostile_attack
	creature.apply_profile(profile)
	creature.position = world_position
	creature.target = target
	creature.inventory_service = inventory
	return creature
