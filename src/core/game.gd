class_name StarWorldGame
extends Node3D

signal world_started(profile_id: String, seed: int, world_id: String)
signal world_start_failed(reason: String)
signal save_requested(state: Dictionary)

const WORLD_SCRIPT_PATH := "res://src/world/voxel_world.gd"
const PLAYER_SCENE_PATH := "res://scenes/game/player.tscn"
const SpawnResolverScript = preload("res://src/player/player_spawn_resolver.gd")

var world: Node3D
var player: CharacterBody3D
var current_profile_id := "star_continent"
var current_seed := 734521
var current_world_id := "quick-world"
var current_saved_state: Dictionary = {}
var _spawn_resolver = SpawnResolverScript.new()

@onready var world_root: Node3D = $WorldRoot
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var service_hub: Node = $GameplayServiceHub


func _ready() -> void:
	_ensure_core_nodes()
	player.visible = false
	world_root.visible = false
	if service_hub.has_signal("start_world_requested"):
		service_hub.connect("start_world_requested", Callable(self, "_on_world_state_requested"))
	if service_hub.has_signal("return_to_menu_requested"):
		service_hub.connect(
			"return_to_menu_requested", Callable(self, "_on_return_to_menu_requested")
		)
	if service_hub.has_method("activate_gameplay"):
		world_started.connect(
			func(_profile_id: String, _seed: int, _world_id: String) -> void:
				service_hub.call("activate_gameplay")
		)
	if service_hub.has_method("handle_world_start_failed"):
		world_start_failed.connect(
			func(reason: String) -> void: service_hub.call("handle_world_start_failed", reason)
		)


func begin_world_state(state: Dictionary) -> void:
	if service_hub.has_method("_begin_world"):
		service_hub.call("_begin_world", state.duplicate(true))
	else:
		_on_world_state_requested(state)


func start_world(
	profile_id: String, seed: int, world_id: String, saved_state: Dictionary = {}
) -> bool:
	_ensure_core_nodes()
	if world == null or player == null:
		world_start_failed.emit("core_nodes_unavailable")
		return false
	current_profile_id = profile_id if not profile_id.is_empty() else "star_continent"
	current_seed = seed
	current_world_id = world_id if not world_id.is_empty() else "quick-world"
	current_saved_state = saved_state.duplicate(true)
	world.call(
		"start_world", current_profile_id, current_seed, current_world_id, current_saved_state
	)
	player.call("bind_world", world)
	var fallback_spawn: Vector3 = world.call("get_spawn_position")
	var player_state: Dictionary = current_saved_state.get("player", {})
	var preferred_spawn := fallback_spawn
	if player_state.has("position"):
		preferred_spawn = _array_to_vector3(player_state.get("position", []), fallback_spawn)
	player.global_position = _spawn_resolver.resolve(world, preferred_spawn, fallback_spawn)
	if player.has_method("restore_orientation"):
		player.call("restore_orientation", player_state)
	player.visible = true
	world_root.visible = true
	world.call("set_focus", player)
	_attach_gameplay_services()
	world_started.emit(current_profile_id, current_seed, current_world_id)
	return true


func collect_state() -> Dictionary:
	var state := current_saved_state.duplicate(true)
	var metadata: Dictionary = state.get("metadata", {})
	metadata["id"] = current_world_id
	metadata["map_id"] = current_profile_id
	metadata["seed"] = current_seed
	state["metadata"] = metadata
	if world != null:
		state["world"] = world.call("serialize")
	if player != null:
		if player.has_method("serialize_state"):
			state["player"] = player.call("serialize_state")
		else:
			state["player"] = {
				"position":
					[
						player.global_position.x,
						player.global_position.y,
						player.global_position.z,
					],
				"rotation": [player.rotation.x, player.rotation.y, player.rotation.z],
			}
	var inventory = service_hub.get("inventory")
	if inventory != null and inventory.has_method("serialize"):
		state["inventory"] = inventory.call("serialize")
	var survival = service_hub.get("survival")
	if survival != null and survival.has_method("serialize"):
		state["survival"] = survival.call("serialize")
	var day_night = service_hub.get("day_night")
	if day_night != null and day_night.has_method("serialize"):
		state["day_night"] = day_night.call("serialize")
	return state


func request_save() -> Dictionary:
	var state := collect_state()
	save_requested.emit(state)
	if service_hub.has_method("save_current"):
		service_hub.call("save_current", state.get("world", {}), state.get("player", {}))
	return state


func _ensure_core_nodes() -> void:
	if world == null and ResourceLoader.exists(WORLD_SCRIPT_PATH):
		var world_script: Script = load(WORLD_SCRIPT_PATH)
		world = world_script.new()
		world.name = "VoxelWorld"
		world_root.add_child(world)
	if player == null and ResourceLoader.exists(PLAYER_SCENE_PATH):
		var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
		player = player_scene.instantiate()
		player.name = "Player"
		add_child(player)


func _attach_gameplay_services() -> void:
	if service_hub.has_method("attach_game"):
		service_hub.call(
			"attach_game",
			world,
			player,
			sun,
			world_environment,
			Callable(world, "resolve_ground_position")
		)


func _on_world_state_requested(state: Dictionary) -> void:
	var metadata: Dictionary = state.get("metadata", {})
	var requested_profile := str(metadata.get("map_id", "star_continent"))
	var requested_seed := int(metadata.get("seed", 734521))
	var requested_world_id := str(metadata.get("id", "quick-world"))
	start_world(requested_profile, requested_seed, requested_world_id, state)


func _on_return_to_menu_requested() -> void:
	if player != null:
		player.visible = false
	if world != null and world.has_method("clear_world"):
		world.call("clear_world")
	world_root.visible = false


func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		var result := Vector3(float(value[0]), float(value[1]), float(value[2]))
		if is_finite(result.x) and is_finite(result.y) and is_finite(result.z):
			return result
	return fallback
