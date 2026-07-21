class_name MachineRuntimeParticipant
extends Node

signal machine_batch_announced(summary: Dictionary)
signal machine_automation_announced(summary: Dictionary)

const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const StateMigrationScript = preload("res://src/machine/machine_state_migration.gd")
const CompletionPolicyScript = preload("res://src/machine/machine_completion_policy.gd")
const StonecutterServiceScript = preload("res://src/machine/stonecutter_service.gd")
const InteractionRouterScript = preload("res://src/machine/machine_interaction_router.gd")
const AutomationServiceScript = preload("res://src/machine/machine_automation_service.gd")
const MAX_PENDING_COMPLETIONS := 128

var hub: Node
var scheduler: Node
var furnace_service: Node
var stonecutter_service: Node
var interaction_router: Node
var automation_service: Node
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
	var inventory: Node = hub.get("inventory") as Node
	var container_storage: Node = hub.get("container_storage") as Node
	var item_registry: Variant = inventory.get("registry") if inventory != null else null
	if (
		furnace_service == null
		or not furnace_service.has_method("advance_machine_runtime")
		or not furnace_service.has_method("get_runtime_snapshot")
		or item_registry == null
		or container_storage == null
		or not container_storage.has_method("can_transact_items")
		or not container_storage.has_method("transact_items")
		or not hub.has_method("_add_service")
	):
		return false
	stonecutter_service = hub.call(
		"_add_service",
		StonecutterServiceScript.new(),
		"StonecutterService"
	) as Node
	if (
		stonecutter_service == null
		or not bool(stonecutter_service.call("setup", item_registry))
	):
		_dispose_service(stonecutter_service)
		stonecutter_service = null
		return false
	scheduler = hub.call("_add_service", SchedulerScript.new(), "MachineRuntime") as Node
	if scheduler == null:
		_dispose_service(stonecutter_service)
		stonecutter_service = null
		return false
	for registration_data: Dictionary in [
		{"id": &"furnace", "service": furnace_service},
		{"id": &"stonecutter", "service": stonecutter_service},
	]:
		var registration: Dictionary = scheduler.call(
			"register_domain",
			registration_data.get("id", &""),
			registration_data.get("service") as Node
		)
		if not bool(registration.get("success", false)):
			_rollback_install()
			return false
	interaction_router = hub.call(
		"_add_service",
		InteractionRouterScript.new(),
		"MachineInteractionRouter"
	) as Node
	if interaction_router == null:
		_rollback_install()
		return false
	var furnace_registration: Dictionary = interaction_router.call(
		"register_machine_type",
		&"furnace",
		furnace_service,
		&"open_furnace",
		["input", "fuel", "output"],
		"熔炉",
		"熔炉中仍有物品，请先清空三个槽位后再拆除"
	)
	var stonecutter_registration: Dictionary = interaction_router.call(
		"register_machine_type",
		&"stonecutter",
		stonecutter_service,
		&"open_stonecutter",
		["input", "output"],
		"石材切割机",
		"石材切割机中仍有物品，请先清空原料与产出槽后再拆除"
	)
	if (
		not bool(furnace_registration.get("success", false))
		or not bool(stonecutter_registration.get("success", false))
	):
		_rollback_install()
		return false
	automation_service = hub.call(
		"_add_service",
		AutomationServiceScript.new(),
		"MachineAutomationService"
	) as Node
	if (
		automation_service == null
		or not bool(automation_service.call(
			"setup", interaction_router, container_storage
		))
	):
		_rollback_install()
		return false
	var automation_registration: Dictionary = scheduler.call(
		"register_domain", &"automation", automation_service
	)
	if not bool(automation_registration.get("success", false)):
		_rollback_install()
		return false
	_connect_completion_signal(
		furnace_service,
		"item_smelted",
		Callable(self, "_on_item_smelted")
	)
	_connect_completion_signal(
		stonecutter_service,
		"item_processed",
		Callable(self, "_on_item_processed")
	)
	_connect_completion_signal(
		automation_service,
		"automation_machine_activated",
		Callable(self, "_on_machine_automation_activated")
	)
	hub.set("machine_runtime", scheduler)
	hub.set("stonecutter_service", stonecutter_service)
	hub.set("machine_interaction_router", interaction_router)
	hub.set("machine_automation_service", automation_service)
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
	if automation_service != null and automation_service.has_method("clear"):
		automation_service.call("clear")
	var machine_state: Dictionary = state.get("machines", {})
	for service: Node in [furnace_service, stonecutter_service]:
		if service == null or not is_instance_valid(service):
			continue
		if service.has_method("clear"):
			service.call("clear")
		service.call("deserialize", machine_state)


func attach_game(
	world,
	_player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	if automation_service != null and automation_service.has_method("attach_world"):
		automation_service.call("attach_world", world)


func activate() -> void:
	if _active or _shutdown:
		return
	_active = true
	if scheduler != null and scheduler.has_method("activate"):
		scheduler.call("activate")


func save_into(payload: Dictionary) -> void:
	var furnace_state: Dictionary = (
		furnace_service.call("serialize")
		if furnace_service != null and furnace_service.has_method("serialize")
		else {}
	)
	var stonecutter_state: Dictionary = (
		stonecutter_service.call("serialize")
		if stonecutter_service != null and stonecutter_service.has_method("serialize")
		else {}
	)
	payload["machines"] = {
		"version": StateMigrationScript.VERSION,
		"saved_at_unix": maxi(
			int(furnace_state.get("saved_at_unix", 0)),
			int(stonecutter_state.get("saved_at_unix", 0))
		),
		"furnaces": furnace_state.get("furnaces", {}).duplicate(true),
		"stonecutters": stonecutter_state.get("stonecutters", {}).duplicate(true),
	}


func snapshot_into(snapshot: Dictionary) -> void:
	var furnace_snapshot: Dictionary = (
		furnace_service.call("get_runtime_snapshot")
		if furnace_service != null and furnace_service.has_method("get_runtime_snapshot")
		else {}
	)
	var stonecutter_snapshot: Dictionary = (
		stonecutter_service.call("get_runtime_snapshot")
		if stonecutter_service != null and stonecutter_service.has_method("get_runtime_snapshot")
		else {}
	)
	var automation_snapshot: Dictionary = (
		automation_service.call("get_runtime_snapshot")
		if automation_service != null and automation_service.has_method("get_runtime_snapshot")
		else {}
	)
	var machine_snapshot := furnace_snapshot.duplicate(true)
	machine_snapshot["machine_count"] = (
		maxi(0, int(furnace_snapshot.get("machine_count", 0)))
		+ maxi(0, int(stonecutter_snapshot.get("machine_count", 0)))
	)
	machine_snapshot["furnace_machine_count"] = maxi(
		0, int(furnace_snapshot.get("machine_count", 0))
	)
	machine_snapshot["stonecutter_machine_count"] = maxi(
		0, int(stonecutter_snapshot.get("machine_count", 0))
	)
	machine_snapshot["automation"] = automation_snapshot.duplicate(true)
	machine_snapshot["domains"] = {
		"furnace": furnace_snapshot.duplicate(true),
		"stonecutter": stonecutter_snapshot.duplicate(true),
		"automation": automation_snapshot.duplicate(true),
	}
	snapshot["machines"] = machine_snapshot
	snapshot["machine_runtime"] = (
		scheduler.call("get_snapshot")
		if scheduler != null and scheduler.has_method("get_snapshot")
		else {}
	)
	snapshot["machine_interactions"] = (
		interaction_router.call("get_snapshot")
		if interaction_router != null and interaction_router.has_method("get_snapshot")
		else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_reset_completion_batch()
	if scheduler != null and scheduler.has_method("deactivate"):
		scheduler.call("deactivate")
	for service: Node in [stonecutter_service, furnace_service]:
		if service != null and is_instance_valid(service) and service.has_method("clear"):
			service.call("clear")
	if automation_service != null and is_instance_valid(automation_service):
		if automation_service.has_method("clear"):
			automation_service.call("clear")


func shutdown() -> void:
	if _shutdown:
		return
	_shutdown = true
	clear(&"shutdown")
	_disconnect_completion_signal(
		furnace_service,
		"item_smelted",
		Callable(self, "_on_item_smelted")
	)
	_disconnect_completion_signal(
		stonecutter_service,
		"item_processed",
		Callable(self, "_on_item_processed")
	)
	_disconnect_completion_signal(
		automation_service,
		"automation_machine_activated",
		Callable(self, "_on_machine_automation_activated")
	)
	if automation_service != null and automation_service.has_method("shutdown"):
		automation_service.call("shutdown")
	if interaction_router != null and interaction_router.has_method("shutdown"):
		interaction_router.call("shutdown")
	for service: Node in [stonecutter_service, furnace_service]:
		if service != null and is_instance_valid(service) and service.has_method("shutdown"):
			service.call("shutdown")
	if scheduler != null and scheduler.has_method("shutdown"):
		scheduler.call("shutdown")


func get_scheduler() -> Node:
	return scheduler


func get_furnace_service() -> Node:
	return furnace_service


func get_stonecutter_service() -> Node:
	return stonecutter_service


func get_interaction_router() -> Node:
	return interaction_router


func get_automation_service() -> Node:
	return automation_service


func get_lifecycle_snapshot() -> Dictionary:
	return {
		"installed": _installed,
		"active": _active,
		"shutdown": _shutdown,
		"scheduler_ready": scheduler != null and is_instance_valid(scheduler),
		"furnace_ready": furnace_service != null and is_instance_valid(furnace_service),
		"stonecutter_ready": (
			stonecutter_service != null and is_instance_valid(stonecutter_service)
		),
		"interaction_router_ready": (
			interaction_router != null and is_instance_valid(interaction_router)
		),
		"automation_ready": (
			automation_service != null and is_instance_valid(automation_service)
		),
		"registered_domain_count": (
			int(scheduler.call("get_snapshot").get("domain_count", 0))
			if scheduler != null and scheduler.has_method("get_snapshot")
			else 0
		),
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
	_queue_completion("furnace", machine_id, recipe_id, output)


func _on_item_processed(machine_id: String, recipe_id: String, output: Dictionary) -> void:
	_queue_completion("stonecutter", machine_id, recipe_id, output)


func _on_machine_automation_activated(summary: Dictionary) -> void:
	if not _active:
		return
	var machine_type := str(summary.get("machine_type", ""))
	var label := (
		"熔炉" if machine_type == "furnace"
		else "石材切割机" if machine_type == "stonecutter"
		else "机器"
	)
	var has_input := not str(summary.get("input_container_id", "")).is_empty()
	var has_output := not str(summary.get("output_container_id", "")).is_empty()
	var detail := (
		"上方供料，下方收货" if has_input and has_output
		else "上方箱子自动供料" if has_input
		else "下方箱子自动收货"
	)
	var message := "已启用%s相邻箱子自动化：%s" % [label, detail]
	_publish_message(
		message,
		"info",
		"machine_automation:%s" % str(summary.get("machine_id", machine_type)),
		3.2
	)
	var announced := summary.duplicate(true)
	announced["message"] = message
	machine_automation_announced.emit(announced)


func _queue_completion(
	machine_type: String,
	machine_id: String,
	recipe_id: String,
	output: Dictionary
) -> void:
	if not _active:
		return
	if _pending_completions.size() >= MAX_PENDING_COMPLETIONS:
		_dropped_completion_events += 1
		return
	_pending_completions.append({
		"machine_type": machine_type,
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
		_max_completions_in_batch,
		int(summary.get("completed_jobs", 0))
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
	message: String,
	severity: String,
	dedupe_key: String,
	duration: float
) -> void:
	if hub != null and hub.has_method("_publish_character_message"):
		hub.call("_publish_character_message", message, severity, dedupe_key, duration)


func _connect_completion_signal(
	service: Node, signal_name: String, callback: Callable
) -> void:
	if (
		service != null
		and is_instance_valid(service)
		and service.has_signal(signal_name)
		and not service.is_connected(signal_name, callback)
	):
		service.connect(signal_name, callback)


func _disconnect_completion_signal(
	service: Node, signal_name: String, callback: Callable
) -> void:
	if (
		service != null
		and is_instance_valid(service)
		and service.has_signal(signal_name)
		and service.is_connected(signal_name, callback)
	):
		service.disconnect(signal_name, callback)


func _rollback_install() -> void:
	if automation_service != null and is_instance_valid(automation_service):
		if automation_service.has_method("shutdown"):
			automation_service.call("shutdown")
		_dispose_service(automation_service)
	if interaction_router != null and is_instance_valid(interaction_router):
		if interaction_router.has_method("shutdown"):
			interaction_router.call("shutdown")
		_dispose_service(interaction_router)
	if scheduler != null and is_instance_valid(scheduler):
		if scheduler.has_method("shutdown"):
			scheduler.call("shutdown")
		_dispose_service(scheduler)
	if stonecutter_service != null and is_instance_valid(stonecutter_service):
		if stonecutter_service.has_method("shutdown"):
			stonecutter_service.call("shutdown")
		_dispose_service(stonecutter_service)
	automation_service = null
	interaction_router = null
	scheduler = null
	stonecutter_service = null


func _dispose_service(service: Node) -> void:
	if service == null or not is_instance_valid(service):
		return
	var parent := service.get_parent()
	if parent != null:
		parent.remove_child(service)
	service.queue_free()
