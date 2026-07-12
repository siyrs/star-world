class_name SurvivalService
extends Node

signal health_changed(current: float, maximum: float)
signal hunger_changed(current: float, maximum: float)
signal player_died(cause: String)
signal player_respawned
signal starvation_started
signal food_consumed(item_id: String, food_points: float)

const SERIAL_VERSION := 1

@export var max_health: float = 20.0
@export var max_hunger: float = 20.0
@export var passive_hunger_interval: float = 12.0
@export var starvation_damage_interval: float = 4.0
@export var natural_regeneration_interval: float = 4.0

var health: float = 20.0
var hunger: float = 20.0
var saturation: float = 5.0
var alive: bool = true
var hunger_multiplier: float = 1.0

var _passive_timer: float = 0.0
var _starvation_timer: float = 0.0
var _regeneration_timer: float = 0.0


func _ready() -> void:
	health = clampf(health, 0.0, max_health)
	hunger = clampf(hunger, 0.0, max_hunger)
	health_changed.emit(health, max_health)
	hunger_changed.emit(hunger, max_hunger)


func _process(delta: float) -> void:
	if not alive:
		return
	_passive_timer += delta
	if _passive_timer >= passive_hunger_interval / maxf(0.1, hunger_multiplier):
		_passive_timer = 0.0
		add_exhaustion(1.0)
	if hunger <= 0.0:
		_starvation_timer += delta
		if _starvation_timer >= starvation_damage_interval:
			_starvation_timer = 0.0
			take_damage(1.0, "starvation")
	else:
		_starvation_timer = 0.0
	if hunger >= 18.0 and health < max_health:
		_regeneration_timer += delta
		if _regeneration_timer >= natural_regeneration_interval:
			_regeneration_timer = 0.0
			heal(1.0)
			add_exhaustion(1.0)
	else:
		_regeneration_timer = 0.0


func set_map_profile(map_id: String) -> void:
	hunger_multiplier = 1.35 if map_id == "frozen_wastes" else 1.0


func take_damage(amount: float, cause: String = "damage") -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		alive = false
		player_died.emit(cause)


# Compatibility alias used by the player controller's public service contract.
func damage(amount: float, cause: String = "damage") -> void:
	take_damage(amount, cause)


func heal(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	var previous := health
	health = minf(max_health, health + amount)
	if not is_equal_approx(previous, health):
		health_changed.emit(health, max_health)


func add_exhaustion(amount: float) -> void:
	if amount <= 0.0 or not alive:
		return
	var remaining := amount
	if saturation > 0.0:
		var saturation_used := minf(saturation, remaining)
		saturation -= saturation_used
		remaining -= saturation_used
	if remaining > 0.0:
		var previous := hunger
		hunger = maxf(0.0, hunger - remaining)
		if not is_equal_approx(previous, hunger):
			hunger_changed.emit(hunger, max_hunger)
			if hunger <= 0.0:
				starvation_started.emit()


func consume_food(item_id: String, food_points: float, saturation_points: float = 0.0) -> bool:
	if not alive or food_points <= 0.0 or hunger >= max_hunger:
		return false
	hunger = minf(max_hunger, hunger + food_points)
	saturation = minf(max_hunger, saturation + maxf(0.0, saturation_points))
	hunger_changed.emit(hunger, max_hunger)
	food_consumed.emit(item_id, food_points)
	return true


func consume_selected_inventory_item(inventory) -> bool:
	if (
		inventory == null
		or not inventory.has_method("get_selected_item")
		or not inventory.has_method("consume_selected")
	):
		return false
	var slot: Dictionary = inventory.call("get_selected_item")
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return false
	var item: Dictionary = inventory.registry.get_item(item_id)
	var food_points := float(item.get("food", 0.0))
	var saturation_points := float(item.get("saturation", 0.0))
	if not item.has("food") or not alive or food_points <= 0.0 or hunger >= max_hunger:
		return false
	var consumed: Dictionary = inventory.call("consume_selected", 1)
	if consumed.is_empty():
		return false
	if consume_food(item_id, food_points, saturation_points):
		return true
	inventory.add_item(item_id, 1, consumed.get("metadata", {}))
	return false


func consume_inventory_item(inventory, item_id: String) -> bool:
	if inventory == null or inventory.count_item(item_id) <= 0:
		return false
	if inventory.has_method("get_selected_item"):
		var selected: Dictionary = inventory.call("get_selected_item")
		if str(selected.get("item_id", "")) == item_id:
			return consume_selected_inventory_item(inventory)
	var item: Dictionary = inventory.registry.get_item(item_id)
	if not item.has("food"):
		return false
	if not consume_food(item_id, float(item.get("food", 0)), float(item.get("saturation", 0))):
		return false
	inventory.remove_item(item_id, 1)
	return true


func report_player_action(action: String) -> void:
	match action:
		"jump":
			add_exhaustion(0.18)
		"sprint":
			add_exhaustion(0.08)
		"mine":
			add_exhaustion(0.03)
		"attack":
			add_exhaustion(0.1)


func respawn() -> void:
	alive = true
	health = max_health
	hunger = max_hunger * 0.75
	saturation = 2.0
	_passive_timer = 0.0
	_starvation_timer = 0.0
	health_changed.emit(health, max_health)
	hunger_changed.emit(hunger, max_hunger)
	player_respawned.emit()


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"health": health,
		"hunger": hunger,
		"saturation": saturation,
		"alive": alive,
		"hunger_multiplier": hunger_multiplier
	}


func deserialize(data: Dictionary) -> bool:
	health = clampf(float(data.get("health", max_health)), 0.0, max_health)
	hunger = clampf(float(data.get("hunger", max_hunger)), 0.0, max_hunger)
	saturation = clampf(float(data.get("saturation", 5.0)), 0.0, max_hunger)
	alive = bool(data.get("alive", health > 0.0)) and health > 0.0
	hunger_multiplier = maxf(0.1, float(data.get("hunger_multiplier", 1.0)))
	health_changed.emit(health, max_health)
	hunger_changed.emit(hunger, max_hunger)
	return true
