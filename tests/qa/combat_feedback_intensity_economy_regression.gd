extends SceneTree

const DamageDirectionPolicy = preload("res://src/combat/damage_direction_policy.gd")
const EncounterIntensityRegistryScript = preload("res://src/entity/encounter_intensity_registry.gd")
const EncounterPolicy = preload("res://src/entity/hostile_encounter_policy.gd")
const RewardRegistryScript = preload("res://src/entity/encounter_reward_registry.gd")
const RewardServiceScript = preload("res://src/entity/encounter_reward_service.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const FeedbackOverlayScript = preload("res://src/ui/combat_feedback_overlay.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")

var checks := 0
var failures: Array[String] = []


class FakeCombat:
	extends Node
	signal outgoing_attack_resolved(result: Dictionary)
	signal incoming_damage_resolved(result: Dictionary)
	signal attack_rejected(result: Dictionary)
	signal cooldown_changed(snapshot: Dictionary)

	func get_cooldown_snapshot() -> Dictionary:
		return {"ready": true, "ready_ratio": 1.0}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_direction_policy()
	_test_settings_and_intensity_policy()
	_test_reward_contracts()
	await _test_feedback_overlay()
	await _test_flint_crafting_loop()
	if failures.is_empty():
		print("QA COMBAT FEEDBACK INTENSITY ECONOMY PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA COMBAT FEEDBACK INTENSITY ECONOMY FAILURE: %s" % failure)
	print(
		"QA COMBAT FEEDBACK INTENSITY ECONOMY FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _test_direction_policy() -> void:
	var player_position := Vector3.ZERO
	var forward := Vector3.FORWARD
	var fixtures := {
		"front": player_position + Vector3.FORWARD * 5.0,
		"right": player_position + Vector3.RIGHT * 5.0,
		"rear": player_position + Vector3.BACK * 5.0,
		"left": player_position + Vector3.LEFT * 5.0,
	}
	for direction: String in DamageDirectionPolicy.DIRECTIONS:
		var result: Dictionary = DamageDirectionPolicy.classify(
			player_position, forward, fixtures[direction]
		)
		_check(
			str(result.get("direction", "")) == direction,
			"direction policy classifies %s damage deterministically" % direction
		)
		_check(bool(result.get("source_available", false)), "%s fixture retains source availability" % direction)
	var missing := DamageDirectionPolicy.classify(player_position, forward, player_position)
	_check(str(missing.get("direction", "")) == "front", "missing source falls back to front without inventing a side")
	_check(not bool(missing.get("source_available", true)), "missing source is explicitly observable")
	_check(DamageDirectionPolicy.normalize_direction("invalid") == "front", "invalid direction normalizes to the accessible front fallback")
	_check(DamageDirectionPolicy.localized_source_label("zombie") == "近战", "damage source label distinguishes melee attackers")
	_check(DamageDirectionPolicy.localized_source_label("abyss_marksman") == "深渊弹", "damage source label distinguishes abyss projectiles")
	_check(DamageDirectionPolicy.localized_source_label("lava") == "环境", "damage source label distinguishes environmental hazards")


func _test_settings_and_intensity_policy() -> void:
	var normalized := SettingsPolicy.normalize({
		"show_damage_direction_pulses": false,
		"damage_camera_impact": 4.0,
		"encounter_intensity": "HIGH_RISK",
	})
	_check(not bool(normalized.get("show_damage_direction_pulses", true)), "visual direction pulses can be disabled locally")
	_check(is_equal_approx(float(normalized.get("damage_camera_impact", 0.0)), 1.5), "camera impact is clamped to the bounded maximum")
	_check(str(normalized.get("encounter_intensity", "")) == "high_risk", "encounter intensity identity normalizes case-insensitively")
	var corrupt := SettingsPolicy.normalize({
		"show_damage_direction_pulses": "false",
		"damage_camera_impact": INF,
		"encounter_intensity": "nightmare",
	})
	_check(bool(corrupt.get("show_damage_direction_pulses", false)), "corrupt pulse setting returns to the safe default")
	_check(is_equal_approx(float(corrupt.get("damage_camera_impact", 0.0)), 1.0), "non-finite camera impact returns to the safe default")
	_check(str(corrupt.get("encounter_intensity", "")) == "standard", "unknown intensity returns to the versioned standard profile")

	var registry = EncounterIntensityRegistryScript.new()
	_check(registry.schema_version == 1, "encounter intensity registry loads schema version one")
	_check(registry.get_validation_errors().is_empty(), "production intensity profiles pass strict validation")
	_check(
		registry.get_profile_ids() == ["casual", "high_risk", "standard"],
		"registry exposes exactly the three planned intensity identities"
	)
	var casual: Dictionary = registry.get_profile("casual")
	var standard: Dictionary = registry.get_profile("standard")
	var high_risk: Dictionary = registry.get_profile("high_risk")
	var profile := {
		"id": "fixture",
		"map_ids": ["star_continent"],
		"phase_ids": ["night"],
		"minimum_player_y": -20.0,
		"maximum_player_y": 120.0,
		"minimum_health_ratio": 0.5,
		"minimum_existing_pressure": 0.0,
		"maximum_existing_pressure": 10.0,
		"maximum_total_pressure": 10.0,
		"member_count": 2,
		"cooldown_seconds": 40.0,
		"members": [{"species_id":"zombie", "role":"vanguard", "count":2}],
	}
	_check(is_equal_approx(EncounterPolicy.effective_cooldown_seconds(profile, casual), 54.0), "casual intensity lengthens encounter cooldown only")
	_check(is_equal_approx(EncounterPolicy.effective_cooldown_seconds(profile, standard), 40.0), "standard intensity preserves encounter cooldown")
	_check(is_equal_approx(EncounterPolicy.effective_cooldown_seconds(profile, high_risk), 30.0), "high-risk intensity shortens encounter cooldown only")
	_check(is_equal_approx(EncounterPolicy.effective_pressure_limit(10.0, casual), 7.5), "casual intensity lowers danger pressure budget")
	_check(is_equal_approx(EncounterPolicy.effective_pressure_limit(10.0, high_risk), 12.5), "high-risk intensity raises danger pressure budget")
	var base_context := {
		"map_id":"star_continent", "phase_id":"night", "player_y":10.0,
		"health_ratio":1.0, "existing_pressure":6.0, "existing_count":2,
		"hostile_cap":20, "active_encounters":0, "tracked_members":0,
		"cooldown_remaining":0.0,
	}
	var casual_context := base_context.duplicate(true)
	casual_context["intensity_profile"] = casual
	var standard_context := base_context.duplicate(true)
	standard_context["intensity_profile"] = standard
	var high_context := base_context.duplicate(true)
	high_context["intensity_profile"] = high_risk
	_check(not EncounterPolicy.is_profile_eligible(profile, casual_context), "casual pressure budget suppresses an otherwise valid high-pressure encounter")
	_check(EncounterPolicy.is_profile_eligible(profile, standard_context), "standard pressure budget preserves the formal encounter")
	_check(EncounterPolicy.is_profile_eligible(profile, high_context), "high-risk pressure budget accepts the same formal encounter")
	_check(
		EncounterPolicy.expand_members(profile) == [
			{"species_id":"zombie", "role":"vanguard"},
			{"species_id":"zombie", "role":"vanguard"},
		],
		"intensity scaling never changes formal enemy composition"
	)


func _test_reward_contracts() -> void:
	var registry = RewardRegistryScript.new()
	_check(registry.get_validation_errors().is_empty(), "production reward registry remains strictly valid")
	for profile_id: String in registry.get_profile_ids():
		for shot_count: int in [0, 4, 8, 16]:
			var reward: Dictionary = registry.build_reward(profile_id, shot_count)
			var rewards: Dictionary = reward.get("rewards", {})
			for ammo_item_id: String in ["arrow", "light_round", "shotgun_shell"]:
				_check(
					int(rewards.get(ammo_item_id, 0)) == 0,
					"%s reward at %d shots contains no completed %s"
					% [profile_id, shot_count, ammo_item_id]
				)
			_check(
				rewards.keys().all(func(item_id: Variant) -> bool: return str(item_id) in ["flint", "gunpowder"]),
				"%s reward contains only bounded crafting inputs" % profile_id
			)
	var service = RewardServiceScript.new()
	_check(bool(service.call("_contains_finished_ammunition", {"arrow":1})), "runtime service detects forbidden completed ammunition")
	_check(bool(service.call("_contains_unsupported_reward_items", {"stone":1})), "runtime service detects unsupported reward inputs")
	var additions: Array = service.call("_reward_additions", {"arrow":4, "flint":2, "gunpowder":1, "stone":9})
	_check(additions == [{"item_id":"flint", "count":2}, {"item_id":"gunpowder", "count":1}], "runtime transaction filter cannot add completed ammunition")
	_check(additions.all(func(entry: Dictionary) -> bool: return str(entry.get("item_id", "")) in ["flint", "gunpowder"]), "runtime transaction filter cannot add unsupported reward inputs")
	service.free()


func _test_feedback_overlay() -> void:
	var combat := FakeCombat.new()
	var overlay = FeedbackOverlayScript.new()
	root.add_child(combat)
	root.add_child(overlay)
	await process_frame
	overlay.setup(combat)
	overlay.set_active(true)
	combat.incoming_damage_resolved.emit({
		"final_damage":7.5,
		"absorbed":2.5,
		"source":"abyss_marksman",
		"damage_direction":"right",
		"source_position":[5.0, 0.0, 0.0],
	})
	await process_frame
	var snapshot: Dictionary = overlay.get_snapshot()
	_check(int(snapshot.get("direction_indicator_pool_size", 0)) == 4, "HUD owns one fixed four-slot direction indicator pool")
	_check(bool(snapshot.get("incoming_visible", false)), "incoming damage text is visible after authoritative damage")
	_check(str(snapshot.get("incoming_text", "")).contains("7.5"), "incoming damage text exposes final damage")
	_check(str(snapshot.get("incoming_text", "")).contains("右侧"), "incoming damage text exposes localized direction")
	_check(str(snapshot.get("incoming_text", "")).contains("深渊弹"), "incoming damage text distinguishes the authoritative attack source")
	_check(str(snapshot.get("incoming_text", "")).contains("护甲吸收 2.5"), "incoming damage text exposes armour absorption")
	_check("right" in snapshot.get("active_damage_directions", []), "right-edge pulse activates from the same authoritative result")
	overlay.apply_settings({"show_damage_direction_pulses":false})
	snapshot = overlay.get_snapshot()
	_check(not bool(snapshot.get("direction_pulses_enabled", true)), "local setting disables visual direction pulses")
	_check(bool(snapshot.get("incoming_visible", false)), "disabling pulses preserves accessible damage text")
	overlay.queue_free()
	combat.queue_free()
	await process_frame


func _test_flint_crafting_loop() -> void:
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	root.add_child(inventory)
	root.add_child(crafting)
	await process_frame
	crafting.setup(inventory)
	crafting.set_station("workbench")
	_check(inventory.registry.has_item("flint"), "formal item registry exposes flint")
	var arrow_recipe: Dictionary = crafting.get_recipe("arrows")
	_check(int(arrow_recipe.get("ingredients", {}).get("flint", 0)) == 1, "formal arrow recipe consumes one flint")
	_check(not arrow_recipe.get("ingredients", {}).has("stone"), "formal arrow recipe no longer consumes generic stone")
	inventory.clear()
	inventory.add_item("stick", 1)
	inventory.add_item("feather", 1)
	inventory.add_item("flint", 1)
	inventory.add_item("stone", 1)
	_check(crafting.craft("arrows"), "encounter flint can close the real arrow crafting loop")
	_check(inventory.count_item("arrow") == 4, "flint recipe creates one bounded four-arrow batch")
	_check(inventory.count_item("flint") == 0, "flint is consumed exactly once")
	_check(inventory.count_item("stone") == 1, "unrelated stone remains untouched")
	inventory.queue_free()
	crafting.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
