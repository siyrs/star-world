class_name CraftingService
extends Node

signal recipes_loaded(count: int)
signal craft_succeeded(recipe_id: String, output: Dictionary)
signal craft_failed(recipe_id: String, reason: String)

const DEFAULT_DATA_PATH := "res://data/recipes.json"

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
		if raw_recipe is Dictionary:
			var recipe_id := str(raw_recipe.get("id", ""))
			if not recipe_id.is_empty():
				_recipes[recipe_id] = raw_recipe.duplicate(true)
	recipes_loaded.emit(_recipes.size())
	return not _recipes.is_empty()


func set_station(station: String) -> void:
	active_station = station if station in ["hand", "workbench", "furnace"] else "hand"


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
	var required: Dictionary = {}
	for item_id in recipe.get("ingredients", {}):
		required[item_id] = int(recipe["ingredients"][item_id]) * times
	return inventory.has_items(required)


func craft(recipe_id: String, times: int = 1) -> bool:
	if inventory == null:
		craft_failed.emit(recipe_id, "inventory_missing")
		return false
	if not _recipes.has(recipe_id):
		craft_failed.emit(recipe_id, "unknown_recipe")
		return false
	if not can_craft(recipe_id, times):
		craft_failed.emit(recipe_id, "requirements_or_station")
		return false
	var recipe: Dictionary = _recipes[recipe_id]
	var ingredients: Dictionary = recipe.get("ingredients", {})
	for item_id in ingredients:
		inventory.remove_item(str(item_id), int(ingredients[item_id]) * times)
	var output: Dictionary = recipe.get("output", {})
	var output_id := str(output.get("id", ""))
	var output_count := int(output.get("count", 1)) * times
	var leftover: int = inventory.add_item(output_id, output_count)
	if leftover > 0:
		inventory.remove_item(output_id, output_count - leftover)
		for item_id in ingredients:
			inventory.add_item(str(item_id), int(ingredients[item_id]) * times)
		craft_failed.emit(recipe_id, "inventory_full")
		return false
	var crafted_output := {"item_id": output_id, "count": output_count}
	craft_succeeded.emit(recipe_id, crafted_output)
	return true


func _station_allowed(required_station: String) -> bool:
	if required_station == "hand":
		return true
	return required_station == active_station
