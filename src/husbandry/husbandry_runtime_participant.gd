class_name HusbandryRuntimeParticipant
extends Node

signal interaction_announced(kind: String, result: Dictionary)
signal lifecycle_batch_announced(summary: Dictionary)

const HusbandryServiceScript = preload(
	"res://src/husbandry/animal_husbandry_service.gd"
)
const InteractionScript = preload(
	"res://src/husbandry/husbandry_interaction_adapter.gd"
)
const StateMigrationScript = preload(
	"res://src/husbandry/husbandry_state_migration.gd"
)
const NotificationPolicyScript = preload(
	"res://src/husbandry/husbandry_notification_policy.gd"
)
const MAX_PENDING_LIFECYCLE_EVENTS := 64

var hub: Node
var husbandry_service: Node
var husbandry_interaction: Node
var _bound_player: Node3D
var _installed := false
var _active := false
var _shutdown := false
var _feed_count := 0
var _ready_count := 0
var _rejection_count := 0
var _lifecycle_batch_count := 0
var _newborn_total := 0
var _grown_total := 0
var _lifecycle_audio_count := 0
var _dropped_lifecycle_events := 0
var _last_lifecycle_summary: Dictionary = {}
var _pending_lifecycle_events: Array[Dictionary] = []
var _lifecycle_flush_scheduled := false


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	var inventory: Node = hub.get("inventory") as Node
	var creature_spawner: Node = hub.get("creature_spawner") as Node
	var player_experience: Node = hub.get("player_experience") as Node
	if (
		inventory == null
		or creature_spawner == null
		or player_experience == null
		or not hub.has_method("_add_service")
	):
		return false
	husbandry_service = hub.call(
		"_add_service", HusbandryServiceScript.new(), "AnimalHusbandryService"
	) as Node
	if husbandry_service == null:
		return false
	husbandry_service.call(
		"setup", inventory.get("registry"), inventory, creature_spawner
	)
	if (
		not husbandry_service.has_method("is_ready")
		or not bool(husbandry_service.call("is_ready"))
	):
		_dispose_service(husbandry_service)
		husbandry_service = null
		return false
	husbandry_interaction = hub.call(
		"_add_service", InteractionScript.new(), "HusbandryInteraction"
	) as Node
	if husbandry_interaction == null:
		husbandry_service.call("shutdown")
		_dispose_service(husbandry_service)
		husbandry_service = null
		return false
	husbandry_interaction.call("setup", husbandry_service)
	if (
		not husbandry_interaction.has_method("is_ready")
		or not bool(husbandry_interaction.call("is_ready"))
	):
		husbandry_service.call("shutdown")
		_dispose_service(husbandry_interaction)
		_dispose_service(husbandry_service)
		husbandry_interaction = null
		husbandry_service = null
		return false
	hub.set("husbandry_service", husbandry_service)
	hub.set("husbandry_interaction", husbandry_interaction)
	_configure_player_experience(husbandry_interaction)
	_connect_runtime_signals()
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	return StateMigrationScript.normalize_world_state(state)


func begin_world(state: Dictionary) -> void:
	_active = false
	_reset_pending_lifecycle_batch()
	_unbind_player()
	if husbandry_service != null:
		if husbandry_service.has_method("clear"):
			husbandry_service.call("clear")
		var normalized: Dictionary = normalize_world_state(state)
		husbandry_service.call("deserialize", normalized.get("husbandry", {}))


func attach_game(
	world,
	player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	_unbind_player()
	if husbandry_service != null:
		if husbandry_service.has_method("detach_world"):
			husbandry_service.call("detach_world")
		husbandry_service.call("attach_world", world, player)
	if player != null and player.has_method("bind_entity_interaction_service"):
		player.call("bind_entity_interaction_service", husbandry_interaction)
		_bound_player = player


func activate() -> void:
	if _active:
		return
	_active = true
	if husbandry_service != null:
		husbandry_service.call("activate")


func save_into(payload: Dictionary) -> void:
	if husbandry_service != null:
		payload["husbandry"] = husbandry_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["husbandry"] = (
		husbandry_service.call("get_snapshot") if husbandry_service != null else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_reset_pending_lifecycle_batch()
	_unbind_player()
	if husbandry_service != null and husbandry_service.has_method("clear"):
		husbandry_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_runtime_signals()
	_configure_player_experience(null)
	if husbandry_interaction != null and husbandry_interaction.has_method("shutdown"):
		husbandry_interaction.call("shutdown")
	if husbandry_service != null and husbandry_service.has_method("shutdown"):
		husbandry_service.call("shutdown")


func get_husbandry_service() -> Node:
	return husbandry_service


func get_interaction_service() -> Node:
	return husbandry_interaction


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"service_ready": (
			husbandry_service != null and is_instance_valid(husbandry_service)
		),
		"interaction_ready": (
			husbandry_interaction != null and is_instance_valid(husbandry_interaction)
		),
		"bound_player_id": (
			_bound_player.get_instance_id()
			if _bound_player != null and is_instance_valid(_bound_player)
			else 0
		),
		"feed_count": _feed_count,
		"ready_count": _ready_count,
		"rejection_count": _rejection_count,
		"lifecycle_batch_count": _lifecycle_batch_count,
		"newborn_total": _newborn_total,
		"grown_total": _grown_total,
		"lifecycle_audio_count": _lifecycle_audio_count,
		"dropped_lifecycle_events": _dropped_lifecycle_events,
		"pending_lifecycle_events": _pending_lifecycle_events.size(),
		"lifecycle_flush_scheduled": _lifecycle_flush_scheduled,
		"last_lifecycle_summary": _last_lifecycle_summary.duplicate(true),
	}


func flush_pending_lifecycle_batch() -> Dictionary:
	_flush_lifecycle_batch()
	return _last_lifecycle_summary.duplicate(true)


func _connect_runtime_signals() -> void:
	_connect_if_needed(husbandry_service, "animal_fed", Callable(self, "_on_animal_fed"))
	_connect_if_needed(husbandry_service, "animal_ready", Callable(self, "_on_animal_ready"))
	_connect_if_needed(husbandry_service, "baby_born", Callable(self, "_on_baby_born"))
	_connect_if_needed(husbandry_service, "animal_grew", Callable(self, "_on_animal_grew"))
	_connect_if_needed(
		husbandry_service,
		"interaction_rejected",
		Callable(self, "_on_interaction_rejected")
	)


func _disconnect_runtime_signals() -> void:
	_disconnect_if_needed(husbandry_service, "animal_fed", Callable(self, "_on_animal_fed"))
	_disconnect_if_needed(husbandry_service, "animal_ready", Callable(self, "_on_animal_ready"))
	_disconnect_if_needed(husbandry_service, "baby_born", Callable(self, "_on_baby_born"))
	_disconnect_if_needed(husbandry_service, "animal_grew", Callable(self, "_on_animal_grew"))
	_disconnect_if_needed(
		husbandry_service,
		"interaction_rejected",
		Callable(self, "_on_interaction_rejected")
	)


func _connect_if_needed(target: Node, signal_name: String, callback: Callable) -> void:
	if (
		target != null
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and not target.is_connected(signal_name, callback)
	):
		target.connect(signal_name, callback)


func _disconnect_if_needed(target: Node, signal_name: String, callback: Callable) -> void:
	if (
		target != null
		and is_instance_valid(target)
		and target.has_signal(signal_name)
		and target.is_connected(signal_name, callback)
	):
		target.disconnect(signal_name, callback)


func _on_animal_fed(result: Dictionary) -> void:
	if not _active:
		return
	_feed_count += 1
	_publish_result(result, "success", 2.0, "feed")
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")
	interaction_announced.emit("fed", result.duplicate(true))


func _on_animal_ready(result: Dictionary) -> void:
	if not _active:
		return
	_ready_count += 1
	_publish_result(result, "success", 2.4, "ready")
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")
	interaction_announced.emit("ready", result.duplicate(true))


func _on_baby_born(result: Dictionary) -> void:
	_enqueue_lifecycle_event("newborn", result)


func _on_animal_grew(result: Dictionary) -> void:
	_enqueue_lifecycle_event("grown", result)


func _on_interaction_rejected(reason: String, context: Dictionary) -> void:
	if not _active:
		return
	_rejection_count += 1
	_publish_message(
		str(context.get("message", "暂时无法进行该动物交互")),
		"warning",
		"husbandry_rejected:%s:%s" % [
			reason,
			str(context.get("species_id", "animal")),
		],
		2.5
	)
	interaction_announced.emit("rejected", context.duplicate(true))


func _enqueue_lifecycle_event(kind: String, result: Dictionary) -> void:
	if not _active:
		return
	if _pending_lifecycle_events.size() >= MAX_PENDING_LIFECYCLE_EVENTS:
		_dropped_lifecycle_events += 1
		return
	_pending_lifecycle_events.append({
		"kind": kind,
		"result": result.duplicate(true),
	})
	if not _lifecycle_flush_scheduled:
		_lifecycle_flush_scheduled = true
		call_deferred("_flush_lifecycle_batch")


func _flush_lifecycle_batch() -> void:
	_lifecycle_flush_scheduled = false
	if not _active:
		_reset_pending_lifecycle_batch()
		return
	var events: Array[Dictionary] = []
	for event: Dictionary in _pending_lifecycle_events:
		events.append(event.duplicate(true))
	_pending_lifecycle_events.clear()
	var summary: Dictionary = NotificationPolicyScript.lifecycle_batch(events)
	if summary.is_empty():
		return
	_lifecycle_batch_count += 1
	_newborn_total += maxi(0, int(summary.get("newborn_count", 0)))
	_grown_total += maxi(0, int(summary.get("grown_count", 0)))
	summary["batch_index"] = _lifecycle_batch_count
	_last_lifecycle_summary = summary.duplicate(true)
	_publish_message(
		str(summary.get("message", "牧场生命状态已更新")),
		str(summary.get("severity", "info")),
		"husbandry_lifecycle_batch:%d" % _lifecycle_batch_count,
		float(summary.get("duration", 3.0))
	)
	if str(summary.get("audio", "none")) == "craft":
		var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
		if audio_service != null and audio_service.has_method("play_craft"):
			audio_service.call("play_craft")
			_lifecycle_audio_count += 1
	lifecycle_batch_announced.emit(summary.duplicate(true))


func _reset_pending_lifecycle_batch() -> void:
	_lifecycle_flush_scheduled = false
	_pending_lifecycle_events.clear()


func _publish_result(
	result: Dictionary, severity: String, duration: float, kind: String
) -> void:
	_publish_message(
		str(result.get("message", "动物状态已更新")),
		severity,
		"husbandry:%s:%s" % [
			kind,
			str(result.get("husbandry_id", result.get("species_id", "animal"))),
		],
		duration
	)


func _publish_message(
	message: String, severity: String, dedupe_key: String, duration: float
) -> void:
	if hub != null and hub.has_method("_publish_character_message"):
		hub.call("_publish_character_message", message, severity, dedupe_key, duration)


func _configure_player_experience(entity_service: Node) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var player_experience: Node = hub.get("player_experience") as Node
	if player_experience == null or not player_experience.has_method("setup"):
		return
	player_experience.call(
		"setup",
		hub.get("inventory"),
		hub.get("game_ui"),
		hub.get("block_interaction"),
		hub.get("furnace_service"),
		entity_service
	)


func _unbind_player() -> void:
	if (
		_bound_player != null
		and is_instance_valid(_bound_player)
		and _bound_player.has_method("bind_entity_interaction_service")
	):
		_bound_player.call("bind_entity_interaction_service", null)
	_bound_player = null


func _dispose_service(service: Node) -> void:
	if service == null or not is_instance_valid(service):
		return
	var parent := service.get_parent()
	if parent != null:
		parent.remove_child(service)
	service.queue_free()
