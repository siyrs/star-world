class_name ScalableAgricultureRuntimeParticipant
extends "res://src/agriculture/agriculture_runtime_participant.gd"

const ScaleAgricultureServiceScript = preload(
	"res://src/agriculture/scalable_agriculture_service.gd"
)
const ScaleInteractionScript = preload(
	"res://src/agriculture/agriculture_interaction_adapter.gd"
)
const ScaleNotificationPolicyScript = preload(
	"res://src/agriculture/agriculture_notification_policy.gd"
)
const MAX_MATURITY_POSITION_SAMPLES := 64
const MAX_TRACKED_MATURITY_TYPES := 16

var _pending_maturity_counts: Dictionary = {}
var _pending_maturity_total := 0
var _pending_unclassified_maturity_count := 0
var _pending_dropped_position_samples := 0
var _dropped_maturity_position_samples := 0


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	var inventory: Node = hub.get("inventory") as Node
	var tool_service: Node = hub.get("tool_service") as Node
	var block_interaction: Node = hub.get("block_interaction") as Node
	if (
		inventory == null
		or tool_service == null
		or block_interaction == null
		or not hub.has_method("_add_service")
		or not block_interaction.has_method("register_extension")
	):
		return false
	agriculture_service = hub.call(
		"_add_service", ScaleAgricultureServiceScript.new(), "AgricultureService"
	) as Node
	if agriculture_service == null:
		return false
	agriculture_service.call("setup", inventory.get("registry"), tool_service)
	if (
		not agriculture_service.has_method("is_ready")
		or not bool(agriculture_service.call("is_ready"))
	):
		_dispose_service(agriculture_service)
		agriculture_service = null
		return false
	agriculture_interaction = hub.call(
		"_add_service", ScaleInteractionScript.new(), "AgricultureInteraction"
	) as Node
	if agriculture_interaction == null:
		agriculture_service.call("shutdown")
		_dispose_service(agriculture_service)
		agriculture_service = null
		return false
	agriculture_interaction.call("setup", agriculture_service)
	if not bool(block_interaction.call("register_extension", agriculture_interaction)):
		agriculture_interaction.call("setup", null)
		_dispose_service(agriculture_interaction)
		agriculture_service.call("shutdown")
		_dispose_service(agriculture_service)
		agriculture_interaction = null
		agriculture_service = null
		return false
	hub.set("agriculture_service", agriculture_service)
	hub.set("agriculture_interaction", agriculture_interaction)
	_connect_runtime_signals()
	agriculture_service.call("deactivate")
	_installed = true
	_shutdown = false
	return true


func begin_world(state: Dictionary) -> void:
	_reset_maturity_counters()
	super.begin_world(state)


func clear(reason: StringName = &"clear") -> void:
	super.clear(reason)
	_reset_maturity_counters()


func get_lifecycle_snapshot() -> Dictionary:
	var result: Dictionary = super.get_lifecycle_snapshot()
	result["pending_maturity_events"] = _pending_maturity_total
	result["pending_maturity_samples"] = _pending_maturity_events.size()
	result["pending_maturity_types"] = _pending_maturity_counts.size()
	result["pending_unclassified_maturity_count"] = _pending_unclassified_maturity_count
	result["dropped_maturity_events"] = _dropped_maturity_events
	result["dropped_maturity_position_samples"] = _dropped_maturity_position_samples
	return result


func _on_crop_stage_changed(position: Vector3i, crop_id: String, stage: int) -> void:
	if not _active or agriculture_service == null:
		return
	var registry: Variant = agriculture_service.get("crop_registry")
	if registry == null or not registry.has_method("get_crop"):
		return
	var definition: Dictionary = registry.call("get_crop", crop_id)
	var stages: Array = definition.get("stage_blocks", [])
	if stages.is_empty() or stage < stages.size() - 1:
		return
	_pending_maturity_total += 1
	if _pending_maturity_counts.has(crop_id):
		_pending_maturity_counts[crop_id] = int(_pending_maturity_counts[crop_id]) + 1
	elif _pending_maturity_counts.size() < MAX_TRACKED_MATURITY_TYPES:
		_pending_maturity_counts[crop_id] = 1
	else:
		_pending_unclassified_maturity_count += 1
	if _pending_maturity_events.size() < MAX_MATURITY_POSITION_SAMPLES:
		_pending_maturity_events.append({
			"crop_id": crop_id,
			"position": [position.x, position.y, position.z],
		})
	else:
		_pending_dropped_position_samples += 1
		_dropped_maturity_position_samples += 1
	if not _maturity_flush_scheduled:
		_maturity_flush_scheduled = true
		call_deferred("_flush_maturity_batch")


func _flush_maturity_batch() -> void:
	_maturity_flush_scheduled = false
	if not _active:
		_reset_maturity_batch()
		return
	if _pending_maturity_total <= 0:
		return
	var counts := _pending_maturity_counts.duplicate(true)
	var positions: Array = []
	for raw_event: Variant in _pending_maturity_events:
		if raw_event is Dictionary:
			positions.append((raw_event as Dictionary).get("position", []))
	var dropped_samples := _pending_dropped_position_samples
	var unclassified := _pending_unclassified_maturity_count
	_pending_maturity_events.clear()
	_pending_maturity_counts.clear()
	_pending_maturity_total = 0
	_pending_unclassified_maturity_count = 0
	_pending_dropped_position_samples = 0
	var registry: Variant = (
		agriculture_service.get("crop_registry") if agriculture_service != null else null
	)
	var summary: Dictionary = ScaleNotificationPolicyScript.maturity_counts(
		counts,
		registry,
		positions,
		dropped_samples,
		unclassified
	)
	if summary.is_empty():
		return
	_maturity_batch_count += 1
	_matured_crop_total += maxi(0, int(summary.get("matured_count", 0)))
	summary["batch_index"] = _maturity_batch_count
	summary["dropped_event_count"] = _dropped_maturity_events
	_last_maturity_summary = summary.duplicate(true)
	_publish_message(
		str(summary.get("message", "农田作物已经成熟")),
		str(summary.get("severity", "success")),
		"agriculture_maturity_batch:%d" % _maturity_batch_count,
		float(summary.get("duration", 3.0))
	)
	if str(summary.get("audio", "none")) == "pickup":
		var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
		if audio_service != null and audio_service.has_method("play_pickup"):
			audio_service.call("play_pickup")
			_maturity_audio_count += 1
	maturity_batch_announced.emit(summary.duplicate(true))


func _reset_maturity_batch() -> void:
	super._reset_maturity_batch()
	_pending_maturity_counts.clear()
	_pending_maturity_total = 0
	_pending_unclassified_maturity_count = 0
	_pending_dropped_position_samples = 0


func _reset_maturity_counters() -> void:
	_reset_maturity_batch()
	_maturity_batch_count = 0
	_matured_crop_total = 0
	_maturity_audio_count = 0
	_dropped_maturity_events = 0
	_dropped_maturity_position_samples = 0
	_last_maturity_summary.clear()
