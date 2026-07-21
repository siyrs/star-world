class_name ToolProgressionServiceHub
extends "res://src/ui/service_hub.gd"

const ToolServiceScript = preload("res://src/tools/tool_service.gd")
const HarvestServiceScript = preload("res://src/harvest/block_harvest_service.gd")
const HarvestOverlayScript = preload("res://src/ui/harvest_progress_overlay.gd")
const MachineAutomationServiceScript = preload(
	"res://src/machine/machine_automation_service.gd"
)
const MACHINE_AUTOMATION_DOMAIN := &"automation"

# Compatibility ports are declared on the first inherited layer so the base
# MachineRuntimeParticipant can publish them during GameplayServiceHub._ready.
var stonecutter_service: Node
var machine_interaction_router: Node
var machine_automation_service: Node
var tool_service: Node
var block_harvest_service: Node
var harvest_progress_overlay: Control


func _ready() -> void:
	super._ready()
	_configure_machine_runtime_ports()
	_setup_machine_automation()
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
	if machine_automation_service != null:
		machine_automation_service.call("clear")
	super._begin_world(state)


func handle_world_start_failed(reason: String) -> void:
	_clear_harvest_state()
	if machine_automation_service != null:
		machine_automation_service.call("clear")
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
	if machine_automation_service != null:
		machine_automation_service.call("attach_world", world)
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
		if machine_automation_service != null:
			machine_automation_service.call("clear")


func _exit_tree() -> void:
	_shutdown_machine_automation()
	_clear_harvest_state()
	super._exit_tree()


func get_machine_automation_service() -> Node:
	return machine_automation_service


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


func _setup_machine_automation() -> void:
	if (
		machine_runtime == null
		or not is_instance_valid(machine_runtime)
		or machine_interaction_router == null
		or not is_instance_valid(machine_interaction_router)
		or container_storage == null
		or not machine_runtime.has_method("register_domain")
	):
		push_error("Unable to compose bounded machine automation")
		return
	machine_automation_service = _add_service(
		MachineAutomationServiceScript.new(), "MachineAutomationService"
	)
	if not bool(machine_automation_service.call(
		"setup", machine_interaction_router, container_storage
	)):
		push_error("Unable to initialize bounded machine automation")
		machine_automation_service.queue_free()
		machine_automation_service = null
		return
	var registration: Dictionary = machine_runtime.call(
		"register_domain", MACHINE_AUTOMATION_DOMAIN, machine_automation_service
	)
	if not bool(registration.get("success", false)):
		push_error(
			"Unable to register bounded machine automation: %s"
			% str(registration.get("reason", "unknown"))
		)
		machine_automation_service.call("shutdown")
		machine_automation_service.queue_free()
		machine_automation_service = null
		return
	var callback := Callable(self, "_on_machine_automation_activated")
	if not machine_automation_service.is_connected(
		"automation_machine_activated", callback
	):
		machine_automation_service.connect("automation_machine_activated", callback)


func _shutdown_machine_automation() -> void:
	if machine_automation_service == null or not is_instance_valid(machine_automation_service):
		return
	var callback := Callable(self, "_on_machine_automation_activated")
	if machine_automation_service.is_connected("automation_machine_activated", callback):
		machine_automation_service.disconnect("automation_machine_activated", callback)
	if machine_runtime != null and is_instance_valid(machine_runtime):
		if machine_runtime.has_method("unregister_domain"):
			machine_runtime.call("unregister_domain", MACHINE_AUTOMATION_DOMAIN)
	machine_automation_service.call("shutdown")
	machine_automation_service = null


func _on_machine_automation_activated(summary: Dictionary) -> void:
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
	_publish_character_message(
		"已启用%s相邻箱子自动化：%s" % [label, detail],
		"info",
		"machine_automation:%s" % str(summary.get("machine_id", machine_type)),
		3.2
	)


func _clear_harvest_state() -> void:
	if block_harvest_service != null and block_harvest_service.has_method("clear"):
		block_harvest_service.call("clear")
	if harvest_progress_overlay != null and harvest_progress_overlay.has_method("clear"):
		harvest_progress_overlay.call("clear")
