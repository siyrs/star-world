class_name RuntimeDiagnosticsCoordinator
extends Node

const TelemetryScript = preload("res://src/diagnostics/runtime_telemetry_service.gd")
const OverlayScript = preload("res://src/ui/diagnostics_overlay.gd")

var telemetry: Node
var overlay: CanvasLayer
var _service_hub: Node


func configure(service_hub: Node) -> void:
	_service_hub = service_hub


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	telemetry = TelemetryScript.new()
	telemetry.name = "RuntimeTelemetry"
	add_child(telemetry)
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
	telemetry.call("setup", input_context, creature_spawner)
	overlay.call("setup", telemetry, gameplay_input)


func attach_runtime(world: Node, player: Node3D) -> void:
	if telemetry != null:
		telemetry.call("attach_runtime", world, player)


func detach_runtime() -> void:
	if telemetry != null:
		telemetry.call("detach_runtime")


func get_latest_snapshot() -> Dictionary:
	if telemetry == null:
		return {}
	return telemetry.call("get_latest_snapshot")


func write_report(path: String) -> bool:
	return telemetry != null and bool(telemetry.call("write_report", path))
