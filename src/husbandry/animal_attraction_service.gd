class_name AnimalAttractionService
extends Node

signal following_changed(count: int)

const AttractionRegistryScript = preload(
	"res://src/husbandry/animal_attraction_registry.gd"
)
const AttractionPolicyScript = preload(
	"res://src/husbandry/animal_attraction_policy.gd"
)
const HusbandryRegistryScript = preload("res://src/husbandry/husbandry_registry.gd")

var inventory: Node
var spawner: Node
var player: Node3D
var registry = AttractionRegistryScript.new()
var husbandry_registry = HusbandryRegistryScript.new()
var policy = AttractionPolicyScript.new()

var _active: bool = false
var _refresh_accumulator: float = 0.0
var _following_ids: Dictionary = {}


func _ready() -> void:
	set_process(false)


func setup(p_inventory: Node, p_spawner: Node) -> void:
	_disconnect_inventory()
	inventory = p_inventory
	spawner = p_spawner
	registry.ensure_loaded()
	husbandry_registry.ensure_loaded()
	if inventory != null and inventory.has_signal("selected_slot_changed"):
		inventory.connect("selected_slot_changed", Callable(self, "_on_selected_slot_changed"))


func attach_player(p_player: Node3D) -> void:
	player = p_player
	_refresh_accumulator = 0.0
	if _active:
		refresh_now()


func activate() -> void:
	_active = true
	set_process(true)
	_refresh_accumulator = 0.0
	refresh_now()


func deactivate() -> void:
	_active = false
	set_process(false)
	_clear_all_attractions()
	_refresh_accumulator = 0.0


func clear() -> void:
	deactivate()
	player = null
	_following_ids.clear()


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"following": _following_ids.size(),
		"supported_species": registry.species_count(),
		"selected_item": _selected_item_id(),
	}


func refresh_now() -> int:
	if not _active or player == null or not is_instance_valid(player):
		_clear_all_attractions()
		return 0
	if spawner == null or not is_instance_valid(spawner):
		_clear_all_attractions()
		return 0
	var selected_item_id := _selected_item_id()
	var next_following: Dictionary = {}
	for child: Node in spawner.get_children():
		if child is not Node3D or not child.is_in_group("animals"):
			continue
		var animal := child as Node3D
		if not animal.has_method("set_attraction_target"):
			continue
		var species_id := _species_id(animal)
		var attraction_profile := registry.get_profile(species_id)
		var husbandry_profile := husbandry_registry.get_species(species_id)
		var feed_item_id := str(husbandry_profile.get("feed_item", ""))
		var evaluation := policy.evaluate(
			attraction_profile,
			feed_item_id,
			selected_item_id,
			animal.global_position.distance_to(player.global_position)
		)
		if bool(evaluation.get("should_follow", false)):
			animal.call(
				"set_attraction_target",
				player,
				registry.get_target_timeout_seconds(),
				float(evaluation.get("stop_distance", 2.0))
			)
			next_following[animal.get_instance_id()] = true
		elif animal.has_method("clear_attraction_target"):
			animal.call("clear_attraction_target")
	var previous_count := _following_ids.size()
	_following_ids = next_following
	if previous_count != _following_ids.size():
		following_changed.emit(_following_ids.size())
	return _following_ids.size()


func _process(delta: float) -> void:
	if not _active:
		return
	_refresh_accumulator += maxf(0.0, delta)
	var refresh_seconds := registry.get_refresh_seconds()
	if _refresh_accumulator < refresh_seconds:
		return
	_refresh_accumulator = fmod(_refresh_accumulator, refresh_seconds)
	refresh_now()


func _selected_item_id() -> String:
	if inventory == null or not inventory.has_method("get_selected_item"):
		return ""
	var selected_value: Variant = inventory.call("get_selected_item")
	if selected_value is not Dictionary:
		return ""
	return str(selected_value.get("item_id", ""))


func _species_id(animal: Node) -> String:
	for property: Dictionary in animal.get_property_list():
		if str(property.get("name", "")) == "species_id":
			return str(animal.get("species_id"))
	return ""


func _clear_all_attractions() -> void:
	if spawner != null and is_instance_valid(spawner):
		for child: Node in spawner.get_children():
			if child.has_method("clear_attraction_target"):
				child.call("clear_attraction_target")
	var had_followers := not _following_ids.is_empty()
	_following_ids.clear()
	if had_followers:
		following_changed.emit(0)


func _on_selected_slot_changed(_index: int, _slot: Dictionary) -> void:
	if _active:
		refresh_now()


func _disconnect_inventory() -> void:
	if inventory == null or not inventory.has_signal("selected_slot_changed"):
		return
	var callback := Callable(self, "_on_selected_slot_changed")
	if inventory.is_connected("selected_slot_changed", callback):
		inventory.disconnect("selected_slot_changed", callback)


func _exit_tree() -> void:
	_disconnect_inventory()
	_clear_all_attractions()
