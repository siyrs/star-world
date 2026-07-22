extends SceneTree

const ScalableFurnaceScript = preload(
	"res://src/machine/scalable_furnace_service.gd"
)
const ScalableStonecutterScript = preload(
	"res://src/machine/scalable_stonecutter_service.gd"
)
const ScalableAutomationScript = preload(
	"res://src/machine/scalable_machine_automation_service.gd"
)
const ScalableParticipantScript = preload(
	"res://src/machine/scalable_machine_runtime_participant.gd"
)
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

const TOTAL_MACHINES_PER_DOMAIN := 2048
const ACTIVE_MACHINES_PER_DOMAIN := 128

var checks := 0
var failures: Array[String] = []


class FakeAudio:
	extends Node
	var craft_count := 0

	func play_craft() -> void:
		craft_count += 1


class FakeHub:
	extends Node
	var inventory: Node
	var audio_service: Node
	var messages: Array[Dictionary] = []

	func _publish_character_message(
		message: String,
		severity: String,
		dedupe_key: String,
		duration: float
	) -> void:
		messages.append({
			"message": message,
			"severity": severity,
			"dedupe_key": dedupe_key,
			"duration": duration,
		})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_indexed_furnace_runtime()
	await _test_indexed_stonecutter_runtime()
	await _test_deferred_automation_sorting()
	await _test_exact_large_completion_batch()
	await _test_production_composition()
	if failures.is_empty():
		print("QA MACHINE SCALE RUNTIME PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MACHINE SCALE RUNTIME FAILURE: %s" % failure)
		print(
			"QA MACHINE SCALE RUNTIME FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_indexed_furnace_runtime() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var furnace = ScalableFurnaceScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(furnace)
	await process_frame
	_check(bool(furnace.setup(inventory.registry)), "scalable furnace loads production registries")
	_check(
		furnace.deserialize(_furnace_state()),
		"scalable furnace restores two thousand forty-eight compatible records",
	)
	var restored: Dictionary = furnace.get_runtime_snapshot()
	_check(
		int(restored.get("machine_count", 0)) == TOTAL_MACHINES_PER_DOMAIN
		and int(restored.get("active_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN,
		"furnace activity index excludes idle persisted machines",
	)
	var pending: Dictionary = furnace.advance_machine_runtime(0.05, true)
	_check(
		int(pending.get("evaluated_machine_count", -1)) == 0
		and str(pending.get("reason", "")) == "runtime_step_pending",
		"furnace runtime coalesces sub-step scheduler calls",
	)
	var completion_counter := {"count": 0}
	furnace.item_smelted.connect(
		func(_machine_id: String, _recipe_id: String, _output: Dictionary) -> void:
			completion_counter["count"] = int(completion_counter.get("count", 0)) + 1
	)
	var batch: Dictionary = furnace.advance_machine_runtime(6.05, true)
	_check(
		int(batch.get("evaluated_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN,
		"furnace runtime evaluates only runnable machines",
	)
	_check(
		int(batch.get("changed_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN
		and int(completion_counter.get("count", 0)) == ACTIVE_MACHINES_PER_DOMAIN,
		"all active furnaces complete through the indexed batch",
	)
	_check(
		(batch.get("changed_machine_ids", []) as Array).size() == 64
		and int(batch.get("dropped_changed_machine_samples", 0)) == 64,
		"furnace runtime keeps exact counts while bounding changed-id samples",
	)
	var runtime: Dictionary = furnace.get_runtime_snapshot()
	_check(
		int(runtime.get("active_machine_count", -1)) == 0
		and int(runtime.get("avoided_idle_evaluation_count", 0))
		>= TOTAL_MACHINES_PER_DOMAIN - ACTIVE_MACHINES_PER_DOMAIN,
		"completed furnaces leave the active index and idle scans remain avoided",
	)
	host.queue_free()
	await process_frame


func _test_indexed_stonecutter_runtime() -> void:
	var host := Node.new()
	var inventory = InventoryScript.new()
	var stonecutter = ScalableStonecutterScript.new()
	root.add_child(host)
	host.add_child(inventory)
	host.add_child(stonecutter)
	await process_frame
	_check(bool(stonecutter.setup(inventory.registry)), "scalable stonecutter loads production registries")
	_check(
		stonecutter.deserialize(_stonecutter_state()),
		"scalable stonecutter restores two thousand forty-eight compatible records",
	)
	var restored: Dictionary = stonecutter.get_runtime_snapshot()
	_check(
		int(restored.get("machine_count", 0)) == TOTAL_MACHINES_PER_DOMAIN
		and int(restored.get("active_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN,
		"stonecutter activity index excludes idle persisted machines",
	)
	var completion_counter := {"count": 0}
	stonecutter.item_processed.connect(
		func(_machine_id: String, _recipe_id: String, _output: Dictionary) -> void:
			completion_counter["count"] = int(completion_counter.get("count", 0)) + 1
	)
	var batch: Dictionary = stonecutter.advance_machine_runtime(3.1, true)
	_check(
		int(batch.get("evaluated_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN
		and int(batch.get("changed_machine_count", 0)) == ACTIVE_MACHINES_PER_DOMAIN,
		"stonecutter runtime evaluates and advances only runnable machines",
	)
	_check(
		int(completion_counter.get("count", 0)) == ACTIVE_MACHINES_PER_DOMAIN
		and (batch.get("changed_machine_ids", []) as Array).size() == 64,
		"stonecutter completion count remains exact with bounded diagnostics",
	)
	var runtime: Dictionary = stonecutter.get_runtime_snapshot()
	_check(
		int(runtime.get("active_machine_count", -1)) == 0
		and int(runtime.get("max_evaluated_machines_in_batch", 0))
		== ACTIVE_MACHINES_PER_DOMAIN,
		"stonecutter index removes completed work without a full idle scan",
	)
	host.queue_free()
	await process_frame


func _test_deferred_automation_sorting() -> void:
	var automation = ScalableAutomationScript.new()
	root.add_child(automation)
	for index in TOTAL_MACHINES_PER_DOMAIN:
		automation.call(
			"_add_candidate",
			&"furnace",
			"furnace@%d,20,0" % index,
			false
		)
	var pending: Dictionary = automation.get_runtime_snapshot()
	_check(
		int(pending.get("tracked_machine_count", 0)) == TOTAL_MACHINES_PER_DOMAIN
		and int(pending.get("candidate_sort_count", -1)) == 0
		and bool(pending.get("candidate_order_dirty", false)),
		"candidate events append without sorting the full automation directory each time",
	)
	automation.call("_ensure_candidate_order")
	var sorted: Dictionary = automation.get_runtime_snapshot()
	_check(
		int(sorted.get("candidate_sort_count", 0)) == 1
		and not bool(sorted.get("candidate_order_dirty", true)),
		"two thousand forty-eight automation candidates sort once at the cycle boundary",
	)
	automation.queue_free()
	await process_frame


func _test_exact_large_completion_batch() -> void:
	var hub := FakeHub.new()
	var inventory = InventoryScript.new()
	var audio := FakeAudio.new()
	var participant = ScalableParticipantScript.new()
	root.add_child(hub)
	hub.add_child(inventory)
	hub.add_child(audio)
	root.add_child(participant)
	hub.inventory = inventory
	hub.audio_service = audio
	participant.set("hub", hub)
	participant.set("_active", true)
	for index in 512:
		var furnace_job := index % 2 == 0
		participant.call(
			"_queue_completion",
			"furnace" if furnace_job else "stonecutter",
			("furnace@%d,20,0" if furnace_job else "stonecutter@%d,20,0") % index,
			"scale_recipe_%d" % (index % 4),
			{
				"item_id": "iron_ingot" if furnace_job else "stone_stairs",
				"count": 1 if furnace_job else 2,
			}
		)
	var pending: Dictionary = participant.get_lifecycle_snapshot()
	_check(
		int(pending.get("pending_completion_count", 0)) == 512
		and int(pending.get("pending_completion_sample_count", 0)) == 64,
		"completion batching retains exact jobs with sixty-four bounded event samples",
	)
	var summary: Dictionary = participant.call("flush_pending_completion_batch")
	_check(
		int(summary.get("completed_jobs", 0)) == 512
		and int(summary.get("item_total", 0)) == 768
		and int(summary.get("machine_count", 0)) == 512,
		"large completion summary preserves jobs, items and contributing machines",
	)
	_check(
		int(summary.get("sampled_event_count", 0)) == 64
		and int(summary.get("dropped_event_samples", 0)) == 448
		and int(summary.get("dropped_event_count", -1)) == 0,
		"only completion samples are dropped while valid domain events remain exact",
	)
	_check(
		hub.messages.size() == 1 and audio.craft_count == 1,
		"five hundred twelve completions produce one player message and one audio cue",
	)
	participant.queue_free()
	hub.queue_free()
	await process_frame


func _test_production_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var furnace: Node = hub.get("furnace_service") as Node
	var stonecutter: Node = hub.get("stonecutter_service") as Node
	var automation: Node = hub.get("machine_automation_service") as Node
	var participant: Node = hub.get("machine_runtime_participant") as Node
	_check(
		furnace != null
		and str(furnace.get_script().resource_path).ends_with("scalable_furnace_service.gd"),
		"production hub composes the scalable furnace without changing its public port",
	)
	_check(
		stonecutter != null
		and str(stonecutter.get_script().resource_path).ends_with("scalable_stonecutter_service.gd"),
		"production hub composes the scalable stonecutter at the stable node path",
	)
	_check(
		automation != null
		and str(automation.get_script().resource_path).ends_with("scalable_machine_automation_service.gd"),
		"production automation uses deferred candidate ordering",
	)
	_check(
		participant != null
		and str(participant.get_script().resource_path).ends_with("scalable_machine_runtime_participant.gd"),
		"production lifecycle installs exact completion aggregation",
	)
	var audio: Node = hub.get("audio_service") as Node
	if audio != null and audio.has_method("shutdown"):
		audio.call("shutdown")
	hub.queue_free()
	await process_frame
	await process_frame


func _furnace_state() -> Dictionary:
	var furnaces: Dictionary = {}
	for index in TOTAL_MACHINES_PER_DOMAIN:
		var active := index < ACTIVE_MACHINES_PER_DOMAIN
		furnaces["furnace@%d,20,0" % index] = {
			"type": "furnace",
			"input": {"item_id": "raw_iron", "count": 1} if active else {},
			"fuel": {"item_id": "coal", "count": 1} if active else {},
			"output": {},
			"active_recipe_id": "",
			"progress_seconds": 0.0,
			"burn_remaining_seconds": 0.0,
			"burn_total_seconds": 0.0,
		}
	return {
		"version": 1,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"furnaces": furnaces,
		"stonecutters": {},
	}


func _stonecutter_state() -> Dictionary:
	var stonecutters: Dictionary = {}
	for index in TOTAL_MACHINES_PER_DOMAIN:
		var active := index < ACTIVE_MACHINES_PER_DOMAIN
		stonecutters["stonecutter@%d,20,0" % index] = {
			"type": "stonecutter",
			"input": {"item_id": "stone", "count": 1} if active else {},
			"output": {},
			"active_recipe_id": "",
			"progress_seconds": 0.0,
		}
	return {
		"version": 1,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"furnaces": {},
		"stonecutters": stonecutters,
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
