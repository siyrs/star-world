class_name RuntimeDiagnosticsCoordinator
extends Node

const TelemetryScript = preload("res://src/diagnostics/runtime_telemetry_service.gd")
const OverlayScript = preload("res://src/ui/diagnostics_overlay.gd")
const StreamingControllerScript = preload(
	"res://src/performance/adaptive_streaming_controller.gd"
)

var telemetry: Node
var overlay: CanvasLayer
var streaming_controller: Node
var _service_hub: Node


func configure(service_hub: Node) -> void:
	_service_hub = service_hub


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	telemetry = TelemetryScript.new()
	telemetry.name = "RuntimeTelemetry"
	add_child(telemetry)
	streaming_controller = StreamingControllerScript.new()
	streaming_controller.name = "AdaptiveStreaming"
	add_child(streaming_controller)
	overlay = OverlayScript.new()
	overlay.name = "DiagnosticsOverlay"
	add_child(overlay)
	var input_context: Node
	var creature_spawner: Node
	var gameplay_input: Node
	if _service_hub != null:
		input_context = _service_hub.get("input_context")
		creature_spawner = _service_hub.get("creature_spawner")
		gameplay_input = _service_hub.get("gameplay_input")
	streaming_controller.call("setup", telemetry)
	telemetry.call("setup", input_context, creature_spawner, streaming_controller)
	overlay.call("setup", telemetry, gameplay_input)


func attach_runtime(world: Node, player: Node3D) -> void:
	if streaming_controller != null:
		streaming_controller.call("attach_world", world)
	if telemetry != null:
		telemetry.call("attach_runtime", world, player)


func detach_runtime() -> void:
	if streaming_controller != null:
		streaming_controller.call("detach_world")
	if telemetry != null:
		telemetry.call("detach_runtime")


func sample_now() -> Dictionary:
	if telemetry == null:
		return {}
	return telemetry.call("sample_now")


func get_latest_snapshot() -> Dictionary:
	if telemetry == null:
		return {}
	return telemetry.call("get_latest_snapshot")


func get_adaptive_streaming_status() -> Dictionary:
	if streaming_controller == null:
		return {}
	return streaming_controller.call("get_status")


func set_adaptive_streaming_enabled(enabled: bool) -> void:
	if streaming_controller != null:
		streaming_controller.call("set_controller_enabled", enabled)


func write_report(path: String) -> bool:
	return telemetry != null and bool(telemetry.call("write_report", path))
