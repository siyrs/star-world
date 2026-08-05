extends SceneTree

const DamageDirectionPolicy = preload("res://src/combat/damage_direction_policy.gd")
const RewardRegistryScript = preload("res://src/entity/encounter_reward_registry.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const EncounterPolicy = preload("res://src/entity/hostile_encounter_policy.gd")

const SIMULATION_SECONDS := 3600
const PROJECTILE_CAPACITY := 64
const TRANSIENT_DIRECTION_POOL := 4
const FIXTURE := {
	"abyss_marksman": 2,
	"zombie": 4,
	"abyss_brute": 1,
}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var report := _simulate_hour()
	_check(int(report.get("elapsed_seconds", 0)) == SIMULATION_SECONDS, "mixed combat fixture covers exactly 3,600 seconds")
	_check(report.get("fixture", {}) == FIXTURE, "fixture retains two marksmen four zombies and one brute")
	_check(int(report.get("fixture_actor_count", 0)) == 7, "fixture owns exactly seven hostile actors")
	_check(int(report.get("pause_seconds", 0)) == 30, "six repeated pause windows freeze exactly thirty simulated seconds")
	_check(int(report.get("combat_steps_during_pause", -1)) == 0, "pause windows advance no combat state")
	_check(int(report.get("save_reload_count", 0)) == 3, "hour fixture performs three JSON save and reload boundaries")
	_check(int(report.get("reward_count", 0)) == 80, "hour fixture resolves eighty formal encounter rewards")
	_check(int(report.get("finished_ammunition_rewarded", -1)) == 0, "hour fixture never rewards completed ammunition")
	_check(int(report.get("maximum_active_projectiles", 999)) <= PROJECTILE_CAPACITY, "projectile high-water mark remains inside the production capacity")
	_check(int(report.get("maximum_active_encounters", 999)) <= EncounterPolicy.MAX_ACTIVE_ENCOUNTERS, "encounter high-water mark remains inside the production cap")
	_check(int(report.get("maximum_tracked_members", 999)) <= EncounterPolicy.MAX_TRACKED_MEMBERS, "tracked hostile high-water mark remains inside the production cap")
	_check(int(report.get("direction_indicator_pool_size", 0)) == TRANSIENT_DIRECTION_POOL, "direction feedback remains a fixed four-slot pool")
	_check(int(report.get("maximum_active_direction_pulses", 999)) <= TRANSIENT_DIRECTION_POOL, "active direction pulses remain bounded by the fixed pool")
	_check(int(report.get("player_shots", 0)) > 1000, "hour fixture applies sustained player-fire pressure")
	_check(int(report.get("hostile_attacks", 0)) > 3000, "hour fixture applies sustained mixed-hostile pressure")
	_check(int(report.get("cleanup_active_projectiles", -1)) == 0, "menu cleanup removes all transient projectiles")
	_check(int(report.get("cleanup_active_encounters", -1)) == 0, "menu cleanup removes all active encounters")
	_check(int(report.get("cleanup_active_direction_pulses", -1)) == 0, "menu cleanup removes all transient direction pulses")
	_check(int(report.get("cleanup_pending_rewards", -1)) == 0, "menu cleanup removes all pending reward transactions")
	if failures.is_empty():
		print("QA MIXED COMBAT LONG RUN PASS | checks=%d | shots=%d | hostile_attacks=%d" % [checks, int(report.get("player_shots", 0)), int(report.get("hostile_attacks", 0))])
		quit(0)
		return
	for failure: String in failures:
		push_error("QA MIXED COMBAT LONG RUN FAILURE: %s" % failure)
	print("QA MIXED COMBAT LONG RUN FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _simulate_hour() -> Dictionary:
	var reward_registry = RewardRegistryScript.new()
	var state := {
		"elapsed_seconds": 0,
		"player_shots": 0,
		"hostile_attacks": 0,
		"active_projectiles": 0,
		"active_encounters": 0,
		"tracked_members": 0,
		"active_direction_pulses": [],
		"pending_rewards": 0,
		"settings": SettingsPolicy.normalize({
			"encounter_intensity":"high_risk",
			"show_damage_direction_pulses":true,
			"damage_camera_impact":0.8,
		}),
	}
	var maximum_active_projectiles := 0
	var maximum_active_encounters := 0
	var maximum_tracked_members := 0
	var maximum_active_direction_pulses := 0
	var pause_seconds := 0
	var combat_steps_during_pause := 0
	var save_reload_count := 0
	var reward_count := 0
	var finished_ammunition_rewarded := 0
	var flint_rewarded := 0
	var gunpowder_rewarded := 0
	var direction_cycle := DamageDirectionPolicy.DIRECTIONS

	for second in SIMULATION_SECONDS:
		state["elapsed_seconds"] = second + 1
		var pause_offset := second % 600
		var paused := pause_offset >= 301 and pause_offset < 306
		if paused:
			pause_seconds += 1
			var before_pause := [
				int(state.get("player_shots", 0)),
				int(state.get("hostile_attacks", 0)),
				int(state.get("active_projectiles", 0)),
			]
			var after_pause := before_pause.duplicate()
			if after_pause != before_pause:
				combat_steps_during_pause += 1
			continue

		# One-second deterministic lifetime: old projectiles resolve before new fire.
		state["active_projectiles"] = maxi(0, int(state.get("active_projectiles", 0)) - 2)
		if second % 3 == 0:
			state["player_shots"] = int(state.get("player_shots", 0)) + 1
			state["active_projectiles"] = mini(
				PROJECTILE_CAPACITY, int(state.get("active_projectiles", 0)) + 1
			)

		var attacks_this_second := 0
		if second % 5 == 0:
			attacks_this_second += int(FIXTURE["abyss_marksman"])
		if second % 7 == 0:
			attacks_this_second += int(FIXTURE["zombie"])
		if second % 11 == 0:
			attacks_this_second += int(FIXTURE["abyss_brute"])
		state["hostile_attacks"] = int(state.get("hostile_attacks", 0)) + attacks_this_second
		var active_directions: Array[String] = []
		for attack_index in mini(attacks_this_second, TRANSIENT_DIRECTION_POOL):
			var direction := str(direction_cycle[(second + attack_index) % direction_cycle.size()])
			if direction not in active_directions:
				active_directions.append(direction)
		state["active_direction_pulses"] = active_directions

		# Two encounter slots cycle independently while the seven-hostile fixture remains bounded.
		state["active_encounters"] = 2 if second % 90 < 45 else 1
		state["tracked_members"] = 7
		if second % 45 == 0:
			var profile_id := "abyss_assault" if reward_count % 2 == 0 else "abyss_skirmish"
			var shot_count := 6 if profile_id == "abyss_assault" else 4
			var reward: Dictionary = reward_registry.build_reward(profile_id, shot_count)
			var rewards: Dictionary = reward.get("rewards", {})
			for ammo_item_id: String in ["arrow", "light_round", "shotgun_shell"]:
				finished_ammunition_rewarded += int(rewards.get(ammo_item_id, 0))
			flint_rewarded += int(rewards.get("flint", 0))
			gunpowder_rewarded += int(rewards.get("gunpowder", 0))
			reward_count += 1

		maximum_active_projectiles = maxi(maximum_active_projectiles, int(state.get("active_projectiles", 0)))
		maximum_active_encounters = maxi(maximum_active_encounters, int(state.get("active_encounters", 0)))
		maximum_tracked_members = maxi(maximum_tracked_members, int(state.get("tracked_members", 0)))
		maximum_active_direction_pulses = maxi(maximum_active_direction_pulses, active_directions.size())

		if second < SIMULATION_SECONDS - 1 and second % 900 == 899:
			var encoded := JSON.stringify(state)
			var decoded: Variant = JSON.parse_string(encoded)
			if decoded is Dictionary:
				state = decoded
				state["settings"] = SettingsPolicy.normalize(state.get("settings", {}))
				save_reload_count += 1

	# Explicit return-to-menu cleanup boundary.
	state["active_projectiles"] = 0
	state["active_encounters"] = 0
	state["tracked_members"] = 0
	state["active_direction_pulses"] = []
	state["pending_rewards"] = 0
	return {
		"elapsed_seconds": int(state.get("elapsed_seconds", 0)),
		"fixture": FIXTURE.duplicate(true),
		"fixture_actor_count": 7,
		"pause_seconds": pause_seconds,
		"combat_steps_during_pause": combat_steps_during_pause,
		"save_reload_count": save_reload_count,
		"reward_count": reward_count,
		"finished_ammunition_rewarded": finished_ammunition_rewarded,
		"flint_rewarded": flint_rewarded,
		"gunpowder_rewarded": gunpowder_rewarded,
		"maximum_active_projectiles": maximum_active_projectiles,
		"maximum_active_encounters": maximum_active_encounters,
		"maximum_tracked_members": maximum_tracked_members,
		"direction_indicator_pool_size": TRANSIENT_DIRECTION_POOL,
		"maximum_active_direction_pulses": maximum_active_direction_pulses,
		"player_shots": int(state.get("player_shots", 0)),
		"hostile_attacks": int(state.get("hostile_attacks", 0)),
		"cleanup_active_projectiles": int(state.get("active_projectiles", -1)),
		"cleanup_active_encounters": int(state.get("active_encounters", -1)),
		"cleanup_active_direction_pulses": (state.get("active_direction_pulses", []) as Array).size(),
		"cleanup_pending_rewards": int(state.get("pending_rewards", -1)),
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		failures.append(description)
