class_name ExplorationProgressionServiceHub
extends "res://src/ui/runtime_health_service_hub.gd"

const ExplorationRuntimeParticipantScript = preload(
	"res://src/exploration/pickup_aware_exploration_runtime_participant.gd"
)
const JournalRewardParticipantScript = preload(
	"res://src/exploration/exploration_journal_reward_participant.gd"
)
const AutosaveRuntimeParticipantScript = preload(
	"res://src/save/autosave_runtime_participant.gd"
)
const EXPLORATION_RUNTIME_FEATURE := &"exploration_runtime"
const JOURNAL_REWARD_FEATURE := &"exploration_journal_rewards"
const AUTOSAVE_RUNTIME_FEATURE := &"autosave_runtime"
const AUTOSAVE_STATUS_DEDUPE_KEY := "autosave_status"

var prospecting_service: Node
var exploration_danger_service: Node
var exploration_journal_service: Node
var exploration_reward_service: Node
var exploration_runtime_participant: Node
var exploration_journal_reward_participant: Node
var pickup_stack_coordinator: Node
var autosave_runtime_participant: Node


func _ready() -> void:
	super._ready()
	current_settings = SettingsPolicyScript.normalize(current_settings)
	_apply_settings(current_settings)
	exploration_runtime_participant = _register_feature_participant(
		EXPLORATION_RUNTIME_FEATURE,
		ExplorationRuntimeParticipantScript.new(),
		"exploration runtime"
	)
	if exploration_runtime_participant != null:
		prospecting_service = exploration_runtime_participant.call(
			"get_prospecting_service"
		) as Node
		exploration_danger_service = exploration_runtime_participant.call(
			"get_danger_service"
		) as Node
		pickup_stack_coordinator = exploration_runtime_participant.call(
			"get_pickup_coordinator"
		) as Node
		exploration_journal_reward_participant = _register_feature_participant(
			JOURNAL_REWARD_FEATURE,
			JournalRewardParticipantScript.new(),
			"exploration journal/reward"
		)
	if exploration_journal_reward_participant != null:
		exploration_journal_service = exploration_journal_reward_participant.call(
			"get_journal_service"
		) as Node
		exploration_reward_service = exploration_journal_reward_participant.call(
			"get_reward_service"
		) as Node
		if (
			exploration_reward_service != null
			and exploration_reward_service.has_signal("reward_claimed")
			and not exploration_reward_service.is_connected(
				"reward_claimed", Callable(self, "_on_reward_claimed_sound")
			)
		):
			exploration_reward_service.connect(
				"reward_claimed", Callable(self, "_on_reward_claimed_sound")
			)
	autosave_runtime_participant = _register_feature_participant(
		AUTOSAVE_RUNTIME_FEATURE,
		AutosaveRuntimeParticipantScript.new(),
		"bounded autosave runtime"
	)
	if autosave_runtime_participant != null:
		var callback := Callable(self, "_on_autosave_completed")
		if not autosave_runtime_participant.is_connected(
			"autosave_completed", callback
		):
			autosave_runtime_participant.connect("autosave_completed", callback)


func _apply_settings(settings: Dictionary) -> void:
	if survival != null and survival.has_method("set_difficulty_profile"):
		survival.call(
			"set_difficulty_profile",
			str(settings.get("survival_difficulty", DEFAULT_SETTINGS.survival_difficulty))
		)
	super._apply_settings(settings)


func _on_settings_changed(settings: Dictionary) -> void:
	var normalized := SettingsPolicyScript.merge(current_settings, settings)
	super._on_settings_changed(normalized)


func _on_reward_claimed_sound(_milestone_id: String, _result: Dictionary) -> void:
	if audio_service != null and audio_service.has_method("play_reward"):
		audio_service.play_reward()


func get_autosave_snapshot() -> Dictionary:
	if (
		autosave_runtime_participant == null
		or not autosave_runtime_participant.has_method("get_snapshot")
	):
		return {}
	return autosave_runtime_participant.call("get_snapshot")


func get_character_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_character_snapshot()
	snapshot["ecology"] = (
		creature_spawner.call("get_ecology_snapshot")
		if creature_spawner != null and creature_spawner.has_method("get_ecology_snapshot")
		else {}
	)
	snapshot["autosave"] = get_autosave_snapshot()
	snapshot["survival_tuning"] = (
		survival.call("get_tuning_snapshot")
		if survival != null and survival.has_method("get_tuning_snapshot")
		else {}
	)
	return snapshot


func _on_autosave_completed(success: bool, snapshot: Dictionary) -> void:
	if success:
		_publish_character_message(
			"世界已自动保存", "success", AUTOSAVE_STATUS_DEDUPE_KEY, 2.2
		)
		return
	var retry_seconds := maxi(
		1, int(ceil(float(snapshot.get("last_retry_delay_seconds", 30.0))))
	)
	_publish_character_message(
		"自动存档失败，将在活动时间 %d 秒后重试" % retry_seconds,
		"warning",
		AUTOSAVE_STATUS_DEDUPE_KEY,
		4.0
	)
