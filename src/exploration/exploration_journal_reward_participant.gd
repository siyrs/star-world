class_name ExplorationJournalRewardParticipant
extends Node

signal claimable_reward_announced(milestone_ids: Array[String], snapshot: Dictionary)

const JournalServiceScript = preload(
	"res://src/exploration/exploration_journal_service.gd"
)
const RewardServiceScript = preload(
	"res://src/exploration/exploration_milestone_reward_service.gd"
)

var hub: Node
var journal_service: Node
var reward_service: Node
var _active := false
var _known_claimable: Dictionary = {}
var _announcement_count := 0
var _installed := false


func get_dependencies() -> Array[StringName]:
	return [&"exploration_runtime"]


func install(p_hub: Node) -> bool:
	if _installed or p_hub == null or not is_instance_valid(p_hub):
		return false
	hub = p_hub
	var prospecting: Node = hub.get("prospecting_service")
	var inventory: Node = hub.get("inventory")
	if (
		prospecting == null
		or inventory == null
		or not hub.has_method("_add_service")
	):
		return false
	journal_service = hub.call(
		"_add_service", JournalServiceScript.new(), "ExplorationJournalService"
	)
	if journal_service == null or not bool(journal_service.call("setup", prospecting)):
		return false
	reward_service = hub.call(
		"_add_service",
		RewardServiceScript.new(),
		"ExplorationMilestoneRewardService"
	)
	if reward_service == null or not bool(reward_service.call("setup", inventory, journal_service)):
		return false
	_connect_reward_signals()
	var game_ui: Node = hub.get("game_ui")
	if game_ui != null and game_ui.has_method("setup_exploration_journal"):
		game_ui.call("setup_exploration_journal", journal_service, reward_service)
	_installed = true
	_sync_claimable_baseline(reward_service.call("get_snapshot"))
	return true


func begin_world(state: Dictionary) -> void:
	_active = false
	_known_claimable.clear()
	if journal_service != null:
		journal_service.call("refresh")
	if reward_service != null:
		var metadata: Dictionary = state.get("metadata", {})
		var map_id := str(metadata.get("map_id", "star_continent"))
		reward_service.call("set_profile", map_id)
		reward_service.call("deserialize", state.get("exploration_rewards", {}))
		_sync_claimable_baseline(reward_service.call("get_snapshot"))


func attach_game(
	_world,
	_player: Node3D,
	_sun: DirectionalLight3D = null,
	_environment: WorldEnvironment = null,
	_ground_resolver: Callable = Callable()
) -> void:
	pass


func activate() -> void:
	_active = true
	if reward_service != null:
		_sync_claimable_baseline(reward_service.call("get_snapshot"))


func save_into(payload: Dictionary) -> void:
	if reward_service != null:
		payload["exploration_rewards"] = reward_service.call("serialize")


func snapshot_into(snapshot: Dictionary) -> void:
	snapshot["exploration_journal"] = (
		journal_service.call("get_snapshot") if journal_service != null else {}
	)
	snapshot["exploration_rewards"] = (
		reward_service.call("get_snapshot") if reward_service != null else {}
	)


func clear(_reason: StringName = &"clear") -> void:
	_active = false
	_known_claimable.clear()
	if journal_service != null and journal_service.has_method("clear"):
		journal_service.call("clear")
	if reward_service != null and reward_service.has_method("clear"):
		reward_service.call("clear")


func shutdown() -> void:
	_active = false
	_disconnect_reward_signals()
	var game_ui: Node = hub.get("game_ui") if hub != null and is_instance_valid(hub) else null
	if game_ui != null and game_ui.has_method("setup_exploration_journal"):
		game_ui.call("setup_exploration_journal", null, null)
	_known_claimable.clear()


func get_journal_service() -> Node:
	return journal_service


func get_reward_service() -> Node:
	return reward_service


func get_lifecycle_snapshot() -> Dictionary:
	var claimable_ids: Array[String] = []
	for raw_id: Variant in _known_claimable.keys():
		claimable_ids.append(str(raw_id))
	claimable_ids.sort()
	return {
		"installed": _installed,
		"active": _active,
		"journal_ready": journal_service != null and is_instance_valid(journal_service),
		"reward_ready": reward_service != null and is_instance_valid(reward_service),
		"known_claimable_ids": claimable_ids,
		"announcement_count": _announcement_count,
	}


func _connect_reward_signals() -> void:
	if reward_service == null:
		return
	_connect_if_needed("reward_claimed", Callable(self, "_on_reward_claimed"))
	_connect_if_needed("reward_rejected", Callable(self, "_on_reward_rejected"))
	_connect_if_needed("rewards_changed", Callable(self, "_on_rewards_changed"))


func _connect_if_needed(signal_name: String, callback: Callable) -> void:
	if (
		reward_service.has_signal(signal_name)
		and not reward_service.is_connected(signal_name, callback)
	):
		reward_service.connect(signal_name, callback)


func _disconnect_reward_signals() -> void:
	if reward_service == null or not is_instance_valid(reward_service):
		return
	for binding: Dictionary in [
		{"signal":"reward_claimed", "callback":Callable(self, "_on_reward_claimed")},
		{"signal":"reward_rejected", "callback":Callable(self, "_on_reward_rejected")},
		{"signal":"rewards_changed", "callback":Callable(self, "_on_rewards_changed")},
	]:
		var signal_name := str(binding.get("signal", ""))
		var callback: Callable = binding.get("callback", Callable())
		if reward_service.has_signal(signal_name) and reward_service.is_connected(signal_name, callback):
			reward_service.disconnect(signal_name, callback)


func _on_rewards_changed(snapshot: Dictionary) -> void:
	var claimable := _claimable_entries(snapshot)
	if _active:
		var new_ids: Array[String] = []
		for raw_id: Variant in claimable.keys():
			var milestone_id := str(raw_id)
			if not _known_claimable.has(milestone_id):
				new_ids.append(milestone_id)
		new_ids.sort()
		if not new_ids.is_empty():
			_announce_claimable_rewards(new_ids, claimable, snapshot)
	_known_claimable = claimable


func _sync_claimable_baseline(raw_snapshot: Variant) -> void:
	_known_claimable = _claimable_entries(raw_snapshot if raw_snapshot is Dictionary else {})


func _claimable_entries(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_rewards: Variant = snapshot.get("rewards", [])
	if raw_rewards is not Array:
		return result
	for raw_reward: Variant in raw_rewards:
		if raw_reward is not Dictionary:
			continue
		var reward: Dictionary = raw_reward
		if str(reward.get("status", "")) != "claimable":
			continue
		var milestone_id := str(reward.get("milestone_id", "")).strip_edges()
		if not milestone_id.is_empty():
			result[milestone_id] = reward.duplicate(true)
	return result


func _announce_claimable_rewards(
	milestone_ids: Array[String], claimable: Dictionary, snapshot: Dictionary
) -> void:
	_announcement_count += 1
	var message := "新增 %d 个探索奖励可领取（按 J 查看）" % milestone_ids.size()
	if milestone_ids.size() == 1:
		var reward: Dictionary = claimable.get(milestone_ids[0], {})
		message = "探索里程碑可领取：%s（按 J 查看）" % str(
			reward.get("name", "新里程碑")
		)
	_publish_message(
		message,
		"success",
		"exploration_reward_available:%s" % ",".join(milestone_ids),
		3.4
	)
	var audio_service: Node = hub.get("audio_service") if hub != null else null
	if audio_service != null and audio_service.has_method("play_ui"):
		audio_service.call("play_ui")
	claimable_reward_announced.emit(milestone_ids.duplicate(), snapshot.duplicate(true))


func _on_reward_claimed(milestone_id: String, result: Dictionary) -> void:
	_publish_message(
		str(result.get("message", "探索奖励已领取")),
		"success",
		"exploration_reward:%s" % milestone_id,
		3.2
	)
	var audio_service: Node = hub.get("audio_service") if hub != null else null
	if audio_service != null and audio_service.has_method("play_pickup"):
		audio_service.call("play_pickup")


func _on_reward_rejected(
	milestone_id: String, reason: String, context: Dictionary
) -> void:
	_publish_message(
		str(context.get("message", "探索奖励暂时无法领取")),
		"warning",
		"exploration_reward_rejected:%s:%s" % [milestone_id, reason],
		2.8
	)


func _publish_message(
	message: String, severity: String, dedupe_key: String, duration: float
) -> void:
	if hub != null and hub.has_method("_publish_character_message"):
		hub.call("_publish_character_message", message, severity, dedupe_key, duration)
