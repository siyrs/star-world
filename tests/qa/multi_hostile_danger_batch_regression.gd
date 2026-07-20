extends SceneTree

const BatchPolicyScript = preload(
	"res://src/exploration/danger_refresh_batch_policy.gd"
)
const RuntimeParticipantScript = preload(
	"res://src/exploration/exploration_runtime_participant.gd"
)
const DangerServiceScript = preload(
	"res://src/exploration/exploration_danger_service.gd"
)
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const HudScript = preload("res://src/ui/hud.gd")

var checks := 0
var failures: Array[String] = []


class FakeDangerService:
	extends Node
	signal danger_changed(snapshot: Dictionary)
	var refresh_count := 0
	var clear_count := 0
	var snapshot := {
		"tier_id":"dangerous",
		"tier_label":"危险",
		"tone":"warning",
		"score":58,
		"reasons":["夜晚", "附近敌对生物 ×5"],
		"assessment":{"last_reused_environment":true},
	}

	func refresh_for_events() -> Dictionary:
		refresh_count += 1
		return snapshot.duplicate(true)

	func refresh_now() -> Dictionary:
		refresh_count += 1
		return snapshot.duplicate(true)

	func clear() -> void:
		clear_count += 1


class FakeDayNight:
	extends Node
	var phase := "night"

	func get_phase() -> String:
		return phase


class FakeDangerSpawner:
	extends Node
	var hostile_count := 5
	var hostile_pressure := 6.0
	var windup_count := 3
	var elite_windup_count := 1

	func get_nearby_hostile_count(_position: Vector3, _radius: float) -> int:
		return hostile_count

	func get_nearby_hostile_pressure(_position: Vector3, _radius: float) -> float:
		return hostile_pressure

	func get_nearby_hostile_windup_summary(
		_position: Vector3, _radius: float
	) -> Dictionary:
		return {
			"active_windup_count":windup_count,
			"elite_windup_count":elite_windup_count,
			"windup_pressure":4.0,
			"soonest_impact_seconds":0.35,
			"source_counts":{"zombie":2, "abyss_brute":1},
			"visited_nodes":5,
			"query_node_cap":64,
			"scan_cap_reached":false,
		}

	func get_ecology_snapshot() -> Dictionary:
		return {"danger_base":24, "profile_id":"fake"}


class FakeWorld:
	extends Node
	var profile_id := "abyss_world"
	var block_reads := 0

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func get_initial_block(position: Vector3i) -> String:
		block_reads += 1
		if position.y <= 3 and posmod(position.x + position.z, 4) == 0:
			return "lava"
		return "air" if posmod(position.x * 3 + position.y + position.z * 5, 11) == 0 else "stone"


class FakeWindupHostile:
	extends Node3D
	var state := "idle"
	var remaining := 0.0
	var source_id := "zombie"
	var danger_weight := 1.0
	var species_id := "zombie"

	func configure(
		p_state: String,
		p_remaining: float,
		p_source_id: String,
		p_elite: bool = false
	) -> void:
		state = p_state
		remaining = p_remaining
		source_id = p_source_id
		species_id = p_source_id
		add_to_group("creatures")
		add_to_group("hostile")
		if p_elite:
			danger_weight = 2.0
			add_to_group("elite")

	func get_hostile_attack_snapshot() -> Dictionary:
		return {
			"state":state,
			"source_id":source_id,
			"windup_remaining":remaining,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_batch_policy()
	await _test_runtime_event_coalescing()
	await _test_spawner_windup_summary()
	await _test_danger_sample_reuse()
	await _test_hud_incoming_warning()
	if failures.is_empty():
		print("QA MULTI HOSTILE DANGER BATCH PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MULTI HOSTILE DANGER BATCH FAILURE: %s" % failure)
		print(
			"QA MULTI HOSTILE DANGER BATCH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_batch_policy() -> void:
	var batch: Dictionary = BatchPolicyScript.build(
		{"ecology_changed":4, "phase_changed":1, "threat_changed":5}, 10, 2
	)
	_check(int(batch.get("event_count", 0)) == 10, "batch policy preserves accepted raw event count")
	_check(int(batch.get("coalesced_event_count", 0)) == 9, "ten events collapse behind one assessment")
	_check(int(batch.get("dropped_event_count", 0)) == 2, "batch policy reports bounded overflow")
	_check(
		batch.get("triggers", []) == ["threat_changed", "ecology_changed", "phase_changed"],
		"trigger order prioritizes immediate attacks before ecology and phase"
	)
	_check(str(batch.get("trigger_key", "")) == "threat_changed+ecology_changed+phase_changed", "batch exposes a stable compatibility trigger key")


func _test_runtime_event_coalescing() -> void:
	var host := Node.new()
	var participant = RuntimeParticipantScript.new()
	var danger := FakeDangerService.new()
	root.add_child(host)
	host.add_child(danger)
	host.add_child(participant)
	participant.set("danger_service", danger)
	participant.set("_active", true)
	var batches: Array[Dictionary] = []
	participant.connect(
		"danger_refresh_batch_completed",
		func(summary: Dictionary) -> void: batches.append(summary.duplicate(true))
	)
	participant.call("_on_phase_changed", "night")
	for _index in 4:
		participant.call("_on_ecology_changed", {})
	for _index in 5:
		participant.call("_on_threat_changed", {})
	await process_frame
	await process_frame
	_check(danger.refresh_count == 1, "ten synchronous runtime events perform one danger assessment")
	_check(batches.size() == 1, "ten synchronous events publish one refresh batch")
	if not batches.is_empty():
		var first: Dictionary = batches[0]
		_check(int(first.get("event_count", 0)) == 10, "refresh batch preserves all ten events")
		_check(int(first.get("coalesced_event_count", 0)) == 9, "refresh batch diagnoses nine avoided assessments")
		_check(bool(first.get("environment_reused", false)), "event refresh uses the cached environment path")
	var lifecycle: Dictionary = participant.call("get_lifecycle_snapshot")
	_check(int(lifecycle.get("immediate_event_count", 0)) == 10, "runtime diagnostics count raw immediate events")
	_check(int(lifecycle.get("immediate_refresh_count", 0)) == 1, "runtime diagnostics separate actual assessments")
	_check(int(lifecycle.get("max_events_in_refresh_batch", 0)) == 10, "runtime diagnostics retain the largest burst")
	for _index in 70:
		participant.call("queue_danger_refresh", "threat_changed")
	await process_frame
	await process_frame
	lifecycle = participant.call("get_lifecycle_snapshot")
	_check(danger.refresh_count == 2, "seventy more events still perform one additional assessment")
	_check(int(lifecycle.get("dropped_danger_event_count", 0)) == 6, "pending event hard cap drops only excess presentation events")
	_check(int(lifecycle.get("max_events_in_refresh_batch", 0)) == 64, "pending batch is hard-capped at sixty-four events")
	participant.call("queue_danger_refresh", "ecology_changed")
	participant.call("clear", &"qa_clear")
	await process_frame
	_check(danger.refresh_count == 2, "clear cancels a scheduled refresh before it reads cleared services")
	host.queue_free()
	await process_frame
	await process_frame


func _test_spawner_windup_summary() -> void:
	var spawner = SpawnerScript.new()
	root.add_child(spawner)
	await process_frame
	var entries := [
		["windup", 0.7, "zombie", false],
		["windup", 0.25, "zombie", false],
		["windup", 1.1, "abyss_brute", true],
		["idle", 0.0, "zombie", false],
		["cooldown", 0.0, "zombie", false],
	]
	for index in entries.size():
		var entry: Array = entries[index]
		var hostile := FakeWindupHostile.new()
		hostile.configure(
			str(entry[0]), float(entry[1]), str(entry[2]), bool(entry[3])
		)
		spawner.add_child(hostile)
		hostile.global_position = Vector3(float(index), 0.0, 0.0)
	var summary: Dictionary = spawner.get_nearby_hostile_windup_summary(
		Vector3.ZERO, 18.0
	)
	_check(int(summary.get("active_windup_count", 0)) == 3, "spawner aggregates three active nearby windups")
	_check(int(summary.get("elite_windup_count", 0)) == 1, "spawner keeps elite windup count separate")
	_check(is_equal_approx(float(summary.get("soonest_impact_seconds", -1.0)), 0.25), "spawner reports the soonest incoming impact")
	_check(int((summary.get("source_counts", {}) as Dictionary).get("zombie", 0)) == 2, "spawner aggregates attack sources without coordinates")
	_check(not summary.has("positions") and not summary.has("coordinates"), "windup summary never exposes exact attacker coordinates")
	_check(int(summary.get("visited_nodes", 0)) <= 64, "windup query obeys the hostile node scan cap")
	spawner.queue_free()
	await process_frame
	await process_frame


func _test_danger_sample_reuse() -> void:
	var day_night := FakeDayNight.new()
	var spawner := FakeDangerSpawner.new()
	var world := FakeWorld.new()
	var player := Node3D.new()
	var service = DangerServiceScript.new()
	root.add_child(day_night)
	root.add_child(spawner)
	root.add_child(world)
	root.add_child(player)
	root.add_child(service)
	player.global_position = Vector3(0.5, 8.0, 0.5)
	await process_frame
	_check(bool(service.setup(day_night, spawner)), "danger service accepts production danger data")
	service.attach_world(world, player)
	var first: Dictionary = service.refresh_now()
	var reads_after_first := world.block_reads
	_check(reads_after_first > 0 and reads_after_first <= 125, "first assessment performs one bounded environment scan")
	_check(int(first.get("windup_count", 0)) == 3, "danger snapshot includes aggregate incoming attacks")
	_check(str(first.get("windup_urgency_label", "")).contains("最快 0.3 秒"), "danger snapshot communicates the soonest attack")
	var second: Dictionary = service.refresh_for_events()
	_check(world.block_reads == reads_after_first, "event refresh reuses the environment sample in the same player block")
	var diagnostics: Dictionary = service.get_diagnostics()
	_check(int(diagnostics.get("environment_scan_count", 0)) == 1, "diagnostics count one physical environment scan")
	_check(int(diagnostics.get("environment_reuse_count", 0)) == 1, "diagnostics count one cached event assessment")
	_check(int(diagnostics.get("assessment_count", 0)) == 2, "diagnostics distinguish assessments from environment scans")
	_check(int(diagnostics.get("max_samples_observed", 0)) <= 125, "all physical scans remain within the 125-sample budget")
	_check(int(second.get("windup_count", 0)) == 3, "cached assessment preserves live windup telemetry")
	player.global_position.x += 1.0
	service.refresh_for_events()
	_check(world.block_reads > reads_after_first, "moving to a new block invalidates the cached environment sample")
	diagnostics = service.get_diagnostics()
	_check(int(diagnostics.get("environment_scan_count", 0)) == 2, "new player block performs exactly one new environment scan")
	service.clear()
	service.queue_free()
	player.queue_free()
	world.queue_free()
	spawner.queue_free()
	day_night.queue_free()
	await process_frame
	await process_frame


func _test_hud_incoming_warning() -> void:
	var hud = HudScript.new()
	root.add_child(hud)
	await process_frame
	hud.call(
		"_on_danger_changed",
		{
			"tier_id":"dangerous",
			"tier_label":"危险",
			"tone":"warning",
			"score":64,
			"reasons":["夜晚", "附近敌对生物 ×5"],
			"windup_count":5,
			"elite_windup_count":1,
			"soonest_impact_seconds":0.4,
			"windup_urgency_label":"来袭攻击 ×5（精英 ×1） · 最快 0.4 秒",
		}
	)
	_check(bool(hud.call("is_danger_warning_visible")), "HUD displays a global incoming attack warning")
	var warning := str(hud.call("get_danger_warning_text"))
	_check(warning.contains("×5") and warning.contains("精英 ×1") and warning.contains("0.4 秒"), "HUD warning preserves count, elite count and soonest impact")
	var warning_label: Label = hud.get("_danger_warning") as Label
	_check(warning_label != null and warning_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "incoming warning remains a mouse-passthrough presentation layer")
	hud.call(
		"_on_danger_changed",
		{
			"tier_id":"safe",
			"tier_label":"低",
			"tone":"success",
			"score":8,
			"reasons":[],
			"windup_count":0,
		}
	)
	_check(not bool(hud.call("is_danger_warning_visible")), "HUD clears the warning when no attacks are winding up")
	hud.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
