extends SceneTree

# Commercial acceptance gap: exercise weather through the production GameScene,
# ServiceHub lifecycle, save service and complete world reload for every formal map.
# This intentionally does not construct WeatherService directly.

const GameScene = preload("res://scenes/game/game.tscn")
const CaptureConfig = preload("res://tests/qa/desktop_capture_config.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")

const OUTPUT_PATH := "user://production-profile-weather-persistence.png"
const JOURNEY_SEED := 20260808
const READY_FRAMES := 360
const CLEANUP_FRAMES := 24
const FORCED_STATES := {
	"star_continent": "rain",
	"desert_ruins": "sandstorm",
	"frozen_wastes": "snow",
	"sky_islands": "cloudburst",
	"abyss_world": "ashfall",
}

var checks := 0
var failures: Array[String] = []
var _capture_path := ""
var _capture_saved := false
var _created_world_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = CaptureConfig.resolve(OS.get_cmdline_user_args(), OUTPUT_PATH)
	root.size = Vector2i(1024, 576)
	root.content_scale_size = Vector2i(1024, 576)
	print("QA_USER_DATA_ROOT weather=%s appdata=%s" % [ProjectSettings.globalize_path("user://"), OS.get_environment("APPDATA")])
	_check(_user_data_uses_inherited_appdata(), "weather journey user data resolves under inherited APPDATA")
	var game := GameScene.instantiate()
	root.add_child(game)
	for _frame in 6:
		await process_frame
	var hub := game.get("service_hub") as Node
	_check(hub != null, "production GameScene mounts the authoritative service hub")
	if hub == null:
		await _finish(game, null, [])
		return
	var save := hub.get("save_service") as Node
	_check(save != null, "production service hub exposes the save authority")
	var profile_ids: Array[String] = MapProfileCatalogScript.get_ids()
	_check(profile_ids.size() == 5, "weather journey discovers exactly five formal map profiles")
	_check(_same_strings(profile_ids, FORCED_STATES.keys()), "weather journey covers every formal production profile")
	var pre_world_ids := _world_ids()

	for profile_id: String in profile_ids:
		await _exercise_profile(game, hub, save, profile_id)

	var post_world_ids := _world_ids()
	_check(pre_world_ids == post_world_ids, "weather journey restores the complete pre-run world directory set")
	_check(_capture_saved, "weather journey writes rendered production evidence")
	await _finish(game, hub, pre_world_ids)


func _exercise_profile(game: Node, hub: Node, save: Node, profile_id: String) -> void:
	var display_name := "qa-production-weather-%s-%d" % [profile_id, Time.get_ticks_msec()]
	var state: Dictionary = save.call(
		"create_world", display_name, profile_id, JOURNEY_SEED
	)
	_check(not state.is_empty(), "%s creates a temporary world through SaveService" % profile_id)
	if state.is_empty():
		return
	var world_id := str(state.get("metadata", {}).get("id", ""))
	if not world_id.is_empty():
		_created_world_ids.append(world_id)
	game.call("begin_world_state", state)
	_check(await _wait_for_world_ready(game, hub, profile_id), "%s starts through the complete GameScene lifecycle" % profile_id)
	var world := game.get("world") as Node
	var weather := hub.get("weather_service") as Node
	var badge := hub.get("weather_status_badge") as Control
	var lifecycle := hub.get("feature_lifecycle") as Node
	_check(
		world != null and str(world.get("profile_id")) == profile_id,
		"%s production world owns the selected map identity" % profile_id
	)
	_check(
		weather != null and lifecycle != null and bool(lifecycle.call("has_participant", &"weather_runtime")),
		"%s weather comes from the registered production lifecycle participant" % profile_id
	)
	if weather == null:
		await _return_and_delete(hub, save, world_id)
		return

	# Freeze only the clock so the exact persistence check is deterministic. The
	# service, lifecycle, day/night composition and HUD remain the production nodes.
	weather.set_process(false)
	var initial_snapshot: Dictionary = weather.call("get_snapshot")
	_check(
		str(initial_snapshot.get("map_id", "")) == profile_id
		and bool(initial_snapshot.get("world_bound", false))
		and bool(initial_snapshot.get("active", false)),
		"%s active weather is bound to the running production map" % profile_id
	)
	var forced_state := str(FORCED_STATES.get(profile_id, ""))
	_check(
		bool(weather.call("force_weather_state", forced_state, 180.0)),
		"%s selects its registered non-default weather through the live service" % profile_id
	)
	weather.call("advance", 7.0)
	await process_frame
	var live_snapshot: Dictionary = hub.call("get_weather_snapshot")
	_check(
		str(live_snapshot.get("map_id", "")) == profile_id
		and str(live_snapshot.get("state_id", "")) == forced_state,
		"%s hub snapshot retains exact map/weather binding" % profile_id
	)
	_check(
		absf(float(live_snapshot.get("remaining_seconds", 0.0)) - 173.0) < 0.01,
		"%s deterministic weather clock advances on the production instance" % profile_id
	)
	var environment_snapshot: Dictionary = hub.get("day_night").call(
		"get_weather_environment_snapshot"
	)
	_check(
		str(environment_snapshot.get("state_id", "")) == forced_state,
		"%s day/night environment consumes the live weather state" % profile_id
	)
	_check(
		badge != null and badge.visible and badge.call("get_display_text").contains(str(live_snapshot.get("label", ""))),
		"%s production HUD displays its active localized weather" % profile_id
	)

	_check(bool(hub.call("save_current")), "%s commits weather through the production save transaction" % profile_id)
	var saved: Dictionary = save.call("load_world", world_id)
	var saved_weather: Dictionary = saved.get("weather", {})
	_check(
		str(saved_weather.get("map_id", "")) == profile_id
		and str(saved_weather.get("state_id", "")) == forced_state
		and absf(float(saved_weather.get("remaining_seconds", 0.0)) - 173.0) < 0.01,
		"%s disk payload persists exact weather map, state and remaining duration" % profile_id
	)

	# A menu return performs another authoritative save and tears down all feature
	# participants. Re-entering the disk payload is therefore a real full reload.
	hub.call("return_to_menu")
	_check(await _wait_for_menu(hub), "%s cleanly tears down to the production menu" % profile_id)
	var reloaded: Dictionary = save.call("load_world", world_id)
	game.call("begin_world_state", reloaded)
	_check(await _wait_for_world_ready(game, hub, profile_id), "%s completes a full production save reload" % profile_id)
	weather = hub.get("weather_service") as Node
	if weather != null:
		weather.set_process(false)
	var restored: Dictionary = hub.call("get_weather_snapshot")
	_check(
		str(restored.get("map_id", "")) == profile_id
		and str(restored.get("state_id", "")) == forced_state
		and absf(float(restored.get("remaining_seconds", 0.0)) - 173.0) < 0.01
		and bool(restored.get("active", false)),
		"%s full GameScene reload restores the live weather identity exactly" % profile_id
	)
	_check(
		str(game.get("current_profile_id")) == profile_id
		and str((game.get("world") as Node).get("profile_id")) == profile_id,
		"%s weather reload cannot drift from GameScene/world profile identity" % profile_id
	)

	if profile_id == "abyss_world":
		await _save_capture()
	await _return_and_delete(hub, save, world_id)


func _wait_for_world_ready(game: Node, hub: Node, profile_id: String) -> bool:
	for _frame in READY_FRAMES:
		await process_frame
		if game == null or hub == null or not is_instance_valid(game) or not is_instance_valid(hub):
			return false
		var world := game.get("world") as Node
		var player := game.get("player") as CharacterBody3D
		if (
			world != null
			and player != null
			and bool(world.get("is_started"))
			and bool(player.get("input_enabled"))
			and str(game.get("current_profile_id")) == profile_id
			and not str(hub.get("current_world_id")).is_empty()
		):
			return true
	return false


func _wait_for_menu(hub: Node) -> bool:
	for _frame in CLEANUP_FRAMES:
		await process_frame
		if hub != null and str(hub.get("current_world_id")).is_empty():
			return true
	return false


func _return_and_delete(hub: Node, save: Node, world_id: String) -> void:
	if hub != null and not str(hub.get("current_world_id")).is_empty():
		hub.call("return_to_menu")
		await _wait_for_menu(hub)
	if save != null and not world_id.is_empty() and bool(save.call("world_exists", world_id)):
		_check(bool(save.call("delete_world", world_id)), "%s deletes its isolated weather world" % world_id)


func _save_capture() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "production weather viewport renders a frame")
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var error := image.save_png(_capture_path)
	_capture_saved = error == OK and FileAccess.file_exists(_capture_path)
	_check(_capture_saved, "production weather screenshot is saved")


func _world_ids() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open("user://worlds")
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and directory.current_is_dir():
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _same_strings(first: Array[String], second_raw: Array) -> bool:
	var second: Array[String] = []
	for value: Variant in second_raw:
		second.append(str(value))
	var first_copy := first.duplicate()
	first_copy.sort()
	second.sort()
	return first_copy == second


func _user_data_uses_inherited_appdata() -> bool:
	var inherited := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/").to_lower()
	if inherited.is_empty():
		return true
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	return user_root.begins_with("%s/" % inherited)


func _finish(game: Node, hub: Node, expected_world_ids: Array[String]) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused = false
	if hub != null and is_instance_valid(hub):
		var save := hub.get("save_service") as Node
		if not str(hub.get("current_world_id")).is_empty():
			hub.call("return_to_menu")
			await _wait_for_menu(hub)
		if save != null:
			for world_id: String in _created_world_ids:
				if bool(save.call("world_exists", world_id)):
					save.call("delete_world", world_id)
		var audio := hub.get("audio_service") as Node
		if audio != null and audio.has_method("shutdown"):
			audio.call("shutdown")
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _frame in CLEANUP_FRAMES:
		await process_frame
	_check(_world_ids() == expected_world_ids, "final weather cleanup preserves the pre-run world set")
	if failures.is_empty():
		print("QA PRODUCTION PROFILE WEATHER PASS | checks=%d | profiles=5 | persistence=true | capture=%s" % [checks, _capture_path])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PRODUCTION PROFILE WEATHER FAILURE: %s" % failure)
		print("QA PRODUCTION PROFILE WEATHER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
