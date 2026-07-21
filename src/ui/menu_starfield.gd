class_name MenuStarfield
extends Control

# Twinkling procedural starfield for the main menu background.

const STAR_COUNT := 90

var _stars: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260721
	for i in STAR_COUNT:
		_stars.append(
			{
				"x": rng.randf(),
				"y": rng.randf(),
				"radius": rng.randf_range(1.0, 2.4),
				"phase": rng.randf_range(0.0, TAU),
				"speed": rng.randf_range(0.5, 1.6),
				"tint": rng.randf_range(0.6, 1.0),
			}
		)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var area := get_rect()
	for star: Dictionary in _stars:
		var twinkle := 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * float(star["speed"]) + float(star["phase"])))
		var tint := float(star["tint"])
		var color := Color(0.62 * tint, 0.78 * tint, 0.95 * tint, twinkle)
		var center := Vector2(
			float(star["x"]) * area.size.x, float(star["y"]) * area.size.y
		)
		draw_circle(center, float(star["radius"]), color)
