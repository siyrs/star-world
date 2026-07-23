class_name RuntimeHealthServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const RuntimeHealthReportServiceScript = preload(
	"res://src/diagnostics/runtime_health_report_service.gd"
)

var runtime_health_report_service: Node


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
	var started_at := Time.get_ticks_usec()
	var saved := super.save_current(world_state, player_state)
	if runtime_health_report_service != null:
		runtime_health_report_service.call(
			"record_save_result",
			world_id,
			saved,
			Time.get_ticks_usec() - started_at
		)
	return saved


func handle_world_start_failed(reason: String) -> void:
	if runtime_health_report_service != null:
		runtime_health_report_service.call("detach_runtime")
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	if runtime_health_report_service != null:
		runtime_health_report_service.call("detach_runtime")
	super.return_to_menu()


func get_runtime_health_snapshot() -> Dictionary:
	if (
		runtime_health_report_service == null
		or not runtime_health_report_service.has_method("get_snapshot")
	):
		return {}
	return runtime_health_report_service.call("get_snapshot")


func _exit_tree() -> void:
	if (
		runtime_health_report_service != null
		and runtime_health_report_service.has_method("shutdown")
	):
		runtime_health_report_service.call("shutdown")
	super._exit_tree()
