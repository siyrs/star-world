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

	func normalize_world_state(state: Dictionary) -> Dictionary:
		var normalized := state.duplicate(true)
		var order: Array = normalized.get("normalization_order", [])
		order.append(participant_id)
		normalized["normalization_order"] = order
		events.append("%s:normalize" % participant_id)
		return normalized

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
		return {"clear_count":clear_count, "shutdown_count":shutdown_count}


class InvalidParticipant:
	extends Node

	func install(_hub: Node) -> bool:
		return true


class FakeWorld:
	extends Node
	var profile_id := "star_continent"
	var blocks: Dictionary = {}

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(
			floori(float(position.x) / 16.0), floori(float(position.z) / 16.0)
		)

	func get_initial_block(position: Vector3i) -> String:
		return get_block(position)

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var key := _key(position)
		var previous := str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		return true

	func resolve_ground_position(candidate: Vector3) -> Vector3:
		return Vector3(candidate.x, maxf(1.05, candidate.y), candidate.z)

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


class FakePlayer:
	extends Node3D
	var prospecting_service: Node
	var entity_interaction_service: Node

	func bind_prospecting_service(service: Node) -> void:
		prospecting_service = service

	func bind_entity_interaction_service(service: Node) -> void:
		entity_interaction_service = service


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_coordinator_contract()
	await _test_production_composition()
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
	_check(
		bool(coordinator.register_participant(&"first", first).get("success", false)),
		"coordinator installs the dependency participant"
	)
	_check(
		bool(coordinator.register_participant(&"second", second).get("success", false)),
		"coordinator installs the dependent participant"
	)
	_check(
		coordinator.get_participant_dependencies(&"second") == ["first"],
		"coordinator exposes normalized dependency diagnostics"
	)
	var duplicate: Dictionary = coordinator.register_participant(
		&"first", FakeParticipant.new("duplicate", events)
	)
	_check(
		str(duplicate.get("reason", "")) == "duplicate_participant",
		"duplicate lifecycle ids are rejected"
	)
	var invalid: Dictionary = coordinator.register_participant(
		&"invalid", InvalidParticipant.new()
	)
	_check(
		str(invalid.get("reason", "")) == "participant_contract",
		"participants missing lifecycle methods are rejected"
	)
	var normalized: Dictionary = coordinator.normalize_world_state(
		{"marker":"world-a", "normalization_order":[]}
	)
	_check(
		(normalized.get("normalization_order", []) as Array) == ["first", "second"],
		"world-state normalization follows dependency registration order"
	)
	coordinator.begin_world(normalized)
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
	_check(
		payload.get("first", "") == "saved"
		and payload.get("second", "") == "saved",
		"participants contribute to one shared save payload"
	)
	_check(
		snapshot.get("first", "") == "snapshot"
		and snapshot.get("second", "") == "snapshot",
		"participants contribute to one shared diagnostics snapshot"
	)
	_check(
		events.find("first:normalize") < events.find("second:normalize"),
		"normalizers execute in dependency order"
	)
	_check(
		events.find("first:begin:world-a") < events.find("second:begin:world-a"),
		"begin lifecycle follows dependency order"
	)
	_check(
		events.find("second:clear:qa_clear") < events.find("first:clear:qa_clear"),
		"clear lifecycle runs in reverse dependency order"
	)
	_check(
		events.count("first:shutdown") == 1
		and events.count("second:shutdown") == 1,
		"shutdown is idempotent per participant"
	)
	var lifecycle_snapshot: Dictionary = coordinator.get_snapshot()
	_check(
		int(lifecycle_snapshot.get("participant_count", 0)) == 2,
		"coordinator diagnostics report installed participants"
	)
	_check(
		(lifecycle_snapshot.get("phase_history", []) as Array).size() <= 48,
		"lifecycle phase history remains bounded"
	)
	host.queue_free()


func _test_production_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var machine_participant: Node = hub.get("machine_runtime_participant")
	var agriculture_participant: Node = hub.get("agriculture_runtime_participant")
	var husbandry_participant: Node = hub.get("husbandry_runtime_participant")
	var ranch_participant: Node = hub.get("ranch_runtime_participant")
	var runtime_participant: Node = hub.get("exploration_runtime_participant")
	var journal_participant: Node = hub.get("exploration_journal_reward_participant")
	var agriculture: Node = hub.get("agriculture_service")
	var agriculture_interaction: Node = hub.get("agriculture_interaction")
	var husbandry: Node = hub.get("husbandry_service")
	var husbandry_interaction: Node = hub.get("husbandry_interaction")
	var attraction: Node = hub.get("animal_attraction_service")
	var products: Node = hub.get("animal_product_service")
	var journal: Node = hub.get("exploration_journal_service")
	var rewards: Node = hub.get("exploration_reward_service")
	var prospecting: Node = hub.get("prospecting_service")
	var danger: Node = hub.get("exploration_danger_service")
	var machine_runtime: Node = hub.get("machine_runtime")
	_check(
		coordinator != null
		and coordinator.has_participant(&"machine_runtime")
		and coordinator.has_participant(&"agriculture_runtime")
		and coordinator.has_participant(&"husbandry_runtime")
		and coordinator.has_participant(&"ranch_runtime")
		and coordinator.has_participant(&"exploration_runtime")
		and coordinator.has_participant(&"exploration_journal_rewards"),
		"production hub registers all six lifecycle participants"
	)
	_check(
		machine_participant != null
		and agriculture_participant != null
		and husbandry_participant != null
		and ranch_participant != null
		and runtime_participant != null
		and journal_participant != null,
		"production hub exposes all six participants for diagnostics"
	)
	_check(
		machine_runtime != null
		and agriculture != null
		and agriculture_interaction != null
		and husbandry != null
		and husbandry_interaction != null
		and attraction != null
		and products != null
		and journal != null
		and rewards != null
		and prospecting != null
		and danger != null,
		"legacy public service fields remain available"
	)
	_check(
		hub.get_node_or_null("AgricultureService") == agriculture
		and hub.get_node_or_null("AgricultureInteraction") == agriculture_interaction,
		"agriculture participant preserves its production node paths"
	)
	_check(
		hub.get_node_or_null("MachineRuntime") == machine_runtime,
		"machine runtime keeps its production node path"
	)
	_check(
		hub.get_node_or_null("FurnaceService") == hub.furnace_service,
		"furnace keeps its legacy production node path"
	)
	_check(
		hub.get_node_or_null("AnimalHusbandryService") == husbandry,
		"husbandry keeps its production node path"
	)
	_check(
		hub.get_node_or_null("HusbandryInteraction") == husbandry_interaction,
		"husbandry interaction keeps its production node path"
	)
	_check(
		hub.get_node_or_null("AnimalAttractionService") == attraction,
		"animal attraction keeps its production node path"
	)
	_check(
		hub.get_node_or_null("AnimalProductService") == products,
		"animal products keep their production node path"
	)
	_check(
		hub.get_node_or_null("ProspectingService") == prospecting,
		"prospecting keeps its production node path"
	)
	_check(
		hub.get_node_or_null("ExplorationDangerService") == danger,
		"danger keeps its production node path"
	)
	_check(
		hub.get_node_or_null("ExplorationJournalService") == journal,
		"journal keeps its production node path"
	)
	_check(
		hub.get_node_or_null("ExplorationMilestoneRewardService") == rewards,
		"reward keeps its production node path"
	)
	_check(
		coordinator.get_participant_dependencies(&"machine_runtime").is_empty()
		and coordinator.get_participant_dependencies(&"agriculture_runtime").is_empty(),
		"machine and agriculture runtimes are independent root participants"
	)
	_check(
		coordinator.get_participant_dependencies(&"ranch_runtime")
		== ["husbandry_runtime"],
		"ranch explicitly depends on husbandry runtime"
	)
	_check(
		coordinator.get_participant_dependencies(&"exploration_journal_rewards")
		== ["exploration_runtime"],
		"journal/reward explicitly depends on exploration runtime"
	)

	var state: Dictionary = hub.save_service.create_world(
		"feature-lifecycle-%d" % Time.get_ticks_msec(), "star_continent", 6512039
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(
		not world_id.is_empty(),
		"production save service creates a lifecycle test world"
	)
	hub.call("_begin_world", state)
	var lifecycle_after_begin: Dictionary = coordinator.call("get_snapshot")
	_check(
		int(lifecycle_after_begin.get("phase_counts", {}).get(
			"normalize_world_state", 0
		)) == 1,
		"production begin runs one ordered normalization phase"
	)
	_check(
		int(lifecycle_after_begin.get("phase_counts", {}).get("begin_world", 0)) == 1,
		"world begin reaches all registered participants once"
	)
	_check(
		str(rewards.call("get_snapshot").get("profile_id", "")) == "star_continent",
		"dependent participant sees the runtime-restored active map"
	)

	var fake_world := FakeWorld.new()
	var fake_player := FakePlayer.new()
	fake_player.global_position = Vector3(0.5, 16.0, 0.5)
	root.add_child(fake_world)
	root.add_child(fake_player)
	coordinator.call("attach_game", fake_world, fake_player)
	coordinator.call("activate")
	_check(
		fake_player.entity_interaction_service == husbandry_interaction,
		"husbandry participant binds the production interaction service"
	)
	_check(
		fake_player.prospecting_service == prospecting,
		"exploration participant binds the production prospecting service"
	)
	_check(
		machine_runtime.call("is_active"),
		"machine participant activates the shared scheduler"
	)
	_check(
		bool(agriculture_participant.call("get_lifecycle_snapshot").get(
			"active", false
		)),
		"agriculture participant activates the pausable crop runtime"
	)
	_check(
		bool(danger.get("active")),
		"exploration participant activates production danger assessment"
	)

	var announced: Array[Array] = []
	journal_participant.connect(
		"claimable_reward_announced",
		func(ids: Array[String], _snapshot: Dictionary) -> void:
			announced.append(ids.duplicate())
	)
	# The scanner needs at least minimum_geology_samples rock blocks in range;
	# an empty (all-air) world is rejected as insufficient_geology.
	for dx in range(-6, 8, 2):
		for dz in range(-6, 8, 2):
			for dy in range(4, 30, 2):
				fake_world.set_block(Vector3i(dx, dy, dz), "stone")
	var scan: Dictionary = prospecting.call("use_item", "prospecting_kit", 5000)
	_check(
		bool(scan.get("success", false)),
		"composed prospecting runtime completes a bounded scan"
	)
	journal.call("refresh")
	await process_frame
	_check(
		announced.size() == 1 and "first_discovery" in announced[0],
		"runtime scan unlocks and announces the dependent reward once"
	)
	journal.call("refresh")
	await process_frame
	_check(
		announced.size() == 1,
		"duplicate reward refresh does not spam the player"
	)

	hub.inventory.clear()
	var claim: Dictionary = rewards.call("claim", "first_discovery")
	_check(
		bool(claim.get("success", false)),
		"dependent reward service still commits the production inventory transaction"
	)
	_check(
		bool(hub.call("save_current")),
		"all participants write into one production save transaction"
	)
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check(
		loaded.has("machines") and loaded.get("machines", {}).has("furnaces"),
		"machine participant persists the compatible machine domain"
	)
	_check(
		loaded.has("agriculture")
		and loaded.get("agriculture", {}).get("soil_moisture", null) is Dictionary,
		"agriculture participant persists the compatible crop and soil domain"
	)
	_check(loaded.has("husbandry"), "husbandry participant persists its domain")
	_check(
		loaded.has("animal_products"),
		"ranch participant persists the animal product domain"
	)
	_check(
		(loaded.get("exploration", {}).get("records", []) as Array).size() == 1,
		"runtime participant persists exploration records"
	)
	_check(
		"first_discovery" in (
			loaded.get("exploration_rewards", {}).get("claimed", []) as Array
		),
		"dependent participant persists claimed rewards"
	)
	var announcement_count_before_reload := int(
		journal_participant.call("get_lifecycle_snapshot").get(
			"announcement_count", 0
		)
	)
	hub.call("return_to_menu")
	_check(
		hub.current_world_id.is_empty(),
		"production return-to-menu completes after participant save"
	)
	_check(
		fake_player.entity_interaction_service == null,
		"reverse cleanup unbinds the old husbandry interaction"
	)
	_check(
		fake_player.prospecting_service == null,
		"reverse cleanup unbinds the old prospecting service"
	)
	_check(
		not machine_runtime.call("is_active"),
		"reverse cleanup stops the shared machine scheduler"
	)
	_check(
		not bool(agriculture_participant.call("get_lifecycle_snapshot").get(
			"active", true
		)),
		"reverse cleanup deactivates agriculture"
	)
	var lifecycle_after_menu: Dictionary = coordinator.call("get_snapshot")
	var history: Array = lifecycle_after_menu.get("phase_history", [])
	_check(
		not history.is_empty()
		and str(history.back()).contains(
			"exploration_journal_rewards,exploration_runtime,ranch_runtime,husbandry_runtime,agriculture_runtime,machine_runtime"
		),
		"clear history records complete reverse dependency order"
	)

	hub.call("_begin_world", loaded)
	coordinator.call("attach_game", fake_world, fake_player)
	coordinator.call("activate")
	await process_frame
	_check(
		rewards.call("is_claimed", "first_discovery"),
		"world reload restores claimed reward through dependent begin_world"
	)
	_check(
		int(journal_participant.call("get_lifecycle_snapshot").get(
			"announcement_count", 0
		)) == announcement_count_before_reload,
		"world reload establishes a baseline without duplicate reward notices"
	)
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(
		character_snapshot.has("machine_runtime")
		and character_snapshot.has("machines"),
		"machine participant contributes runtime diagnostics"
	)
	_check(
		character_snapshot.has("agriculture"),
		"agriculture participant contributes bounded runtime diagnostics"
	)
	_check(
		character_snapshot.has("husbandry"),
		"husbandry participant contributes legacy diagnostics"
	)
	_check(
		character_snapshot.has("animal_attraction")
		and character_snapshot.has("animal_products"),
		"ranch participant contributes legacy diagnostics"
	)
	_check(
		character_snapshot.has("exploration")
		and character_snapshot.has("danger"),
		"runtime participant contributes legacy exploration diagnostics"
	)
	_check(
		character_snapshot.has("exploration_journal")
		and character_snapshot.has("exploration_rewards"),
		"dependent participant contributes legacy journal diagnostics"
	)
	_check(
		int(character_snapshot.get("feature_lifecycle", {}).get(
			"participant_count", 0
		)) == 6,
		"character diagnostics expose all six lifecycle participants"
	)

	hub.call("handle_world_start_failed", "qa_simulated_failure")
	_check(
		hub.current_world_id.is_empty(),
		"world-start failure resets the production hub identity"
	)
	_check(
		fake_player.entity_interaction_service == null
		and fake_player.prospecting_service == null,
		"world-start failure unbinds player capability ports"
	)
	_check(
		not machine_runtime.call("is_active"),
		"world-start failure stops machine processing"
	)
	_check(
		not bool(agriculture_participant.call("get_lifecycle_snapshot").get(
			"active", true
		)),
		"world-start failure stops agriculture processing"
	)
	if not world_id.is_empty():
		hub.save_service.delete_world(world_id)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	coordinator.call("shutdown")
	_check(
		bool(coordinator.call("get_snapshot").get("shutdown", false)),
		"coordinator records deterministic shutdown"
	)
	fake_player.queue_free()
	fake_world.queue_free()
	hub.queue_free()
	for _frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
