class_name GameplayServiceHub
extends Node

signal start_world_requested(world_state: Dictionary)
signal world_save_completed(world_id: String)
signal return_to_menu_requested
signal settings_applied(settings: Dictionary)

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ContainerStorageScript = preload("res://src/inventory/container_storage_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const ScalableFurnaceScript = preload(
	"res://src/machine/scalable_furnace_service.gd"
)
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const SaveScript = preload("res://src/save/save_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const AudioScript = preload("res://src/audio/audio_service.gd")
const AudioBridgeScript = preload("res://src/audio/audio_event_bridge.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const GameplayInputScript = preload("res://src/input/gameplay_input_service.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const SimulationPauseScript = preload("res://src/core/simulation_pause_service.gd")
const BlockInteractionScript = preload("res://src/interaction/block_interaction_service.gd")
const PlayerExperienceScript = preload("res://src/experience/player_experience_coordinator.gd")
const FeatureCoordinatorScript = preload(
	"res://src/core/service_hub_feature_coordinator.gd"
)
const MachineRuntimeParticipantScript = preload(
	"res://src/machine/machine_runtime_participant.gd"
)
const ScalableMachineRuntimeParticipantScript = preload(
	"res://src/machine/scalable_machine_runtime_participant.gd"
)
const MACHINE_RUNTIME_FEATURE := &"machine_runtime"
const DEFAULT_SETTINGS := {
	"mouse_sensitivity": 0.18,
	"render_distance": 3,
	"master_volume": 0.8,
	"fullscreen": false,
	"cycle_minutes": 10,
	"show_tutorial": true,
	"show_interaction_prompts": true,
}
const AMBIENT_BY_MAP := {
	"star_continent": "forest",
	"desert_ruins": "desert",
	"frozen_wastes": "wind",
	"sky_islands": "sky",
	"abyss_world": "cave",
}

var inventory
var container_storage
var furnace_service
var crafting
var save_service
var survival
var day_night
var audio_service
var audio_bridge
var creature_spawner
var gameplay_input
var input_context
var simulation_pause
var block_interaction
var player_experience
var feature_lifecycle: Node
var machine_runtime_participant: Node
var machine_runtime: Node
var main_menu
var game_ui
var current_state: Dictionary = {}
var current_world_id: String = ""
var current_settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var world_node
var player_node
var _pending_ambient := "forest"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	gameplay_input = _add_service(GameplayInputScript.new(), "GameplayInput")
	input_context = _add_service(InputContextScript.new(), "InputContext")
	input_context.gameplay_input_changed.connect(gameplay_input.set_active)
	simulation_pause = _add_service(SimulationPauseScript.new(), "SimulationPause")
	inventory = _add_service(InventoryScript.new(), "Inventory")
	container_storage = _add_service(ContainerStorageScript.new(), "ContainerStorage")
	container_storage.setup(inventory.registry)
	furnace_service = _add_service(ScalableFurnaceScript.new(), "FurnaceService")
	furnace_service.setup(inventory.registry)
	crafting = _add_service(CraftingScript.new(), "Crafting")
	save_service = _add_service(SaveScript.new(), "Save")
	survival = _add_service(SurvivalScript.new(), "Survival")
	day_night = _add_service(DayNightScript.new(), "DayNight")
	audio_service = _add_service(AudioScript.new(), "AudioService")
	audio_bridge = _add_service(AudioBridgeScript.new(), "AudioBridge")
	creature_spawner = _add_service(SpawnerScript.new(), "CreatureSpawner")
	block_interaction = _add_service(BlockInteractionScript.new(), "BlockInteraction")
	player_experience = _add_service(PlayerExperienceScript.new(), "PlayerExperience")
	feature_lifecycle = _add_service(
		FeatureCoordinatorScript.new(), "FeatureLifecycle"
	)
	feature_lifecycle.call("setup", self)
	machine_runtime_participant = _register_feature_participant(
		MACHINE_RUNTIME_FEATURE,
		ScalableMachineRuntimeParticipantScript.new(),
		"machine runtime"
	)
	if machine_runtime_participant != null:
		machine_runtime = machine_runtime_participant.call("get_scheduler") as Node
	var creature_callback := Callable(self, "_on_creature_spawned")
	if not creature_spawner.creature_spawned.is_connected(creature_callback):
		creature_spawner.creature_spawned.connect(creature_callback)
	crafting.setup(inventory)
	current_settings = save_service.load_settings(DEFAULT_SETTINGS)
	current_settings["render_distance"] = clampi(
		int(current_settings.get("render_distance", DEFAULT_SETTINGS.render_distance)), 1, 5
	)
	main_menu = get_node_or_null("MainMenu")
	game_ui = get_node_or_null("GameUI")
	player_experience.setup(inventory, game_ui, block_interaction, furnace_service)
	if main_menu != null:
		main_menu.setup(save_service, audio_service)
		main_menu.new_world_requested.connect(_begin_world)
		main_menu.continue_world_requested.connect(_begin_world)
		main_menu.settings_changed.connect(_on_settings_changed)
	if game_ui != null:
		game_ui.setup(
			inventory,
			crafting,
			survival,
			day_night,
			audio_service,
			gameplay_input,
			container_storage,
			furnace_service,
			player_experience
		)
		game_ui.end_gameplay()
		game_ui.save_requested.connect(_on_ui_save_requested)
		game_ui.return_to_menu_requested.connect(return_to_menu)
		game_ui.input_context_requested.connect(_on_input_context_requested)
		game_ui.simulation_pause_requested.connect(_on_simulation_pause_requested)
	block_interaction.setup(game_ui, container_storage, inventory, furnace_service)
	audio_bridge.setup(audio_service, null, inventory, crafting, survival)
	_apply_settings(current_settings)
	simulation_pause.reset()
	input_context.set_context(InputContextScript.CONTEXT_MENU)


func _add_service(service: Node, service_name: String) -> Node:
	service.name = service_name
	add_child(service)
	return service


func _register_feature_participant(
	participant_id: StringName, participant: Node, label: String
) -> Node:
	if feature_lifecycle == null:
		return null
	var registration: Dictionary = feature_lifecycle.call(
		"register_participant", participant_id, participant
	)
	if bool(registration.get("success", false)):
		return registration.get("participant") as Node
	push_error(
		"Unable to install %s lifecycle participant: %s"
		% [label, str(registration.get("reason", "unknown"))]
	)
	return null


func _begin_world(state: Dictionary) -> void:
	var migrated_state := state.duplicate(true)
	if feature_lifecycle != null and feature_lifecycle.has_method("normalize_world_state"):
		var raw_migrated: Variant = feature_lifecycle.call(
			"normalize_world_state", state
		)
		if raw_migrated is Dictionary:
			migrated_state = raw_migrated
	simulation_pause.reset()
	input_context.set_context(InputContextScript.CONTEXT_LOADING)
	input_context.unbind_player()
	player_experience.end_gameplay()
	player_experience.detach_player()
	if game_ui != null:
		game_ui.end_gameplay()
	if main_menu != null and main_menu.has_method("show_loading"):
		main_menu.call("show_loading", "正在准备世界和渲染资源…")
	creature_spawner.set_active(false)
	creature_spawner.clear_creatures()
	current_state = migrated_state.duplicate(true)
	if feature_lifecycle != null:
		feature_lifecycle.call("begin_world", current_state)
	player_experience.prepare_world(current_state.get("experience", {}))
	player_experience.apply_settings(current_settings)
	var metadata: Dictionary = current_state.get("metadata", {})
	current_world_id = str(metadata.get("id", ""))
	var inventory_data: Dictionary = current_state.get("inventory", {})
	if inventory_data.is_empty():
		inventory.clear()
		inventory.grant_starter_kit()
	else:
		inventory.deserialize(inventory_data)
	container_storage.deserialize(current_state.get("containers", {}))
	crafting.set_station("hand")
	survival.deserialize(current_state.get("survival", {}))
	survival.set_map_profile(str(metadata.get("map_id", "star_continent")))
	day_night.deserialize(current_state.get("day_night", {}))
	day_night.set_map_profile(str(metadata.get("map_id", "star_continent")))
	var profile: Dictionary = metadata.get("map_profile", {})
	_pending_ambient = str(
		profile.get("ambient", _ambient_for_map(str(metadata.get("map_id", ""))))
	)
	start_world_requested.emit(current_state.duplicate(true))


func activate_gameplay() -> void:
	simulation_pause.reset()
	creature_spawner.set_active(true)
	audio_service.start_ambient(_pending_ambient)
	if main_menu != null:
		main_menu.visible = false
	if game_ui != null:
		game_ui.begin_gameplay()
	else:
		input_context.set_context(InputContextScript.CONTEXT_GAMEPLAY)
	player_experience.begin_gameplay()
	if feature_lifecycle != null:
		feature_lifecycle.call("activate")


func handle_world_start_failed(reason: String) -> void:
	if feature_lifecycle != null:
		feature_lifecycle.call("clear", &"world_start_failed")
	elif furnace_service != null:
		furnace_service.clear()
	simulation_pause.reset()
	creature_spawner.set_active(false)
	creature_spawner.clear_creatures()
	container_storage.clear()
	audio_service.stop_ambient()
	player_experience.end_gameplay()
	player_experience.detach_player()
	if game_ui != null:
		game_ui.end_gameplay()
	input_context.set_context(InputContextScript.CONTEXT_MENU)
	input_context.unbind_player()
	world_node = null
	player_node = null
	current_state.clear()
	current_world_id = ""
	if main_menu != null:
		main_menu.show_main()
		if main_menu.has_method("show_error"):
			main_menu.call("show_error", "世界启动失败：%s" % reason)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	world_node = world
	player_node = player
	block_interaction.setup(game_ui, container_storage, inventory, furnace_service)
	if player != null:
		input_context.bind_player(player)
		player_experience.attach_player(player)
	else:
		input_context.unbind_player()
		player_experience.detach_player()
	day_night.attach_lighting(sun, environment)
	creature_spawner.setup(player, inventory, day_night, ground_resolver, false)
	audio_bridge.setup(audio_service, world, inventory, crafting, survival)
	if player != null:
		audio_bridge.connect_player(player)
		if player.has_method("setup_gameplay_services"):
			var services := {
				"inventory": inventory,
				"survival": survival,
				"audio": audio_service,
				"game_ui": game_ui,
				"input": gameplay_input,
				"interaction": block_interaction,
				"experience": player_experience,
			}
			player.call("setup_gameplay_services", services)
		elif player.has_method("bind_inventory"):
			player.call("bind_inventory", inventory)
			if player.has_method("bind_survival"):
				player.call("bind_survival", survival)
			if player.has_method("bind_input_service"):
				player.call("bind_input_service", gameplay_input)
			if player.has_method("bind_interaction_service"):
				player.call("bind_interaction_service", block_interaction)
		elif player.has_method("set_inventory_service"):
			player.call("set_inventory_service", inventory)
	_apply_settings(current_settings)
	if feature_lifecycle != null:
		feature_lifecycle.call(
			"attach_game", world, player, sun, environment, ground_resolver
		)


func _on_input_context_requested(context: StringName) -> void:
	input_context.set_context(context)


func _on_simulation_pause_requested(paused: bool) -> void:
	simulation_pause.set_paused(paused)


func _on_ui_save_requested() -> void:
	var saved: bool = save_current()
	if game_ui != null and game_ui.has_method("show_save_result"):
		game_ui.call("show_save_result", saved)


func _on_settings_changed(settings: Dictionary) -> void:
	var merged: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	merged.merge(current_settings, true)
	merged.merge(settings, true)
	merged["render_distance"] = clampi(
		int(merged.get("render_distance", DEFAULT_SETTINGS.render_distance)), 1, 5
	)
	current_settings = merged
	var saved: bool = bool(save_service.save_settings(current_settings))
	_apply_settings(current_settings)
	if main_menu != null and main_menu.has_method("show_settings_result"):
		main_menu.call("show_settings_result", saved)


func _apply_settings(settings: Dictionary) -> void:
	var volume := clampf(
		float(settings.get("master_volume", DEFAULT_SETTINGS.master_volume)), 0.0, 1.0
	)
	audio_service.set_master_volume(volume)
	player_experience.apply_settings(settings)
	if DisplayServer.get_name() != "headless":
		var fullscreen := bool(settings.get("fullscreen", DEFAULT_SETTINGS.fullscreen))
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_FULLSCREEN
				if fullscreen
				else DisplayServer.WINDOW_MODE_WINDOWED
			)
		)
	day_night.cycle_duration_seconds = (
		maxf(1.0, float(settings.get("cycle_minutes", DEFAULT_SETTINGS.cycle_minutes))) * 60.0
	)
	if player_node != null:
		_set_property_if_present(
			player_node,
			"mouse_sensitivity",
			float(settings.get("mouse_sensitivity", DEFAULT_SETTINGS.mouse_sensitivity)) / 100.0
		)
	if world_node != null:
		var render_distance := clampi(
			int(settings.get("render_distance", DEFAULT_SETTINGS.render_distance)), 1, 5
		)
		_set_property_if_present(world_node, "render_distance", render_distance)
		_set_property_if_present(world_node, "unload_distance", render_distance + 1)
	settings_applied.emit(settings.duplicate(true))


func _set_property_if_present(target: Object, property_name: String, value: Variant) -> bool:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			target.set(property_name, value)
			return true
	return false


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if current_world_id.is_empty():
		return false
	var payload: Dictionary = current_state.duplicate(true)
	payload["inventory"] = inventory.serialize()
	payload["containers"] = container_storage.serialize()
	payload["survival"] = survival.serialize()
	payload["day_night"] = day_night.serialize()
	payload["experience"] = player_experience.serialize()
	if feature_lifecycle != null:
		feature_lifecycle.call("save_into", payload)
	elif furnace_service != null:
		payload["machines"] = furnace_service.serialize()
	if not world_state.is_empty():
		payload["world"] = world_state.duplicate(true)
	elif world_node != null:
		if world_node.has_method("serialize_state"):
			payload["world"] = world_node.call("serialize_state")
		elif world_node.has_method("serialize"):
			payload["world"] = world_node.call("serialize")
		elif world_node.has_method("serialize_overrides"):
			payload["world"] = {"block_overrides": world_node.call("serialize_overrides")}
	if not player_state.is_empty():
		payload["player"] = player_state.duplicate(true)
	elif player_node != null:
		payload["player"] = _player_state(player_node)
	var saved: bool = bool(save_service.save_world(current_world_id, payload))
	if saved:
		current_state = payload
		world_save_completed.emit(current_world_id)
	return saved


func return_to_menu() -> void:
	if not save_current():
		if game_ui != null and game_ui.has_method("show_save_result"):
			game_ui.call("show_save_result", false)
		return
	simulation_pause.reset()
	if feature_lifecycle != null:
		feature_lifecycle.call("clear", &"return_to_menu")
	elif furnace_service != null:
		furnace_service.clear()
	creature_spawner.set_active(false)
	creature_spawner.clear_creatures()
	audio_service.stop_ambient()
	player_experience.end_gameplay()
	player_experience.detach_player()
	if game_ui != null:
		game_ui.end_gameplay()
	input_context.set_context(InputContextScript.CONTEXT_MENU)
	input_context.unbind_player(player_node)
	container_storage.clear()
	world_node = null
	player_node = null
	current_state.clear()
	current_world_id = ""
	if main_menu != null:
		main_menu.show_main()
	return_to_menu_requested.emit()


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	if feature_lifecycle != null:
		feature_lifecycle.call("snapshot_into", snapshot)
		snapshot["feature_lifecycle"] = feature_lifecycle.call("get_snapshot")
	return snapshot


func _exit_tree() -> void:
	if feature_lifecycle != null and feature_lifecycle.has_method("shutdown"):
		feature_lifecycle.call("shutdown")
	var creature_callback := Callable(self, "_on_creature_spawned")
	if (
		creature_spawner != null
		and is_instance_valid(creature_spawner)
		and creature_spawner.has_signal("creature_spawned")
		and creature_spawner.is_connected("creature_spawned", creature_callback)
	):
		creature_spawner.disconnect("creature_spawned", creature_callback)


func _on_creature_spawned(creature: Node3D) -> void:
	audio_bridge.connect_creature(creature)


func _player_state(player: Node3D) -> Dictionary:
	if player.has_method("serialize_state"):
		return player.call("serialize_state")
	return {
		"position": [
			player.global_position.x,
			player.global_position.y,
			player.global_position.z,
		],
		"rotation": [player.rotation.x, player.rotation.y, player.rotation.z],
	}


func _ambient_for_map(map_id: String) -> String:
	return str(AMBIENT_BY_MAP.get(map_id, "forest"))
