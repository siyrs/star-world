class_name UiAccessibilityPolicy
extends RefCounted

const MODE_MOUSE: StringName = &"mouse"
const MODE_KEYBOARD: StringName = &"keyboard"
const MODE_CONTROLLER: StringName = &"controller"
const COMMAND_NONE: StringName = &""
const COMMAND_ACCEPT: StringName = &"accept"
const COMMAND_CANCEL: StringName = &"cancel"
const DEFAULT_SCALE := 1.0
const ALLOWED_SCALES: Array[float] = [0.8, 1.0, 1.25, 1.5]
const CONTROLLER_AXIS_THRESHOLD := 0.55
const MOUSE_MOTION_THRESHOLD_SQUARED := 4.0
const CONTROLLER_MOUSE_MOTION_GUARD_MSEC := 350
const UI_TRANSITION_MOUSE_MOTION_GUARD_MSEC := 750


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


static func is_intentional_controller_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= CONTROLLER_AXIS_THRESHOLD
	return false


static func is_intentional_mouse_motion(event: InputEvent) -> bool:
	return (
		event is InputEventMouseMotion
		and (event as InputEventMouseMotion).relative.length_squared()
		>= MOUSE_MOTION_THRESHOLD_SQUARED
	)


static func should_ignore_mouse_motion_after_controller(
	event: InputEvent,
	current_mode: StringName,
	now_msec: int,
	last_controller_input_msec: int
) -> bool:
	if normalize_mode(current_mode) != MODE_CONTROLLER:
		return false
	if not is_intentional_mouse_motion(event) or last_controller_input_msec < 0:
		return false
	var elapsed_msec := maxi(0, now_msec - last_controller_input_msec)
	return elapsed_msec < CONTROLLER_MOUSE_MOTION_GUARD_MSEC


static func classify_event(
	event: InputEvent,
	current_mode: StringName = MODE_KEYBOARD
) -> StringName:
	if event == null:
		return normalize_mode(current_mode)
	if is_intentional_controller_event(event):
		return MODE_CONTROLLER
	if event is InputEventMouseButton:
		return MODE_MOUSE if (event as InputEventMouseButton).pressed else normalize_mode(current_mode)
	if is_intentional_mouse_motion(event):
		return MODE_MOUSE
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return MODE_KEYBOARD if key_event.pressed and not key_event.echo else normalize_mode(current_mode)
	return normalize_mode(current_mode)


static func controller_command(event: InputEvent) -> StringName:
	if event is not InputEventJoypadButton:
		return COMMAND_NONE
	var button_event := event as InputEventJoypadButton
	if not button_event.pressed:
		return COMMAND_NONE
	match button_event.button_index:
		JOY_BUTTON_A:
			return COMMAND_ACCEPT
		JOY_BUTTON_B:
			return COMMAND_CANCEL
	return COMMAND_NONE
