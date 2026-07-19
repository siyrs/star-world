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
	"zombie": preload("res://src/entity/zombie.gd")
}

var profiles: Dictionary = {}
var hostile_attack_registry = HostileAttackRegistryScript.new()


func _init() -> void:
	load_profiles()


func load_profiles(path: String = DATA_PATH) -> bool:
	profiles.clear()
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var raw_profiles: Variant = parsed.get("creatures", {})
		if raw_profiles is Dictionary:
			profiles = raw_profiles.duplicate(true)
	return not profiles.is_empty()


func get_hostile_attack_profile(species_id: String) -> Dictionary:
	return hostile_attack_registry.get_profile(species_id)


func get_hostile_attack_validation_errors() -> Array[String]:
	return hostile_attack_registry.get_validation_errors()


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
	var raw_profile: Variant = profiles.get(species_id, {})
	var profile: Dictionary = raw_profile.duplicate(true) if raw_profile is Dictionary else {}
	var hostile_attack := hostile_attack_registry.get_profile(species_id)
	if not hostile_attack.is_empty():
		profile["hostile_attack"] = hostile_attack
	creature.apply_profile(profile)
	creature.position = world_position
	creature.target = target
	creature.inventory_service = inventory
	return creature
