class_name ExplorationProgressionServiceHub
extends "res://src/ui/runtime_health_service_hub.gd"

signal application_quit_requested(source: StringName)

const ExplorationRuntimeParticipantScript = preload(
	"res://src/exploration/pickup_aware_exploration_runtime_participant.gd"
)
const JournalRewardParticipantScript = preload(
	"res://src/exploration/exploration_journal_reward_participant.gd"
)
const AutosaveRuntimeParticipantScript = preload(
	"res://src/save/autosave_runtime_participant.gd"
)
const UiAccessibilityServiceScript = preload(
	"res://src/ui/ui_accessibility_service.gd"
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
var ui_accessibility: Node
var _application_quit_request_count := 0
var _application_quit_success_count := 0
var _application_quit_failure_count := 0
var _last_application_quit_source: StringName = &""


func _ready() -> void:
	super._ready()
	ui_accessibility = _add_service(
		UiAccessibilityServiceScript.new(),
		"UiAccessibility"
	)
	ui_accessibility.call("setup", current_settings)
	if main_menu != null:
		if main_menu.has_method("setup_accessibility"):
			main_menu.call("setup_accessibility", ui_accessibility)
		var menu_quit_callback := Callable(self, "_on_main_menu_quit_requested")
		if main_menu.has_signal("quit_requested") and not main_menu.is_connected(
			"quit_requested", menu_quit_callback
		):
			main_menu.connect("quit_requested", menu_quit_callback)
	if game_ui != null:
		if game_ui.has_method("setup_accessibility"):
			game_ui.call("setup_accessibility", ui_accessibility)
		var gameplay_quit_callback := Callable(self, "_on_gameplay_quit_requested")
		if game_ui.has_signal("quit_to_desktop_requested") and not game_ui.is_connected(
			"quit_to_desktop_requested", gameplay_quit_callback
		):
			game_ui.connect("quit_to_desktop_requested", gameplay_quit_callback)
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
	# Registered last with explicit dependencies so reverse lifecycle cleanup
	# disables checkpoint activity before any gameplay domain releases state.
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


func prepare_application_quit(source: StringName = &"system") -> bool:
	_application_quit_request_count += 1
	_last_application_quit_source = source
	if game_ui != null and game_ui.has_method("show_quit_progress"):
		game_ui.call("show_quit_progress")
	if current_world_id.is_empty():
		_application_quit_success_count += 1
		return true
	return_to_menu()
	var prepared := current_world_id.is_empty()
	if prepared:
		_application_quit_success_count += 1
		if game_ui != null and game_ui.has_method("show_quit_result"):
			game_ui.call("show_quit_result", true)
	else:
		_application_quit_failure_count += 1
		if game_ui != null and game_ui.has_method("show_quit_result"):
			game_ui.call("show_quit_result", false)
	return prepared


func show_application_quit_prepared() -> void:
	if main_menu != null and main_menu.has_method("show_shutdown_ready"):
		main_menu.call("show_shutdown_ready")


func _apply_settings(settings: Dictionary) -> void:
	if ui_accessibility != null and ui_accessibility.has_method("apply_settings"):
		ui_accessibility.call("apply_settings", settings)
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


func get_ui_accessibility_snapshot() -> Dictionary:
	if ui_accessibility == null or not ui_accessibility.has_method("get_snapshot"):
		return {}
	return ui_accessibility.call("get_snapshot")


func get_application_quit_snapshot() -> Dictionary:
	return {
		"request_count": _application_quit_request_count,
		"success_count": _application_quit_success_count,
		"failure_count": _application_quit_failure_count,
		"last_source": str(_last_application_quit_source),
		"world_active": not current_world_id.is_empty(),
	}


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
	snapshot["ui_accessibility"] = get_ui_accessibility_snapshot()
	snapshot["session_recovery"] = get_session_recovery_snapshot()
	snapshot["application_quit"] = get_application_quit_snapshot()
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


func _on_main_menu_quit_requested() -> void:
	application_quit_requested.emit(&"main_menu")


func _on_gameplay_quit_requested() -> void:
	application_quit_requested.emit(&"pause_menu")
