class_name SurvivalTuningPolicy
extends RefCounted

const SCHEMA_VERSION := 2
const DEFAULT_PROFILE := "relaxed"
const PROFILE_IDS: Array[String] = ["relaxed", "balanced", "challenging"]
const PROFILE_LABELS := {
	"relaxed": "轻松建造",
	"balanced": "平衡生存",
	"challenging": "挑战生存",
}
const FALLBACK_PROFILES := {
	"relaxed": {
		"passive_hunger_interval": 90.0,
		"starvation_damage_interval": 8.0,
		"natural_regeneration_interval": 4.0,
		"regeneration_hunger_threshold": 18.0,
	},
	"balanced": {
		"passive_hunger_interval": 70.0,
		"starvation_damage_interval": 4.0,
		"natural_regeneration_interval": 3.5,
		"regeneration_hunger_threshold": 17.0,
	},
	"challenging": {
		"passive_hunger_interval": 50.0,
		"starvation_damage_interval": 3.0,
		"natural_regeneration_interval": 5.0,
		"regeneration_hunger_threshold": 18.0,
	},
}


static func allowed_profile_ids() -> Array[String]:
	return PROFILE_IDS.duplicate()


static func profile_label(profile_id: String) -> String:
	return str(PROFILE_LABELS.get(normalize_profile_id(profile_id), PROFILE_LABELS[DEFAULT_PROFILE]))


static func normalize_profile_id(value: Variant) -> String:
	var profile_id := str(value).strip_edges().to_lower()
	return profile_id if profile_id in PROFILE_IDS else DEFAULT_PROFILE


static func fallback_catalog() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"default_profile": DEFAULT_PROFILE,
		"profiles": FALLBACK_PROFILES.duplicate(true),
	}


static func normalize_catalog(raw: Dictionary = {}) -> Dictionary:
	var normalized := fallback_catalog()
	normalized["default_profile"] = normalize_profile_id(raw.get("default_profile", DEFAULT_PROFILE))
	var raw_profiles: Dictionary = raw.get("profiles", {}) if raw.get("profiles", {}) is Dictionary else {}
	var profiles: Dictionary = {}
	for profile_id: String in PROFILE_IDS:
		var candidate: Dictionary = (
			raw_profiles.get(profile_id, {})
			if raw_profiles.get(profile_id, {}) is Dictionary
			else {}
		)
		profiles[profile_id] = normalize_profile(candidate, FALLBACK_PROFILES[profile_id])
	normalized["profiles"] = profiles
	return normalized


static func normalize_profile(raw: Dictionary, fallback: Dictionary = {}) -> Dictionary:
	var base: Dictionary = fallback.duplicate(true)
	if base.is_empty():
		base = FALLBACK_PROFILES[DEFAULT_PROFILE].duplicate(true)
	return {
		"passive_hunger_interval": _bounded_number(
			raw.get("passive_hunger_interval"),
			float(base["passive_hunger_interval"]),
			10.0,
			300.0
		),
		"starvation_damage_interval": _bounded_number(
			raw.get("starvation_damage_interval"),
			float(base["starvation_damage_interval"]),
			1.0,
			30.0
		),
		"natural_regeneration_interval": _bounded_number(
			raw.get("natural_regeneration_interval"),
			float(base["natural_regeneration_interval"]),
			0.5,
			30.0
		),
		"regeneration_hunger_threshold": _bounded_number(
			raw.get("regeneration_hunger_threshold"),
			float(base["regeneration_hunger_threshold"]),
			1.0,
			20.0
		),
	}


static func profile_from_catalog(catalog: Dictionary, profile_id: String) -> Dictionary:
	var normalized := normalize_catalog(catalog)
	var selected := normalize_profile_id(profile_id)
	return (normalized["profiles"] as Dictionary).get(selected, {}).duplicate(true)


static func _bounded_number(
	value: Variant,
	default_value: float,
	minimum: float,
	maximum: float
) -> float:
	if value is int or value is float:
		var numeric := float(value)
		if is_finite(numeric):
			return clampf(numeric, minimum, maximum)
	return default_value
