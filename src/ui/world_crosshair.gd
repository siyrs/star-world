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
	custom_minimum_size = Vector2(24.0, 24.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	position = Vector2(-12.0, -12.0)
	size = Vector2(24.0, 24.0)
	queue_redraw()


func get_aim_point() -> Vector2:
	return global_position + size * 0.5


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
