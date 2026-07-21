class_name AgricultureRuntimeParticipant
extends Node

signal maturity_batch_announced(summary: Dictionary)

const AgricultureServiceScript = preload(
	"res://src/agriculture/fertilizable_agriculture_service.gd"
)
const InteractionScript = preload(
	"res://src/agriculture/agriculture_interaction_adapter.gd"
)
const StateMigrationScript = preload(
	"res://src/agriculture/agriculture_state_migration.gd"
)
const NotificationPolicyScript = preload(
	"res://src/agriculture/agriculture_notification_policy.gd"
)
const MAX_PENDING_MATURITY_EVENTS := 64

var hub: Node
var agriculture_service: Node
var agriculture_interaction: Node
var _installed := false
var _active := false
var _shutdown := false
var _pending_maturity_events: Array[Dictionary] = []
var _maturity_flush_scheduled := false
var _maturity_batch_count := 0
var _matured_crop_total := 0
var _maturity_audio_count := 0
var _dropped_maturity_events := 0
var _till_audio_count := 0
var _water_audio_count := 0
var _plant_audio_count := 0
var _fertilize_audio_count := 0
var _harvest_audio_count := 0
var _last_maturity_summary: Dictionary = {}


func get_dependencies() -> Array[StringName]:
	return []


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
		"_add_service", AgricultureServiceScript.new(), "AgricultureService"
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
		"_add_service", InteractionScript.new(), "AgricultureInteraction"
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


func normalize_world_state(state: Dictionary) -> Dictionary:
	return StateMigrationScript.normalize_world_state(state)


func begin_world(state: Dictionary) -> void:
	_active = false
	_reset_maturity_batch()
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return
	agriculture_service.call("deactivate")
	agriculture_service.call("clear")
	var normalized := normalize_world_state(state)
	agriculture_service.call("deserialize", normalized.get("agriculture", {}))


func attach_game(
	world,
	_player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	if agriculture_service == null or not is_instance_valid(agriculture_service):
		return
	if agriculture_service.has_method("detach_world"):
		agriculture_service.call("detach_world")
	var inventory: Node = hub.get("inventory") as Node if hub != null else null
	agriculture_service.call("attach_world", world, inventory)


func activate() -> void:
	if _active or _shutdown:
		return
	_active = true
	if agriculture_service != null and is_instance_valid(agriculture_service):
		agriculture_service.call("activate")


func save_into(payload: Dictionary) -> void:
	if agriculture_service != null and is_instance_valid(agriculture_service):
		payload["agriculture"] = agriculture_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["agriculture"] = (
		agriculture_service.call("get_runtime_snapshot")
		if agriculture_service != null
		and is_instance_valid(agriculture_service)
		and agriculture_service.has_method("get_runtime_snapshot")
		else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_reset_maturity_batch()
	if agriculture_service != null and is_instance_valid(agriculture_service):
		agriculture_service.call("deactivate")
		agriculture_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_runtime_signals()
	var block_interaction: Node = hub.get("block_interaction") as Node if hub != null else null
	if (
		block_interaction != null
		and is_instance_valid(block_interaction)
		and agriculture_interaction != null
		and is_instance_valid(agriculture_interaction)
		and block_interaction.has_method("unregister_extension")
	):
		block_interaction.call("unregister_extension", agriculture_interaction)
	if agriculture_interaction != null and is_instance_valid(agriculture_interaction):
		agriculture_interaction.call("setup", null)
	if agriculture_service != null and is_instance_valid(agriculture_service):
		agriculture_service.call("shutdown")


func get_agriculture_service() -> Node:
	return agriculture_service


func get_interaction_service() -> Node:
	return agriculture_interaction


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"service_ready": (
			agriculture_service != null and is_instance_valid(agriculture_service)
		),
		"interaction_ready": (
			agriculture_interaction != null and is_instance_valid(agriculture_interaction)
		),
		"maturity_batch_count": _maturity_batch_count,
		"matured_crop_total": _matured_crop_total,
		"maturity_audio_count": _maturity_audio_count,
		"dropped_maturity_events": _dropped_maturity_events,
		"pending_maturity_events": _pending_maturity_events.size(),
		"maturity_flush_scheduled": _maturity_flush_scheduled,
		"till_audio_count": _till_audio_count,
		"water_audio_count": _water_audio_count,
		"plant_audio_count": _plant_audio_count,
		"fertilize_audio_count": _fertilize_audio_count,
		"harvest_audio_count": _harvest_audio_count,
		"last_maturity_summary": _last_maturity_summary.duplicate(true),
		"runtime": (
			agriculture_service.call("get_runtime_snapshot")
			if agriculture_service != null
			and is_instance_valid(agriculture_service)
			and agriculture_service.has_method("get_runtime_snapshot")
			else {}
		),
	}


func flush_pending_maturity_batch() -> Dictionary:
	_flush_maturity_batch()
	return _last_maturity_summary.duplicate(true)


func _connect_runtime_signals() -> void:
	_connect_if_needed(agriculture_service, "soil_tilled", Callable(self, "_on_soil_tilled"))
	_connect_if_needed(agriculture_service, "crop_planted", Callable(self, "_on_crop_planted"))
	_connect_if_needed(
		agriculture_service, "crop_stage_changed", Callable(self, "_on_crop_stage_changed")
	)
	_connect_if_needed(
		agriculture_service, "crop_harvested", Callable(self, "_on_crop_harvested")
	)
	_connect_if_needed(
		agriculture_service, "crop_fertilized", Callable(self, "_on_crop_fertilized")
	)
	var moisture: Variant = (
		agriculture_service.get("soil_moisture") if agriculture_service != null else null
	)
	_connect_if_needed(moisture, "soil_watered", Callable(self, "_on_soil_watered"))


func _disconnect_runtime_signals() -> void:
	_disconnect_if_needed(agriculture_service, "soil_tilled", Callable(self, "_on_soil_tilled"))
	_disconnect_if_needed(agriculture_service, "crop_planted", Callable(self, "_on_crop_planted"))
	_disconnect_if_needed(
		agriculture_service, "crop_stage_changed", Callable(self, "_on_crop_stage_changed")
	)
	_disconnect_if_needed(
		agriculture_service, "crop_harvested", Callable(self, "_on_crop_harvested")
	)
	_disconnect_if_needed(
		agriculture_service, "crop_fertilized", Callable(self, "_on_crop_fertilized")
	)
	var moisture: Variant = (
		agriculture_service.get("soil_moisture") if agriculture_service != null else null
	)
	_disconnect_if_needed(moisture, "soil_watered", Callable(self, "_on_soil_watered"))


func _connect_if_needed(target: Variant, signal_name: String, callback: Callable) -> void:
	if (
		target is Object
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and not target.is_connected(signal_name, callback)
	):
		target.connect(signal_name, callback)


func _disconnect_if_needed(target: Variant, signal_name: String, callback: Callable) -> void:
	if (
		target is Object
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and target.is_connected(signal_name, callback)
	):
		target.disconnect(signal_name, callback)


func _on_soil_tilled(_position: Vector3i, _previous_block: String) -> void:
	if not _active:
		return
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_block_place"):
		audio_service.call("play_block_place", "dirt")
		_till_audio_count += 1


func _on_soil_watered(_position: Vector3i, _duration_seconds: float) -> void:
	if not _active:
		return
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_block_place"):
		audio_service.call("play_block_place", "water")
		_water_audio_count += 1


func _on_crop_planted(_position: Vector3i, _crop_id: String) -> void:
	if not _active:
		return
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_block_place"):
		audio_service.call("play_block_place", "leaves")
		_plant_audio_count += 1


func _on_crop_fertilized(
	_position: Vector3i,
	_crop_id: String,
	_fertilizer_item_id: String,
	_from_stage: int,
	_to_stage: int
) -> void:
	if not _active:
		return
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")
		_fertilize_audio_count += 1


func _on_crop_harvested(_position: Vector3i, _crop_id: String, _outputs: Array) -> void:
	if not _active:
		return
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")
		_harvest_audio_count += 1


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
	if _pending_maturity_events.size() >= MAX_PENDING_MATURITY_EVENTS:
		_dropped_maturity_events += 1
		return
	_pending_maturity_events.append({
		"crop_id": crop_id,
		"position": [position.x, position.y, position.z],
	})
	if not _maturity_flush_scheduled:
		_maturity_flush_scheduled = true
		call_deferred("_flush_maturity_batch")


func _flush_maturity_batch() -> void:
	_maturity_flush_scheduled = false
	if not _active:
		_reset_maturity_batch()
		return
	var events: Array = _pending_maturity_events.duplicate(true)
	_pending_maturity_events.clear()
	var registry: Variant = (
		agriculture_service.get("crop_registry") if agriculture_service != null else null
	)
	var summary: Dictionary = NotificationPolicyScript.maturity_batch(events, registry)
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
	_pending_maturity_events.clear()
	_maturity_flush_scheduled = false


func _publish_message(
	message: String,
	severity: String,
	dedupe_key: String,
	duration: float
) -> void:
	if hub != null and hub.has_method("_publish_character_message"):
		hub.call("_publish_character_message", message, severity, dedupe_key, duration)


func _dispose_service(service: Node) -> void:
	if service == null or not is_instance_valid(service):
		return
	var parent := service.get_parent()
	if parent != null:
		parent.remove_child(service)
	service.queue_free()
