class_name ExplorationProgressionServiceHub
extends "res://src/ui/ranch_progression_service_hub.gd"

const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingStateMigrationScript = preload(
	"res://src/exploration/prospecting_state_migration.gd"
)
const DangerServiceScript = preload(
	"res://src/exploration/exploration_danger_service.gd"
)
const FeatureCoordinatorScript = preload(
	"res://src/core/service_hub_feature_coordinator.gd"
)
const JournalRewardParticipantScript = preload(
	"res://src/exploration/exploration_journal_reward_participant.gd"
)
const JOURNAL_REWARD_FEATURE := &"exploration_journal_rewards"

var prospecting_service: Node
var exploration_danger_service: Node
var exploration_journal_service: Node
var exploration_reward_service: Node
var feature_lifecycle: Node
var exploration_journal_reward_participant: Node
var _last_announced_danger_tier := ""


func _ready() -> void:
	super._ready()
	exploration_danger_service = _add_service(
		DangerServiceScript.new(), "ExplorationDangerService"
	)
	exploration_danger_service.call("setup", day_night, creature_spawner)
	exploration_danger_service.connect(
		"danger_changed", Callable(self, "_on_exploration_danger_changed")
	)
	prospecting_service = _add_service(
		ProspectingServiceScript.new(), "ProspectingService"
	)
	prospecting_service.call(
		"setup", inventory.registry, exploration_danger_service, day_night
	)
	prospecting_service.connect("scan_completed", Callable(self, "_on_prospecting_completed"))
	prospecting_service.connect("scan_rejected", Callable(self, "_on_prospecting_rejected"))
	feature_lifecycle = _add_service(
		FeatureCoordinatorScript.new(), "FeatureLifecycle"
	)
	feature_lifecycle.call("setup", self)
	var registration: Dictionary = feature_lifecycle.call(
		"register_participant",
		JOURNAL_REWARD_FEATURE,
		JournalRewardParticipantScript.new()
	)
	if bool(registration.get("success", false)):
		exploration_journal_reward_participant = registration.get("participant") as Node
		exploration_journal_service = exploration_journal_reward_participant.call(
			"get_journal_service"
		)
		exploration_reward_service = exploration_journal_reward_participant.call(
			"get_reward_service"
		)
	else:
		push_error(
			"Unable to install exploration journal/reward lifecycle participant: %s"
			% str(registration.get("reason", "unknown"))
		)
	if game_ui != null and game_ui.get("hud") != null and game_ui.hud.has_method("setup_danger"):
		game_ui.hud.call("setup_danger", exploration_danger_service)


func _begin_world(state: Dictionary) -> void:
	var migrated_state := ProspectingStateMigrationScript.normalize_world_state(state)
	var metadata: Dictionary = migrated_state.get("metadata", {})
	var map_id := str(metadata.get("map_id", "star_continent"))
	if creature_spawner != null and creature_spawner.has_method("set_map_profile"):
		creature_spawner.call("set_map_profile", map_id)
	if exploration_danger_service != null:
		exploration_danger_service.call("deactivate")
	_last_announced_danger_tier = ""
	if prospecting_service != null:
		prospecting_service.call("deserialize", migrated_state.get("exploration", {}))
	if feature_lifecycle != null:
		feature_lifecycle.call("begin_world", migrated_state)
	super._begin_world(migrated_state)


func attach_game(
	world,
	player: Node3D,
	sun: DirectionalLight3D = null,
	environment: WorldEnvironment = null,
	ground_resolver: Callable = Callable()
) -> void:
	super.attach_game(world, player, sun, environment, ground_resolver)
	if exploration_danger_service != null:
		exploration_danger_service.call("attach_world", world, player)
	if prospecting_service != null:
		prospecting_service.call("attach_world", world, player)
	if player != null and player.has_method("bind_prospecting_service"):
		player.call("bind_prospecting_service", prospecting_service)
	if feature_lifecycle != null:
		feature_lifecycle.call(
			"attach_game", world, player, sun, environment, ground_resolver
		)


func activate_gameplay() -> void:
	super.activate_gameplay()
	if exploration_danger_service != null:
		exploration_danger_service.call("activate")
	if feature_lifecycle != null:
		feature_lifecycle.call("activate")


func save_current(world_state: Dictionary = {}, player_state: Dictionary = {}) -> bool:
	if prospecting_service != null:
		current_state["exploration"] = prospecting_service.call("serialize")
	if feature_lifecycle != null:
		feature_lifecycle.call("save_into", current_state)
	return super.save_current(world_state, player_state)


func handle_world_start_failed(reason: String) -> void:
	if feature_lifecycle != null:
		feature_lifecycle.call("clear", &"world_start_failed")
	_clear_exploration_runtime()
	super.handle_world_start_failed(reason)


func return_to_menu() -> void:
	super.return_to_menu()
	if current_world_id.is_empty():
		if feature_lifecycle != null:
			feature_lifecycle.call("clear", &"return_to_menu")
		_clear_exploration_runtime()


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["exploration"] = (
		prospecting_service.call("get_snapshot") if prospecting_service != null else {}
	)
	snapshot["danger"] = (
		exploration_danger_service.call("get_snapshot")
		if exploration_danger_service != null
		else {}
	)
	snapshot["ecology"] = (
		creature_spawner.call("get_ecology_snapshot")
		if creature_spawner != null and creature_spawner.has_method("get_ecology_snapshot")
		else {}
	)
	if feature_lifecycle != null:
		feature_lifecycle.call("snapshot_into", snapshot)
		snapshot["feature_lifecycle"] = feature_lifecycle.call("get_snapshot")
	return snapshot


func _exit_tree() -> void:
	if feature_lifecycle != null and feature_lifecycle.has_method("shutdown"):
		feature_lifecycle.call("shutdown")
	_clear_exploration_runtime()
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


func _on_exploration_danger_changed(snapshot: Dictionary) -> void:
	var tier_id := str(snapshot.get("tier_id", "safe"))
	if tier_id == _last_announced_danger_tier:
		return
	_last_announced_danger_tier = tier_id
	if tier_id not in ["dangerous", "severe"]:
		return
	_publish_character_message(
		str(snapshot.get("message", "当前区域危险度上升")),
		"error" if tier_id == "severe" else "warning",
		"danger_tier:%s" % tier_id,
		3.4
	)


func _clear_exploration_runtime() -> void:
	_last_announced_danger_tier = ""
	if exploration_danger_service != null and exploration_danger_service.has_method("clear"):
		exploration_danger_service.call("clear")
	if prospecting_service != null and prospecting_service.has_method("clear"):
		prospecting_service.call("clear")
