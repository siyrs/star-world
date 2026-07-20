extends SceneTree

const ProgressPolicyScript = preload("res://src/machine/machine_progress_policy.gd")
const StateMigrationScript = preload("res://src/machine/machine_state_migration.gd")
const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const CompletionPolicyScript = preload("res://src/machine/machine_completion_policy.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeMachineDomain:
	extends Node
	var external_scheduler := false
	var advance_count := 0
	var elapsed_total := 0.0
	var machine_count := 2
	var changed_per_tick := 1

	func set_external_scheduler(value: bool) -> void:
		external_scheduler = value

	func advance_machine_runtime(seconds: float, _emit_events: bool = true) -> Dictionary:
		advance_count += 1
		elapsed_total += seconds
		return {
			"machine_count": machine_count,
			"changed_machine_count": changed_per_tick,
		}

	func get_runtime_snapshot() -> Dictionary:
		return {
			"machine_count": machine_count,
			"advance_count": advance_count,
			"elapsed_total": elapsed_total,
		}


class InvalidMachineDomain:
	extends Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_progress_policy()
	_test_state_migration()
	await _test_shared_scheduler()
	await _test_production_furnace_adapter()
	await _test_production_service_hub()
	if failures.is_empty():
		print("QA MACHINE BASE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE BASE FAILURE: %s" % failure)
		print("QA MACHINE BASE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_progress_policy() -> void:
	_check(
		is_equal_approx(ProgressPolicyScript.progress_ratio(3.0, 6.0), 0.5),
		"machine progress ratio is a pure bounded calculation"
	)
	_check(
		is_equal_approx(ProgressPolicyScript.remaining_seconds(3.0, 6.0), 3.0),
		"machine policy exposes remaining work time"
	)
	_check(
		ProgressPolicyScript.queued_jobs(8, 1, 1, 60, 64) == 4,
		"machine queue is bounded by output capacity"
	)
	_check(
		is_equal_approx(
			ProgressPolicyScript.estimated_total_seconds(2.0, 6.0, 3), 16.0
		),
		"machine policy estimates the complete queued duration"
	)
	_check(
		is_zero_approx(ProgressPolicyScript.normalize_elapsed(INF, 10.0)),
		"non-finite elapsed time is rejected"
	)


func _test_state_migration() -> void:
	var raw := {
		"version": 99,
		"saved_at_unix": -50,
		"unknown_root": "discard",
		"furnaces": {
			"furnace@valid": {
				"type": "unexpected",
				"input": {"item_id":"raw_iron", "count":999999, "metadata":{"batch":1}},
				"fuel": {"item_id":"coal", "count":1},
				"output": {},
				"active_recipe_id": "smelt_iron_ingot",
				"progress_seconds": INF,
				"burn_remaining_seconds": 5.0,
				"burn_total_seconds": 2.0,
				"unknown_field": "discard",
			},
			"bad\nid": {"input":{}},
		},
	}
	var normalized: Dictionary = StateMigrationScript.normalize_machine_state(raw)
	_check(int(normalized.get("version", 0)) == 1, "machine migration preserves schema version one")
	_check(int(normalized.get("saved_at_unix", -1)) == 0, "negative machine save time is normalized")
	var furnaces: Dictionary = normalized.get("furnaces", {})
	_check(furnaces.size() == 1 and furnaces.has("furnace@valid"), "invalid machine ids are removed")
	var furnace: Dictionary = furnaces.get("furnace@valid", {})
	_check(str(furnace.get("type", "")) == "furnace", "machine type is restored from the authoritative domain")
	_check(int(furnace.get("input", {}).get("count", 0)) == 4096, "machine slot counts are hard-capped before registry validation")
	_check(is_zero_approx(float(furnace.get("progress_seconds", -1.0))), "non-finite progress is removed")
	_check(
		is_equal_approx(float(furnace.get("burn_total_seconds", 0.0)), 5.0),
		"total fuel time cannot be lower than remaining fuel time"
	)
	_check(not furnace.has("unknown_field") and not normalized.has("unknown_root"), "machine migration uses a strict whitelist")


func _test_shared_scheduler() -> void:
	var host := Node.new()
	var scheduler = SchedulerScript.new()
	var first := FakeMachineDomain.new()
	var second := FakeMachineDomain.new()
	root.add_child(host)
	host.add_child(first)
	host.add_child(second)
	host.add_child(scheduler)
	await process_frame
	var first_registration: Dictionary = scheduler.register_domain(&"first", first)
	var second_registration: Dictionary = scheduler.register_domain(&"second", second)
	_check(bool(first_registration.get("success", false)), "machine scheduler registers the first domain")
	_check(bool(second_registration.get("success", false)), "machine scheduler registers the second domain")
	_check(first.external_scheduler and second.external_scheduler, "registered domains disable their private process loops")
	var duplicate: Dictionary = scheduler.register_domain(&"first", FakeMachineDomain.new())
	_check(str(duplicate.get("reason", "")) == "duplicate_domain", "duplicate machine domain ids are rejected")
	var invalid: Dictionary = scheduler.register_domain(&"invalid", InvalidMachineDomain.new())
	_check(str(invalid.get("reason", "")) == "domain_contract", "machine domains missing the runtime contract are rejected")
	var batch: Dictionary = scheduler.advance_time(2.5, true)
	_check(first.advance_count == 1 and second.advance_count == 1, "one scheduler tick advances each registered domain exactly once")
	_check(int(batch.get("advanced_domain_count", 0)) == 2, "scheduler batch reports both domains")
	_check(int(batch.get("changed_machine_count", 0)) == 2, "scheduler batch aggregates changed machine counts")
	var snapshot: Dictionary = scheduler.get_snapshot()
	_check(int(snapshot.get("machine_count", 0)) == 4, "scheduler diagnostics aggregate domain machine counts")
	_check(int(snapshot.get("max_domains_per_tick", 0)) == 2, "scheduler diagnostics retain the largest domain batch")
	scheduler.shutdown()
	_check(not scheduler.is_active(), "scheduler shutdown deterministically stops processing")
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_furnace_adapter() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	var scheduler = SchedulerScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(furnace)
	host.add_child(scheduler)
	await process_frame
	_check(bool(furnace.setup(inventory.registry)), "production furnace validates its registries")
	_check(furnace.recipes.recipe_count() == 9, "all nine production furnace recipes load")
	var now := int(Time.get_unix_time_from_system())
	var machine_state := {
		"version":1,
		"saved_at_unix":now,
		"furnaces":{
			"furnace@iron":{
				"type":"furnace",
				"input":{"item_id":"raw_iron", "count":2},
				"fuel":{"item_id":"coal", "count":1},
				"output":{},
				"progress_seconds":0.0,
				"burn_remaining_seconds":0.0,
				"burn_total_seconds":0.0,
			},
			"furnace@gold":{
				"type":"furnace",
				"input":{"item_id":"raw_gold", "count":1},
				"fuel":{"item_id":"oak_log", "count":1},
				"output":{},
				"progress_seconds":0.0,
				"burn_remaining_seconds":0.0,
				"burn_total_seconds":0.0,
			},
		},
	}
	_check(furnace.deserialize(machine_state), "production furnace accepts the compatible machine schema")
	var before: Dictionary = furnace.get_machine_snapshot("furnace@iron")
	_check(int(before.get("queued_jobs", 0)) == 2, "furnace snapshot exposes queued work")
	_check(is_equal_approx(float(before.get("estimated_total_seconds", 0.0)), 12.0), "furnace snapshot exposes a deterministic queue estimate")
	var registration: Dictionary = scheduler.register_domain(&"furnace", furnace)
	_check(bool(registration.get("success", false)), "production furnace implements the shared scheduler contract")
	_check(furnace.is_externally_scheduled() and not furnace.is_processing(), "service-hub furnaces do not keep a second process loop")
	var completion_events: Array[Dictionary] = []
	furnace.item_smelted.connect(
		func(machine_id: String, recipe_id: String, output: Dictionary) -> void:
			completion_events.append({"machine_id":machine_id, "recipe_id":recipe_id, "output":output.duplicate(true)})
	)
	var batch: Dictionary = scheduler.advance_time(6.1, true)
	_check(int(batch.get("changed_machine_count", 0)) == 2, "one shared tick advances both production furnaces")
	_check(completion_events.size() == 2, "both production furnace jobs emit domain completions")
	var iron: Dictionary = furnace.get_machine_snapshot("furnace@iron")
	var gold: Dictionary = furnace.get_machine_snapshot("furnace@gold")
	_check(int(iron.get("output", {}).get("count", 0)) == 1, "iron furnace completes one job")
	_check(int(gold.get("output", {}).get("count", 0)) == 1, "gold furnace completes one job")
	var summary: Dictionary = CompletionPolicyScript.build(completion_events, inventory.registry)
	_check(int(summary.get("machine_count", 0)) == 2, "completion policy preserves the number of contributing machines")
	_check(int(summary.get("item_total", 0)) == 2, "completion policy preserves the complete output count")
	_check(str(summary.get("message", "")).contains("铁锭") and str(summary.get("message", "")).contains("金锭"), "completion summary uses player-facing item names")
	var serialized: Dictionary = furnace.serialize()
	_check(serialized.has("furnaces") and int(serialized.get("version", 0)) == 1, "furnace serialization remains backward compatible")
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_service_hub() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 4:
		await process_frame
	var coordinator: Node = hub.get("feature_lifecycle")
	var participant: Node = hub.get("machine_runtime_participant")
	var scheduler: Node = hub.get("machine_runtime")
	_check(
		coordinator != null
		and coordinator.has_participant(&"machine_runtime")
		and coordinator.has_participant(&"husbandry_runtime")
		and coordinator.has_participant(&"ranch_runtime")
		and coordinator.has_participant(&"exploration_runtime")
		and coordinator.has_participant(&"exploration_journal_rewards"),
		"production hub registers all five lifecycle participants"
	)
	_check(participant != null and scheduler != null, "production hub exposes machine lifecycle diagnostics")
	_check(hub.get_node_or_null("MachineRuntime") == scheduler, "machine scheduler keeps a stable production node path")
	_check(hub.get_node_or_null("FurnaceService") == hub.furnace_service, "legacy furnace node path remains unchanged")
	_check(hub.furnace_service.is_externally_scheduled(), "production furnace is owned by the shared runtime")
	var state: Dictionary = hub.save_service.create_world(
		"machine-base-%d" % Time.get_ticks_msec(), "star_continent", 915731
	)
	var world_id := str(state.get("metadata", {}).get("id", ""))
	_check(not world_id.is_empty(), "machine-base regression creates a temporary production world")
	var now := int(Time.get_unix_time_from_system())
	state["machines"] = {
		"version":1,
		"saved_at_unix":now,
		"furnaces":{
			"furnace@one":{"type":"furnace", "input":{"item_id":"raw_iron", "count":1}, "fuel":{"item_id":"coal", "count":1}, "output":{}, "progress_seconds":0.0, "burn_remaining_seconds":0.0, "burn_total_seconds":0.0},
			"furnace@two":{"type":"furnace", "input":{"item_id":"raw_gold", "count":1}, "fuel":{"item_id":"coal", "count":1}, "output":{}, "progress_seconds":0.0, "burn_remaining_seconds":0.0, "burn_total_seconds":0.0},
		},
	}
	hub.call("_begin_world", state)
	hub.call("activate_gameplay")
	var announced: Array[Dictionary] = []
	participant.connect(
		"machine_batch_announced",
		func(summary: Dictionary) -> void: announced.append(summary.duplicate(true))
	)
	scheduler.call("advance_time", 6.1, true)
	await process_frame
	await process_frame
	_check(announced.size() == 1, "two synchronous furnace completions publish one player-facing batch")
	if not announced.is_empty():
		_check(int(announced[0].get("completed_jobs", 0)) == 2, "batched production feedback preserves both jobs")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("completion_audio_count", 0)) == 1, "two synchronous completions play one craft sound")
	_check(bool(hub.call("save_current")), "machine participant contributes to the production save transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	_check((loaded.get("machines", {}).get("furnaces", {}) as Dictionary).size() == 2, "both furnaces persist under the original machines.furnaces schema")
	var character_snapshot: Dictionary = hub.call("get_character_snapshot")
	_check(character_snapshot.has("machine_runtime") and character_snapshot.has("machines"), "machine runtime diagnostics join the character snapshot")
	hub.call("return_to_menu")
	var history: Array = coordinator.call("get_snapshot").get("phase_history", [])
	_check(
		not history.is_empty()
		and str(history.back()).contains(
			"exploration_journal_rewards,exploration_runtime,ranch_runtime,husbandry_runtime,machine_runtime"
		),
		"production cleanup records complete reverse dependency order"
	)
	_check(int(hub.furnace_service.get_runtime_snapshot().get("machine_count", -1)) == 0, "return-to-menu clears machine state")
	hub.save_service.delete_world(world_id)
	if hub.audio_service != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
