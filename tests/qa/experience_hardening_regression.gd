extends SceneTree

const CameraPolicy = preload("res://src/player/camera_feel_policy.gd")
const SurvivalPolicy = preload("res://src/survival/survival_tuning_policy.gd")
const SettingsPolicy = preload("res://src/settings/game_settings_policy.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const ParticleScript = preload("res://src/harvest/block_break_particles.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_camera_policy()
	_test_survival_policy()
	_test_settings_policy()
	await _test_survival_service()
	await _test_camera_lifecycle()
	await _test_particle_budget()
	if failures.is_empty():
		print("QA EXPERIENCE HARDENING PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA EXPERIENCE HARDENING FAILURE: %s" % failure)
	print("QA EXPERIENCE HARDENING FAIL | checks=%d | failures=%d" % [checks, failures.size()])
	quit(1)


func _test_camera_policy() -> void:
	var normalized: Dictionary = CameraPolicy.normalize({
		"bob_walk_amplitude": INF,
		"bob_sprint_amplitude": 50.0,
		"base_fov": 140.0,
		"sprint_fov": 20.0,
		"land_min_impact_speed": 8.0,
		"land_sound_min_impact_speed": 2.0,
		"floor_poll_interval_seconds": -4.0,
		"unknown_camera_field": "discard",
	})
	_check(
		normalized.keys().size() == CameraPolicy.DEFAULTS.size()
		and not normalized.has("unknown_camera_field"),
		"camera feel policy uses a strict key whitelist"
	)
	_check(
		is_equal_approx(float(normalized["bob_walk_amplitude"]), 0.035)
		and is_equal_approx(float(normalized["bob_sprint_amplitude"]), 0.10),
		"camera feel amplitudes reject non-finite values and remain bounded"
	)
	_check(
		is_equal_approx(float(normalized["base_fov"]), 95.0)
		and float(normalized["sprint_fov"]) >= float(normalized["base_fov"]),
		"camera FOV remains within an accessible monotonic range"
	)
	_check(
		is_equal_approx(float(normalized["land_sound_min_impact_speed"]), 8.0)
		and is_equal_approx(float(normalized["floor_poll_interval_seconds"]), 0.05),
		"camera event thresholds remain internally consistent and bounded"
	)


func _test_survival_policy() -> void:
	var raw := {
		"default_profile": "unknown",
		"profiles": {
			"relaxed": {"passive_hunger_interval": INF},
			"balanced": {"starvation_damage_interval": -5.0},
			"challenging": {"regeneration_hunger_threshold": 99.0},
			"extra": {"passive_hunger_interval": 1.0},
		},
		"unknown_root": true,
	}
	var catalog: Dictionary = SurvivalPolicy.normalize_catalog(raw)
	var profiles: Dictionary = catalog["profiles"]
	_check(
		str(catalog["default_profile"]) == "relaxed"
		and profiles.keys().size() == 3
		and not profiles.has("extra")
		and not catalog.has("unknown_root"),
		"survival tuning catalog exposes exactly three strict profiles"
	)
	_check(
		is_equal_approx(float(profiles["relaxed"]["passive_hunger_interval"]), 90.0)
		and is_equal_approx(float(profiles["balanced"]["starvation_damage_interval"]), 1.0)
		and is_equal_approx(float(profiles["challenging"]["regeneration_hunger_threshold"]), 20.0),
		"survival profile values reject non-finite input and obey hard bounds"
	)
	_check(
		SurvivalPolicy.profile_label("relaxed") == "轻松建造"
		and SurvivalPolicy.profile_label("balanced") == "平衡生存"
		and SurvivalPolicy.profile_label("challenging") == "挑战生存",
		"survival profiles have stable player-facing labels"
	)


func _test_settings_policy() -> void:
	var normalized := SettingsPolicy.normalize({
		"survival_difficulty": "invalid",
		"camera_bob": "invalid",
		"unknown": true,
	})
	_check(
		str(normalized["survival_difficulty"]) == "relaxed"
		and bool(normalized["camera_bob"])
		and not normalized.has("unknown"),
		"game settings normalize difficulty and camera accessibility through one whitelist"
	)
	_check(
		SettingsPolicy.allowed_survival_difficulties() == ["relaxed", "balanced", "challenging"],
		"game settings expose the same three ordered survival profiles"
	)


func _test_survival_service() -> void:
	var survival = SurvivalScript.new()
	root.add_child(survival)
	await process_frame
	var initial: Dictionary = survival.get_tuning_snapshot()
	_check(
		str(initial["profile_id"]) == "relaxed"
		and is_equal_approx(float(initial["passive_hunger_interval"]), 90.0)
		and is_equal_approx(float(initial["starvation_damage_interval"]), 8.0),
		"production survival defaults preserve the child-friendly legacy pacing"
	)
	_check(survival.set_difficulty_profile("balanced"), "balanced difficulty applies as a real runtime change")
	var balanced: Dictionary = survival.get_tuning_snapshot()
	_check(
		is_equal_approx(float(balanced["passive_hunger_interval"]), 70.0)
		and is_equal_approx(float(balanced["starvation_damage_interval"]), 4.0),
		"balanced difficulty retains K3's stronger survival loop"
	)
	survival.saturation = 0.0
	survival.hunger = 20.0
	survival.call("_process", 69.0)
	_check(is_equal_approx(survival.hunger, 20.0), "balanced hunger does not fire before its exact boundary")
	survival.call("_process", 1.1)
	_check(is_equal_approx(survival.hunger, 19.0), "balanced hunger fires once after seventy seconds")
	_check(survival.set_difficulty_profile("challenging"), "challenging difficulty can be selected without a new world")
	var challenging: Dictionary = survival.get_tuning_snapshot()
	_check(
		is_equal_approx(float(challenging["passive_hunger_interval"]), 50.0)
		and is_equal_approx(float(challenging["starvation_damage_interval"]), 3.0),
		"challenging profile exposes the intended bounded pressure"
	)
	_check(
		not survival.serialize().has("difficulty_profile"),
		"global survival preference never creates a second per-world persistence owner"
	)
	survival.set_difficulty_profile("unknown")
	_check(str(survival.get_tuning_snapshot()["profile_id"]) == "relaxed", "unknown difficulty safely falls back to relaxed")
	survival.queue_free()
	await process_frame


func _test_camera_lifecycle() -> void:
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var feel: Node = player.get_node_or_null("CameraFeel")
	_check(feel != null, "production player mounts one camera feel controller")
	if feel != null:
		var snapshot: Dictionary = feel.call("get_snapshot")
		_check(
			int(snapshot["configured_key_count"]) == int(snapshot["expected_key_count"]),
			"production camera controller consumes only normalized policy keys"
		)
		player.call("take_damage", 1.0, "qa")
		snapshot = feel.call("get_snapshot")
		_check(
			int(snapshot["damage_shake_count"]) == 1
			and float(snapshot["shake_strength"]) > 0.0,
			"real player damage enters the bounded camera feedback path exactly once"
		)
		player.set("camera_bob_enabled", false)
		_check(not bool(feel.get("bob_enabled")), "camera bob accessibility setting applies immediately")
	player.queue_free()
	for _frame in 3:
		await process_frame


func _test_particle_budget() -> void:
	var particles = ParticleScript.new()
	root.add_child(particles)
	await process_frame
	var initial: Dictionary = particles.get_snapshot()
	_check(
		int(initial["pool_capacity"]) == 64
		and int(initial["available_count"]) == 64
		and not bool(initial["processing"]),
		"block debris owns one fixed idle pool and no permanent process loop"
	)
	particles.spawn_burst(Vector3i.ZERO, "stone")
	var active: Dictionary = particles.get_snapshot()
	_check(
		int(active["active_count"]) == 14
		and int(active["available_count"]) == 50
		and bool(active["processing"]),
		"one block break creates an exact bounded debris burst"
	)
	for _frame in 8:
		particles.call("_process", 0.1)
	var settled: Dictionary = particles.get_snapshot()
	_check(
		int(settled["active_count"]) == 0
		and int(settled["available_count"]) == 64
		and not bool(settled["processing"]),
		"debris returns every node to the pool and disables processing"
	)
	_check(
		int(settled["material_count"]) <= int(settled["material_limit"]),
		"debris material reuse remains under a hard cache budget"
	)
	particles.queue_free()
	for _frame in 3:
		await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
