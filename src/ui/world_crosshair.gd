class_name WorldCrosshair
extends Control

@export var arm_length := 7.0
@export var gap := 2.0
@export var line_width := 2.0
@export var outline_width := 4.0
@export var foreground := Color("#F7FBFFEE")
@export var outline := Color("#07111ACC")

const STATE_NEUTRAL := &"neutral"
const STATE_ACTIONABLE := &"actionable"
const STATE_HOSTILE := &"hostile"
const COLOR_ACTIONABLE := Color("#8BE28FEE")
const COLOR_HOSTILE := Color("#FF7B6BEE")

var _target_state: StringName = STATE_NEUTRAL
var _display_arm := 7.0
var _display_color: Color


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -12.0
	offset_right = 12.0
	offset_top = -12.0
	offset_bottom = 12.0
	_display_color = foreground
	set_process(true)
	queue_redraw()


func get_aim_point() -> Vector2:
	# Camera3D projects its forward ray through the Viewport center. Expose that
	# coordinate directly; the symmetric 50% anchors keep the drawing on it.
	return get_viewport_rect().get_center()


func set_target_state(state: StringName) -> void:
	if state == _target_state:
		return
	_target_state = state


func _process(delta: float) -> void:
	var goal_arm := arm_length
	var goal_color := foreground
	match _target_state:
		STATE_ACTIONABLE:
			goal_arm = arm_length + 2.0
			goal_color = COLOR_ACTIONABLE
		STATE_HOSTILE:
			goal_arm = arm_length + 1.0
			goal_color = COLOR_HOSTILE
	var weight := clampf(delta * 12.0, 0.0, 1.0)
	var new_arm := lerpf(_display_arm, goal_arm, weight)
	var new_color: Color = _display_color.lerp(goal_color, weight)
	# Only redraw when something visibly changed; a per-frame queue_redraw is
	# wasted canvas work on every machine, headless or not.
	if absf(new_arm - _display_arm) > 0.001 or not new_color.is_equal_approx(_display_color):
		_display_arm = new_arm
		_display_color = new_color
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var arm := _display_arm
	var segments := [
		[Vector2(center.x - arm, center.y), Vector2(center.x - gap, center.y)],
		[Vector2(center.x + gap, center.y), Vector2(center.x + arm, center.y)],
		[Vector2(center.x, center.y - arm), Vector2(center.x, center.y - gap)],
		[Vector2(center.x, center.y + gap), Vector2(center.x, center.y + arm)],
	]
	for segment: Array in segments:
		draw_line(segment[0], segment[1], outline, outline_width, false)
	for segment: Array in segments:
		draw_line(segment[0], segment[1], _display_color, line_width, false)
	draw_circle(center, 1.0, _display_color)
