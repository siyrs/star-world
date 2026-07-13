class_name ToolProgressionServiceHub
extends "res://src/ui/service_hub.gd"

const ToolServiceScript = preload("res://src/tools/tool_service.gd")
const HarvestServiceScript = preload("res://src/harvest/block_harvest_service.gd")
const HarvestOverlayScript = preload("res://src/ui/harvest_progress_overlay.gd")

var tool_service: Node
var block_harvest_service: Node
var harvest_progress_overlay: Control


func _ready() -> void:
	super._ready()
	tool_service = _add_service(ToolServiceScript.new(), "ToolService")
	tool_service.call("setup", inventory.registry)
	block_harvest_service = _add_service(HarvestServiceScript.new(), "BlockHarvestService")
	block_harvest_service.call("setup", tool_service, block_interaction)
	harvest_progress_overlay = HarvestOverlayScript.new()
	harvest_progress_overlay.name = "HarvestProgressOverlay"
	if game_ui != null:
		game_ui.add_child(harvest_progress_overlay)
	else:
		add_child(harvest_progress_overlay)
	harvest_progress_overlay.call(
		"setup", block_harvest_service, tool_service, player_experience
	)


func _begin_world(state: Dictionary) -> void:
	_clear_harvest_state()
	super._begin_world(state)


func handle_world_start_failed(reason: String) -> void:
	_clear_harvest_state()
	super.handle_world_start_failed(reason)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if player == null:
		return
	if player.has_method("bind_tool_service"):
		player.call("bind_tool_service", tool_service)
	if player.has_method("bind_harvest_service"):
		player.call("bind_harvest_service", block_harvest_service)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_harvest_state()


func _exit_tree() -> void:
	_clear_harvest_state()


func _clear_harvest_state() -> void:
	if block_harvest_service != null and block_harvest_service.has_method("clear"):
		block_harvest_service.call("clear")
	if harvest_progress_overlay != null and harvest_progress_overlay.has_method("clear"):
		harvest_progress_overlay.call("clear")
