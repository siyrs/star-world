class_name WorldCrosshair
extends Control

@export var arm_length := 8.0
@export var gap := 3.0
@export var line_width := 2.0
@export var outline_width := 4.0
@export var foreground := Color("#F7FBFFEE")
@export var outline := Color("#101010CC")

const STATE_NEUTRAL := &"neutral"
const STATE_ACTIONABLE := &"actionable"
const STATE_HOSTILE := &"hostile"
const COLOR_ACTIONABLE := Color("#9BE37BEE")
const COLOR_HOSTILE := Color("#FF7B6BEE")

var _target_state: StringName = STATE_NEUTRAL
var _display_arm := 8.0
var _display_color: Color


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -14.0
	offset_right = 14.0
	offset_top = -14.0
	offset_bottom = 14.0
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
	# Pixel plus-sign: sharp 2px white core over a 4px dark silhouette, drawn
	# without anti-aliasing so it reads as part of the voxel world.
	var center := (size * 0.5).round()
	var arm := roundf(_display_arm)
	var rects := [
		Rect2(center.x - arm, center.y - 1.0, arm - gap, 2.0),
		Rect2(center.x + gap, center.y - 1.0, arm - gap, 2.0),
		Rect2(center.x - 1.0, center.y - arm, 2.0, arm - gap),
		Rect2(center.x - 1.0, center.y + gap, 2.0, arm - gap),
	]
	for rect: Rect2 in rects:
		draw_rect(rect.grow(1.0), outline, true)
	for rect: Rect2 in rects:
		draw_rect(rect, _display_color, true)
	draw_rect(Rect2(center.x - 1.0, center.y - 1.0, 2.0, 2.0), outline, true)
