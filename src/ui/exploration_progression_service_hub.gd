class_name ExplorationProgressionServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingStateMigrationScript = preload(
	"res://src/exploration/prospecting_state_migration.gd"
)

var prospecting_service: Node


func _ready() -> void:
	super._ready()
	prospecting_service = _add_service(
		ProspectingServiceScript.new(), "ProspectingService"
	)
	prospecting_service.call("setup", inventory.registry)
	prospecting_service.connect("scan_completed", Callable(self, "_on_prospecting_completed"))
	prospecting_service.connect("scan_rejected", Callable(self, "_on_prospecting_rejected"))


func _begin_world(state: Dictionary) -> void:
	var migrated_state := ProspectingStateMigrationScript.normalize_world_state(state)
	if prospecting_service != null:
		prospecting_service.call("deserialize", migrated_state.get("exploration", {}))
	super._begin_world(migrated_state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if prospecting_service != null:
		prospecting_service.call("attach_world", world, player)
	if player != null and player.has_method("bind_prospecting_service"):
		player.call("bind_prospecting_service", prospecting_service)


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if prospecting_service != null:
		current_state["exploration"] = prospecting_service.call("serialize")
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	_clear_exploration_state()
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		_clear_exploration_state()


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["exploration"] = (
		prospecting_service.call("get_snapshot") if prospecting_service != null else {}
	)
	return snapshot


func _exit_tree() -> void:
	_clear_exploration_state()
	super._exit_tree()


func _on_prospecting_completed(result: Dictionary) -> void:
	_publish_character_message(
		str(result.get("message", "区域勘探完成")),
		"success",
		"prospecting:%s" % str(result.get("record_key", "area")),
		3.8
	)
	if audio_service != null and audio_service.has_method("play_ui"):
		audio_service.call("play_ui")


func _on_prospecting_rejected(reason: String, context: Dictionary) -> void:
	_publish_character_message(
		str(context.get("message", "暂时无法勘探")),
		"warning",
		"prospecting_rejected:%s" % reason,
		2.4
	)


func _clear_exploration_state() -> void:
	if prospecting_service != null and prospecting_service.has_method("clear"):
		prospecting_service.call("clear")
