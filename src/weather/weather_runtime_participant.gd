class_name WeatherRuntimeParticipant
extends Node

const WeatherServiceScript = preload("res://src/weather/weather_service.gd")
const WeatherStatusBadgeScript = preload("res://src/weather/weather_status_badge.gd")

var hub: Node
var weather_service: Node
var weather_status_badge: Control
var _installed := false
var _active := false
var _shutdown := false
var _bound_player_id := 0
var _announced_transition_count := 0


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	if not p_hub.has_method("_add_service"):
		return false
	hub = p_hub
	var survival: Node = hub.get("survival") as Node
	var day_night: Node = hub.get("day_night") as Node
	if survival == null or day_night == null:
		return false
	weather_service = hub.call(
		"_add_service", WeatherServiceScript.new(), "WeatherService"
	) as Node
	if weather_service == null or not bool(weather_service.call("setup", survival, day_night)):
		_dispose_node(weather_service)
		weather_service = null
		return false
	var transition_callback := Callable(self, "_on_weather_transitioned")
	if not weather_service.is_connected("weather_transitioned", transition_callback):
		weather_service.connect("weather_transitioned", transition_callback)
	var game_ui: Node = hub.get("game_ui") as Node
	if game_ui != null:
		weather_status_badge = WeatherStatusBadgeScript.new()
		game_ui.add_child(weather_status_badge)
		weather_status_badge.call("setup", weather_service)
	_set_hub_property("weather_service", weather_service)
	_set_hub_property("weather_status_badge", weather_status_badge)
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	var raw_weather: Variant = normalized.get("weather", {})
	normalized["weather"] = raw_weather.duplicate(true) if raw_weather is Dictionary else {}
	return normalized


func begin_world(state: Dictionary) -> void:
	_active = false
	_bound_player_id = 0
	if weather_service == null:
		return
	var normalized := normalize_world_state(state)
	var metadata: Dictionary = normalized.get("metadata", {})
	weather_service.call(
		"begin_world",
		str(metadata.get("map_id", "star_continent")),
		int(metadata.get("seed", 0)),
		normalized.get("weather", {})
	)


func attach_game(
	_world,
	player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	_bound_player_id = (
		player.get_instance_id() if player != null and is_instance_valid(player) else 0
	)


func activate() -> void:
	if weather_service == null or _shutdown:
		return
	_active = true
	weather_service.call("activate")


func save_into(payload: Dictionary) -> void:
	if weather_service != null:
		payload["weather"] = weather_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["weather"] = (
		weather_service.call("get_snapshot") if weather_service != null else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_bound_player_id = 0
	if weather_service != null and weather_service.has_method("clear"):
		weather_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	if weather_service != null:
		var callback := Callable(self, "_on_weather_transitioned")
		if weather_service.has_signal("weather_transitioned") and weather_service.is_connected(
			"weather_transitioned", callback
		):
			weather_service.disconnect("weather_transitioned", callback)
		if weather_service.has_method("shutdown"):
			weather_service.call("shutdown")
	if weather_status_badge != null and is_instance_valid(weather_status_badge):
		weather_status_badge.call("setup", null)
		weather_status_badge.queue_free()
	weather_status_badge = null
	_set_hub_property("weather_status_badge", null)
	_set_hub_property("weather_service", null)


func get_weather_service() -> Node:
	return weather_service


func get_status_badge() -> Control:
	return weather_status_badge


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"weather_ready": weather_service != null and is_instance_valid(weather_service),
		"hud_ready": weather_status_badge != null and is_instance_valid(weather_status_badge),
		"bound_player_id": _bound_player_id,
		"announced_transition_count": _announced_transition_count,
		"weather": (
			weather_service.call("get_snapshot") if weather_service != null else {}
		),
	}


func _on_weather_transitioned(
	_previous_state_id: String, _state_id: String, _transition_index: int
) -> void:
	if not _active or weather_service == null:
		return
	var snapshot: Dictionary = weather_service.call("get_snapshot")
	if snapshot.is_empty():
		return
	_announced_transition_count += 1
	var game_ui: Node = hub.get("game_ui") as Node if hub != null else null
	if game_ui != null and game_ui.has_method("show_message"):
		game_ui.call(
			"show_message",
			"天气变化：%s" % str(snapshot.get("label", "未知")),
			3.2,
			str(snapshot.get("tone", "info")),
			"weather_transition"
		)


func _set_hub_property(property_name: String, value: Variant) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	for property: Dictionary in hub.get_property_list():
		if str(property.get("name", "")) == property_name:
			hub.set(property_name, value)
			return


func _dispose_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
