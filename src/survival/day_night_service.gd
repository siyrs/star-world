class_name DayNightService
extends Node

signal time_changed(time_of_day: float, day: int)
signal phase_changed(phase: String)
signal night_state_changed(is_night: bool)
signal time_skipped(previous_time: float, previous_day: int, time_of_day: float, day: int)

const SERIAL_VERSION := 1

@export_range(60.0, 3600.0, 1.0) var cycle_duration_seconds: float = 600.0
@export_range(0.0, 24.0, 0.1) var time_of_day: float = 8.0
@export var day_count: int = 1
@export var running: bool = true

var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var map_id: String = "star_continent"
var _last_phase: String = ""
var _last_night: bool = false
var _sky_material: ProceduralSkyMaterial
var _cloud_mesh: MeshInstance3D
var _cloud_material: StandardMaterial3D
var _cloud_scroll_accum := 0.0


func _ready() -> void:
	_apply_lighting()


func _process(delta: float) -> void:
	_update_clouds(delta)
	if not running:
		return
	var previous_day := day_count
	time_of_day += delta * 24.0 / maxf(1.0, cycle_duration_seconds)
	while time_of_day >= 24.0:
		time_of_day -= 24.0
		day_count += 1
	_apply_lighting()
	if previous_day != day_count or Engine.get_process_frames() % 12 == 0:
		time_changed.emit(time_of_day, day_count)


func attach_lighting(p_sun: DirectionalLight3D, p_environment: WorldEnvironment = null) -> void:
	sun = p_sun
	world_environment = p_environment
	_apply_lighting()


func set_map_profile(p_map_id: String) -> void:
	map_id = p_map_id
	_apply_lighting()


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)


func skip_to_time(hours: float) -> Dictionary:
	var previous_time := time_of_day
	var previous_day := day_count
	var target := fposmod(hours, 24.0)
	if target <= time_of_day:
		day_count += 1
	time_of_day = target
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)
	time_skipped.emit(previous_time, previous_day, time_of_day, day_count)
	return {
		"previous_time": previous_time,
		"previous_day": previous_day,
		"time_of_day": time_of_day,
		"day": day_count,
	}


func is_night() -> bool:
	return time_of_day < 6.0 or time_of_day >= 19.0


func get_phase() -> String:
	if time_of_day < 5.0:
		return "night"
	if time_of_day < 7.0:
		return "dawn"
	if time_of_day < 18.0:
		return "day"
	if time_of_day < 20.0:
		return "dusk"
	return "night"


func get_sun_strength() -> float:
	var angle := (time_of_day - 6.0) / 24.0 * TAU
	return clampf(sin(angle), 0.0, 1.0)


func _apply_lighting() -> void:
	var strength := get_sun_strength()
	if map_id == "abyss_world":
		strength *= 0.18
	if sun != null and is_instance_valid(sun):
		sun.rotation_degrees = Vector3(time_of_day / 24.0 * 360.0 - 90.0, -35.0, 0.0)
		sun.light_energy = lerpf(0.08, 1.15, strength)
		sun.light_color = Color("#9CB7E8").lerp(Color("#FFF1CD"), strength)
	if (
		world_environment != null
		and is_instance_valid(world_environment)
		and world_environment.environment != null
	):
		var environment := world_environment.environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("#17213A").lerp(Color("#AFC7D2"), strength)
		environment.ambient_light_energy = lerpf(0.25, 0.85, strength)
		var day_color := Color("#72B5E8")
		if map_id == "desert_ruins":
			day_color = Color("#E2B96C")
		elif map_id == "frozen_wastes":
			day_color = Color("#A9D1E7")
		elif map_id == "sky_islands":
			day_color = Color("#78C8FA")
		elif map_id == "abyss_world":
			day_color = Color("#191D31")
		environment.background_color = Color("#091020").lerp(day_color, strength)
		_apply_sky(environment, day_color, strength)
	var phase := get_phase()
	if phase != _last_phase:
		_last_phase = phase
		phase_changed.emit(phase)
	var night := is_night()
	if night != _last_night:
		_last_night = night
		night_state_changed.emit(night)


func serialize() -> Dictionary:
	return {
		"version": SERIAL_VERSION,
		"time_of_day": time_of_day,
		"day": day_count,
		"cycle_duration": cycle_duration_seconds,
		"map_id": map_id,
	}


func _apply_sky(environment: Environment, day_color: Color, strength: float) -> void:
	if _sky_material == null:
		_sky_material = ProceduralSkyMaterial.new()
		_sky_material.sun_angle_max = 12.0
		_sky_material.sun_curve = 0.08
		_sky_material.use_debanding = true
		var sky := Sky.new()
		sky.sky_material = _sky_material
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
	# Warm band around sunrise and sunset so the horizon glows.
	var dusk_amount := clampf(1.0 - absf(strength - 0.35) * 4.0, 0.0, 1.0)
	var zenith_day := Color("#3D7AC2").lerp(day_color, 0.35)
	var zenith_dusk := Color("#3B3163")
	var zenith_night := Color("#0A1026")
	var horizon_day := day_color.lerp(Color("#FFFFFF"), 0.25)
	var horizon_dusk := Color("#E8875A")
	var horizon_night := Color("#182238")
	var zenith := zenith_night.lerp(zenith_day, strength).lerp(zenith_dusk, dusk_amount * 0.55)
	var horizon := horizon_night.lerp(horizon_day, strength).lerp(horizon_dusk, dusk_amount * 0.7)
	_sky_material.sky_top_color = zenith
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_bottom_color = horizon.darkened(0.55)
	_sky_material.ground_horizon_color = horizon.lerp(Color("#3A3328"), 0.45)
	_sky_material.sky_energy_multiplier = lerpf(0.25, 1.0, strength)
	_sky_material.ground_energy_multiplier = lerpf(0.1, 0.6, strength)


func _update_clouds(delta: float) -> void:
	if sun == null or not is_instance_valid(sun):
		return
	if _cloud_mesh == null:
		_cloud_mesh = _create_cloud_layer()
		sun.get_parent().add_child(_cloud_mesh)
	# Material writes are throttled: dirtying the material every frame costs
	# real time on low-end machines and CI runners.
	_cloud_scroll_accum += delta
	if _cloud_material != null and _cloud_scroll_accum >= 0.2:
		var offset: Vector3 = _cloud_material.uv1_offset
		offset.x = fposmod(offset.x + _cloud_scroll_accum * 0.0175, 1.0)
		_cloud_material.uv1_offset = offset
		var tint := Color("#3A4A6B").lerp(Color("#FFFFFF"), get_sun_strength())
		_cloud_material.albedo_color = tint
		_cloud_scroll_accum = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_cloud_mesh.global_position = Vector3(
			camera.global_position.x, 88.0, camera.global_position.z
		)


func _create_cloud_layer() -> MeshInstance3D:
	var texture := _build_cloud_texture()
	_cloud_material = StandardMaterial3D.new()
	_cloud_material.albedo_texture = texture
	# Alpha scissor (cutout) instead of alpha blending: fullscreen transparent
	# blending is the most expensive possible fill on software rasterizers,
	# while cutout pixels can be depth-tested and discarded cheaply. The hard
	# edges also fit the voxel look.
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_cloud_material.alpha_scissor_threshold = 0.5
	_cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_material.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	_cloud_material.no_depth_test = false
	_cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	plane.subdivide_depth = 1
	plane.subdivide_width = 1
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = plane
	mesh_instance.material_override = _cloud_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	mesh_instance.name = "CloudLayer"
	return mesh_instance


static func _build_cloud_texture() -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in size:
		for x in size:
			var value := _cloud_hash(x >> 2, y >> 2)
			if value < 0.56:
				continue
			var softness := clampf((value - 0.56) * 9.0, 0.0, 1.0)
			var edge_x: int = mini(x, size - 1 - x)
			var edge_y: int = mini(y, size - 1 - y)
			var edge := clampf(float(mini(edge_x, edge_y)) / 10.0, 0.0, 1.0)
			var alpha := clampf(softness * edge, 0.0, 0.9)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


static func _cloud_hash(x: int, y: int) -> float:
	var value := (x * 73856093) ^ (y * 19349663) ^ 83492791
	value = value ^ (value >> 13)
	value = value * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7FFFFFFF) / float(0x7FFFFFFF)


func deserialize(data: Dictionary) -> bool:
	time_of_day = fposmod(float(data.get("time_of_day", 8.0)), 24.0)
	day_count = maxi(1, int(data.get("day", 1)))
	cycle_duration_seconds = maxf(60.0, float(data.get("cycle_duration", 600.0)))
	map_id = str(data.get("map_id", map_id))
	_apply_lighting()
	time_changed.emit(time_of_day, day_count)
	return true
