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
	var dependencies: Array[StringName] = []
	var clear_count := 0
	var shutdown_count := 0

	func _init(
		p_participant_id: String,
		p_events: Array[String],
		p_dependencies: Array[StringName] = []
	) -> void:
		participant_id = p_participant_id
		events = p_events
		dependencies = p_dependencies.duplicate()

	func get_dependencies() -> Array[StringName]:
		return dependencies.duplicate()

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


class FakeWorld:
	extends Node
	var profile_id := "star_continent"

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))

	func get_initial_block(position: Vector3i) -> String:
		if position.y < 1 or position.y > 63:
			return "air"
		return "stone"


class FakePlayer:
	extends Node3D
	var prospecting_service: Node

	func bind_prospecting_service(service: Node) -> void:
		prospecting_service = service


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
	var missing_dependency: Dictionary = coordinator.register_participant(
		&"dependent", FakeParticipant.new("dependent", events, [&"first"])
	)
	_check(
		str(missing_dependency.get("reason", "")) == "participant_dependency_missing",
		"participant dependencies must already be installed"
	)
	var self_dependency: Dictionary = coordinator.register_participant(
		&"cycle", FakeParticipant.new("cycle", events, [&"cycle"])
	)
	_check(
		str(self_dependency.get("reason", "")) == "participant_dependency_cycle",
		"self dependencies are rejected before installation"
	)
	var first := FakeParticipant.new("first", events)
	var second := FakeParticipant.new("second", events, [&"first"])
	var first_registration: Dictionary = coordinator.register_participant(&"first", first)
	var second_registration: Dictionary = coordinator.register_participant(&"second", second)
	_check(bool(first_registration.get("success", false)), "coordinator installs the dependency participant")
	_check(bool(second_registration.get("success", false)), "coordinator installs the dependent participant")
	_check(
		coordinator.get_participant_dependencies(&"second") == ["first"],
		"coordinator exposes normalized dependency diagnostics"
	)
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
	for _index in 60:
		coordinator.snapshot_into({})
	coordinator.clear(&"qa_clear")
	coordinator.shutdown()
	coordinator.shutdown()
	_check(payload.get("first", "") == "saved" and payload.get("second", "") == "saved", "participants contribute to one shared save payload")
	_check(snapshot.get("first", "") == "snapshot" and snapshot.get("second", "") == "snapshot", "participants contribute to one shared diagnostics snapshot")
	var begin_first := events.find("first:begin:world-a")
	var begin_second := events.find("second:begin:world-a")
	_check(begin_first >= 0 and begin_second > begin_first, "begin lifecycle follows dependency order")
	var clear_second := events.find("second:clear:qa_clear")
	var clear_first := events.find("first:clear:qa_clear")
	_check(clear_second >= 0 and clear_first > clear_second, "clear lifecycle runs in reverse dependency order")
	_check(events.count("first:shutdown") == 1 and events.count("second:shutdown") == 1, "shutdown is idempotent per participant")
	var lifecycle_snapshot: Dictionary = coordinator.get_snapshot()
	_check(int(lifecycle_snapshot.get("participant_count", 0)) == 2, "coordinator diagnostics report installed participants")
	_check(
		(lifecycle_snapshot.get("participant_dependencies", {}) as Dictionary).get("second", []) == ["first"],
		"coordinator snapshot preserves the dependency graph"
	)
	_check((lifecycle_snapshot.get("phase_history", []) as Array).size() <= 48, "lifecycle phase history remains bounded")
	host.queue_free()


func _test_production_exploration_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 3:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var runtime_participant: Node = hub.get("exploration_runtime_participant")
	var journal_participant: Node = hub.get("exploration_journal_reward_participant")
	var journal: Node = hub.get("exploration_journal_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var prospecting: Node = hub.get("prospecting_service")
	var danger: Node = hub.get("exploration_danger_service")
	_check(
		coordinator != null
		and coordinator.has_participant(&"exploration_runtime")
		and coordinator.has_participant(&"exploration_journal_rewards"),
		"production hub registers both exploration participants"
	)
	_check(runtime_participant != null and journal_participant != null, "production hub exposes both participants for diagnostics")
	_check(journal != null and rewards != null and prospecting != null and danger != null, "legacy public exploration service fields remain available")
	_check(hub.get_node_or_null("ProspectingService") == prospecting, "prospecting keeps its production node path")
	_check(hub.get_node_or_null("ExplorationDangerService") == danger, "danger keeps its production node path")
	_check(hub.get_node_or_null("ExplorationJournalService") == journal, "journal keeps its production node path")
	_check(hub.get_node_or_null("ExplorationMilestoneRewardService") == rewards, "reward keeps its production node path")
	_check(
		coordinator.get_participant_dependencies(&"exploration_journal_rewards") == ["exploration_runtime"],
		"journal/reward explicitly depends on exploration runtime"
	)

	var state: Dictionary = hub.save_service.create_world(
		"feature-lifecycle-%d" % Time.get_ticks_msec(),
		"star_continent",
		6512039
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "production save service creates a lifecycle test world")
	hub.call("_begin_world", state)
	var lifecycle_after_begin: Dictionary = coordinator.call("get_snapshot")
	_check(int(lifecycle_after_begin.get("phase_counts", {}).get("begin_world", 0)) == 1, "world begin reaches both registered participants once")
	_check(str(rewards.call("get_snapshot").get("profile_id", "")) == "star_continent", "dependent participant sees the runtime-restored active map")

	var fake_world := FakeWorld.new()
	var fake_player := FakePlayer.new()
	fake_player.global_position = Vector3(0.5, 16.0, 0.5)
	root.add_child(fake_world)
	root.add_child(fake_player)
	coordinator.call("attach_game", fake_world, fake_player)
	var transitions: Array[String] = []
	var refresh_triggers: Array[String] = []
	runtime_participant.connect(
		"danger_transition_announced",
		func(kind: String, _snapshot: Dictionary) -> void: transitions.append(kind)
	)
	runtime_participant.connect(
		"immediate_danger_refreshed",
		func(trigger: String, _snapshot: Dictionary) -> void: refresh_triggers.append(trigger)
	)
	coordinator.call("activate")
	_check(fake_player.prospecting_service == prospecting, "runtime participant binds the production prospecting service to the player")
	_check(bool(danger.get("active")), "runtime participant activates production danger assessment")
	hub.day_night.set_time(21.0)
	await process_frame
	_check("phase_changed" in refresh_triggers, "phase changes refresh danger immediately")
	_check("danger" in transitions, "night transition publishes an immediate dangerous-area notice")
	hub.day_night.set_time(8.0)
	await process_frame
	_check("recovered" in transitions, "returning to daytime publishes one danger recovery notice")
	hub.creature_spawner.emit_signal("ecology_changed", {})
	await process_frame
	_check("ecology_changed" in refresh_triggers, "ecology changes refresh danger immediately")
	var runtime_snapshot: Dictionary = runtime_participant.call("get_lifecycle_snapshot")
	_check(int(runtime_snapshot.get("immediate_refresh_count", 0)) >= 3, "runtime diagnostics count immediate danger refreshes")
	_check(int(runtime_snapshot.get("danger_recovery_count", 0)) == 1, "runtime diagnostics count the player-facing recovery transition once")

	var announced: Array[Array] = []
	journal_participant.connect(
		"claimable_reward_announced",
		func(ids: Array[String], _snapshot: Dictionary) -> void: announced.append(ids.duplicate())
	)
	var scan: Dictionary = prospecting.call("use_item", "prospecting_kit", 5000)
	_check(bool(scan.get("success", false)), "composed prospecting runtime completes a bounded scan")
	journal.call("refresh")
	await process_frame
	_check(announced.size() == 1 and "first_discovery" in announced[0], "runtime scan unlocks and announces the dependent reward once")
	journal.call("refresh")
	await process_frame
	_check(announced.size() == 1, "duplicate reward refresh does not spam the player")

	hub.inventory.clear()
	var claim: Dictionary = rewards.call("claim", "first_discovery")
	_check(bool(claim.get("success", false)), "dependent reward service still commits the production inventory transaction")
	_check(bool(hub.call("save_current")), "both participants write into one production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check((loaded.get("exploration", {}).get("records", []) as Array).size() == 1, "runtime participant persists exploration records")
	_check("first_discovery" in (loaded.get("exploration_rewards", {}).get("claimed", []) as Array), "dependent participant persists claimed rewards")
	var announcement_count_before_reload := int(journal_participant.call("get_lifecycle_snapshot").get("announcement_count", 0))
	hub.call("return_to_menu")
	_check(hub.current_world_id.is_empty(), "production return-to-menu completes after participant save")
	_check(fake_player.prospecting_service == null, "reverse cleanup explicitly unbinds the old player")
	_check((prospecting.call("get_snapshot") as Dictionary).get("record_count", 0) == 0, "return-to-menu clears composed prospecting state")
	_check((danger.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears composed danger state")
	_check((journal.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears dependent journal state")
	_check((rewards.call("get_snapshot") as Dictionary).is_empty(), "return-to-menu clears dependent reward state")
	var lifecycle_after_menu: Dictionary = coordinator.call("get_snapshot")
	var history: Array = lifecycle_after_menu.get("phase_history", [])
	_check(not history.is_empty() and str(history.back()).contains("exploration_journal_rewards,exploration_runtime"), "clear history records reverse dependency order")

	hub.call("_begin_world", loaded)
	coordinator.call("attach_game", fake_world, fake_player)
	coordinator.call("activate")
	await process_frame
	_check(rewards.call("is_claimed", "first_discovery"), "world reload restores claimed reward through dependent begin_world")
	_check(int(journal_participant.call("get_lifecycle_snapshot").get("announcement_count", 0)) == announcement_count_before_reload, "world reload establishes a baseline without duplicate reward notices")
	_check(fake_player.prospecting_service == prospecting, "world reload rebinds prospecting through the runtime participant")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(character_snapshot.has("exploration") and character_snapshot.has("danger"), "runtime participant contributes legacy exploration diagnostics")
	_check(character_snapshot.has("exploration_journal") and character_snapshot.has("exploration_rewards"), "dependent participant contributes legacy journal diagnostics")
	_check(int(character_snapshot.get("feature_lifecycle", {}).get("participant_count", 0)) == 2, "character diagnostics expose both lifecycle participants")

	hub.call("handle_world_start_failed", "qa_simulated_failure")
	_check(hub.current_world_id.is_empty(), "world-start failure resets the production hub identity")
	_check(fake_player.prospecting_service == null, "world-start failure unbinds prospecting from the old player")
	_check((prospecting.call("get_snapshot") as Dictionary).get("record_count", 0) == 0 and (danger.call("get_snapshot") as Dictionary).is_empty(), "world-start failure clears runtime exploration state")
	_check((journal.call("get_snapshot") as Dictionary).is_empty() and (rewards.call("get_snapshot") as Dictionary).is_empty(), "world-start failure clears dependent exploration state")
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	coordinator.call("shutdown")
	var shutdown_snapshot: Dictionary = coordinator.call("get_snapshot")
	_check(bool(shutdown_snapshot.get("shutdown", false)), "coordinator records deterministic shutdown")
	fake_player.queue_free()
	fake_world.queue_free()
	hub.queue_free()
	for _frame in 4:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
