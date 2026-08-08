extends SceneTree

const WeatherScript = preload("res://src/weather/weather_service.gd")
const BadgeScript = preload("res://src/weather/weather_status_badge.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")

const OUTPUT_PATH := "user://weather-climate-desktop.png"
const CLEANUP_FRAMES := 6

var checks := 0
var failures: Array[String] = []
var _capture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	var host := Node3D.new()
	root.add_child(host)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#D8B57A")
	world_environment.environment = environment
	host.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	host.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.2, 13.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, -5.0), Vector3.UP)
	camera.current = true
	host.add_child(camera)
	_build_scene(host)
	var survival = SurvivalScript.new()
	var day_night = DayNightScript.new()
	var weather = WeatherScript.new()
	for node in [survival, day_night, weather]:
		host.add_child(node)
	var badge = BadgeScript.new()
	root.add_child(badge)
	await process_frame
	await process_frame
	day_night.running = false
	day_night.set_map_profile("desert_ruins")
	day_night.set_time(15.0)
	day_night.set_view_distance(72.0)
	day_night.attach_lighting(sun, world_environment)
	_check(weather.setup(survival, day_night), "desktop weather service installs")
	weather.begin_world("desert_ruins", 24681357, {})
	weather.activate()
	weather.force_weather_state("sandstorm", 120.0)
	badge.setup(weather)
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var snapshot := weather.get_snapshot()
	var environment_snapshot := day_night.get_weather_environment_snapshot()
	_check(str(snapshot.get("state_id", "")) == "sandstorm", "real desktop scene runs sandstorm state")
	_check(badge.visible and badge.get_display_text().contains("沙尘暴"), "desktop HUD exposes active sandstorm")
	_check(float(environment_snapshot.get("fog_multiplier", 0.0)) > 2.0, "desktop environment consumes sandstorm fog modifier")
	_check(float(environment_snapshot.get("light_multiplier", 1.0)) < 0.8, "desktop environment consumes sandstorm light modifier")
	_check(environment.fog_enabled and environment.fog_depth_end < 40.0, "real desktop fog hides distant geometry")
	_check(root.get_camera_3d() == camera, "weather desktop acceptance owns a real 3D camera")
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "weather desktop viewport produces a rendered frame")
	if image != null and not image.is_empty():
		_save_image(image)
	weather.clear()
	badge.queue_free()
	host.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	if failures.is_empty():
		print("QA WEATHER DESKTOP PASS | checks=%d | state=sandstorm | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WEATHER DESKTOP FAILURE: %s" % failure)
		print("QA WEATHER DESKTOP FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _build_scene(host: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	var floor := BoxMesh.new()
	floor.size = Vector3(18.0, 0.4, 34.0)
	floor_mesh.mesh = floor
	floor_mesh.position = Vector3(0.0, -0.2, -5.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#A97B42")
	floor_material.roughness = 0.92
	floor_mesh.material_override = floor_material
	host.add_child(floor_mesh)
	for index in 5:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.2, 2.2 + index * 0.35, 2.2)
		marker.mesh = box
		marker.position = Vector3(-4.0 + index * 2.0, box.size.y * 0.5, -2.0 - index * 5.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#C79B61").darkened(index * 0.055)
		material.roughness = 0.85
		marker.material_override = material
		host.add_child(marker)


func _save_image(image: Image) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_check(error == OK and FileAccess.file_exists(_capture_path), "weather desktop screenshot is saved")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
