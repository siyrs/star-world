class_name StonecutterRecipeRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/stonecutter_recipes.json"
const FALLBACK_DURATION_SECONDS := 3.0

var default_duration_seconds := FALLBACK_DURATION_SECONDS
var _recipes: Dictionary = {}
var _recipes_by_input: Dictionary = {}
var _validation_errors: Array[String] = []


func _init(path: String = DEFAULT_DATA_PATH) -> void:
	load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_recipes.clear()
	_recipes_by_input.clear()
	_validation_errors.clear()
	default_duration_seconds = FALLBACK_DURATION_SECONDS
	if not FileAccess.file_exists(path):
		_record_error("Stonecutter recipe registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open stonecutter recipe registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Invalid stonecutter recipe registry root: %s" % path)
		return false
	var root_data: Dictionary = parsed
	var raw_recipes: Variant = root_data.get("recipes", [])
	if raw_recipes is not Array:
		_record_error("Stonecutter recipes must be an array: %s" % path)
		return false
	default_duration_seconds = maxf(
		0.1, float(root_data.get("default_duration_seconds", FALLBACK_DURATION_SECONDS))
	)
	for raw_recipe: Variant in raw_recipes:
		if raw_recipe is not Dictionary:
			_record_error("Stonecutter recipe entry must be an object")
			continue
		var recipe: Dictionary = _normalize_recipe(raw_recipe)
		var recipe_id := str(recipe.get("id", ""))
		var input_id := str(recipe.get("input", {}).get("id", ""))
		if recipe_id.is_empty() or input_id.is_empty():
			continue
		if _recipes.has(recipe_id):
			_record_error("Duplicate stonecutter recipe id: %s" % recipe_id)
			continue
		if _recipes_by_input.has(input_id):
			_record_error("Stonecutter input has multiple implicit recipes: %s" % input_id)
			continue
		_recipes[recipe_id] = recipe
		_recipes_by_input[input_id] = recipe_id
	return not _recipes.is_empty() and _validation_errors.is_empty()


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
	for raw_recipe: Variant in _recipes.values():
		if raw_recipe is Dictionary:
			result.append((raw_recipe as Dictionary).duplicate(true))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_recipe(raw_recipe: Dictionary) -> Dictionary:
	var recipe_id := str(raw_recipe.get("id", "")).strip_edges()
	var input_data: Dictionary = raw_recipe.get("input", {})
	var output_data: Dictionary = raw_recipe.get("output", {})
	var input_id := str(input_data.get("id", "")).strip_edges()
	var output_id := str(output_data.get("id", "")).strip_edges()
	if recipe_id.is_empty() or input_id.is_empty() or output_id.is_empty():
		_record_error("Stonecutter recipe id, input and output must be non-empty")
		return {}
	return {
		"id": recipe_id,
		"name": str(raw_recipe.get("name", recipe_id)),
		"input": {
			"id": input_id,
			"count": maxi(1, int(input_data.get("count", 1))),
		},
		"output": {
			"id": output_id,
			"count": maxi(1, int(output_data.get("count", 1))),
		},
		"duration_seconds": maxf(
			0.1,
			float(raw_recipe.get("duration_seconds", default_duration_seconds))
		),
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
