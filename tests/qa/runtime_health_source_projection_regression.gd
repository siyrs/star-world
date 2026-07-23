extends SceneTree

const ReportServiceScript = preload(
	"res://src/diagnostics/runtime_health_report_service.gd"
)
const SchedulerScript = preload("res://src/machine/machine_runtime_scheduler.gd")
const AgricultureScript = preload("res://src/agriculture/scalable_agriculture_service.gd")

var checks := 0
var failures: Array[String] = []


class CountingHealthSource extends Node:
	var health_snapshot: Dictionary = {}
	var health_calls := 0
	var snapshot_calls := 0
	var runtime_calls := 0

	func get_health_snapshot() -> Dictionary:
		health_calls += 1
		return health_snapshot.duplicate(true)

	func get_snapshot() -> Dictionary:
		snapshot_calls += 1
		return {"heavy_snapshot_must_not_run": true}

	func get_runtime_snapshot() -> Dictionary:
		runtime_calls += 1
		return {"heavy_runtime_must_not_run": true}


class GenericSnapshotSource extends Node:
	var snapshot: Dictionary = {}

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_ecology_snapshot() -> Dictionary:
		return snapshot.duplicate(true)

	func get_streaming_stats() -> Dictionary:
		return snapshot.duplicate(true)


class FakeSaveService extends Node:
	signal save_recovered(world_id: String, source: String)
	var catalog: Dictionary = {}

	func get_catalog_diagnostics() -> Dictionary:
		return catalog.duplicate(true)


class FakeHub extends Node:
	var save_service: Node
	var machine_runtime: Node
	var agriculture_service: Node
	var husbandry_service: Node
	var animal_attraction_service: Node
	var animal_product_service: Node
	var creature_spawner: Node
	var pickup_stack_coordinator: Node
	var structural_integrity_service: Node


class CountingMachineDomain extends Node:
	var machine_count := 0
	var active_machine_count := 0
	var tracked_machine_count := 0
	var health_calls := 0
	var runtime_calls := 0
	var externally_scheduled := false

	func advance_machine_runtime(_seconds: float, _emit_events: bool = true) -> Dictionary:
		return {"changed_machine_count": 0}

	func get_health_snapshot() -> Dictionary:
		health_calls += 1
		return {
			"machine_count": machine_count,
			"active_machine_count": active_machine_count,
			"tracked_machine_count": tracked_machine_count,
		}

	func get_runtime_snapshot() -> Dictionary:
		runtime_calls += 1
		var heavy_domains: Dictionary = {}
		for index in 256:
			heavy_domains["domain-%d" % index] = {"state": index}
		return {
			"machine_count": machine_count,
			"domains": heavy_domains,
		}

	func set_external_scheduler(value: bool) -> void:
		externally_scheduled = value


class LegacyMachineDomain extends Node:
	var runtime_calls := 0

	func advance_machine_runtime(_seconds: float, _emit_events: bool = true) -> Dictionary:
		return {"changed_machine_count": 0}

	func get_runtime_snapshot() -> Dictionary:
		runtime_calls += 1
		return {"machine_count": 7, "legacy_payload": {"bounded": false}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_report_prefers_lightweight_sources()
	await _test_scheduler_uses_domain_health_ports()
	await _test_agriculture_maturity_cache()
	if failures.is_empty():
		print("QA RUNTIME HEALTH SOURCES PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RUNTIME HEALTH SOURCES FAILURE: %s" % failure)
		print(
			"QA RUNTIME HEALTH SOURCES FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_report_prefers_lightweight_sources() -> void:
	var host := Node.new()
	root.add_child(host)
	var hub := FakeHub.new()
	var save := FakeSaveService.new()
	var world := GenericSnapshotSource.new()
	var machines := CountingHealthSource.new()
	var agriculture := CountingHealthSource.new()
	var husbandry := GenericSnapshotSource.new()
	var attraction := GenericSnapshotSource.new()
	var products := GenericSnapshotSource.new()
	var ecology := GenericSnapshotSource.new()
	var pickups := GenericSnapshotSource.new()
	var structural := GenericSnapshotSource.new()
	world.snapshot = {"loaded": 12, "pending": 3}
	machines.health_snapshot = {
		"machine_count": 4096,
		"domain_count": 16,
		"domain_limit": 16,
	}
	agriculture.health_snapshot = {
		"crop_count": 2048,
		"mature_crop_count": 512,
		"soil_count": 2048,
		"world_mutation_batch": {"rejection_count": 0, "unsupported_count": 0},
	}
	husbandry.snapshot = {"managed_animals": 4, "maximum": 64}
	attraction.snapshot = {"following": 2}
	products.snapshot = {"tracked_animals": 3, "pending_products": 1}
	ecology.snapshot = {
		"passive_count": 2,
		"passive_cap": 12,
		"hostile_count": 0,
		"hostile_cap": 2,
	}
	pickups.snapshot = {"pickup_node_count": 2, "max_pickup_nodes": 128}
	structural.snapshot = {"pending_candidates": 0, "candidate_queue_budget": 65536}
	save.catalog = {"hit_count": 1, "last_hit_count": 1, "last_world_count": 1}
	for node: Node in [
		hub,
		save,
		world,
		machines,
		agriculture,
		husbandry,
		attraction,
		products,
		ecology,
		pickups,
		structural,
	]:
		host.add_child(node)
	hub.save_service = save
	hub.machine_runtime = machines
	hub.agriculture_service = agriculture
	hub.husbandry_service = husbandry
	hub.animal_attraction_service = attraction
	hub.animal_product_service = products
	hub.creature_spawner = ecology
	hub.pickup_stack_coordinator = pickups
	hub.structural_integrity_service = structural
	var report_service = ReportServiceScript.new()
	host.add_child(report_service)
	await process_frame
	_check(report_service.setup(hub), "lightweight report service accepts a complete source hub")
	report_service.begin_world("qa-health-sources")
	report_service.attach_runtime(world)
	var report: Dictionary = report_service.get_snapshot()
	var methods: Dictionary = report.get("source_methods", {})
	_check(
		str(methods.get("machines", "")) == "get_health_snapshot",
		"machine aggregation selects the dedicated health port",
	)
	_check(
		str(methods.get("agriculture", "")) == "get_health_snapshot",
		"agriculture aggregation selects the dedicated health port",
	)
	_check(
		int(report.get("fallback_source_count", -1)) == 0
		and int(report.get("unavailable_source_count", -1)) == 0,
		"complete production-style sources require no fallback or unavailable port",
	)
	_check(
		machines.health_calls == 1 and machines.snapshot_calls == 0 and machines.runtime_calls == 0,
		"machine heavy snapshots are never called by health aggregation",
	)
	_check(
		agriculture.health_calls == 1
		and agriculture.snapshot_calls == 0
		and agriculture.runtime_calls == 0,
		"agriculture heavy snapshots are never called by health aggregation",
	)
	var serialized := JSON.stringify(report)
	_check(
		not serialized.contains("heavy_snapshot_must_not_run")
		and not serialized.contains("heavy_runtime_must_not_run"),
		"heavy source payloads cannot escape into telemetry history",
	)
	_check(
		int(report.get("preferred_source_count", 0)) == 11,
		"all eleven fixed sources use their preferred bounded contract",
	)
	report_service.shutdown()
	host.queue_free()
	await process_frame
	await process_frame


func _test_scheduler_uses_domain_health_ports() -> void:
	var scheduler = SchedulerScript.new()
	var furnace := CountingMachineDomain.new()
	var stonecutter := CountingMachineDomain.new()
	furnace.machine_count = 3000
	furnace.active_machine_count = 16
	stonecutter.machine_count = 1096
	stonecutter.active_machine_count = 8
	root.add_child(scheduler)
	root.add_child(furnace)
	root.add_child(stonecutter)
	await process_frame
	_check(
		bool(scheduler.register_domain(&"furnace", furnace).get("success", false))
		and bool(scheduler.register_domain(&"stonecutter", stonecutter).get("success", false)),
		"scheduler accepts two lightweight machine domains",
	)
	var health: Dictionary = scheduler.get_health_snapshot()
	_check(
		int(health.get("machine_count", 0)) == 4096,
		"scheduler aggregates the full 4,096-machine capacity from scalar counts",
	)
	_check(
		int(health.get("active_machine_count", 0)) == 24,
		"scheduler aggregates active machine counts without enumerating machines",
	)
	_check(
		furnace.health_calls == 1
		and stonecutter.health_calls == 1
		and furnace.runtime_calls == 0
		and stonecutter.runtime_calls == 0,
		"scheduler never constructs heavy domain dictionaries when health ports exist",
	)
	_check(
		int(health.get("fallback_domain_count", -1)) == 0,
		"production machine domains require zero health fallback",
	)
	var legacy := LegacyMachineDomain.new()
	root.add_child(legacy)
	await process_frame
	_check(
		bool(scheduler.register_domain(&"legacy", legacy).get("success", false)),
		"legacy machine domains retain a compatibility registration path",
	)
	var compatible: Dictionary = scheduler.get_health_snapshot()
	_check(
		int(compatible.get("machine_count", 0)) == 4103
		and int(compatible.get("fallback_domain_count", 0)) == 1
		and int(compatible.get("total_health_fallback_count", 0)) == 1,
		"legacy fallback is bounded, visible and counted exactly once",
	)
	_check(legacy.runtime_calls == 1, "legacy fallback calls its heavy snapshot only when required")
	scheduler.shutdown()
	for node: Node in [scheduler, furnace, stonecutter, legacy]:
		node.queue_free()
	await process_frame
	await process_frame


func _test_agriculture_maturity_cache() -> void:
	var service = AgricultureScript.new()
	root.add_child(service)
	await process_frame
	var registry: Variant = service.get("crop_registry")
	var definition: Dictionary = registry.call("get_crop", "wheat")
	var stages: Array = definition.get("stage_blocks", [])
	_check(stages.size() >= 2, "production wheat exposes multiple growth stages")
	var mature_stage := maxi(0, stages.size() - 1)
	var payload := {
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"crops": {
			"0,1,0": {
				"crop_id": "wheat",
				"position": [0, 1, 0],
				"stage": mature_stage,
				"elapsed_seconds": 0.0,
			},
			"1,1,0": {
				"crop_id": "wheat",
				"position": [1, 1, 0],
				"stage": 0,
				"elapsed_seconds": 0.0,
			},
		},
		"soil_moisture": {},
	}
	_check(service.deserialize(payload), "agriculture health cache accepts production save data")
	var health: Dictionary = service.get_health_snapshot()
	_check(
		int(health.get("crop_count", 0)) == 2
		and int(health.get("mature_crop_count", 0)) == 1,
		"agriculture cache restores exact crop and mature counts",
	)
	var crops: Dictionary = service.get("_crops")
	var growing: Dictionary = crops.get("1,1,0", {}).duplicate(true)
	growing["stage"] = mature_stage
	crops["1,1,0"] = growing
	service.set("_crops", crops)
	service.emit_signal("crop_stage_changed", Vector3i(1, 1, 0), "wheat", mature_stage)
	_check(
		int(service.get_health_snapshot().get("mature_crop_count", 0)) == 2,
		"maturity signal updates the cached count without a crop dictionary scan",
	)
	service.emit_signal("crop_harvested", Vector3i(1, 1, 0), "wheat", [])
	_check(
		int(service.get_health_snapshot().get("mature_crop_count", 0)) == 1,
		"harvest signal decrements the cached mature count",
	)
	var serialized := JSON.stringify(service.get_health_snapshot())
	_check(
		not serialized.contains("crop_counts")
		and not serialized.contains("last_atomic_harvest")
		and not serialized.contains("soil_refresh_cache"),
		"agriculture health snapshot excludes full runtime dictionaries",
	)
	service.clear()
	_check(
		int(service.get_health_snapshot().get("crop_count", -1)) == 0
		and int(service.get_health_snapshot().get("mature_crop_count", -1)) == 0,
		"agriculture clear resets cached health counters",
	)
	service.shutdown()
	service.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
