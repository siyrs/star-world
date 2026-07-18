extends SceneTree

const CoordinatorScript = preload(
	"res://src/core/service_hub_feature_coordinator.gd"
)
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeParticipant:
	extends Node
	var participant_id := ""
	var events: Array[String]
	var clear_count := 0
	var shutdown_count := 0

	func _init(p_participant_id: String, p_events: Array[String]) -> void:
		participant_id = p_participant_id
		events = p_events

	func install(_hub: Node) -> bool:
		events.append("%s:install" % participant_id)
		return true

	func begin_world(state: Dictionary) -> void:
		events.append("%s:begin:%s" % [participant_id, state.get("marker", "")])

	func attach_game(
		_world,
		_player: Node3D,
		_sun: DirectionalLight3D = null,
		_environment: WorldEnvironment = null,
		_ground_resolver: Callable = Callable()
	) -> void:
		events.append("%s:attach" % participant_id)

	func activate() -> void:
		events.append("%s:activate" % participant_id)

	func save_into(payload: Dictionary) -> void:
		payload[participant_id] = "saved"
		events.append("%s:save" % participant_id)

	func snapshot_into(snapshot: Dictionary) -> void:
		snapshot[participant_id] = "snapshot"
		events.append("%s:snapshot" % participant_id)

	func clear(reason: StringName = &"clear") -> void:
		clear_count += 1
		events.append("%s:clear:%s" % [participant_id, str(reason)])

	func shutdown() -> void:
		shutdown_count += 1
		events.append("%s:shutdown" % participant_id)

	func get_lifecycle_snapshot() -> Dictionary:
		return {
			"clear_count": clear_count,
			"shutdown_count": shutdown_count,
		}


class InvalidParticipant:
	extends Node
	func install(_hub: Node) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_coordinator_contract()
	await _test_production_exploration_composition()
	if failures.is_empty():
		print("QA SERVICE HUB FEATURE LIFECYCLE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SERVICE HUB FEATURE LIFECYCLE FAILURE: %s" % failure)
		print(
			"QA SERVICE HUB FEATURE LIFECYCLE FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_coordinator_contract() -> void:
	var host := Node.new()
	var coordinator = CoordinatorScript.new()
	root.add_child(host)
	host.add_child(coordinator)
	coordinator.setup(host)
	var events: Array[String] = []
	var first := FakeParticipant.new("first", events)
	var second := FakeParticipant.new("second", events)
	var first_registration: Dictionary = coordinator.register_participant(&"first", first)
	var second_registration: Dictionary = coordinator.register_participant(&"second", second)
	_check(bool(first_registration.get("success", false)), "coordinator installs the first participant")
	_check(bool(second_registration.get("success", false)), "coordinator installs the second participant")
	_check(coordinator.has_participant(&"first") and coordinator.has_participant(&"second"), "coordinator exposes registered participant ids")
	var duplicate: Dictionary = coordinator.register_participant(
		&"first", FakeParticipant.new("duplicate", events)
	)
	_check(str(duplicate.get("reason", "")) == "duplicate_participant", "duplicate lifecycle ids are rejected")
	var invalid: Dictionary = coordinator.register_participant(&"invalid", InvalidParticipant.new())
	_check(str(invalid.get("reason", "")) == "participant_contract", "participants missing lifecycle methods are rejected")
	coordinator.begin_world({"marker":"world-a"})
	coordinator.attach_game(null, null)
	coordinator.activate()
	var payload: Dictionary = {}
	coordinator.save_into(payload)
	var snapshot: Dictionary = {}
	coordinator.snapshot_into(snapshot)
	coordinator.clear(&"qa_clear")
	coordinator.shutdown()
	coordinator.shutdown()
	_check(payload.get("first", "") == "saved" and payload.get("second", "") == "saved", "participants contribute to one shared save payload")
	_check(snapshot.get("first", "") == "snapshot" and snapshot.get("second", "") == "snapshot", "participants contribute to one shared diagnostics snapshot")
	var begin_first := events.find("first:begin:world-a")
	var begin_second := events.find("second:begin:world-a")
	_check(begin_first >= 0 and begin_second > begin_first, "begin lifecycle follows registration order")
	var clear_second := events.find("second:clear:qa_clear")
	var clear_first := events.find("first:clear:qa_clear")
	_check(clear_second >= 0 and clear_first > clear_second, "clear lifecycle runs in reverse dependency order")
	_check(events.count("first:shutdown") == 1 and events.count("second:shutdown") == 1, "shutdown is idempotent per participant")
	var lifecycle_snapshot: Dictionary = coordinator.get_snapshot()
	_check(int(lifecycle_snapshot.get("participant_count", 0)) == 2, "coordinator diagnostics report installed participants")
	_check(int(lifecycle_snapshot.get("phase_counts", {}).get("activate", 0)) == 1, "coordinator diagnostics count lifecycle phases")
	host.queue_free()


func _test_production_exploration_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 3:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var participant: Node = hub.get("exploration_journal_reward_participant")
	var journal: Node = hub.get("exploration_journal_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var prospecting: Node = hub.get("prospecting_service")
	_check(coordinator != null and coordinator.has_participant(&"exploration_journal_rewards"), "production hub registers the exploration lifecycle participant")
	_check(participant != null, "production hub exposes the installed participant for diagnostics")
	_check(journal != null and rewards != null and prospecting != null, "legacy public exploration service fields remain available")
	_check(hub.get_node_or_null("ExplorationJournalService") == journal, "journal service keeps its production node path")
	_check(hub.get_node_or_null("ExplorationMilestoneRewardService") == rewards, "reward service keeps its production node path")

	var state: Dictionary = hub.save_service.create_world(
		"feature-lifecycle-%d" % Time.get_ticks_msec(),
		"star_continent",
		6512039
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production save service creates a lifecycle test world")
	hub.call("_begin_world", state)
	var lifecycle_after_begin: Dictionary = coordinator.call("get_snapshot")
	_check(int(lifecycle_after_begin.get("phase_counts", {}).get("begin_world", 0)) == 1, "world begin reaches registered lifecycle participants once")
	_check(str(rewards.call("get_snapshot").get("profile_id", "")) == "star_continent", "participant applies the active map before gameplay")

	var announced: Array[Array] = []
	participant.connect(
		"claimable_reward_announced",
		func(ids: Array[String], _snapshot: Dictionary) -> void: announced.append(ids.duplicate())
	)
	coordinator.call("activate")
	prospecting.call(
		"deserialize",
		{
			"version":3,
			"records":[_record("0,0:middle", [0,0], 1)],
			"last_result":{},
		}
	)
	journal.call("refresh")
	await process_frame
	_check(announced.size() == 1 and "first_discovery" in announced[0], "newly completed exploration reward is announced once during active gameplay")
	var feedback: Node = hub.player_experience.call("get_feedback")
	var toast: Dictionary = feedback.call("get_active_toast")
	_check(str(toast.get("text", "")).contains("按 J"), "player-facing reward notice explains how to open the journal")
	journal.call("refresh")
	await process_frame
	_check(announced.size() == 1, "duplicate reward refresh does not spam the player")

	var claim: Dictionary = rewards.call("claim", "first_discovery")
	_check(bool(claim.get("success", false)), "composed reward service still commits the production inventory transaction")
	_check(bool(hub.call("save_current")), "feature participant writes reward state into the production save payload")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check("first_discovery" in (loaded.get("exploration_rewards", {}).get("claimed", []) as Array), "claimed reward persists through participant save_into")
	var announcement_count_before_reload := int(participant.call("get_lifecycle_snapshot").get("announcement_count", 0))
	hub.call("return_to_menu")
	_check(hub.current_world_id.is_empty(), "production return-to-menu completes after participant save")
	_check((journal.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears composed journal state")
	_check((rewards.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears composed reward state")

	hub.call("_begin_world", loaded)
	coordinator.call("activate")
	await process_frame
	_check(rewards.call("is_claimed", "first_discovery"), "world reload restores claimed reward through participant begin_world")
	_check(int(participant.call("get_lifecycle_snapshot").get("announcement_count", 0)) == announcement_count_before_reload, "world reload establishes a baseline without duplicate reward notices")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(character_snapshot.has("exploration_journal") and character_snapshot.has("exploration_rewards"), "participant contributes legacy character snapshot fields")
	_check(int(character_snapshot.get("feature_lifecycle", {}).get("participant_count", 0)) == 1, "character diagnostics expose lifecycle composition")

	hub.call("handle_world_start_failed", "qa_simulated_failure")
	_check(hub.current_world_id.is_empty(), "world-start failure resets the production hub identity")
	_check((journal.call("get_snapshot") as Dictionary).is_empty() and (rewards.call("get_snapshot") as Dictionary).is_empty(), "world-start failure clears all composed exploration state")
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	coordinator.call("shutdown")
	var shutdown_snapshot: Dictionary = coordinator.call("get_snapshot")
	_check(bool(shutdown_snapshot.get("shutdown", false)), "coordinator records deterministic shutdown")
	hub.queue_free()
	for _frame in 4:
		await process_frame


func _record(record_key: String, chunk: Array, sequence: int) -> Dictionary:
	return {
		"record_key": record_key,
		"chunk": chunk.duplicate(),
		"profile_id": "star_continent",
		"depth_band_id": "middle",
		"depth_label": "中层",
		"density_id": "normal",
		"density_label": "普通",
		"ore_ratio": 0.03,
		"dominant_block_id": "iron_ore",
		"dominant_label": "铁矿",
		"danger_tier_id": "safe",
		"danger_label": "低",
		"danger_score": 12,
		"danger_reasons": [],
		"message": "粗粒度趋势",
		"sequence": sequence,
		"world_day": 1,
		"world_time": 8.0,
		"scanned_at_msec": sequence * 1000,
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
