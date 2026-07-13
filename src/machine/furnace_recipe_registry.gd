class_name FurnaceRecipeRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/furnace_recipes.json"
const FALLBACK_DURATION_SECONDS := 6.0

var default_duration_seconds := FALLBACK_DURATION_SECONDS
var _recipes: Dictionary = {}
var _recipes_by_input: Dictionary = {}


func _init(path: String = DEFAULT_DATA_PATH) -> void:
	load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_recipes.clear()
	_recipes_by_input.clear()
	default_duration_seconds = FALLBACK_DURATION_SECONDS
	if not FileAccess.file_exists(path):
		push_error("Furnace recipe registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("recipes", []) is not Array:
		push_error("Invalid furnace recipe registry: %s" % path)
		return false
	default_duration_seconds = maxf(
		0.1, float(parsed.get("default_duration_seconds", FALLBACK_DURATION_SECONDS))
	)
	for raw_recipe in parsed.get("recipes", []):
		if raw_recipe is not Dictionary:
			continue
		var recipe := _normalize_recipe(raw_recipe)
		var recipe_id := str(recipe.get("id", ""))
		var input_id := str(recipe.get("input", {}).get("id", ""))
		if recipe_id.is_empty() or input_id.is_empty():
			continue
		_recipes[recipe_id] = recipe
		_recipes_by_input[input_id] = recipe_id
	return not _recipes.is_empty()


func recipe_count() -> int:
	return _recipes.size()


func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)


func has_input(item_id: String) -> bool:
	return _recipes_by_input.has(item_id)


func get_recipe(recipe_id: String) -> Dictionary:
	return _recipes.get(recipe_id, {}).duplicate(true)


func get_recipe_for_input(item_id: String) -> Dictionary:
	var recipe_id := str(_recipes_by_input.get(item_id, ""))
	return get_recipe(recipe_id) if not recipe_id.is_empty() else {}


func get_all_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in _recipes.values():
		result.append(recipe.duplicate(true))
	return result


func _normalize_recipe(raw_recipe: Dictionary) -> Dictionary:
	var input: Dictionary = raw_recipe.get("input", {})
	var output: Dictionary = raw_recipe.get("output", {})
	var input_id := str(input.get("id", ""))
	var output_id := str(output.get("id", ""))
	if input_id.is_empty() or output_id.is_empty():
		return {}
	return {
		"id": str(raw_recipe.get("id", "")),
		"name": str(raw_recipe.get("name", raw_recipe.get("id", ""))),
		"input": {"id": input_id, "count": maxi(1, int(input.get("count", 1)))},
		"output": {"id": output_id, "count": maxi(1, int(output.get("count", 1)))},
		"duration_seconds": maxf(
			0.1, float(raw_recipe.get("duration_seconds", default_duration_seconds))
		),
	}
