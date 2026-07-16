class_name GameplayFeedbackService
extends Node

signal active_toast_changed(toast: Dictionary)
signal prompt_changed(prompt: Dictionary)
signal toast_published(toast: Dictionary)

const DEFAULT_DURATION := 2.4
const MAX_QUEUE_SIZE := 5

var _queue: Array[Dictionary] = []
var _active_toast: Dictionary = {}
var _active_remaining := 0.0
var _prompt: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	if _active_toast.is_empty():
		return
	_active_remaining -= maxf(0.0, delta)
	if _active_remaining <= 0.0:
		_activate_next_toast()


func publish(
	text: String,
	severity: String = "info",
	duration: float = DEFAULT_DURATION,
	dedupe_key: String = ""
) -> void:
	var normalized_text := text.strip_edges()
	if normalized_text.is_empty():
		return
	var key := dedupe_key.strip_edges()
	if key.is_empty():
		key = "%s:%s" % [severity, normalized_text]
	var toast := {
		"text": normalized_text,
		"severity": _normalize_severity(severity),
		"duration": clampf(duration, 0.6, 8.0),
		"key": key,
		"created_at_msec": Time.get_ticks_msec(),
	}
	if str(_active_toast.get("key", "")) == key:
		_active_toast = toast
		_active_remaining = float(toast["duration"])
		active_toast_changed.emit(_active_toast.duplicate(true))
		toast_published.emit(_active_toast.duplicate(true))
		return
	for index in _queue.size():
		if str(_queue[index].get("key", "")) == key:
			_queue[index] = toast
			toast_published.emit(toast.duplicate(true))
			return
	_queue.append(toast)
	while _queue.size() > MAX_QUEUE_SIZE:
		_queue.pop_front()
	toast_published.emit(toast.duplicate(true))
	if _active_toast.is_empty():
		_activate_next_toast()


func set_prompt(prompt: Dictionary) -> void:
	var normalized := _normalize_prompt(prompt)
	if normalized == _prompt:
		return
	_prompt = normalized
	prompt_changed.emit(_prompt.duplicate(true))


func clear_prompt() -> void:
	set_prompt({})


func clear_toasts() -> void:
	_queue.clear()
	_active_toast.clear()
	_active_remaining = 0.0
	active_toast_changed.emit({})


func clear() -> void:
	clear_toasts()
	clear_prompt()


func get_active_toast() -> Dictionary:
	return _active_toast.duplicate(true)


func get_prompt() -> Dictionary:
	return _prompt.duplicate(true)


func get_queue_size() -> int:
	return _queue.size()


func _activate_next_toast() -> void:
	if _queue.is_empty():
		_active_toast.clear()
		_active_remaining = 0.0
		active_toast_changed.emit({})
		return
	var next_toast: Dictionary = _queue.pop_front()
	_active_toast = next_toast.duplicate(true)
	_active_remaining = float(_active_toast.get("duration", DEFAULT_DURATION))
	active_toast_changed.emit(_active_toast.duplicate(true))


func _normalize_severity(value: String) -> String:
	return value if value in ["info", "success", "warning", "error"] else "info"


func _normalize_prompt(value: Dictionary) -> Dictionary:
	if value.is_empty() or not bool(value.get("visible", true)):
		return {}
	var title := str(value.get("title", "")).strip_edges()
	var primary := str(value.get("primary", "")).strip_edges()
	var secondary := str(value.get("secondary", "")).strip_edges()
	if title.is_empty() and primary.is_empty() and secondary.is_empty():
		return {}
	return {
		"visible": true,
		"title": title,
		"subtitle": str(value.get("subtitle", "")).strip_edges(),
		"primary": primary,
		"secondary": secondary,
		"tone": _normalize_severity(str(value.get("tone", "info"))),
	}
