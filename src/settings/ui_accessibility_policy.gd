class_name UiAccessibilityPolicy
extends RefCounted

const MODE_MOUSE: StringName = &"mouse"
const MODE_KEYBOARD: StringName = &"keyboard"
const MODE_CONTROLLER: StringName = &"controller"
const DEFAULT_SCALE := 1.0
const ALLOWED_SCALES: Array[float] = [0.8, 1.0, 1.25, 1.5]
const CONTROLLER_AXIS_THRESHOLD := 0.55
const MOUSE_MOTION_THRESHOLD_SQUARED := 4.0


static func allowed_scales() -> Array[float]:
	return ALLOWED_SCALES.duplicate()


static func normalize_scale(value: Variant) -> float:
	if value is not int and value is not float:
		return DEFAULT_SCALE
	var requested := float(value)
	if not is_finite(requested):
		return DEFAULT_SCALE
	var selected := DEFAULT_SCALE
	var best_distance := absf(requested - selected)
	for candidate: float in ALLOWED_SCALES:
		var distance := absf(requested - candidate)
		if distance < best_distance or (
			is_equal_approx(distance, best_distance) and candidate < selected
		):
			selected = candidate
			best_distance = distance
	return selected


static func scale_label(value: Variant) -> String:
	return "%d%%" % roundi(normalize_scale(value) * 100.0)


static func normalize_mode(value: Variant) -> StringName:
	var requested := StringName(str(value).strip_edges().to_lower())
	return (
		requested
		if requested in [MODE_MOUSE, MODE_KEYBOARD, MODE_CONTROLLER]
		else MODE_KEYBOARD
	)


static func classify_event(
	event: InputEvent,
	current_mode: StringName = MODE_KEYBOARD
) -> StringName:
	if event == null:
		return normalize_mode(current_mode)
	if event is InputEventJoypadButton:
		return MODE_CONTROLLER if (event as InputEventJoypadButton).pressed else normalize_mode(current_mode)
	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		return (
			MODE_CONTROLLER
			if absf(joy_motion.axis_value) >= CONTROLLER_AXIS_THRESHOLD
			else normalize_mode(current_mode)
		)
	if event is InputEventMouseButton:
		return MODE_MOUSE if (event as InputEventMouseButton).pressed else normalize_mode(current_mode)
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		return (
			MODE_MOUSE
			if mouse_motion.relative.length_squared() >= MOUSE_MOTION_THRESHOLD_SQUARED
			else normalize_mode(current_mode)
		)
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return MODE_KEYBOARD if key_event.pressed and not key_event.echo else normalize_mode(current_mode)
	return normalize_mode(current_mode)
