class_name MenuStarfield
extends Control

const STAR_COUNT := 128
const CONSTELLATION_COUNT := 7

var _stars: Array[Dictionary] = []
var _constellations: Array[PackedInt32Array] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260728
	for index in STAR_COUNT:
		_stars.append({
			"x": rng.randf(),
			"y": rng.randf_range(0.02, 0.94),
			"radius": rng.randf_range(0.7, 2.15),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.35, 1.45),
			"temperature": rng.randf(),
			"depth": rng.randf_range(0.25, 1.0),
		})
	for constellation_index in CONSTELLATION_COUNT:
		var chain := PackedInt32Array()
		var start := constellation_index * 13 + 5
		for point_index in 4:
			chain.append((start + point_index * 3) % STAR_COUNT)
		_constellations.append(chain)
	set_process(true)


func _process(delta: float) -> void:
	_time += minf(maxf(delta, 0.0), 0.1)
	queue_redraw()


func _draw() -> void:
	var area := get_rect()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	_draw_nebula(area)
	_draw_orbits(area)
	_draw_constellations(area)
	_draw_stars(area)
	_draw_planet(area)


func _draw_nebula(area: Rect2) -> void:
	var left_center := Vector2(area.size.x * 0.24, area.size.y * 0.46)
	var right_center := Vector2(area.size.x * 0.82, area.size.y * 0.18)
	for ring in range(9, 0, -1):
		var ratio := float(ring) / 9.0
		draw_circle(
			left_center,
			area.size.y * (0.14 + ratio * 0.14),
			Color(0.08, 0.46, 0.62, 0.007 + (1.0 - ratio) * 0.006)
		)
		draw_circle(
			right_center,
			area.size.y * (0.08 + ratio * 0.10),
			Color(0.36, 0.24, 0.48, 0.006 + (1.0 - ratio) * 0.005)
		)


func _draw_orbits(area: Rect2) -> void:
	var center := Vector2(area.size.x * 0.80, area.size.y * 0.80)
	var base_radius := minf(area.size.x, area.size.y) * 0.32
	for orbit_index in 3:
		var radius := base_radius + orbit_index * 38.0
		var alpha := 0.12 - orbit_index * 0.025
		draw_arc(
			center,
			radius,
			PI * 0.94,
			TAU * 1.04,
			96,
			Color(0.33, 0.72, 0.88, alpha),
			1.0,
			true
		)
	var satellite_angle := _time * 0.07 + PI * 1.27
	var satellite_position := center + Vector2(cos(satellite_angle), sin(satellite_angle)) * (base_radius + 38.0)
	draw_circle(satellite_position, 3.0, Color("#F5C760CC"))
	draw_circle(satellite_position, 7.0, Color("#F5C76022"))


func _draw_constellations(area: Rect2) -> void:
	for chain: PackedInt32Array in _constellations:
		for index in range(chain.size() - 1):
			var first := _star_position(_stars[chain[index]], area.size)
			var second := _star_position(_stars[chain[index + 1]], area.size)
			if first.distance_to(second) > area.size.x * 0.18:
				continue
			draw_line(first, second, Color(0.36, 0.72, 0.86, 0.11), 1.0, true)


func _draw_stars(area: Rect2) -> void:
	for star: Dictionary in _stars:
		var twinkle := 0.48 + 0.52 * (
			0.5 + 0.5 * sin(_time * float(star["speed"]) + float(star["phase"]))
		)
		var depth := float(star["depth"])
		var temperature := float(star["temperature"])
		var warm := Color("#F7DFA7")
		var cool := Color("#A7E7FF")
		var color := cool.lerp(warm, temperature)
		color.a = (0.28 + depth * 0.60) * twinkle
		var center := _star_position(star, area.size)
		var radius := float(star["radius"]) * (0.72 + depth * 0.38)
		if radius > 1.6:
			draw_circle(center, radius * 3.0, Color(color.r, color.g, color.b, color.a * 0.08))
		draw_circle(center, radius, color)


func _draw_planet(area: Rect2) -> void:
	var radius := clampf(area.size.y * 0.22, 96.0, 175.0)
	var center := Vector2(area.size.x - radius * 0.52, area.size.y + radius * 0.34)
	for ring in range(18, 0, -1):
		var ratio := float(ring) / 18.0
		var fill := Color("#102D42").lerp(Color("#27637A"), 1.0 - ratio)
		fill.a = 0.62 + (1.0 - ratio) * 0.20
		draw_circle(center + Vector2(-radius * 0.06 * ratio, -radius * 0.04 * ratio), radius * ratio, fill)
	draw_arc(center, radius * 1.01, PI * 1.03, PI * 1.72, 72, Color("#77DFFF99"), 2.0, true)
	var ring_color := Color(0.45, 0.82, 0.95, 0.16)
	draw_arc(center + Vector2(-16, 4), radius * 1.34, PI * 1.12, PI * 1.88, 96, ring_color, 3.0, true)


func _star_position(star: Dictionary, viewport_size: Vector2) -> Vector2:
	var depth := float(star["depth"])
	var drift := sin(_time * 0.025 + float(star["phase"])) * (1.0 - depth) * 3.0
	return Vector2(
		float(star["x"]) * viewport_size.x + drift,
		float(star["y"]) * viewport_size.y
	)
