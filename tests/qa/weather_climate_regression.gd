extends SceneTree

const RegistryScript = preload("res://src/weather/weather_registry.gd")
const WeatherScript = preload("res://src/weather/weather_service.gd")
const BadgeScript = preload("res://src/weather/weather_status_badge.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const DayNightScript = preload("res://src/survival/day_night_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = RegistryScript.new()
	_check(registry.get_validation_errors().is_empty(), "weather registry validates")
	_check(registry.get_profile_ids().size() == 5, "weather registry covers five formal maps")
	for map_id: String in RegistryScript.EXPECTED_MAP_IDS:
		var profile := registry.get_profile(map_id)
		_check(not profile.is_empty(), "%s profile exists" % map_id)
		var state_ids := registry.get_state_ids(map_id)
		_check("clear" in state_ids, "%s has a clear baseline" % map_id)
		_check(state_ids.size() >= 2 and state_ids.size() <= 4, "%s state count is bounded" % map_id)
		for transition in range(1, 9):
			var first := registry.choose_state_id(map_id, 24681357, transition)
			var second := registry.choose_state_id(map_id, 24681357, transition)
			_check(first == second, "%s transition %d is deterministic" % [map_id, transition])
			var duration := registry.duration_for_state(map_id, first, 24681357, transition)
			_check(duration >= 15.0 and duration <= 600.0, "%s duration remains bounded" % map_id)

	var host := Node.new()
	root.add_child(host)
	var survival = SurvivalScript.new()
	var day_night = DayNightScript.new()
	var weather = WeatherScript.new()
	var sun := DirectionalLight3D.new()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	world_environment.environment = environment
	for node in [survival, day_night, weather, sun, world_environment]:
		host.add_child(node)
	await process_frame
	day_night.running = false
	day_night.set_map_profile("frozen_wastes")
	day_night.set_time(12.0)
	day_night.set_view_distance(64.0)
	day_night.attach_lighting(sun, world_environment)
	_check(weather.setup(survival, day_night), "weather service accepts survival/day-night authorities")
	weather.begin_world("frozen_wastes", 24681357, {})
	weather.activate()
	weather.set_process(false)
	_check(weather.force_weather_state("blizzard", 600.0), "blizzard can be selected through the service API")
	var blizzard := weather.get_snapshot()
	_check(str(blizzard.get("label", "")) == "暴风雪", "blizzard exposes localized HUD label")
	_check(is_equal_approx(float(blizzard.get("fog_multiplier", 0.0)), 2.4), "blizzard exposes exact fog modifier")
	var environment_snapshot := day_night.get_weather_environment_snapshot()
	_check(str(environment_snapshot.get("state_id", "")) == "blizzard", "day-night owns applied weather state")
	_check(float(environment_snapshot.get("light_multiplier", 1.0)) < 0.7, "blizzard dims day-night lighting")
	_check(environment.fog_enabled, "weather composition preserves depth fog")
	_check(environment.fog_depth_end < 30.0, "blizzard visibly pulls the fog boundary inward")
	_check(sun.light_energy < 0.8, "blizzard reduces noon sun energy without owning the light")

	var saturation_before := float(survival.get("saturation"))
	for _cycle in 13:
		weather.force_weather_state("blizzard", 600.0)
		weather.advance(60.0)
	var exposure_snapshot := weather.get_snapshot()
	_check(float(exposure_snapshot.get("exhaustion_total", 0.0)) > 4.0, "hazardous weather accumulates bounded survival exhaustion")
	_check(float(survival.get("saturation")) < saturation_before, "weather exposure consumes existing survival reserves")
	_check(int(exposure_snapshot.get("exposure_application_count", 0)) <= 13 * 12, "exposure calls remain hard bounded")

	weather.force_weather_state("snow", 77.0)
	weather.advance(12.0)
	var saved := weather.serialize()
	var restored = WeatherScript.new()
	host.add_child(restored)
	await process_frame
	_check(restored.setup(survival, day_night), "restored weather service installs")
	restored.begin_world("frozen_wastes", 24681357, saved)
	var restored_snapshot := restored.get_snapshot()
	_check(str(restored_snapshot.get("state_id", "")) == "snow", "weather state survives save/reload")
	_check(absf(float(restored_snapshot.get("remaining_seconds", 0.0)) - 65.0) < 0.01, "weather remaining duration survives save/reload")
	_check(int(restored_snapshot.get("transition_index", -1)) == int(saved.get("transition_index", -2)), "transition identity survives save/reload")

	var badge = BadgeScript.new()
	root.add_child(badge)
	await process_frame
	badge.setup(weather)
	weather.force_weather_state("blizzard", 90.0)
	await process_frame
	_check(badge.visible, "weather badge becomes visible during gameplay state")
	_check(badge.get_display_text().contains("暴风雪"), "weather badge renders the active climate")
	_check(badge.get_display_text().contains("环境消耗"), "hazardous weather communicates survival impact")

	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get("weather_service") != null, "production service hub installs weather service")
	_check(hub.get("weather_status_badge") != null, "production service hub installs weather HUD extension")
	var lifecycle: Node = hub.get("feature_lifecycle") as Node
	_check(lifecycle != null and bool(lifecycle.call("has_participant", &"weather_runtime")), "weather participates in the production lifecycle")
	var normalized: Dictionary = lifecycle.call(
		"normalize_world_state",
		{
			"metadata": {"id": "weather-test", "map_id": "desert_ruins", "seed": 99},
		}
	)
	_check(normalized.has("weather") and normalized.weather is Dictionary, "legacy worlds receive a migrated weather state container")
	var participant: Node = lifecycle.call("get_participant", &"weather_runtime") as Node
	participant.call("begin_world", normalized)
	participant.call("activate")
	var payload := normalized.duplicate(true)
	participant.call("save_into", payload)
	_check(payload.has("weather") and str(payload.weather.get("map_id", "")) == "desert_ruins", "feature lifecycle persists map-bound weather")
	participant.call("clear", &"test")
	_check((hub.get("weather_service") as Node).call("get_snapshot").is_empty(), "weather clear removes active world state")

	hub.queue_free()
	badge.queue_free()
	host.queue_free()
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("QA WEATHER CLIMATE PASS | checks=%d | maps=5 | persistence=true | environment=true | survival=true | lifecycle=true" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WEATHER CLIMATE FAILURE: %s" % failure)
		print("QA WEATHER CLIMATE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
