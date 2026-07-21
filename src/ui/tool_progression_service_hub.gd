class_name ToolProgressionServiceHub
extends "res://src/ui/service_hub.gd"

const ToolServiceScript = preload("res://src/tools/tool_service.gd")
const HarvestServiceScript = preload("res://src/harvest/block_harvest_service.gd")
const HarvestOverlayScript = preload("res://src/ui/harvest_progress_overlay.gd")
const DoorInteractionServiceScript = preload(
	"res://src/interaction/block_door_interaction_service.gd"
)

# Compatibility ports are declared on the first inherited layer so the base
# MachineRuntimeParticipant can publish them during GameplayServiceHub._ready.
var stonecutter_service: Node
var machine_interaction_router: Node
var machine_automation_service: Node
var tool_service: Node
var block_harvest_service: Node
var door_interaction_service: Node
var harvest_progress_overlay: Control


func _ready() -> void:
	super._ready()
	_configure_machine_runtime_ports()
	tool_service = _add_service(ToolServiceScript.new(), "ToolService")
	tool_service.call("setup", inventory.registry)
	door_interaction_service = _add_service(
		DoorInteractionServiceScript.new(), "DoorInteraction"
	)
	if block_interaction != null and block_interaction.has_method("register_extension"):
		block_interaction.call("register_extension", door_interaction_service)
	_connect_door_feedback()
	block_harvest_service = _add_service(HarvestServiceScript.new(), "BlockHarvestService")
	block_harvest_service.call(
		"setup", tool_service, block_interaction, door_interaction_service
	)
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
	# GameplayServiceHub retains its legacy furnace fallback; restore the generic
	# production router after every world bind.
	_configure_machine_runtime_ports()
	if player == null:
		return
	if player.has_method("bind_tool_service"):
		player.call("bind_tool_service", tool_service)
	if player.has_method("bind_harvest_service"):
		player.call("bind_harvest_service", block_harvest_service)
	if player.has_method("bind_block_structure_service"):
		player.call("bind_block_structure_service", door_interaction_service)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_harvest_state()


func _exit_tree() -> void:
	if (
		block_interaction != null
		and door_interaction_service != null
		and block_interaction.has_method("unregister_extension")
	):
		block_interaction.call("unregister_extension", door_interaction_service)
	if door_interaction_service != null and door_interaction_service.has_method("shutdown"):
		door_interaction_service.call("shutdown")
	_clear_harvest_state()
	super._exit_tree()


func _configure_machine_runtime_ports() -> void:
	if (
		machine_interaction_router != null
		and machine_interaction_router.has_method("setup_ui")
	):
		machine_interaction_router.call("setup_ui", game_ui)
	if game_ui != null and game_ui.has_method("setup_machine_runtime"):
		game_ui.call("setup_machine_runtime", stonecutter_service)
	if block_interaction != null and block_interaction.has_method("set_machine_access"):
		block_interaction.call(
			"set_machine_access",
			machine_interaction_router
			if machine_interaction_router != null
			else furnace_service
		)


func _connect_door_feedback() -> void:
	if door_interaction_service == null:
		return
	if door_interaction_service.has_signal("door_toggled"):
		door_interaction_service.connect(
			"door_toggled", Callable(self, "_on_door_toggled")
		)


func _on_door_toggled(
	_opened: bool,
	_lower_position: Vector3i,
	_lower_block_id: String
) -> void:
	if audio_service != null and audio_service.has_method("play_block_place"):
		audio_service.call("play_block_place", "oak_door")


func _clear_harvest_state() -> void:
	if block_harvest_service != null and block_harvest_service.has_method("clear"):
		block_harvest_service.call("clear")
	if door_interaction_service != null and door_interaction_service.has_method("clear"):
		door_interaction_service.call("clear")
	if harvest_progress_overlay != null and harvest_progress_overlay.has_method("clear"):
		harvest_progress_overlay.call("clear")
