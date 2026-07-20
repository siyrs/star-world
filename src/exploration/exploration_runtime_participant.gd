class_name ExplorationRuntimeParticipant
extends Node

signal danger_transition_announced(kind: String, snapshot: Dictionary)
signal immediate_danger_refreshed(trigger: String, snapshot: Dictionary)
signal danger_refresh_batch_completed(summary: Dictionary)

const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingStateMigrationScript = preload(
	"res://src/exploration/prospecting_state_migration.gd"
)
const DangerServiceScript = preload(
	"res://src/exploration/exploration_danger_service.gd"
)
const DangerRefreshBatchPolicyScript = preload(
	"res://src/exploration/danger_refresh_batch_policy.gd"
)
const MAX_PENDING_DANGER_EVENTS := 64

var hub: Node
var prospecting_service: Node
var danger_service: Node
var _bound_player: Node3D
var _installed := false
var _active := false
var _shutdown := false
var _last_announced_danger_tier := ""
var _last_refresh_trigger := ""
var _scan_success_count := 0
var _scan_rejection_count := 0
var _danger_announcement_count := 0
var _danger_recovery_count := 0
var _immediate_event_count := 0
var _immediate_refresh_count := 0
var _coalesced_danger_event_count := 0
var _dropped_danger_event_count := 0
var _max_events_in_refresh_batch := 0
var _pending_danger_trigger_counts: Dictionary = {}
var _pending_danger_event_count := 0
var _pending_danger_dropped_count := 0
var _danger_refresh_flush_scheduled := false
var _last_refresh_triggers: Array[String] = []
var _last_refresh_summary: Dictionary = {}


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	var inventory: Node = hub.get("inventory") as Node
	var day_night: Node = hub.get("day_night") as Node
	var creature_spawner: Node = hub.get("creature_spawner") as Node
	if inventory == null or not hub.has_method("_add_service"):
		return false
	danger_service = hub.call(
		"_add_service", DangerServiceScript.new(), "ExplorationDangerService"
	) as Node
	if danger_service == null or not bool(
		danger_service.call("setup", day_night, creature_spawner)
	):
		_dispose_service(danger_service)
		danger_service = null
		return false
	prospecting_service = hub.call(
		"_add_service", ProspectingServiceScript.new(), "ProspectingService"
	) as Node
	if prospecting_service == null or not bool(
		prospecting_service.call(
			"setup", inventory.get("registry"), danger_service, day_night
		)
	):
		_dispose_service(prospecting_service)
		_dispose_service(danger_service)
		prospecting_service = null
		danger_service = null
		return false
	hub.set("exploration_danger_service", danger_service)
	hub.set("prospecting_service", prospecting_service)
	_connect_runtime_signals()
	_configure_hud(danger_service)
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	return ProspectingStateMigrationScript.normalize_world_state(state)


func begin_world(state: Dictionary) -> void:
	_active = false
	_last_announced_danger_tier = ""
	_last_refresh_trigger = ""
	_last_refresh_triggers.clear()
	_last_refresh_summary.clear()
	_reset_pending_danger_batch()
	_unbind_player()
	if danger_service != null and danger_service.has_method("clear"):
		danger_service.call("clear")
	if prospecting_service != null:
		if prospecting_service.has_method("clear"):
			prospecting_service.call("clear")
		var normalized := normalize_world_state(state)
		prospecting_service.call("deserialize", normalized.get("exploration", {}))
	var metadata: Dictionary = state.get("metadata", {})
	var map_id := str(metadata.get("map_id", "star_continent"))
	var creature_spawner: Node = hub.get("creature_spawner") as Node if hub != null else null
	if creature_spawner != null and creature_spawner.has_method("set_map_profile"):
		creature_spawner.call("set_map_profile", map_id)


func attach_game(
	world,
	player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	_unbind_player()
	if danger_service != null:
		danger_service.call("attach_world", world, player)
	if prospecting_service != null:
		prospecting_service.call("attach_world", world, player)
	if player != null and player.has_method("bind_prospecting_service"):
		player.call("bind_prospecting_service", prospecting_service)
		_bound_player = player


func activate() -> void:
	if _active:
		return
	_active = true
	if danger_service != null:
		danger_service.call("activate")


func save_into(payload: Dictionary) -> void:
	if prospecting_service != null:
		payload["exploration"] = prospecting_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["exploration"] = (
		prospecting_service.call("get_snapshot") if prospecting_service != null else {}
	)
	snapshot["danger"] = (
		danger_service.call("get_snapshot") if danger_service != null else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_last_announced_danger_tier = ""
	_last_refresh_trigger = ""
	_last_refresh_triggers.clear()
	_last_refresh_summary.clear()
	_reset_pending_danger_batch()
	_unbind_player()
	if danger_service != null and danger_service.has_method("clear"):
		danger_service.call("clear")
	if prospecting_service != null and prospecting_service.has_method("clear"):
		prospecting_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_runtime_signals()
	_configure_hud(null)


func get_prospecting_service() -> Node:
	return prospecting_service


func get_danger_service() -> Node:
	return danger_service


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"prospecting_ready": (
			prospecting_service != null and is_instance_valid(prospecting_service)
		),
		"danger_ready": danger_service != null and is_instance_valid(danger_service),
		"bound_player_id": (
			_bound_player.get_instance_id()
			if _bound_player != null and is_instance_valid(_bound_player)
			else 0
		),
		"last_danger_tier": _last_announced_danger_tier,
		"last_refresh_trigger": _last_refresh_trigger,
		"last_refresh_triggers": _last_refresh_triggers.duplicate(),
		"last_refresh_summary": _last_refresh_summary.duplicate(true),
		"scan_success_count": _scan_success_count,
		"scan_rejection_count": _scan_rejection_count,
		"danger_announcement_count": _danger_announcement_count,
		"danger_recovery_count": _danger_recovery_count,
		"immediate_event_count": _immediate_event_count,
		"immediate_refresh_count": _immediate_refresh_count,
		"coalesced_danger_event_count": _coalesced_danger_event_count,
		"dropped_danger_event_count": _dropped_danger_event_count,
		"max_events_in_refresh_batch": _max_events_in_refresh_batch,
		"pending_danger_event_count": _pending_danger_event_count,
		"pending_trigger_count": _pending_danger_trigger_counts.size(),
		"danger_refresh_flush_scheduled": _danger_refresh_flush_scheduled,
	}


func queue_danger_refresh(trigger: String) -> bool:
	if not _active or danger_service == null or not is_instance_valid(danger_service):
		return false
	_immediate_event_count += 1
	if _pending_danger_event_count >= MAX_PENDING_DANGER_EVENTS:
		_pending_danger_dropped_count += 1
		_dropped_danger_event_count += 1
		return false
	var normalized_trigger := trigger.strip_edges()
	if normalized_trigger.is_empty():
		normalized_trigger = "manual"
	_pending_danger_event_count += 1
	_pending_danger_trigger_counts[normalized_trigger] = int(
		_pending_danger_trigger_counts.get(normalized_trigger, 0)
	) + 1
	if not _danger_refresh_flush_scheduled:
		_danger_refresh_flush_scheduled = true
		call_deferred("_flush_danger_refresh_batch")
	return true


func flush_pending_danger_refresh() -> Dictionary:
	_flush_danger_refresh_batch()
	return _last_refresh_summary.duplicate(true)


func _connect_runtime_signals() -> void:
	_connect_if_needed(
		danger_service, "danger_changed", Callable(self, "_on_danger_changed")
	)
	_connect_if_needed(
		prospecting_service, "scan_completed", Callable(self, "_on_scan_completed")
	)
	_connect_if_needed(
		prospecting_service, "scan_rejected", Callable(self, "_on_scan_rejected")
	)
	var day_night: Node = hub.get("day_night") as Node if hub != null else null
	_connect_if_needed(
		day_night, "phase_changed", Callable(self, "_on_phase_changed")
	)
	var creature_spawner: Node = hub.get("creature_spawner") as Node if hub != null else null
	_connect_if_needed(
		creature_spawner, "ecology_changed", Callable(self, "_on_ecology_changed")
	)
	_connect_if_needed(
		creature_spawner, "threat_changed", Callable(self, "_on_threat_changed")
	)


func _disconnect_runtime_signals() -> void:
	_disconnect_if_needed(
		danger_service, "danger_changed", Callable(self, "_on_danger_changed")
	)
	_disconnect_if_needed(
		prospecting_service, "scan_completed", Callable(self, "_on_scan_completed")
	)
	_disconnect_if_needed(
		prospecting_service, "scan_rejected", Callable(self, "_on_scan_rejected")
	)
	var day_night: Node = hub.get("day_night") as Node if hub != null and is_instance_valid(hub) else null
	_disconnect_if_needed(
		day_night, "phase_changed", Callable(self, "_on_phase_changed")
	)
	var creature_spawner: Node = hub.get("creature_spawner") as Node if hub != null and is_instance_valid(hub) else null
	_disconnect_if_needed(
		creature_spawner, "ecology_changed", Callable(self, "_on_ecology_changed")
	)
	_disconnect_if_needed(
		creature_spawner, "threat_changed", Callable(self, "_on_threat_changed")
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


func _configure_hud(service: Node) -> void:
	var game_ui: Node = hub.get("game_ui") as Node if hub != null and is_instance_valid(hub) else null
	if game_ui == null:
		return
	var hud: Node = game_ui.get("hud") as Node
	if hud != null and hud.has_method("setup_danger"):
		hud.call("setup_danger", service)


func _on_scan_completed(result: Dictionary) -> void:
	_scan_success_count += 1
	_publish_message(
		str(result.get("message", "区域勘探完成")),
		"success",
		"prospecting:%s" % str(result.get("record_key", "area")),
		3.8
	)
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_ui"):
		audio_service.call("play_ui")


func _on_scan_rejected(reason: String, context: Dictionary) -> void:
	_scan_rejection_count += 1
	_publish_message(
		str(context.get("message", "暂时无法勘探")),
		"warning",
		"prospecting_rejected:%s" % reason,
		2.4
	)


func _on_danger_changed(snapshot: Dictionary) -> void:
	if not _active:
		return
	var tier_id := str(snapshot.get("tier_id", "safe"))
	if tier_id == _last_announced_danger_tier:
		return
	var previous_tier := _last_announced_danger_tier
	_last_announced_danger_tier = tier_id
	if tier_id in ["dangerous", "severe"]:
		_danger_announcement_count += 1
		_publish_message(
			str(snapshot.get("message", "当前区域危险度上升")),
			"error" if tier_id == "severe" else "warning",
			"danger_tier:%s" % tier_id,
			3.4
		)
		danger_transition_announced.emit("danger", snapshot.duplicate(true))
	elif previous_tier in ["dangerous", "severe"] and tier_id in ["safe", "guarded"]:
		_danger_recovery_count += 1
		_publish_message(
			"区域危险已缓解：%s" % str(snapshot.get("tier_label", "低")),
			"success" if tier_id == "safe" else "info",
			"danger_recovery:%s" % tier_id,
			3.0
		)
		danger_transition_announced.emit("recovered", snapshot.duplicate(true))


func _on_phase_changed(_phase: String) -> void:
	queue_danger_refresh("phase_changed")


func _on_ecology_changed(_snapshot: Dictionary) -> void:
	queue_danger_refresh("ecology_changed")


func _on_threat_changed(_snapshot: Dictionary) -> void:
	queue_danger_refresh("threat_changed")


func _refresh_danger_immediately(trigger: String) -> void:
	queue_danger_refresh(trigger)


func _flush_danger_refresh_batch() -> void:
	_danger_refresh_flush_scheduled = false
	if _pending_danger_event_count <= 0:
		_pending_danger_trigger_counts.clear()
		_pending_danger_dropped_count = 0
		return
	var trigger_counts := _pending_danger_trigger_counts.duplicate(true)
	var event_count := _pending_danger_event_count
	var dropped_count := _pending_danger_dropped_count
	_pending_danger_trigger_counts.clear()
	_pending_danger_event_count = 0
	_pending_danger_dropped_count = 0
	if not _active or danger_service == null or not is_instance_valid(danger_service):
		return
	var summary: Dictionary = DangerRefreshBatchPolicyScript.build(
		trigger_counts, event_count, dropped_count
	)
	var raw_snapshot: Variant
	if danger_service.has_method("refresh_for_events"):
		raw_snapshot = danger_service.call("refresh_for_events")
	elif danger_service.has_method("refresh_now"):
		raw_snapshot = danger_service.call("refresh_now")
	else:
		return
	var snapshot: Dictionary = raw_snapshot if raw_snapshot is Dictionary else {}
	_immediate_refresh_count += 1
	_coalesced_danger_event_count += int(summary.get("coalesced_event_count", 0))
	_max_events_in_refresh_batch = maxi(
		_max_events_in_refresh_batch, int(summary.get("event_count", 0))
	)
	var raw_triggers: Variant = summary.get("triggers", [])
	_last_refresh_triggers.clear()
	if raw_triggers is Array:
		for raw_trigger: Variant in raw_triggers:
			_last_refresh_triggers.append(str(raw_trigger))
	_last_refresh_trigger = str(summary.get("trigger_key", "manual"))
	summary["refresh_index"] = _immediate_refresh_count
	summary["snapshot"] = snapshot.duplicate(true)
	var assessment: Dictionary = (
		snapshot.get("assessment", {})
		if snapshot.get("assessment", {}) is Dictionary
		else {}
	)
	summary["environment_reused"] = bool(
		assessment.get("last_reused_environment", false)
	)
	_last_refresh_summary = summary.duplicate(true)
	_last_refresh_summary.erase("snapshot")
	# Preserve the original signal contract for existing listeners. Each
	# unique reason is announced with the same single-assessment snapshot.
	var compatibility_triggers := _last_refresh_triggers.duplicate()
	if compatibility_triggers.is_empty():
		compatibility_triggers.append("manual")
	for compatibility_trigger: String in compatibility_triggers:
		immediate_danger_refreshed.emit(
			compatibility_trigger, snapshot.duplicate(true)
		)
	danger_refresh_batch_completed.emit(summary.duplicate(true))


func _reset_pending_danger_batch() -> void:
	_pending_danger_trigger_counts.clear()
	_pending_danger_event_count = 0
	_pending_danger_dropped_count = 0
	_danger_refresh_flush_scheduled = false


func _unbind_player() -> void:
	if (
		_bound_player != null
		and is_instance_valid(_bound_player)
		and _bound_player.has_method("bind_prospecting_service")
	):
		_bound_player.call("bind_prospecting_service", null)
	_bound_player = null


func _publish_message(
	message: String, severity: String, dedupe_key: String, duration: float
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
