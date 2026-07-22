class_name ScalableMachineRuntimeParticipant
extends "res://src/machine/machine_runtime_participant.gd"

const ScaleCompletionPolicyScript = preload(
	"res://src/machine/scalable_machine_completion_policy.gd"
)
const ScaleStonecutterServiceScript = preload(
	"res://src/machine/scalable_stonecutter_service.gd"
)
const ScaleAutomationServiceScript = preload(
	"res://src/machine/scalable_machine_automation_service.gd"
)
const ScaleSchedulerScript = preload(
	"res://src/machine/machine_runtime_scheduler.gd"
)
const ScaleInteractionRouterScript = preload(
	"res://src/machine/machine_interaction_router.gd"
)
const MAX_COMPLETION_EVENT_SAMPLES := 64
const MAX_TRACKED_COMPLETION_MACHINES := 4096
const MAX_TRACKED_COMPLETION_RECIPES := 256
const MAX_TRACKED_COMPLETION_OUTPUT_TYPES := 64
const MAX_TRACKED_COMPLETION_MACHINE_TYPES := 16

var _pending_completion_job_count := 0
var _pending_completion_item_total := 0
var _pending_completion_output_counts: Dictionary = {}
var _pending_completion_machine_ids: Dictionary = {}
var _pending_completion_recipe_ids: Dictionary = {}
var _pending_completion_machine_types: Dictionary = {}
var _pending_unclassified_completion_jobs := 0
var _pending_unclassified_completion_items := 0
var _pending_dropped_completion_samples := 0
var _dropped_completion_sample_count := 0


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
		ScaleStonecutterServiceScript.new(),
		"StonecutterService"
	) as Node
	if (
		stonecutter_service == null
		or not bool(stonecutter_service.call("setup", item_registry))
	):
		_dispose_service(stonecutter_service)
		stonecutter_service = null
		return false
	scheduler = hub.call(
		"_add_service", ScaleSchedulerScript.new(), "MachineRuntime"
	) as Node
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
		ScaleInteractionRouterScript.new(),
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
		ScaleAutomationServiceScript.new(),
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


func begin_world(state: Dictionary) -> void:
	_reset_completion_runtime()
	super.begin_world(state)


func clear(reason: StringName = &"clear") -> void:
	super.clear(reason)
	_reset_completion_runtime()


func get_lifecycle_snapshot() -> Dictionary:
	var result: Dictionary = super.get_lifecycle_snapshot()
	result["pending_completion_count"] = _pending_completion_job_count
	result["pending_completion_sample_count"] = _pending_completions.size()
	result["pending_completion_output_types"] = _pending_completion_output_counts.size()
	result["pending_completion_machine_count"] = _pending_completion_machine_ids.size()
	result["pending_completion_recipe_count"] = _pending_completion_recipe_ids.size()
	result["pending_dropped_completion_samples"] = _pending_dropped_completion_samples
	result["dropped_completion_sample_count"] = _dropped_completion_sample_count
	result["completion_event_sample_limit"] = MAX_COMPLETION_EVENT_SAMPLES
	result["tracked_completion_machine_limit"] = MAX_TRACKED_COMPLETION_MACHINES
	result["tracked_completion_recipe_limit"] = MAX_TRACKED_COMPLETION_RECIPES
	result["tracked_completion_output_type_limit"] = MAX_TRACKED_COMPLETION_OUTPUT_TYPES
	result["tracked_completion_machine_type_limit"] = MAX_TRACKED_COMPLETION_MACHINE_TYPES
	return result


func flush_pending_completion_batch() -> Dictionary:
	_flush_completion_batch()
	return _last_completion_summary.duplicate(true)


func _queue_completion(
	machine_type: String,
	machine_id: String,
	recipe_id: String,
	output: Dictionary
) -> void:
	if not _active:
		return
	var item_id := str(output.get("item_id", "")).strip_edges()
	var count := maxi(0, int(output.get("count", 0)))
	if item_id.is_empty() or count <= 0:
		_dropped_completion_events += 1
		return
	_pending_completion_job_count += 1
	_pending_completion_item_total += count
	if _pending_completion_output_counts.has(item_id):
		_pending_completion_output_counts[item_id] = (
			int(_pending_completion_output_counts[item_id]) + count
		)
	elif _pending_completion_output_counts.size() < MAX_TRACKED_COMPLETION_OUTPUT_TYPES:
		_pending_completion_output_counts[item_id] = count
	else:
		_pending_unclassified_completion_jobs += 1
		_pending_unclassified_completion_items += count
	var normalized_machine_id := machine_id.strip_edges()
	if (
		not normalized_machine_id.is_empty()
		and (
			_pending_completion_machine_ids.has(normalized_machine_id)
			or _pending_completion_machine_ids.size() < MAX_TRACKED_COMPLETION_MACHINES
		)
	):
		_pending_completion_machine_ids[normalized_machine_id] = true
	var normalized_recipe_id := recipe_id.strip_edges()
	if (
		not normalized_recipe_id.is_empty()
		and (
			_pending_completion_recipe_ids.has(normalized_recipe_id)
			or _pending_completion_recipe_ids.size() < MAX_TRACKED_COMPLETION_RECIPES
		)
	):
		_pending_completion_recipe_ids[normalized_recipe_id] = true
	var normalized_machine_type := machine_type.strip_edges()
	if (
		not normalized_machine_type.is_empty()
		and (
			_pending_completion_machine_types.has(normalized_machine_type)
			or _pending_completion_machine_types.size()
			< MAX_TRACKED_COMPLETION_MACHINE_TYPES
		)
	):
		_pending_completion_machine_types[normalized_machine_type] = true
	if _pending_completions.size() < MAX_COMPLETION_EVENT_SAMPLES:
		_pending_completions.append({
			"machine_type": normalized_machine_type,
			"machine_id": normalized_machine_id,
			"recipe_id": normalized_recipe_id,
			"output": output.duplicate(true),
		})
	else:
		_pending_dropped_completion_samples += 1
		_dropped_completion_sample_count += 1
	if not _completion_flush_scheduled:
		_completion_flush_scheduled = true
		call_deferred("_flush_completion_batch")


func _flush_completion_batch() -> void:
	_completion_flush_scheduled = false
	if not _active or _pending_completion_job_count <= 0:
		_reset_completion_batch()
		return
	var output_counts := _pending_completion_output_counts.duplicate(true)
	var machine_types := _pending_completion_machine_types.duplicate(true)
	var completed_jobs := _pending_completion_job_count
	var item_total := _pending_completion_item_total
	var machine_count := _pending_completion_machine_ids.size()
	var recipe_count := _pending_completion_recipe_ids.size()
	var sampled_events := _pending_completions.size()
	var dropped_samples := _pending_dropped_completion_samples
	var unclassified_jobs := _pending_unclassified_completion_jobs
	var unclassified_items := _pending_unclassified_completion_items
	_reset_completion_batch()
	var item_registry: Variant = null
	var inventory: Node = hub.get("inventory") as Node if hub != null else null
	if inventory != null:
		item_registry = inventory.get("registry")
	var summary: Dictionary = ScaleCompletionPolicyScript.build_counts(
		output_counts,
		completed_jobs,
		item_total,
		machine_count,
		machine_types,
		recipe_count,
		item_registry,
		sampled_events,
		dropped_samples,
		unclassified_jobs,
		unclassified_items
	)
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
	super._reset_completion_batch()
	_pending_completion_job_count = 0
	_pending_completion_item_total = 0
	_pending_completion_output_counts.clear()
	_pending_completion_machine_ids.clear()
	_pending_completion_recipe_ids.clear()
	_pending_completion_machine_types.clear()
	_pending_unclassified_completion_jobs = 0
	_pending_unclassified_completion_items = 0
	_pending_dropped_completion_samples = 0


func _reset_completion_runtime() -> void:
	_reset_completion_batch()
	_dropped_completion_events = 0
	_completion_batch_count = 0
	_completed_job_count = 0
	_completed_item_count = 0
	_completion_audio_count = 0
	_max_completions_in_batch = 0
	_last_completion_summary.clear()
	_dropped_completion_sample_count = 0
