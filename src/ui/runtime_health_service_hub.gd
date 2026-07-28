class_name RuntimeHealthServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const RuntimeHealthReportServiceScript = preload(
	"res://src/diagnostics/session_scoped_runtime_health_report_service.gd"
)
const SaveTimelinePolicyScript = preload(
	"res://src/save/save_checkpoint_timeline_policy.gd"
)

var runtime_health_report_service: Node
var _save_reason_context: StringName = SaveTimelinePolicyScript.REASON_MANUAL


func _ready() -> void:
	super._ready()
	runtime_health_report_service = _add_service(
		RuntimeHealthReportServiceScript.new(), "RuntimeHealthReport"
	)
	if runtime_health_report_service != null:
		runtime_health_report_service.call("setup", self)


func _begin_world(state: Dictionary) -> void:
	if runtime_health_report_service != null:
		var metadata: Dictionary = state.get("metadata", {})
		runtime_health_report_service.call("begin_world", str(metadata.get("id", "")))
	super._begin_world(state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if runtime_health_report_service != null:
		runtime_health_report_service.call("attach_runtime", world)


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	var world_id := current_world_id
	var reason := _resolve_save_reason()
	var started_at := Time.get_ticks_usec()
	var saved := super.save_current(world_state, player_state)
	if runtime_health_report_service != null:
		runtime_health_report_service.call(
			"record_save_result",
			world_id,
			saved,
			Time.get_ticks_usec() - started_at,
			-1,
			reason
		)
	return saved


func save_current_with_reason(
	reason: StringName,
	world_state: Dictionary = {},
	player_state: Dictionary = {}
) -> bool:
	var previous_reason := _save_reason_context
	_save_reason_context = SaveTimelinePolicyScript.normalize_reason(reason)
	var saved := save_current(world_state, player_state)
	_save_reason_context = previous_reason
	return saved


func handle_world_start_failed(reason: String) -> void:
	super.handle_world_start_failed(reason)
	if runtime_health_report_service != null:
		runtime_health_report_service.call("detach_runtime")
		runtime_health_report_service.call("end_world")


func return_to_menu() -> void:
	# The authoritative return path may refuse to leave gameplay when its final
	# save fails. Preserve both the world identity and diagnostics in that case.
	var previous_reason := _save_reason_context
	_save_reason_context = SaveTimelinePolicyScript.REASON_RETURN_TO_MENU
	super.return_to_menu()
	_save_reason_context = previous_reason
	if current_world_id.is_empty() and runtime_health_report_service != null:
		runtime_health_report_service.call("detach_runtime")
		runtime_health_report_service.call("end_world")


func get_runtime_health_snapshot() -> Dictionary:
	if (
		runtime_health_report_service == null
		or not runtime_health_report_service.has_method("get_snapshot")
	):
		return {}
	return runtime_health_report_service.call("get_snapshot")


func get_save_checkpoint_timeline_snapshot() -> Dictionary:
	if (
		runtime_health_report_service == null
		or not runtime_health_report_service.has_method("get_save_timeline_snapshot")
	):
		return {}
	return runtime_health_report_service.call("get_save_timeline_snapshot")


func _resolve_save_reason() -> StringName:
	var contextual := SaveTimelinePolicyScript.normalize_reason(_save_reason_context)
	if contextual != SaveTimelinePolicyScript.REASON_MANUAL:
		return contextual
	var autosave := _property_node(&"autosave_runtime_participant")
	if autosave != null and autosave.has_method("get_snapshot"):
		var raw_snapshot: Variant = autosave.call("get_snapshot")
		if raw_snapshot is Dictionary and bool(raw_snapshot.get("saving", false)):
			return SaveTimelinePolicyScript.REASON_AUTOSAVE
	return SaveTimelinePolicyScript.REASON_MANUAL


func _property_node(property_name: StringName) -> Node:
	for property: Dictionary in get_property_list():
		if str(property.get("name", "")) != str(property_name):
			continue
		var value: Variant = get(property_name)
		return value as Node if value is Node and is_instance_valid(value) else null
	return null


func _exit_tree() -> void:
	if (
		runtime_health_report_service != null
		and runtime_health_report_service.has_method("shutdown")
	):
		runtime_health_report_service.call("shutdown")
	super._exit_tree()
