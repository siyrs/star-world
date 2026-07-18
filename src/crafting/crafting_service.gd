class_name CraftingService
extends Node

signal recipes_loaded(count: int)
signal craft_succeeded(recipe_id: String, output: Dictionary)
signal craft_failed(recipe_id: String, reason: String)

const DEFAULT_DATA_PATH := "res://data/recipes.json"
const VALID_STATIONS := ["hand", "workbench"]

var inventory
var active_station: String = "hand"
var _recipes: Dictionary = {}


func _ready() -> void:
	if _recipes.is_empty():
		load_recipes()


func setup(inventory_service) -> void:
	inventory = inventory_service
	if _recipes.is_empty():
		load_recipes()


func load_recipes(path: String = DEFAULT_DATA_PATH) -> bool:
	_recipes.clear()
	if not FileAccess.file_exists(path):
		push_error("Recipe registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("recipes"):
		push_error("Invalid recipe registry: %s" % path)
		return false
	for raw_recipe in parsed["recipes"]:
		if raw_recipe is not Dictionary:
			continue
		var recipe_id := str(raw_recipe.get("id", ""))
		var station := str(raw_recipe.get("station", "hand"))
		if recipe_id.is_empty() or station not in VALID_STATIONS:
			continue
		_recipes[recipe_id] = raw_recipe.duplicate(true)
	recipes_loaded.emit(_recipes.size())
	return not _recipes.is_empty()


func set_station(station: String) -> void:
	active_station = station if station in VALID_STATIONS else "hand"


func recipe_count() -> int:
	return _recipes.size()


func get_recipe(recipe_id: String) -> Dictionary:
	return _recipes.get(recipe_id, {}).duplicate(true)


func get_recipes(station_filter: String = "") -> Array:
	var result: Array = []
	for recipe in _recipes.values():
		if station_filter.is_empty() or str(recipe.get("station", "hand")) == station_filter:
			result.append(recipe.duplicate(true))
	return result


func get_available_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes.values():
		if _station_allowed(str(recipe.get("station", "hand"))) and can_craft(str(recipe.get("id", ""))):
			result.append(recipe.duplicate(true))
	return result


func can_craft(recipe_id: String, times: int = 1) -> bool:
	if inventory == null or not _recipes.has(recipe_id) or times <= 0:
		return false
	var recipe: Dictionary = _recipes[recipe_id]
	if not _station_allowed(str(recipe.get("station", "hand"))):
		return false
	var required := _requirements_for(recipe, times)
	return inventory.has_items(required)


func craft(recipe_id: String, times: int = 1) -> bool:
	if inventory == null:
		craft_failed.emit(recipe_id, "inventory_missing")
		return false
	if not _recipes.has(recipe_id):
		craft_failed.emit(recipe_id, "unknown_recipe")
		return false
	if times <= 0 or not _station_allowed(str(_recipes[recipe_id].get("station", "hand"))):
		craft_failed.emit(recipe_id, "requirements_or_station")
		return false
	var recipe: Dictionary = _recipes[recipe_id]
	var required := _requirements_for(recipe, times)
	var output: Dictionary = recipe.get("output", {})
	var output_id := str(output.get("id", ""))
	var output_count := int(output.get("count", 1)) * times
	if output_id.is_empty() or output_count <= 0:
		craft_failed.emit(recipe_id, "invalid_output")
		return false
	if inventory.has_method("transact_items"):
		var transaction: Dictionary = inventory.call(
			"transact_items",
			required,
			[{"item_id": output_id, "count": output_count}]
		)
		if not bool(transaction.get("success", false)):
			var reason := str(transaction.get("reason", "transaction_failed"))
			craft_failed.emit(
				recipe_id,
				"inventory_full" if reason == "inventory_full" else "requirements_or_station"
			)
			return false
	else:
		if not inventory.has_items(required):
			craft_failed.emit(recipe_id, "requirements_or_station")
			return false
		for item_id in required:
			inventory.remove_item(str(item_id), int(required[item_id]))
		var leftover: int = inventory.add_item(output_id, output_count)
		if leftover > 0:
			inventory.remove_item(output_id, output_count - leftover)
			for item_id in required:
				inventory.add_item(str(item_id), int(required[item_id]))
			craft_failed.emit(recipe_id, "inventory_full")
			return false
	var crafted_output := {"item_id": output_id, "count": output_count}
	craft_succeeded.emit(recipe_id, crafted_output)
	return true


func _requirements_for(recipe: Dictionary, times: int) -> Dictionary:
	var required: Dictionary = {}
	var raw_ingredients: Variant = recipe.get("ingredients", {})
	if raw_ingredients is not Dictionary:
		return required
	for raw_item_id: Variant in raw_ingredients.keys():
		required[str(raw_item_id)] = int(raw_ingredients[raw_item_id]) * maxi(1, times)
	return required


func _station_allowed(required_station: String) -> bool:
	if required_station == "hand":
		return true
	return required_station == active_station
