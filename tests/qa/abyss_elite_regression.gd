extends SceneTree

const FactoryScript = preload("res://src/entity/creature_factory.gd")
const EcologyRegistryScript = preload("res://src/entity/creature_ecology_registry.gd")
const EcologyPolicyScript = preload("res://src/entity/creature_ecology_policy.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const DangerRegistryScript = preload("res://src/exploration/exploration_danger_registry.gd")
const DangerPolicyScript = preload("res://src/exploration/exploration_danger_policy.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")

var checks := 0
var failures: Array[String] = []


class FakeDayNight:
	extends Node
	var phase := "night"
	func get_phase() -> String:
		return phase


class FakeTarget:
	extends Node3D
	var health := 20.0
	var damage_events := 0
	var last_source := ""
	func _ready() -> void:
		add_to_group("player")
	func is_combat_target_available() -> bool:
		return health > 0.0
	func take_damage(amount: float, source: String = "world") -> void:
		health = maxf(0.0, health - maxf(0.0, amount))
		damage_events += 1
		last_source = source


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_conditions()
	await _test_production_spawner_and_elite_pressure()
	await _test_heavy_attack_and_drop()
	_test_danger_and_prompt()
	if failures.is_empty():
		print("QA ABYSS ELITE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA ABYSS ELITE FAILURE: %s" % failure)
		print("QA ABYSS ELITE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_catalog_and_conditions() -> void:
	var factory = FactoryScript.new()
	_check(factory.get_validation_errors().is_empty(), "production creature script/profile catalog has no drift")
	_check(factory.get_hostile_attack_validation_errors().is_empty(), "elite hostile attack data is valid")
	_check(factory.get_species_ids() == ["abyss_brute", "chicken", "cow", "pig", "zombie"], "factory exposes the fifth production species")
	var brute_profile: Dictionary = factory.get_profile("abyss_brute")
	var zombie_profile: Dictionary = factory.get_profile("zombie")
	_check(bool(brute_profile.get("elite", false)), "abyss brute is explicitly elite")
	_check(float(brute_profile.get("danger_weight", 0.0)) == 2.0, "abyss brute contributes double hostile pressure")
	_check(float(brute_profile.get("max_health", 0.0)) > float(zombie_profile.get("max_health", 99.0)), "elite health exceeds the normal zombie")
	_check(float(brute_profile.get("speed", 99.0)) < float(zombie_profile.get("speed", 0.0)), "elite trades speed for a readable heavy strike")
	_check(int(brute_profile.get("drops", {}).get("abyss_cinder", [0, 0])[0]) == 1, "elite drop enters the existing abyss progression route")

	var registry = EcologyRegistryScript.new()
	_check(registry.schema_version == 2, "conditional ecology schema is version 2")
	_check(registry.get_validation_errors().is_empty(), "production conditional ecology data is valid")
	var abyss: Dictionary = registry.get_profile("abyss_world")
	var hostile_entries: Array = abyss.get("hostile_species", [])
	var surface_day := EcologyPolicyScript.weighted_species(
		hostile_entries,
		0.99,
		"day",
		{"player_y":35.0, "species_counts":{}}
	)
	_check(surface_day == "zombie", "surface daytime abyss excludes the elite")
	var surface_night := EcologyPolicyScript.weighted_species(
		hostile_entries,
		0.99,
		"night",
		{"player_y":35.0, "species_counts":{}}
	)
	_check(surface_night == "abyss_brute", "night makes the rare abyss elite eligible")
	var deep_day := EcologyPolicyScript.weighted_species(
		hostile_entries,
		0.99,
		"day",
		{"player_y":15.0, "species_counts":{}}
	)
	_check(deep_day == "abyss_brute", "deep layers make the elite eligible outside night")
	var capped := EcologyPolicyScript.weighted_species(
		hostile_entries,
		0.99,
		"night",
		{"player_y":15.0, "species_counts":{"abyss_brute":1}}
	)
	_check(capped == "zombie", "per-species cap prevents a second abyss elite")
	for profile_id: String in ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands"]:
		var profile: Dictionary = registry.get_profile(profile_id)
		var ids: Array[String] = []
		for entry: Dictionary in profile.get("hostile_species", []):
			ids.append(str(entry.get("id", "")))
		_check("abyss_brute" not in ids, "%s cannot select the abyss-only elite" % profile_id)


func _test_production_spawner_and_elite_pressure() -> void:
	var day_night := FakeDayNight.new()
	var player := Node3D.new()
	player.global_position = Vector3(0.0, 15.0, 0.0)
	var spawner = SpawnerScript.new()
	root.add_child(day_night)
	root.add_child(player)
	root.add_child(spawner)
	await process_frame
	spawner.set_map_profile("abyss_world")
	spawner.setup(player, null, day_night, Callable(), true)
	var brute_variant: Variant = spawner.spawn_creature("abyss_brute", Vector3(2.0, 15.0, 0.0))
	_check(brute_variant is Node3D, "production spawner creates the abyss elite")
	if brute_variant is Node3D:
		var brute: Node3D = brute_variant
		_check(brute.is_in_group("hostile"), "elite participates in the generic hostile population")
		_check(brute.is_in_group("elite"), "elite owns an explicit high-signal group")
		_check(brute.get("target") == player, "generic hostile capability binds the real player target")
		_check(spawner.get_species_count("abyss_brute") == 1, "production spawner tracks elite species count")
		_check(spawner.get_nearby_hostile_count(Vector3.ZERO, 18.0) == 1, "generic hostile count includes the elite")
		_check(is_equal_approx(spawner.get_nearby_hostile_pressure(Vector3.ZERO, 18.0), 2.0), "elite contributes weighted danger pressure")
		var snapshot: Dictionary = spawner.get_ecology_snapshot()
		_check(int(snapshot.get("elite_count", 0)) == 1, "ecology diagnostics expose one bounded elite")
		_check(int(snapshot.get("species_counts", {}).get("abyss_brute", 0)) == 1, "ecology diagnostics expose per-species counts")
	var zombie_variant: Variant = spawner.spawn_creature("zombie", Vector3(3.0, 15.0, 0.0))
	_check(zombie_variant is Node3D, "production spawner still creates normal zombies")
	_check(spawner.get_nearby_hostile_count(Vector3.ZERO, 18.0) == 2, "normal and elite hostiles share the same cap accounting")
	_check(is_equal_approx(spawner.get_nearby_hostile_pressure(Vector3.ZERO, 18.0), 3.0), "normal plus elite pressure is additive")
	spawner.clear_creatures()
	spawner.queue_free()
	player.queue_free()
	day_night.queue_free()
	await process_frame
	await process_frame


func _test_heavy_attack_and_drop() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var target := FakeTarget.new()
	host.add_child(target)
	target.global_position = Vector3(0.0, 2.0, 1.8)
	var factory = FactoryScript.new()
	var brute_variant: Variant = factory.create("abyss_brute", Vector3(0.0, 2.0, 0.0), target, null)
	_check(brute_variant is Node3D, "factory creates the production elite instance")
	if brute_variant is not Node3D:
		host.queue_free()
		await process_frame
		return
	var brute: Node3D = brute_variant
	host.add_child(brute)
	await process_frame
	brute.set_physics_process(false)
	brute.set("target", target)
	var attack: Dictionary = brute.call("get_hostile_attack_snapshot")
	_check(float(attack.get("windup_seconds", 0.0)) == 1.35, "elite uses its authoritative long windup")
	_check(float(attack.get("attack_range", 0.0)) == 2.2, "elite owns the larger committed hit range")
	_check(bool(brute.call("_begin_attack_windup")), "elite starts a readable heavy windup")
	brute.call("_advance_attack_windup", 0.8)
	_check(target.damage_events == 0, "partial elite windup deals no early damage")
	target.global_position = Vector3(0.0, 2.0, 3.0)
	brute.call("_advance_attack_windup", 0.1)
	attack = brute.call("get_hostile_attack_snapshot")
	_check(str(attack.get("last_cancel_reason", "")) == "target_evaded", "leaving the elite warning zone cancels the heavy attack")
	_check(target.damage_events == 0, "successful elite dodge prevents all damage")
	brute.call("_physics_process", 0.9)
	target.global_position = Vector3(0.0, 2.0, 1.8)
	brute.set("target", target)
	_check(bool(brute.call("_begin_attack_windup")), "elite can attack again after bounded cancel recovery")
	brute.call("_advance_attack_windup", 1.36)
	_check(target.damage_events == 1 and is_equal_approx(target.health, 16.0), "completed elite windup commits exactly one four-point hit")
	_check(target.last_source == "abyss_brute", "elite hit preserves its stable source identity")
	var drops: Dictionary = brute.call("_roll_drops")
	_check(int(drops.get("abyss_cinder", 0)) == 1, "elite always yields one useful abyss cinder")
	_check(not brute.call("get_hostile_attack_snapshot").has("position"), "elite attack diagnostics expose no navigation coordinates")
	host.queue_free()
	await process_frame
	await process_frame


func _test_danger_and_prompt() -> void:
	var config: Dictionary = DangerRegistryScript.new().get_config()
	var normal: Dictionary = DangerPolicyScript.assess(
		{"map_id":"abyss_world", "map_base":36, "player_y":20, "phase":"night", "hostile_count":1, "hostile_pressure":1.0, "lava_samples":0, "air_samples":0, "total_samples":125},
		config
	)
	var elite: Dictionary = DangerPolicyScript.assess(
		{"map_id":"abyss_world", "map_base":36, "player_y":20, "phase":"night", "hostile_count":1, "hostile_pressure":2.0, "lava_samples":0, "air_samples":0, "total_samples":125},
		config
	)
	_check(int(elite.get("score", 0)) > int(normal.get("score", 0)), "one elite raises danger above one normal hostile")
	_check((elite.get("reasons", []) as Array).has("附近精英敌对生物"), "danger feedback explains elite pressure")
	_check(is_equal_approx(float(elite.get("hostile_pressure", 0.0)), 2.0), "danger snapshot preserves weighted hostile pressure")
	var prompt: Dictionary = PromptResolverScript.new().resolve(
		{
			"type":"entity",
			"display_name":"深渊重击者",
			"elite":true,
			"health":28.0,
			"max_health":28.0,
			"hostile_attack":{"enabled":true, "state":"windup", "windup_remaining":0.7},
		},
		null,
		null,
		null
	)
	_check(str(prompt.get("title", "")).contains("精英"), "elite focus is explicitly labelled")
	_check(str(prompt.get("subtitle", "")).contains("精英重击蓄力"), "elite prompt explains the heavy windup")
	_check(str(prompt.get("secondary", "")).contains("离开红色预警圈"), "elite prompt teaches the real dodge response")
	_check(str(prompt.get("tone", "")) == "error", "elite combat prompt uses urgent presentation")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
