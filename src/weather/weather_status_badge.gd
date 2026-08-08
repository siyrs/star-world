class_name WeatherStatusBadge
extends PanelContainer

const ThemeFactory = preload("res://src/ui/theme_factory.gd")
const Tokens = preload("res://src/ui/design_tokens.gd")

var weather_service: Node
var _title: Label
var _detail: Label
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	name = "WeatherStatusBadge"
	position = Vector2(18, 66)
	custom_minimum_size = Vector2(218, 58)
	theme = ThemeFactory.create_theme()
	theme_type_variation = "HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_content()
	visible = false
	var pending_service := weather_service
	weather_service = null
	setup(pending_service)


func setup(service: Node) -> void:
	if not is_node_ready() or _title == null or _detail == null:
		weather_service = service
		return
	_disconnect_service()
	weather_service = service
	if weather_service != null and weather_service.has_signal("weather_changed"):
		weather_service.connect("weather_changed", Callable(self, "_on_weather_changed"))
	if weather_service != null and weather_service.has_method("get_snapshot"):
		var raw_snapshot: Variant = weather_service.call("get_snapshot")
		if raw_snapshot is Dictionary:
			_on_weather_changed(raw_snapshot)
			return
	_on_weather_changed({})


func get_display_text() -> String:
	if _last_snapshot.is_empty() or _title == null or _detail == null:
		return ""
	return "%s · %s" % [_title.text, _detail.text]


func get_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func _build_content() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	add_child(content)
	_title = Label.new()
	_title.theme_type_variation = "SectionTitle"
	content.add_child(_title)
	_detail = Label.new()
	_detail.theme_type_variation = "CaptionLabel"
	content.add_child(_detail)


func _on_weather_changed(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)
	if _title == null or _detail == null:
		return
	if snapshot.is_empty():
		visible = false
		_title.text = ""
		_detail.text = ""
		return
	var label := str(snapshot.get("label", "天气未知"))
	var remaining := maxi(0, int(ceil(float(snapshot.get("remaining_seconds", 0.0)))))
	var exhaustion := maxf(0.0, float(snapshot.get("exhaustion_per_minute", 0.0)))
	_title.text = "天气 · %s" % label
	_title.add_theme_color_override(
		"font_color", Tokens.color(_tone_color(str(snapshot.get("tone", "info"))))
	)
	if exhaustion > 0.001:
		_detail.text = "约 %d 秒 · 环境消耗 %.2f/分钟" % [remaining, exhaustion]
	else:
		_detail.text = "约 %d 秒 · 环境稳定" % remaining
	visible = true


func _tone_color(tone: String) -> String:
	match tone:
		"success": return Tokens.COLOR_SUCCESS
		"warning": return Tokens.COLOR_WARNING
		"error": return Tokens.COLOR_DANGER
		_: return Tokens.COLOR_ACCENT


func _disconnect_service() -> void:
	if weather_service == null or not is_instance_valid(weather_service):
		return
	var callback := Callable(self, "_on_weather_changed")
	if weather_service.has_signal("weather_changed") and weather_service.is_connected(
		"weather_changed", callback
	):
		weather_service.disconnect("weather_changed", callback)
