class_name MachineRuntimeParticipant
extends Node

signal machine_batch_announced(summary: Dictionary)

const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const StateMigrationScript = preload("res://src/machine/machine_state_migration.gd")
const CompletionPolicyScript = preload("res://src/machine/machine_completion_policy.gd")
const MAX_PENDING_COMPLETIONS := 128

var hub: Node
var scheduler: Node
var furnace_service: Node
var _installed := false
var _active := false
var _shutdown := false
var _pending_completions: Array[Dictionary] = []
var _completion_flush_scheduled := false
var _dropped_completion_events := 0
var _completion_batch_count := 0
var _completed_job_count := 0
var _completed_item_count := 0
var _completion_audio_count := 0
var _max_completions_in_batch := 0
var _last_completion_summary: Dictionary = {}


func get_dependencies() -> Array[StringName]:
	return []


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	furnace_service = hub.get("furnace_service") as Node
	if (
		furnace_service == null
		or not furnace_service.has_method("advance_machine_runtime")
		or not furnace_service.has_method("get_runtime_snapshot")
		or not hub.has_method("_add_service")
	):
		return false
	scheduler = hub.call("_add_service", SchedulerScript.new(), "MachineRuntime") as Node
	if scheduler == null:
		return false
	var registration: Dictionary = scheduler.call(
		"register_domain", &"furnace", furnace_service
	)
	if not bool(registration.get("success", false)):
		_dispose_service(scheduler)
		scheduler = null
		return false
	if furnace_service.has_signal("item_smelted"):
		var callback := Callable(self, "_on_item_smelted")
		if not furnace_service.is_connected("item_smelted", callback):
			furnace_service.connect("item_smelted", callback)
	hub.set("machine_runtime", scheduler)
	_installed = true
	_shutdown = false
	return true


func normalize_world_state(state: Dictionary) -> Dictionary:
	return StateMigrationScript.normalize_world_state(state)


func begin_world(state: Dictionary) -> void:
	_active = false
	_reset_completion_batch()
	if scheduler != null and scheduler.has_method("deactivate"):
		scheduler.call("deactivate")
	if furnace_service != null:
		if furnace_service.has_method("clear"):
			furnace_service.call("clear")
		var machine_state: Dictionary = state.get("machines", {})
		furnace_service.call("deserialize", machine_state)


func attach_game(
	_world,
	_player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	pass


func activate() -> void:
	if _active or _shutdown:
		return
	_active = true
	if scheduler != null and scheduler.has_method("activate"):
		scheduler.call("activate")


func save_into(payload: Dictionary) -> void:
	if furnace_service != null and furnace_service.has_method("serialize"):
		payload["machines"] = furnace_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["machines"] = (
		furnace_service.call("get_runtime_snapshot")
		if furnace_service != null and furnace_service.has_method("get_runtime_snapshot")
		else {}
	)
	snapshot["machine_runtime"] = (
		scheduler.call("get_snapshot")
		if scheduler != null and scheduler.has_method("get_snapshot")
		else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_reset_completion_batch()
	if scheduler != null and scheduler.has_method("deactivate"):
		scheduler.call("deactivate")
	if furnace_service != null and furnace_service.has_method("clear"):
		furnace_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	if furnace_service != null and is_instance_valid(furnace_service):
		var callback := Callable(self, "_on_item_smelted")
		if (
			furnace_service.has_signal("item_smelted")
			and furnace_service.is_connected("item_smelted", callback)
		):
			furnace_service.disconnect("item_smelted", callback)
		if furnace_service.has_method("shutdown"):
			furnace_service.call("shutdown")
	if scheduler != null and scheduler.has_method("shutdown"):
		scheduler.call("shutdown")


func get_scheduler() -> Node:
	return scheduler


func get_furnace_service() -> Node:
	return furnace_service


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"scheduler_ready": scheduler != null and is_instance_valid(scheduler),
		"furnace_ready": furnace_service != null and is_instance_valid(furnace_service),
		"pending_completion_count": _pending_completions.size(),
		"completion_flush_scheduled": _completion_flush_scheduled,
		"dropped_completion_events": _dropped_completion_events,
		"completion_batch_count": _completion_batch_count,
		"completed_job_count": _completed_job_count,
		"completed_item_count": _completed_item_count,
		"completion_audio_count": _completion_audio_count,
		"max_completions_in_batch": _max_completions_in_batch,
		"last_completion_summary": _last_completion_summary.duplicate(true),
	}


func _on_item_smelted(machine_id: String, recipe_id: String, output: Dictionary) -> void:
	if not _active:
		return
	if _pending_completions.size() >= MAX_PENDING_COMPLETIONS:
		_dropped_completion_events += 1
		return
	_pending_completions.append({
		"machine_id": machine_id,
		"recipe_id": recipe_id,
		"output": output.duplicate(true),
	})
	if not _completion_flush_scheduled:
		_completion_flush_scheduled = true
		call_deferred("_flush_completion_batch")


func _flush_completion_batch() -> void:
	_completion_flush_scheduled = false
	if not _active or _pending_completions.is_empty():
		_pending_completions.clear()
		return
	var events := _pending_completions.duplicate(true)
	_pending_completions.clear()
	var item_registry: Variant = null
	var inventory: Node = hub.get("inventory") as Node if hub != null else null
	if inventory != null:
		item_registry = inventory.get("registry")
	var summary: Dictionary = CompletionPolicyScript.build(events, item_registry)
	if summary.is_empty():
		return
	_completion_batch_count += 1
	_completed_job_count += maxi(0, int(summary.get("completed_jobs", 0)))
	_completed_item_count += maxi(0, int(summary.get("item_total", 0)))
	_max_completions_in_batch = maxi(
		_max_completions_in_batch, int(summary.get("completed_jobs", 0))
	)
	summary["batch_index"] = _completion_batch_count
	summary["dropped_event_count"] = _dropped_completion_events
	_last_completion_summary = summary.duplicate(true)
	_publish_message(
		str(summary.get("message", "机器加工完成")),
		"success",
		"machine_batch:%d" % _completion_batch_count,
		3.0
	)
	var audio_service: Node = hub.get("audio_service") as Node if hub != null else null
	if audio_service != null and audio_service.has_method("play_craft"):
		audio_service.call("play_craft")
		_completion_audio_count += 1
	machine_batch_announced.emit(summary.duplicate(true))


func _reset_completion_batch() -> void:
	_pending_completions.clear()
	_completion_flush_scheduled = false


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
