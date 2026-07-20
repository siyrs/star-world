class_name CreatureSpawner
extends Node3D

signal creature_spawned(creature: Node3D)
signal creature_despawned(creature: Node3D)
signal ecology_changed(snapshot: Dictionary)
signal threat_changed(snapshot: Dictionary)

const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const PopulationPolicyScript = preload("res://src/entity/creature_population_policy.gd")
const EcologyRegistryScript = preload("res://src/entity/creature_ecology_registry.gd")
const EcologyPolicyScript = preload("res://src/entity/creature_ecology_policy.gd")
const MAX_HOSTILE_QUERY_NODES := 64

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
var _ecology_registry = EcologyRegistryScript.new()
var _ecology_profile: Dictionary = {}
var _spawn_timer: float = 2.0
var _maintenance_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _last_snapshot: Dictionary = {}
var _exit_publish_scheduled := false


func _ready() -> void:
	_rng.randomize()
	set_map_profile(map_id)
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
	_publish_ecology_if_changed(true)


func set_map_profile(p_map_id: String) -> void:
	var profile := _ecology_registry.get_profile(p_map_id)
	map_id = str(profile.get("id", "star_continent"))
	_ecology_profile = profile.duplicate(true)
	spawn_interval = clampf(float(profile.get("spawn_interval_seconds", spawn_interval)), 1.0, 30.0)
	max_animals = maxi(0, int(profile.get("passive_cap", max_animals)))
	max_zombies = EcologyPolicyScript.hostile_cap(profile, _current_phase())
	_spawn_timer = minf(_spawn_timer, spawn_interval)
	_publish_ecology_if_changed(true)


func set_active(value: bool) -> void:
	active = value
	set_process(active)
	if active:
		_spawn_timer = 2.0
		_maintenance_timer = 0.0
	_publish_ecology_if_changed(true)


func clear_creatures() -> void:
	# ItemPickup nodes share this parent with creatures.  Only clear actual
	# creatures so a simultaneous population reset cannot erase earned drops.
	for child: Node in get_children():
		if child.is_in_group("creatures"):
			_dispose_child(child, false)
	_publish_ecology_if_changed(true)


func maintain_population() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var removed := 0
	for creature: Node3D in PopulationPolicyScript.collect_out_of_range(self, player, despawn_radius):
		_dispose_child(creature, true)
		removed += 1
	if removed > 0:
		_publish_ecology_if_changed(true)
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
		_publish_ecology_if_changed(false)
		return
	_spawn_timer = maxf(0.25, spawn_interval)
	var passive_count := _count_group(&"animals")
	var hostile_count := _count_group(&"hostile")
	var phase := _current_phase()
	max_animals = maxi(0, int(_ecology_profile.get("passive_cap", max_animals)))
	max_zombies = EcologyPolicyScript.hostile_cap(_ecology_profile, phase)
	var species_id := EcologyPolicyScript.choose_species(
		_ecology_profile,
		phase,
		passive_count,
		hostile_count,
		_rng.randf(),
		_rng.randf(),
		_selection_context()
	)
	if not species_id.is_empty():
		spawn_creature(species_id)
	_publish_ecology_if_changed(true)


func spawn_creature(species_id: String, fixed_position: Variant = null):
	if not active or player == null or not is_instance_valid(player):
		return null
	var spawn_position: Vector3 = (
		fixed_position if fixed_position is Vector3 else _choose_position()
	)
	var creature = _factory.create(
		species_id,
		spawn_position,
		player if _factory.is_hostile_species(species_id) else null,
		inventory_service
	)
	if creature == null:
		return null
	add_child(creature)
	_connect_creature_runtime_signals(creature)
	creature.global_position = spawn_position
	creature_spawned.emit(creature)
	_publish_ecology_if_changed(true)
	return creature


func get_nearby_hostile_count(position: Vector3, radius: float) -> int:
	var radius_squared := maxf(0.0, radius) * maxf(0.0, radius)
	var count := 0
	for child: Node in get_children():
		if not _is_live_hostile(child):
			continue
		var hostile := child as Node3D
		if hostile != null and hostile.global_position.distance_squared_to(position) <= radius_squared:
			count += 1
	return count


func get_nearby_hostile_pressure(position: Vector3, radius: float) -> float:
	var radius_squared := maxf(0.0, radius) * maxf(0.0, radius)
	var pressure := 0.0
	for child: Node in get_children():
		if not _is_live_hostile(child):
			continue
		var hostile := child as Node3D
		if hostile == null or hostile.global_position.distance_squared_to(position) > radius_squared:
			continue
		pressure += clampf(float(_property_value(hostile, "danger_weight", 1.0)), 0.5, 6.0)
	return pressure


func get_nearby_hostile_windup_summary(position: Vector3, radius: float) -> Dictionary:
	var safe_radius := maxf(0.0, radius)
	var radius_squared := safe_radius * safe_radius
	var visited_nodes := 0
	var hostile_nodes := 0
	var active_windups := 0
	var elite_windups := 0
	var windup_pressure := 0.0
	var soonest_impact := INF
	var source_counts: Dictionary = {}
	var scan_cap_reached := false
	for child: Node in get_children():
		visited_nodes += 1
		if visited_nodes > MAX_HOSTILE_QUERY_NODES:
			scan_cap_reached = true
			break
		if not _is_live_hostile(child):
			continue
		var hostile := child as Node3D
		if hostile == null or hostile.global_position.distance_squared_to(position) > radius_squared:
			continue
		hostile_nodes += 1
		if not hostile.has_method("get_hostile_attack_snapshot"):
			continue
		var raw_attack: Variant = hostile.call("get_hostile_attack_snapshot")
		if raw_attack is not Dictionary:
			continue
		var attack: Dictionary = raw_attack
		if str(attack.get("state", "")) != "windup":
			continue
		active_windups += 1
		if hostile.is_in_group("elite"):
			elite_windups += 1
		windup_pressure += clampf(float(_property_value(hostile, "danger_weight", 1.0)), 0.5, 6.0)
		soonest_impact = minf(
			soonest_impact,
			maxf(0.0, float(attack.get("windup_remaining", 0.0)))
		)
		var source_id := str(attack.get("source_id", _property_value(hostile, "species_id", "hostile"))).strip_edges()
		if source_id.is_empty():
			source_id = "hostile"
		source_counts[source_id] = int(source_counts.get(source_id, 0)) + 1
	return {
		"active_windup_count": active_windups,
		"elite_windup_count": elite_windups,
		"windup_pressure": windup_pressure,
		"soonest_impact_seconds": soonest_impact if active_windups > 0 else -1.0,
		"source_counts": source_counts,
		"hostile_nodes_in_radius": hostile_nodes,
		"visited_nodes": mini(visited_nodes, MAX_HOSTILE_QUERY_NODES),
		"query_node_cap": MAX_HOSTILE_QUERY_NODES,
		"scan_cap_reached": scan_cap_reached,
	}


func get_species_count(species_id: String) -> int:
	return int(_species_counts().get(species_id, 0))


func get_ecology_snapshot() -> Dictionary:
	return EcologyPolicyScript.snapshot(
		_ecology_profile,
		_current_phase(),
		_count_group(&"animals"),
		_count_group(&"hostile"),
		_selection_context()
	)


func get_ecology_profile() -> Dictionary:
	return _ecology_profile.duplicate(true)


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


func _current_phase() -> String:
	if day_night_service != null and day_night_service.has_method("get_phase"):
		return str(day_night_service.call("get_phase"))
	if day_night_service != null and day_night_service.has_method("is_night"):
		return "night" if bool(day_night_service.call("is_night")) else "day"
	return "day"


func _selection_context() -> Dictionary:
	return {
		"player_y": player.global_position.y if player != null and is_instance_valid(player) else 32.0,
		"species_counts": _species_counts(),
		"elite_count": _count_group(&"elite"),
	}


func _species_counts() -> Dictionary:
	var result: Dictionary = {}
	for child: Node in get_children():
		if not child.is_in_group("creatures") or child.is_queued_for_deletion():
			continue
		var species_id := str(_property_value(child, "species_id", ""))
		if species_id.is_empty():
			continue
		result[species_id] = int(result.get(species_id, 0)) + 1
	return result


func _count_group(group_name: StringName) -> int:
	if group_name == &"hostile":
		var live_count := 0
		for child: Node in get_children():
			if _is_live_hostile(child):
				live_count += 1
		return live_count
	return PopulationPolicyScript.count_group(self, group_name)


func _publish_ecology_if_changed(force: bool) -> void:
	var snapshot := get_ecology_snapshot()
	if not force and snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot.duplicate(true)
	ecology_changed.emit(_last_snapshot.duplicate(true))


func _connect_creature_runtime_signals(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	if creature.has_signal("attack_state_changed"):
		var attack_callback := Callable(self, "_on_creature_attack_state_changed").bind(creature)
		if not creature.is_connected("attack_state_changed", attack_callback):
			creature.connect("attack_state_changed", attack_callback)
	if creature.has_signal("died"):
		var died_callback := Callable(self, "_on_creature_died_for_threat").bind(creature)
		if not creature.is_connected("died", died_callback):
			creature.connect("died", died_callback)
	var exit_callback := Callable(self, "_on_creature_tree_exiting").bind(creature)
	if not creature.is_connected("tree_exiting", exit_callback):
		creature.connect("tree_exiting", exit_callback)


func _disconnect_creature_runtime_signals(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	if creature.has_signal("attack_state_changed"):
		var attack_callback := Callable(self, "_on_creature_attack_state_changed").bind(creature)
		if creature.is_connected("attack_state_changed", attack_callback):
			creature.disconnect("attack_state_changed", attack_callback)
	if creature.has_signal("died"):
		var died_callback := Callable(self, "_on_creature_died_for_threat").bind(creature)
		if creature.is_connected("died", died_callback):
			creature.disconnect("died", died_callback)
	var exit_callback := Callable(self, "_on_creature_tree_exiting").bind(creature)
	if creature.is_connected("tree_exiting", exit_callback):
		creature.disconnect("tree_exiting", exit_callback)


func _on_creature_attack_state_changed(attack: Dictionary, creature: Node) -> void:
	var summary := _current_threat_summary()
	summary["event"] = "attack_state_changed"
	summary["state"] = str(attack.get("state", ""))
	summary["source_id"] = str(attack.get("source_id", _property_value(creature, "species_id", "hostile")))
	threat_changed.emit(summary)


func _on_creature_died_for_threat(
	species_id: String,
	drops: Dictionary,
	_world_position: Vector3,
	_creature: Node
) -> void:
	threat_changed.emit({
		"event":"creature_died",
		"species_id":species_id,
		"drop_types":drops.size(),
	})
	_publish_ecology_if_changed(true)


func _on_creature_tree_exiting(creature: Node) -> void:
	if creature != null and creature.is_in_group("hostile"):
		threat_changed.emit({
			"event":"creature_exiting",
			"species_id":str(_property_value(creature, "species_id", "hostile")),
		})
	_schedule_exit_publish()


func _schedule_exit_publish() -> void:
	if _exit_publish_scheduled:
		return
	_exit_publish_scheduled = true
	call_deferred("_flush_exit_publish")


func _flush_exit_publish() -> void:
	_exit_publish_scheduled = false
	if not is_inside_tree():
		return
	_publish_ecology_if_changed(true)
	threat_changed.emit(_current_threat_summary())


func _current_threat_summary() -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {
			"active_windup_count":0,
			"elite_windup_count":0,
			"soonest_impact_seconds":-1.0,
		}
	return get_nearby_hostile_windup_summary(player.global_position, 24.0)


func _dispose_child(child: Node, emit_event: bool) -> void:
	if not is_instance_valid(child):
		return
	if child is Node3D and child.is_in_group("hostile"):
		threat_changed.emit({
			"event":"creature_removed",
			"species_id":str(_property_value(child, "species_id", "hostile")),
		})
	_disconnect_creature_runtime_signals(child)
	if child.get_parent() == self:
		remove_child(child)
	if emit_event and child is Node3D and child.is_in_group("creatures"):
		creature_despawned.emit(child)
	child.queue_free()


func _is_live_hostile(child: Node) -> bool:
	if (
		child is not Node3D
		or not child.is_in_group("hostile")
		or child.is_queued_for_deletion()
	):
		return false
	if child.has_method("is_combat_target_available"):
		return bool(child.call("is_combat_target_available"))
	return true


func _property_value(target: Object, property_name: String, fallback: Variant) -> Variant:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return fallback
