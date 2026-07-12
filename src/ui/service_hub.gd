class_name GameplayServiceHub
extends Node

signal start_world_requested(world_state: Dictionary)
signal world_save_completed(world_id: String)
signal return_to_menu_requested
signal settings_applied(settings: Dictionary)

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const SaveScript = preload("res://src/save/save_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const AudioScript = preload("res://src/audio/audio_service.gd")
const AudioBridgeScript = preload("res://src/audio/audio_event_bridge.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const DEFAULT_SETTINGS := {
	"mouse_sensitivity": 0.18,
	"render_distance": 4,
	"master_volume": 0.8,
	"fullscreen": false,
	"cycle_minutes": 10
}
const AMBIENT_BY_MAP := {
	"star_continent": "forest",
	"desert_ruins": "desert",
	"frozen_wastes": "wind",
	"sky_islands": "sky",
	"abyss_world": "cave"
}

var inventory
var crafting
var save_service
var survival
var day_night
var audio_service
var audio_bridge
var creature_spawner
var input_context
var main_menu
var game_ui
var current_state: Dictionary = {}
var current_world_id: String = ""
var current_settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var world_node
var player_node


func _ready() -> void:
	input_context = _add_service(InputContextScript.new(), "InputContext")
	inventory = _add_service(InventoryScript.new(), "Inventory")
	crafting = _add_service(CraftingScript.new(), "Crafting")
	save_service = _add_service(SaveScript.new(), "Save")
	survival = _add_service(SurvivalScript.new(), "Survival")
	day_night = _add_service(DayNightScript.new(), "DayNight")
	audio_service = _add_service(AudioScript.new(), "AudioService")
	audio_bridge = _add_service(AudioBridgeScript.new(), "AudioBridge")
	creature_spawner = _add_service(SpawnerScript.new(), "CreatureSpawner")
	var creature_callback := Callable(self, "_on_creature_spawned")
	if not creature_spawner.creature_spawned.is_connected(creature_callback):
		creature_spawner.creature_spawned.connect(creature_callback)
	crafting.setup(inventory)
	current_settings = save_service.load_settings(DEFAULT_SETTINGS)
	current_settings["render_distance"] = clampi(
		int(current_settings.get("render_distance", DEFAULT_SETTINGS.render_distance)), 1, 5
	)
	_apply_settings(current_settings)
	main_menu = get_node_or_null("MainMenu")
	game_ui = get_node_or_null("GameUI")
	if main_menu != null:
		main_menu.setup(save_service, audio_service)
		main_menu.new_world_requested.connect(_begin_world)
		main_menu.continue_world_requested.connect(_begin_world)
		main_menu.settings_changed.connect(_on_settings_changed)
	if game_ui != null:
		game_ui.setup(inventory, crafting, survival, day_night, audio_service)
		game_ui.end_gameplay()
		game_ui.save_requested.connect(func(): save_current())
		game_ui.return_to_menu_requested.connect(return_to_menu)
		game_ui.input_context_requested.connect(_on_input_context_requested)
	audio_bridge.setup(audio_service, null, inventory, crafting, survival)
	input_context.set_context(InputContextScript.CONTEXT_MENU)


func _add_service(service: Node, service_name: String) -> Node:
	service.name = service_name
	add_child(service)
	return service


func _begin_world(state: Dictionary) -> void:
	creature_spawner.set_active(false)
	creature_spawner.clear_creatures()
	current_state = state.duplicate(true)
	var metadata: Dictionary = current_state.get("metadata", {})
	current_world_id = str(metadata.get("id", ""))
	var inventory_data: Dictionary = current_state.get("inventory", {})
	if inventory_data.is_empty():
		inventory.clear()
		inventory.grant_starter_kit()
	else:
		inventory.deserialize(inventory_data)
	survival.deserialize(current_state.get("survival", {}))
	survival.set_map_profile(str(metadata.get("map_id", "star_continent")))
	day_night.deserialize(current_state.get("day_night", {}))
	day_night.set_map_profile(str(metadata.get("map_id", "star_continent")))
	var profile: Dictionary = metadata.get("map_profile", {})
	audio_service.start_ambient(
		str(profile.get("ambient", _ambient_for_map(str(metadata.get("map_id", "")))))
	)
	if main_menu != null:
		main_menu.visible = false
	if game_ui != null:
		game_ui.begin_gameplay()
	else:
		input_context.set_context(InputContextScript.CONTEXT_GAMEPLAY)
	start_world_requested.emit(current_state.duplicate(true))


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	world_node = world
	player_node = player
	if player != null:
		input_context.bind_player(player)
	else:
		input_context.unbind_player()
	day_night.attach_lighting(sun, environment)
	creature_spawner.setup(player, inventory, day_night, ground_resolver)
	audio_bridge.setup(audio_service, world, inventory, crafting, survival)
	if player != null:
		audio_bridge.connect_player(player)
		if player.has_method("setup_gameplay_services"):
			player.call(
				"setup_gameplay_services",
				{
					"inventory": inventory,
					"survival": survival,
					"audio": audio_service,
					"game_ui": game_ui
				}
			)
		elif player.has_method("bind_inventory"):
			player.call("bind_inventory", inventory)
			if player.has_method("bind_survival"):
				player.call("bind_survival", survival)
		elif player.has_method("set_inventory_service"):
			player.call("set_inventory_service", inventory)
	_apply_settings(current_settings)


func _on_input_context_requested(context: StringName) -> void:
	input_context.set_context(context)


func _on_settings_changed(settings: Dictionary) -> void:
	var merged := DEFAULT_SETTINGS.duplicate(true)
	merged.merge(current_settings, true)
	merged.merge(settings, true)
	merged["render_distance"] = clampi(
		int(merged.get("render_distance", DEFAULT_SETTINGS.render_distance)), 1, 5
	)
	current_settings = merged
	save_service.save_settings(current_settings)
	_apply_settings(current_settings)


func _apply_settings(settings: Dictionary) -> void:
	var volume := clampf(
		float(settings.get("master_volume", DEFAULT_SETTINGS.master_volume)), 0.0, 1.0
	)
	audio_service.set_master_volume(volume)
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
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			target.set(property_name, value)
			return true
	return false


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if current_world_id.is_empty():
		return false
	var payload := current_state.duplicate(true)
	payload["inventory"] = inventory.serialize()
	payload["survival"] = survival.serialize()
	payload["day_night"] = day_night.serialize()
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
	save_current()
	creature_spawner.set_active(false)
	creature_spawner.clear_creatures()
	audio_service.stop_ambient()
	if game_ui != null:
		game_ui.end_gameplay()
	input_context.set_context(InputContextScript.CONTEXT_MENU)
	if main_menu != null:
		main_menu.show_main()
	return_to_menu_requested.emit()


func _on_creature_spawned(creature: Node3D) -> void:
	audio_bridge.connect_creature(creature)


func _player_state(player: Node3D) -> Dictionary:
	return {
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"rotation": [player.rotation.x, player.rotation.y, player.rotation.z]
	}


func _ambient_for_map(map_id: String) -> String:
	return str(AMBIENT_BY_MAP.get(map_id, "forest"))
