class_name CreatureSpawner
extends Node3D

signal creature_spawned(creature: Node3D)

const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")

@export var spawn_interval: float = 8.0
@export var max_animals: int = 12
@export var max_zombies: int = 6
@export var min_spawn_radius: float = 12.0
@export var max_spawn_radius: float = 28.0

var player: Node3D
var inventory_service
var day_night_service
var ground_resolver: Callable
var map_id: String = "star_continent"
var active: bool = false
var _factory = CreatureFactoryScript.new()
var _timer: float = 2.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(active)


func setup(p_player: Node3D, p_inventory = null, p_day_night = null, p_ground_resolver: Callable = Callable()) -> void:
	player = p_player
	inventory_service = p_inventory
	day_night_service = p_day_night
	ground_resolver = p_ground_resolver
	set_active(true)


func set_active(value: bool) -> void:
	active = value
	set_process(active)
	if active:
		_timer = 2.0


func clear_creatures() -> void:
	for creature in get_children():
		remove_child(creature)
		creature.queue_free()


func _process(delta: float) -> void:
	if not active or player == null or not is_instance_valid(player):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = spawn_interval
	var animals := _count_group("animals")
	var zombies := _count_group("zombie")
	var night: bool = day_night_service != null and bool(day_night_service.is_night())
	if night and zombies < max_zombies:
		spawn_creature("zombie")
	elif animals < max_animals:
		var choices := ["chicken", "cow", "pig"]
		spawn_creature(choices[_rng.randi_range(0, choices.size() - 1)])


func spawn_creature(species_id: String, fixed_position: Variant = null):
	if not active or player == null or not is_instance_valid(player):
		return null
	var spawn_position: Vector3 = fixed_position if fixed_position is Vector3 else _choose_position()
	var creature = _factory.create(species_id, spawn_position, player if species_id == "zombie" else null, inventory_service)
	if creature == null:
		return null
	add_child(creature)
	creature.global_position = spawn_position
	creature_spawned.emit(creature)
	return creature


func _choose_position() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(min_spawn_radius, max_spawn_radius)
	var candidate := player.global_position + Vector3(sin(angle) * radius, 2.0, cos(angle) * radius)
	if ground_resolver.is_valid():
		var resolved = ground_resolver.call(candidate)
		if resolved is Vector3:
			return resolved
		if resolved is float or resolved is int:
			candidate.y = float(resolved) + 1.0
	return candidate


func _count_group(group_name: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node and is_ancestor_of(node):
			count += 1
	return count
