class_name StreamingBudgetAdapter
extends RefCounted

const REQUIRED_PROPERTIES: Array[StringName] = [
	&"chunk_build_budget_ms",
	&"chunk_build_cells_per_step",
	&"max_chunk_build_steps_per_frame",
	&"chunks_per_frame",
]


func supports(target: Object) -> bool:
	if target == null:
		return false
	var available: Dictionary = {}
	for property in target.get_property_list():
		available[StringName(property.get("name", ""))] = true
	for property_name in REQUIRED_PROPERTIES:
		if not available.has(property_name):
			return false
	return true


func read_profile(target: Object) -> Dictionary:
	if not supports(target):
		return {}
	return {
		"budget_ms": clampf(float(target.get("chunk_build_budget_ms")), 0.5, 12.0),
		"cells_per_step": clampi(int(target.get("chunk_build_cells_per_step")), 256, 8192),
		"max_steps_per_frame": clampi(
			int(target.get("max_chunk_build_steps_per_frame")), 1, 8
		),
		"chunks_per_frame": clampi(int(target.get("chunks_per_frame")), 1, 4),
	}


func apply_profile(target: Object, profile: Dictionary) -> bool:
	if not supports(target) or profile.is_empty():
		return false
	target.set(
		"chunk_build_budget_ms",
		clampf(float(profile.get("budget_ms", target.get("chunk_build_budget_ms"))), 0.5, 12.0)
	)
	target.set(
		"chunk_build_cells_per_step",
		clampi(int(profile.get("cells_per_step", target.get("chunk_build_cells_per_step"))), 256, 8192)
	)
	target.set(
		"max_chunk_build_steps_per_frame",
		clampi(
			int(
				profile.get(
					"max_steps_per_frame", target.get("max_chunk_build_steps_per_frame")
				)
			),
			1,
			8
		)
	)
	target.set(
		"chunks_per_frame",
		clampi(int(profile.get("chunks_per_frame", target.get("chunks_per_frame"))), 1, 4)
	)
	return true
