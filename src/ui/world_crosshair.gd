class_name WorldCrosshair
extends Control

@export var arm_length := 7.0
@export var gap := 2.0
@export var line_width := 2.0
@export var outline_width := 4.0
@export var foreground := Color("#F7FBFFEE")
@export var outline := Color("#07111ACC")


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
	queue_redraw()


func get_aim_point() -> Vector2:
	# Camera3D projects its forward ray through the Viewport center. Expose that
	# coordinate directly; the symmetric 50% anchors keep the drawing on it.
	return get_viewport_rect().get_center()


func _draw() -> void:
	var center := size * 0.5
	var segments := [
		[Vector2(center.x - arm_length, center.y), Vector2(center.x - gap, center.y)],
		[Vector2(center.x + gap, center.y), Vector2(center.x + arm_length, center.y)],
		[Vector2(center.x, center.y - arm_length), Vector2(center.x, center.y - gap)],
		[Vector2(center.x, center.y + gap), Vector2(center.x, center.y + arm_length)],
	]
	for segment: Array in segments:
		draw_line(segment[0], segment[1], outline, outline_width, false)
	for segment: Array in segments:
		draw_line(segment[0], segment[1], foreground, line_width, false)
	draw_circle(center, 1.0, foreground)
