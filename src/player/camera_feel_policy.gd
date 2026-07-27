class_name CameraFeelPolicy
extends RefCounted

const DEFAULTS := {
	"bob_enabled_default": true,
	"bob_walk_amplitude": 0.035,
	"bob_sprint_amplitude": 0.052,
	"bob_lateral_factor": 0.55,
	"bob_step_frequency": 1.85,
	"base_fov": 75.0,
	"sprint_fov": 82.0,
	"fov_transition_speed": 7.0,
	"sprint_speed_threshold": 6.4,
	"land_dip_depth": 0.085,
	"land_min_impact_speed": 3.2,
	"land_sound_min_impact_speed": 4.6,
	"shake_decay_per_second": 6.5,
	"shake_max_roll_degrees": 1.6,
	"hurt_shake_strength": 0.9,
	"floor_poll_interval_seconds": 0.12,
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func normalize(raw: Dictionary = {}) -> Dictionary:
	var normalized := defaults()
	normalized["bob_enabled_default"] = _bool_or_default(
		raw.get("bob_enabled_default"), bool(DEFAULTS["bob_enabled_default"])
	)
	normalized["bob_walk_amplitude"] = _bounded_number(
		raw.get("bob_walk_amplitude"), float(DEFAULTS["bob_walk_amplitude"]), 0.0, 0.08
	)
	normalized["bob_sprint_amplitude"] = _bounded_number(
		raw.get("bob_sprint_amplitude"), float(DEFAULTS["bob_sprint_amplitude"]), 0.0, 0.10
	)
	normalized["bob_lateral_factor"] = _bounded_number(
		raw.get("bob_lateral_factor"), float(DEFAULTS["bob_lateral_factor"]), 0.0, 1.0
	)
	normalized["bob_step_frequency"] = _bounded_number(
		raw.get("bob_step_frequency"), float(DEFAULTS["bob_step_frequency"]), 0.2, 4.0
	)
	normalized["base_fov"] = _bounded_number(
		raw.get("base_fov"), float(DEFAULTS["base_fov"]), 55.0, 95.0
	)
	normalized["sprint_fov"] = _bounded_number(
		raw.get("sprint_fov"), float(DEFAULTS["sprint_fov"]), 55.0, 110.0
	)
	normalized["sprint_fov"] = maxf(
		float(normalized["base_fov"]), float(normalized["sprint_fov"])
	)
	normalized["fov_transition_speed"] = _bounded_number(
		raw.get("fov_transition_speed"), float(DEFAULTS["fov_transition_speed"]), 0.5, 20.0
	)
	normalized["sprint_speed_threshold"] = _bounded_number(
		raw.get("sprint_speed_threshold"), float(DEFAULTS["sprint_speed_threshold"]), 0.5, 20.0
	)
	normalized["land_dip_depth"] = _bounded_number(
		raw.get("land_dip_depth"), float(DEFAULTS["land_dip_depth"]), 0.0, 0.15
	)
	normalized["land_min_impact_speed"] = _bounded_number(
		raw.get("land_min_impact_speed"), float(DEFAULTS["land_min_impact_speed"]), 0.0, 20.0
	)
	normalized["land_sound_min_impact_speed"] = _bounded_number(
		raw.get("land_sound_min_impact_speed"),
		float(DEFAULTS["land_sound_min_impact_speed"]),
		0.0,
		30.0
	)
	normalized["land_sound_min_impact_speed"] = maxf(
		float(normalized["land_min_impact_speed"]),
		float(normalized["land_sound_min_impact_speed"])
	)
	normalized["shake_decay_per_second"] = _bounded_number(
		raw.get("shake_decay_per_second"), float(DEFAULTS["shake_decay_per_second"]), 0.5, 30.0
	)
	normalized["shake_max_roll_degrees"] = _bounded_number(
		raw.get("shake_max_roll_degrees"), float(DEFAULTS["shake_max_roll_degrees"]), 0.0, 4.0
	)
	normalized["hurt_shake_strength"] = _bounded_number(
		raw.get("hurt_shake_strength"), float(DEFAULTS["hurt_shake_strength"]), 0.0, 1.6
	)
	normalized["floor_poll_interval_seconds"] = _bounded_number(
		raw.get("floor_poll_interval_seconds"),
		float(DEFAULTS["floor_poll_interval_seconds"]),
		0.05,
		1.0
	)
	return normalized


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


static func _bool_or_default(value: Variant, default_value: bool) -> bool:
	return bool(value) if value is bool else default_value
