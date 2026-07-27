class_name GameSettingsPolicy
extends RefCounted

const DEFAULTS := {
	"mouse_sensitivity": 0.18,
	"render_distance": 3,
	"master_volume": 0.8,
	"fullscreen": false,
	"cycle_minutes": 10,
	"show_tutorial": true,
	"show_interaction_prompts": true,
	"autosave_minutes": 5,
	"camera_bob": true,
	"survival_difficulty": "relaxed",
}
const AUTOSAVE_MINUTES := [0, 2, 5, 10, 15]
const SURVIVAL_DIFFICULTIES: Array[String] = ["relaxed", "balanced", "challenging"]
const SURVIVAL_DIFFICULTY_LABELS := {
	"relaxed": "轻松建造",
	"balanced": "平衡生存",
	"challenging": "挑战生存",
}
const MIN_MOUSE_SENSITIVITY := 0.05
const MAX_MOUSE_SENSITIVITY := 0.60
const MIN_RENDER_DISTANCE := 1
const MAX_RENDER_DISTANCE := 5
const MIN_CYCLE_MINUTES := 2
const MAX_CYCLE_MINUTES := 30


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func allowed_autosave_minutes() -> Array[int]:
	var values: Array[int] = []
	for raw_value: Variant in AUTOSAVE_MINUTES:
		values.append(int(raw_value))
	return values


static func allowed_survival_difficulties() -> Array[String]:
	return SURVIVAL_DIFFICULTIES.duplicate()


static func survival_difficulty_label(profile_id: String) -> String:
	var normalized := normalize_survival_difficulty(profile_id)
	return str(SURVIVAL_DIFFICULTY_LABELS[normalized])


static func normalize(raw_settings: Dictionary = {}) -> Dictionary:
	var normalized := defaults()
	normalized["mouse_sensitivity"] = clampf(
		_number_or_default(
			raw_settings.get("mouse_sensitivity"),
			float(DEFAULTS["mouse_sensitivity"])
		),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	normalized["render_distance"] = clampi(
		int(_number_or_default(
			raw_settings.get("render_distance"),
			float(DEFAULTS["render_distance"])
		)),
		MIN_RENDER_DISTANCE,
		MAX_RENDER_DISTANCE
	)
	normalized["master_volume"] = clampf(
		_number_or_default(
			raw_settings.get("master_volume"),
			float(DEFAULTS["master_volume"])
		),
		0.0,
		1.0
	)
	normalized["fullscreen"] = _bool_or_default(
		raw_settings.get("fullscreen"), bool(DEFAULTS["fullscreen"])
	)
	normalized["cycle_minutes"] = clampi(
		int(_number_or_default(
			raw_settings.get("cycle_minutes"),
			float(DEFAULTS["cycle_minutes"])
		)),
		MIN_CYCLE_MINUTES,
		MAX_CYCLE_MINUTES
	)
	normalized["show_tutorial"] = _bool_or_default(
		raw_settings.get("show_tutorial"), bool(DEFAULTS["show_tutorial"])
	)
	normalized["show_interaction_prompts"] = _bool_or_default(
		raw_settings.get("show_interaction_prompts"),
		bool(DEFAULTS["show_interaction_prompts"])
	)
	normalized["autosave_minutes"] = normalize_autosave_minutes(
		raw_settings.get("autosave_minutes")
	)
	normalized["camera_bob"] = _bool_or_default(
		raw_settings.get("camera_bob"), bool(DEFAULTS["camera_bob"])
	)
	normalized["survival_difficulty"] = normalize_survival_difficulty(
		raw_settings.get("survival_difficulty")
	)
	return normalized


static func merge(current: Dictionary, incoming: Dictionary) -> Dictionary:
	var merged := current.duplicate(true)
	merged.merge(incoming, true)
	return normalize(merged)


static func normalize_autosave_minutes(value: Variant) -> int:
	if value is not int and value is not float:
		return int(DEFAULTS["autosave_minutes"])
	var numeric_value := float(value)
	if not is_finite(numeric_value):
		return int(DEFAULTS["autosave_minutes"])
	var requested := int(round(numeric_value))
	var selected := int(DEFAULTS["autosave_minutes"])
	var best_distance := absi(requested - selected)
	for raw_candidate: Variant in AUTOSAVE_MINUTES:
		var candidate := int(raw_candidate)
		var distance := absi(requested - candidate)
		if distance < best_distance or (distance == best_distance and candidate < selected):
			selected = candidate
			best_distance = distance
	return selected


static func normalize_survival_difficulty(value: Variant) -> String:
	var requested := str(value).strip_edges().to_lower()
	return (
		requested
		if requested in SURVIVAL_DIFFICULTIES
		else str(DEFAULTS["survival_difficulty"])
	)


static func _number_or_default(value: Variant, default_value: float) -> float:
	if value is int or value is float:
		var numeric_value := float(value)
		if is_finite(numeric_value):
			return numeric_value
	return default_value


static func _bool_or_default(value: Variant, default_value: bool) -> bool:
	if value is bool:
		return bool(value)
	return default_value
