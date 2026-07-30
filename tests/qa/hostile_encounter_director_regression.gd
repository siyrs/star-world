extends SceneTree

const RegistryScript = preload("res://src/entity/hostile_encounter_registry.gd")
const PolicyScript = preload("res://src/entity/hostile_encounter_policy.gd")
const DirectorScript = preload("res://src/entity/hostile_encounter_director.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")

var checks := 0
var failures: Array[String] = []


class FakeDayNight:
	extends Node
	var phase := "night"

	func get_phase() -> String:
		return phase


class FakeSurvival:
	extends Node
	var health := 20.0
	var max_health := 20.0


class FakePlayer:
	extends CharacterBody3D
	var survival: Node

	func _ready() -> void:
		add_to_group("player")

	func is_combat_target_available() -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_policy()
	await _test_real_director_and_spawner()
	_test_sixty_minute_planner()
	if failures.is_empty():
		print("QA HOSTILE ENCOUNTER DIRECTOR PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA HOSTILE ENCOUNTER DIRECTOR FAILURE: %s" % failure)
	print("QA HOSTILE ENCOUNTER DIRECTOR FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_registry_and_policy() -> void:
	var registry = RegistryScript.new()
	_check(registry.schema_version == 1, "encounter registry loads schema version one")
	_check(registry.get_validation_errors().is_empty(), "production encounter profiles pass strict normalization")
	_check(registry.get_profile_ids() == ["abyss_assault", "abyss_skirmish", "continent_night_patrol"], "registry exposes the exact three release profiles")
	var assault: Dictionary = registry.get_profile("abyss_assault")
	_check(int(assault.get("member_count", 0)) == 4, "abyss assault expands to four bounded members")
	_check(is_equal_approx(PolicyScript.estimate_pressure(assault), 5.6), "abyss assault pressure is the exact role composition total")
	var invalid_path := "user://invalid-hostile-encounters.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(file != null, "invalid encounter fixture opens for writing")
	if file != null:
		file.store_string(JSON.stringify({
			"schema_version":1,
			"profiles":[
				assault,
				{
					"id":"broken", "display_name":"broken",
					"map_ids":["abyss_world"], "phase_ids":["night"],
					"weight":1, "minimum_player_y":-64, "maximum_player_y":64,
					"minimum_health_ratio":0.5, "cooldown_seconds":20,
					"minimum_existing_pressure":0, "maximum_existing_pressure":0,
					"maximum_total_pressure":99, "minimum_spawn_radius":10,
					"maximum_spawn_radius":99,
					"members":[{"species_id":"zombie", "role":"vanguard", "count":6}],
				}
			]
		}, "  "))
		file.close()
		_check(not registry.load_from_file(invalid_path), "invalid encounter profile rejects the entire staged registry")
		_check(registry.get_profile_ids() == ["abyss_assault", "abyss_skirmish", "continent_night_patrol"], "failed encounter load preserves the previous complete registry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))

	var context := {
		"map_id":"abyss_world", "phase_id":"night", "player_y":10.0,
		"health_ratio":1.0, "existing_pressure":0.0, "existing_count":0,
		"hostile_cap":5, "active_encounters":0, "tracked_members":0,
		"cooldown_remaining":0.0,
	}
	_check(PolicyScript.is_profile_eligible(assault, context), "healthy deep-night player admits the bounded abyss assault")
	var low_health := context.duplicate(true)
	low_health["health_ratio"] = 0.25
	_check(not PolicyScript.is_profile_eligible(assault, low_health), "low health suppresses new hostile encounters")
	var pressure_blocked := context.duplicate(true)
	pressure_blocked["existing_pressure"] = 1.0
	pressure_blocked["existing_count"] = 1
	_check(not PolicyScript.is_profile_eligible(assault, pressure_blocked), "existing pressure blocks an oversized assault")
	var requests: Array[Dictionary] = PolicyScript.formation_requests(assault, Vector3.ZERO, 0.0)
	_check(requests.size() == 4, "formation planner emits one request per assault member")
	_check(str(requests[0].get("role", "")) == "vanguard", "formation begins with a vanguard pressure role")
	_check(str(requests[2].get("role", "")) == "support", "formation keeps the marksman in the support role")
	_check(float(requests[2].get("radius", 0.0)) > float(requests[0].get("radius", 0.0)), "support member receives the farther formation radius")


func _test_real_director_and_spawner() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var player := FakePlayer.new()
	var survival := FakeSurvival.new()
	player.survival = survival
	player.add_child(survival)
	player.position = Vector3(0.0, 10.0, 0.0)
	host.add_child(player)
	var day_night := FakeDayNight.new()
	host.add_child(day_night)
	var spawner = SpawnerScript.new()
	host.add_child(spawner)
	spawner.set_map_profile("abyss_world")
	spawner.setup(
		player,
		null,
		day_night,
		func(candidate: Vector3) -> Vector3: return Vector3(candidate.x, 1.0, candidate.z),
		true
	)
	spawner.set_process(false)
	var director = DirectorScript.new()
	director.auto_bind_parent = false
	host.add_child(director)
	director.setup(spawner, player, day_night, "abyss_world")
	await process_frame
	var started: Dictionary = director.force_decision_for_test("abyss_assault", 0.0)
	_check(bool(started.get("success", false)), "abyss assault creates exactly four role-aware members")
	var snapshot: Dictionary = director.get_snapshot()
	_check(int(snapshot.get("active_encounter_count", 0)) == 1, "director tracks one active encounter")
	_check(int(snapshot.get("tracked_member_count", 0)) == 4, "director tracks exactly four living members")
	_check(float(snapshot.get("active_pressure", 0.0)) <= 6.5, "real encounter remains inside its pressure budget")
	var encounter_members: Array[Node3D] = []
	var roles: Dictionary = {}
	var species: Dictionary = {}
	for child: Node in spawner.get_children():
		if child is not Node3D or not child.is_in_group("encounter_hostile"):
			continue
		var member := child as Node3D
		encounter_members.append(member)
		member.set_physics_process(false)
		var role := str(member.get_meta("encounter_role", ""))
		var species_id := str(member.get("species_id"))
		roles[role] = int(roles.get(role, 0)) + 1
		species[species_id] = int(species.get(species_id, 0)) + 1
		_check(member.get("target") == player, "encounter member shares the local player target")
		_check(not str(member.get_meta("encounter_id", "")).is_empty(), "encounter member owns a runtime-only encounter id")
	_check(encounter_members.size() == 4, "real spawner creates the complete four-member assault atomically")
	_check(int(roles.get("vanguard", 0)) == 2 and int(roles.get("support", 0)) == 1 and int(roles.get("finisher", 0)) == 1, "real assault preserves vanguard support and finisher roles")
	_check(int(species.get("zombie", 0)) == 2 and int(species.get("abyss_marksman", 0)) == 1 and int(species.get("abyss_brute", 0)) == 1, "real assault preserves the intended mixed-species composition")
	var blocked: Dictionary = director.force_decision_for_test("abyss_skirmish", 0.0)
	_check(not bool(blocked.get("success", true)), "encounter cooldown prevents an immediate second squad")
	for member: Node3D in encounter_members:
		spawner.call("_dispose_child", member, false)
	for _frame in 8:
		await process_frame
	director.advance_for_test(0.0)
	snapshot = director.get_snapshot()
	_check(int(snapshot.get("active_encounter_count", -1)) == 0, "cleared members complete the tracked encounter")
	_check(int(snapshot.get("completion_count", 0)) == 1, "director records one completed encounter")

	director.clear("test_reset")
	survival.health = 5.0
	var low_health_rejection: Dictionary = director.force_decision_for_test("", 0.0)
	_check(str(low_health_rejection.get("reason", "")) == "low_health", "low health rejection publishes the exact suppression reason")
	survival.health = survival.max_health
	var restarted: Dictionary = director.force_decision_for_test("abyss_skirmish", 0.0)
	_check(bool(restarted.get("success", false)), "director can start a new squad after health recovery")
	spawner.clear_creatures()
	director.clear("world_changed")
	for _frame in 8:
		await process_frame
	_check(int(director.get_snapshot().get("tracked_member_count", -1)) == 0 and spawner.get_child_count() == 0, "world clear removes every tracked encounter member")

	host.queue_free()
	for _frame in 24:
		await process_frame


func _test_sixty_minute_planner() -> void:
	var registry = RegistryScript.new()
	var profiles: Array[Dictionary] = registry.get_profiles()
	var active_duration := 0
	var cooldown := 0.0
	var active_encounters := 0
	var tracked_members := 0
	var active_pressure := 0.0
	var starts := 0
	var maximum_active := 0
	var maximum_tracked := 0
	var maximum_pressure := 0.0
	var active_bound_violations := 0
	var member_bound_violations := 0
	var pressure_bound_violations := 0
	for second in 3600:
		if active_duration > 0:
			active_duration -= 1
			if active_duration == 0:
				active_encounters = 0
				tracked_members = 0
				active_pressure = 0.0
		cooldown = maxf(0.0, cooldown - 1.0)
		var context := {
			"map_id":"abyss_world", "phase_id":"night", "player_y":10.0,
			"health_ratio":0.8, "existing_pressure":0.0, "existing_count":0,
			"hostile_cap":5, "active_encounters":active_encounters,
			"tracked_members":tracked_members, "cooldown_remaining":cooldown,
		}
		var selected: Dictionary = PolicyScript.select_profile(
			profiles, context, float(second % 100) / 100.0
		)
		if not selected.is_empty():
			active_encounters = 1
			tracked_members = int(selected.get("member_count", 0))
			active_pressure = PolicyScript.estimate_pressure(selected)
			active_duration = 28
			cooldown = float(selected.get("cooldown_seconds", 30.0))
			starts += 1
		maximum_active = maxi(maximum_active, active_encounters)
		maximum_tracked = maxi(maximum_tracked, tracked_members)
		maximum_pressure = maxf(maximum_pressure, active_pressure)
		if active_encounters > PolicyScript.MAX_ACTIVE_ENCOUNTERS:
			active_bound_violations += 1
		if tracked_members > PolicyScript.MAX_TRACKED_MEMBERS:
			member_bound_violations += 1
		if active_pressure > 8.0:
			pressure_bound_violations += 1
	_check(starts > 20, "sixty minute planner simulation starts repeated encounters")
	_check(active_bound_violations == 0, "sixty minute planner never exceeds the active encounter limit")
	_check(member_bound_violations == 0, "sixty minute planner never exceeds the tracked member limit")
	_check(pressure_bound_violations == 0, "sixty minute planner never exceeds the pressure hard limit")
	_check(maximum_active <= 1 and maximum_tracked <= 4 and maximum_pressure <= 5.6, "sixty minute planner simulation never exceeds encounter budgets")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
