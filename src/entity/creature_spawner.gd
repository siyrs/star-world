class_name CreatureSpawner
extends Node3D

signal creature_spawned(creature: Node3D)
signal creature_despawned(creature: Node3D)

const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const PopulationPolicyScript = preload("res://src/entity/creature_population_policy.gd")

@export var spawn_interval: float = 8.0
@export var maintenance_interval: float = 2.0
@export var max_animals: int = 12
@export var max_zombies: int = 2
@export var min_spawn_radius: float = 28.0
@export var max_spawn_radius: float = 28.0
@export var despawn_radius: float = 56.0

var player: Node3D
var inventory_service
var day_night_service
var ground_resolver: Callable
var map_id: String = "star_continent"
var active: bool = false
var _factory = CreatureFactoryScript.new()
var _spawn_timer: float = 2.0
var _maintenance_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(active)


func setup(
	p_player: Node3D,
	p_inventory = null,
	p_day_night = null,
	p_ground_resolver: Callable = Callable(),
	activate_immediately: bool = true
) -> void:
	player = p_player
	inventory_service = p_inventory
	day_night_service = p_day_night
	ground_resolver = p_ground_resolver
	set_active(activate_immediately)


func set_active(value: bool) -> void:
	active = value
	set_process(active)
	if active:
		_spawn_timer = 2.0
		_maintenance_timer = 0.0


func clear_creatures() -> void:
	for child in get_children():
		_dispose_child(child, false)


func maintain_population() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var removed := 0
	for creature in PopulationPolicyScript.collect_out_of_range(self, player, despawn_radius):
		_dispose_child(creature, true)
		removed += 1
	return removed


func _process(delta: float) -> void:
	if not active or player == null or not is_instance_valid(player):
		return
	_maintenance_timer -= delta
	if _maintenance_timer <= 0.0:
		_maintenance_timer = maxf(0.25, maintenance_interval)
		maintain_population()
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = maxf(0.25, spawn_interval)
	var animals := _count_group(&"animals")
	var zombies := _count_group(&"zombie")
	var night: bool = day_night_service != null and bool(day_night_service.is_night())
	if night and zombies < max_zombies:
		spawn_creature("zombie")
	elif animals < max_animals:
		var choices := ["chicken", "cow", "pig"]
		spawn_creature(choices[_rng.randi_range(0, choices.size() - 1)])


func spawn_creature(species_id: String, fixed_position: Variant = null):
	if not active or player == null or not is_instance_valid(player):
		return null
	var spawn_position: Vector3 = (
		fixed_position if fixed_position is Vector3 else _choose_position()
	)
	var creature = _factory.create(
		species_id, spawn_position, player if species_id == "zombie" else null, inventory_service
	)
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


func _count_group(group_name: StringName) -> int:
	return PopulationPolicyScript.count_group(self, group_name)


func _dispose_child(child: Node, emit_event: bool) -> void:
	if not is_instance_valid(child):
		return
	if child.get_parent() == self:
		remove_child(child)
	if emit_event and child is Node3D and child.is_in_group("creatures"):
		creature_despawned.emit(child)
	child.queue_free()
