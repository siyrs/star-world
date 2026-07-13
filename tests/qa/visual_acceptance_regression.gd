extends SceneTree

const VisualPolicy = preload("res://src/diagnostics/visual_acceptance_policy.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sky_only_frame_is_rejected()
	_test_world_geometry_frame_is_accepted()
	if failures.is_empty():
		print("QA VISUAL ACCEPTANCE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA VISUAL ACCEPTANCE FAILURE: %s" % failure)
		print(
			"QA VISUAL ACCEPTANCE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_sky_only_frame_is_rejected() -> void:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(Color("#6097BD"))
	var decorative_colors := [
		Color("#0D1724"),
		Color("#62C7E9"),
		Color("#FFD36C"),
		Color("#F06F78"),
		Color("#E9B755"),
		Color("#75D28B"),
		Color("#F27B82"),
		Color("#315673"),
		Color("#183044"),
		Color("#24364C"),
		Color("#91AABD"),
		Color("#FFFFFF"),
		Color("#7892A7"),
		Color("#4F7899"),
	]
	for index in decorative_colors.size():
		var x := (index % 7) * 20
		var y := 4 if index < 7 else 160
		image.fill_rect(Rect2i(x, y, 12, 12), decorative_colors[index])
	image.fill_rect(Rect2i(159, 88, 2, 5), Color.WHITE)
	image.fill_rect(Rect2i(157, 90, 6, 2), Color.WHITE)
	var result: Dictionary = VisualPolicy.evaluate(image)
	_check(
		not bool(result.get("ok", true)),
		"colorful HUD decorations cannot make a sky-only world pass",
	)
	_check(
		str(result.get("reason", "")) == "world_region_flat_or_sky_only",
		"sky-only failure reports the world-region reason",
	)
	_check(
		float(result.get("world_dominant_ratio", 0.0)) > 0.94,
		"sky-only center is recognized as one dominant color",
	)


func _test_world_geometry_frame_is_accepted() -> void:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(Color("#6097BD"))
	var terrain_colors := [
		Color("#587A42"),
		Color("#6B8B4A"),
		Color("#7B623F"),
		Color("#866D46"),
		Color("#6A6E72"),
		Color("#777C81"),
		Color("#4E7041"),
		Color("#8E754E"),
	]
	for y in range(62, 150, 8):
		for x in range(30, 290, 10):
			var color_index := (int(x / 10) + int(y / 8)) % terrain_colors.size()
			image.fill_rect(Rect2i(x, y, 10, 8), terrain_colors[color_index])
	for index in 14:
		image.fill_rect(
			Rect2i(index * 18, 4, 10, 10),
			Color.from_hsv(float(index) / 14.0, 0.65, 0.85)
		)
	var result: Dictionary = VisualPolicy.evaluate(image)
	_check(bool(result.get("ok", false)), "visible terrain in the gameplay region passes acceptance")
	_check(
		int(result.get("world_unique_color_buckets", 0)) >= 6,
		"world-region evidence contains multiple terrain colors",
	)
	_check(
		float(result.get("world_dominant_ratio", 1.0)) < 0.94,
		"terrain prevents one sky color from dominating the gameplay region",
	)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
