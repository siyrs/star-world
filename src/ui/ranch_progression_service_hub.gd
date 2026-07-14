class_name RanchProgressionServiceHub
extends "res://src/ui/husbandry_progression_service_hub.gd"

const AttractionServiceScript = preload(
	"res://src/husbandry/animal_attraction_service.gd"
)
const ProductServiceScript = preload(
	"res://src/husbandry/animal_product_service.gd"
)

var animal_attraction_service: Node
var animal_product_service: Node


func _ready() -> void:
	super._ready()
	animal_attraction_service = _add_service(
		AttractionServiceScript.new(), "AnimalAttractionService"
	)
	animal_attraction_service.call("setup", inventory, creature_spawner)
	animal_product_service = _add_service(
		ProductServiceScript.new(), "AnimalProductService"
	)
	animal_product_service.call(
		"setup", inventory.registry, inventory, husbandry_service, creature_spawner
	)
	if husbandry_interaction != null and husbandry_interaction.has_method("set_product_service"):
		husbandry_interaction.call("set_product_service", animal_product_service)
	if animal_product_service.has_signal("product_spawned"):
		animal_product_service.connect(
			"product_spawned", Callable(self, "_on_animal_product_spawned")
		)


func _begin_world(state: Dictionary) -> void:
	if animal_product_service != null:
		animal_product_service.call("deserialize", state.get("animal_products", {}))
	if animal_attraction_service != null:
		animal_attraction_service.call("deactivate")
	super._begin_world(state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if animal_attraction_service != null:
		animal_attraction_service.call("attach_player", player)
	if animal_product_service != null:
		animal_product_service.call("attach_player", player)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if animal_attraction_service != null:
		animal_attraction_service.call("activate")
	if animal_product_service != null:
		animal_product_service.call("activate")


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if animal_product_service != null:
		current_state["animal_products"] = animal_product_service.call("serialize")
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	_clear_ranch_state()
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_ranch_state()


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["animal_attraction"] = (
		animal_attraction_service.call("get_snapshot")
		if animal_attraction_service != null
		else {}
	)
	snapshot["animal_products"] = (
		animal_product_service.call("get_snapshot")
		if animal_product_service != null
		else {}
	)
	return snapshot


func _exit_tree() -> void:
	_clear_ranch_state()
	super._exit_tree()


func _on_animal_product_spawned(result: Dictionary) -> void:
	_publish_character_message(
		str(result.get("message", "动物产物已生成")),
		"success",
		"animal_product:%s:%s" % [
			str(result.get("husbandry_id", "animal")),
			str(result.get("product_item", "product")),
		],
		2.8
	)
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")


func _clear_ranch_state() -> void:
	if animal_attraction_service != null and animal_attraction_service.has_method("clear"):
		animal_attraction_service.call("clear")
	if animal_product_service != null and animal_product_service.has_method("clear"):
		animal_product_service.call("clear")
