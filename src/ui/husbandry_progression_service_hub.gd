class_name HusbandryProgressionServiceHub
extends "res://src/ui/repair_progression_service_hub.gd"

const HusbandryServiceScript = preload(
	"res://src/husbandry/animal_husbandry_service.gd"
)
const HusbandryInteractionScript = preload(
	"res://src/husbandry/husbandry_interaction_adapter.gd"
)

var husbandry_service: Node
var husbandry_interaction: Node


func _ready() -> void:
	super._ready()
	husbandry_service = _add_service(
		HusbandryServiceScript.new(), "AnimalHusbandryService"
	)
	husbandry_service.call("setup", inventory.registry, inventory, creature_spawner)
	husbandry_interaction = _add_service(
		HusbandryInteractionScript.new(), "HusbandryInteraction"
	)
	husbandry_interaction.call("setup", husbandry_service)
	player_experience.call(
		"setup",
		inventory,
		game_ui,
		block_interaction,
		furnace_service,
		husbandry_interaction
	)
	_connect_husbandry_feedback()


func _begin_world(state: Dictionary) -> void:
	if husbandry_service != null:
		husbandry_service.call("deserialize", state.get("husbandry", {}))
	super._begin_world(state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if husbandry_service != null:
		husbandry_service.call("attach_world", world, player)
	if player != null and player.has_method("bind_entity_interaction_service"):
		player.call("bind_entity_interaction_service", husbandry_interaction)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if husbandry_service != null:
		husbandry_service.call("activate")


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if husbandry_service != null:
		current_state["husbandry"] = husbandry_service.call("serialize")
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	if husbandry_service != null:
		husbandry_service.call("clear")
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty() and husbandry_service != null:
		husbandry_service.call("clear")


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["husbandry"] = (
		husbandry_service.call("get_snapshot") if husbandry_service != null else {}
	)
	return snapshot


func _exit_tree() -> void:
	if husbandry_service != null:
		husbandry_service.call("clear")
	super._exit_tree()


func _connect_husbandry_feedback() -> void:
	if husbandry_service == null:
		return
	husbandry_service.connect("animal_fed", Callable(self, "_on_animal_fed"))
	husbandry_service.connect("animal_ready", Callable(self, "_on_animal_ready"))
	husbandry_service.connect("baby_born", Callable(self, "_on_baby_born"))
	husbandry_service.connect("animal_grew", Callable(self, "_on_animal_grew"))
	husbandry_service.connect(
		"interaction_rejected", Callable(self, "_on_husbandry_rejected")
	)


func _on_animal_fed(result: Dictionary) -> void:
	_publish_husbandry_result(result, "success", 2.0)
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")


func _on_animal_ready(result: Dictionary) -> void:
	_publish_husbandry_result(result, "success", 2.4)
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")


func _on_baby_born(result: Dictionary) -> void:
	_publish_husbandry_result(result, "success", 3.2)
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")


func _on_animal_grew(result: Dictionary) -> void:
	_publish_husbandry_result(result, "info", 2.4)


func _on_husbandry_rejected(reason: String, context: Dictionary) -> void:
	var message := str(context.get("message", "暂时无法进行该动物交互"))
	_publish_character_message(
		message,
		"warning",
		"husbandry_rejected:%s:%s" % [reason, str(context.get("species_id", "animal"))],
		2.5
	)


func _publish_husbandry_result(
	result: Dictionary, severity: String, duration: float
) -> void:
	_publish_character_message(
		str(result.get("message", "动物状态已更新")),
		severity,
		"husbandry:%s:%s" % [
			str(result.get("action", "update")),
			str(result.get("husbandry_id", result.get("species_id", "animal"))),
		],
		duration
	)
