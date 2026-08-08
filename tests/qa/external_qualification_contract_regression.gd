extends SceneTree

const ContractScript = preload("res://src/diagnostics/external_qualification_contract.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var contract = ContractScript.new()

	var fixture := _base_package("fixture", true, true)
	var fixture_result: Dictionary = contract.validate_package(fixture)
	if not bool(fixture_result.get("contract_valid", false)):
		print("FIXTURE CONTRACT ERRORS: %s" % [fixture_result.get("errors", [])])
	_check(bool(fixture_result.get("contract_valid", false)), "complete fixture satisfies the schema")
	_check(
		not bool(fixture_result.get("release_gate_passed", true))
		and str(fixture_result.get("status", "")) == "fixture_contract_complete",
		"fixture evidence never closes the commercial release gate"
	)

	var hosted := _base_package("hosted_reference", false, true)
	var hosted_result: Dictionary = contract.validate_package(hosted)
	_check(bool(hosted_result.get("contract_valid", false)), "hosted reference package remains structurally valid")
	_check(
		not bool(hosted_result.get("release_gate_passed", true))
		and str(hosted_result.get("status", "")) == "reference_only",
		"hosted reference evidence is explicitly non-qualifying"
	)

	var real := _base_package("target_hardware", false, false)
	_attest_real_package(real)
	var real_result: Dictionary = contract.validate_package(real)
	_check(bool(real_result.get("contract_valid", false)), "complete target-hardware package satisfies the contract")
	_check(
		bool(real_result.get("release_gate_passed", false))
		and str(real_result.get("status", "")) == "external_evidence_complete",
		"only a complete real package reaches the evidence-complete state"
	)

	var self_review := real.duplicate(true)
	self_review["experiential_review"]["reviewer_id"] = "implementer-a"
	_check_invalid(contract, self_review, "independent", "self-review is rejected")

	var hosted_target := real.duplicate(true)
	hosted_target["hosted_runner"] = true
	_check_invalid(contract, hosted_target, "hosted runner", "hosted runner cannot impersonate target hardware")

	var short_soak := real.duplicate(true)
	short_soak["strict_soak"]["requested_seconds"] = 600
	short_soak["strict_soak"]["elapsed_seconds"] = 600
	_check_invalid(contract, short_soak, "7200", "short target soak is rejected")

	var missing_tier := real.duplicate(true)
	missing_tier["hardware_qualification"] = [missing_tier["hardware_qualification"][0]]
	_check_invalid(contract, missing_tier, "recommended", "both minimum and recommended tiers are required")

	var missing_profile := real.duplicate(true)
	missing_profile["hardware_qualification"][0]["profiles"].erase("abyss_world")
	_check_invalid(contract, missing_profile, "abyss_world", "each hardware tier must traverse all formal profiles")

	var bad_digest := real.duplicate(true)
	bad_digest["build"]["executable_sha256"] = "not-a-digest"
	_check_invalid(contract, bad_digest, "executable_sha256", "invalid release digest is rejected")

	var blocker := real.duplicate(true)
	blocker["findings"] = [{"severity":"blocker", "state":"open", "summary":"crash"}]
	_check_invalid(contract, blocker, "unresolved blocker", "open blocker prevents qualification")

	var missing_fault := real.duplicate(true)
	missing_fault["fault_lab"]["scenarios"].pop_back()
	_check_invalid(contract, missing_fault, "power_loss", "all required real fault scenarios are required")

	var unattested_fault := real.duplicate(true)
	unattested_fault["fault_lab"]["scenarios"][0]["attested_real"] = false
	_check_invalid(contract, unattested_fault, "real attestation", "synthetic fault evidence cannot close the gate")

	var unapproved_owner := real.duplicate(true)
	unapproved_owner["release_owner_attestation"]["approved_for_release"] = false
	_check_invalid(contract, unapproved_owner, "explicitly approve", "release-owner approval is mandatory")

	var non_target_claim := hosted.duplicate(true)
	non_target_claim["reference_only"] = false
	_check_invalid(contract, non_target_claim, "must be reference_only", "non-target packages cannot claim acceptance")

	var target_reference := real.duplicate(true)
	target_reference["reference_only"] = true
	_check_invalid(contract, target_reference, "cannot be reference_only", "target evidence cannot downgrade its declaration")

	var duplicate_tier := real.duplicate(true)
	duplicate_tier["hardware_qualification"][1]["tier"] = "minimum"
	_check_invalid(contract, duplicate_tier, "duplicated", "hardware tiers cannot be duplicated")

	var tampered_review := real.duplicate(true)
	tampered_review["experiential_review"]["build"]["commit_sha"] = "f".repeat(40)
	_check_invalid(contract, tampered_review, "review commit", "E4-H review cannot be rebound to another commit")

	var tampered_hardware := real.duplicate(true)
	tampered_hardware["hardware_qualification"][0]["build"]["executable_sha256"] = _hash_char("f")
	_check_invalid(contract, tampered_hardware, "hardware minimum executable", "hardware evidence cannot be mixed from another executable")

	var tampered_soak := real.duplicate(true)
	tampered_soak["strict_soak"]["pck_sha256"] = _hash_char("f")
	_check_invalid(contract, tampered_soak, "strict soak PCK", "soak evidence cannot be mixed from another PCK")

	var tampered_fault := real.duplicate(true)
	tampered_fault["fault_lab"]["scenarios"][0]["build"]["pck_sha256"] = _hash_char("f")
	_check_invalid(contract, tampered_fault, "fault hdd PCK", "fault evidence cannot be mixed from another PCK")

	var mixed_source := real.duplicate(true)
	mixed_source["hardware_qualification"][0]["evidence_source"] = "hosted_reference"
	_check_invalid(contract, mixed_source, "evidence_source does not match", "hosted evidence cannot be inserted into a target package")

	var mixed_reference_flag := real.duplicate(true)
	mixed_reference_flag["strict_soak"]["reference_only"] = true
	_check_invalid(contract, mixed_reference_flag, "reference_only does not match", "child reference flags must match the package")

	var mixed_fault_operator := real.duplicate(true)
	mixed_fault_operator["fault_lab"]["scenarios"][0]["operator_id"] = "other-operator"
	_check_invalid(contract, mixed_fault_operator, "operator does not match", "fault scenarios must retain one operator identity")

	var forged_metric := real.duplicate(true)
	forged_metric["hardware_qualification"][1]["metric_evaluation"]["profiles"][0]["avg_fps"] = 0.0
	_check_invalid(contract, forged_metric, "metric threshold failed", "forged passing performance is recomputed and rejected")

	var forged_policy := real.duplicate(true)
	forged_policy["hardware_qualification"][0]["qualification_policy"]["sha256"] = _hash_char("f")
	_check_invalid(contract, forged_policy, "repository policy", "qualification thresholds remain bound to repository policy")

	var short_routes := real.duplicate(true)
	short_routes["strict_soak"]["completed_routes"] = 9
	short_routes["strict_soak"]["cycle_count"] = 9
	short_routes["strict_soak"]["authoritative_cycle_lifecycle_count"] = 9
	_check_invalid(contract, short_routes, "complete at least", "strict soak requires ten completed routes")

	var memory_growth := real.duplicate(true)
	memory_growth["strict_soak"]["working_set_last_p95_mib"] = 140.0
	memory_growth["strict_soak"]["memory_growth_percent"] = 40.0
	_check_invalid(contract, memory_growth, "Working Set growth exceeds policy", "strict soak enforces policy memory growth")

	var fatal_diagnostic := real.duplicate(true)
	fatal_diagnostic["strict_soak"]["fatal_diagnostics_count"] = 1
	_check_invalid(contract, fatal_diagnostic, "fatal diagnostics exceed policy", "strict soak requires zero fatal diagnostics")

	var dirty_lifecycle := real.duplicate(true)
	dirty_lifecycle["strict_soak"]["lifecycle"]["quit_prepared"] = false
	dirty_lifecycle["strict_soak"]["lifecycle"]["termination_reason"] = "scene_exit_without_prepared_quit"
	dirty_lifecycle["strict_soak"]["lifecycle"]["authoritative_clean_quit"] = false
	_check_invalid(contract, dirty_lifecycle, "termination_reason must equal prepared_quit", "scene exit without prepared quit is rejected")

	var reexported := real.duplicate(true)
	reexported["hardware_qualification"][0]["exact_final_package_reused"] = false
	_check_invalid(contract, reexported, "exact final package reuse", "qualification cannot silently re-export the final package")

	if failures.is_empty():
		print("QA EXTERNAL QUALIFICATION CONTRACT PASS | checks=%d" % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error("QA EXTERNAL QUALIFICATION CONTRACT FAILURE: %s" % failure)
	print(
		"QA EXTERNAL QUALIFICATION CONTRACT FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _base_package(source: String, fixture_mode: bool, reference_only: bool) -> Dictionary:
	var profiles: Array[String] = ContractScript.REQUIRED_PROFILES.duplicate()
	var policy := _qualification_policy()
	var commit_sha := "a".repeat(40)
	var executable_sha := _hash_char("1")
	var pck_sha := _hash_char("2")
	var hardware: Array[Dictionary] = []
	for index: int in ContractScript.REQUIRED_TIERS.size():
		var tier: String = ContractScript.REQUIRED_TIERS[index]
		var tier_metrics: Dictionary = policy["tiers"][tier]["metrics"]
		var metric_profiles: Array[Dictionary] = []
		for profile_id: String in profiles:
			metric_profiles.append(_passing_metric_profile(profile_id, tier_metrics))
		hardware.append({
			"schema_version": 2,
			"exact_final_package_reused": true,
			"tier": tier,
			"evidence_source": source,
			"reference_only": reference_only,
			"operator_id": "operator-%d" % index,
			"operator_attested": false,
			"machine_fingerprint_sha256": _hash_char("b" if index == 0 else "c"),
			"cpu": "fixture cpu",
			"gpu": "fixture gpu",
			"ram_gib": 16.0 + float(index * 16),
			"os": "Windows fixture",
			"storage": {"drive_type":"ssd", "model":"fixture storage"},
			"profiles": profiles.duplicate(),
			"started_at_unix": 1000 + index * 100,
			"completed_at_unix": 1050 + index * 100,
			"result": "pass",
			"qualification_policy": _hardware_policy_snapshot(policy, tier),
			"metric_evaluation": {
				"profile_count": profiles.size(),
				"assertion_count": profiles.size() * 7,
				"failure_count": 0,
				"passed": true,
				"violations": [],
				"profiles": metric_profiles,
			},
			"build": {
				"executable_sha256": executable_sha,
				"pck_sha256": pck_sha,
			},
		})
	var scenarios: Array[Dictionary] = []
	for scenario_type: String in ContractScript.REQUIRED_FAULT_SCENARIOS:
		scenarios.append({
			"type": scenario_type,
			"evidence_source": source,
			"reference_only": reference_only,
			"operator_id": "fault-operator",
			"attested_real": false,
			"interruption_observed": true,
			"recovery_verified": true,
			"world_integrity_verified": true,
			"before_world_sha256": _hash_char("d"),
			"after_world_sha256": _hash_char("e"),
			"build": {
				"executable_sha256": executable_sha,
				"pck_sha256": pck_sha,
			},
		})
	return {
		"schema_version": ContractScript.SCHEMA_VERSION,
		"package_id": "qualification-fixture",
		"fixture_mode": fixture_mode,
		"reference_only": reference_only,
		"evidence_source": source,
		"hosted_runner": source == "hosted_reference",
		"build": {
			"commit_sha": commit_sha,
			"executable_sha256": executable_sha,
			"pck_sha256": pck_sha,
			"version": "v1.3.0-fixture",
		},
		"experiential_review": {
			"reviewer_id": "reviewer-b",
			"implementer_id": "implementer-a",
			"independent": true,
			"signed_at_unix": 2000,
			"result": "pass",
			"blockers": [],
			"checklist": {
				"fresh_install": true,
				"new_world": true,
				"save_reload": true,
				"five_profiles": true,
				"input_and_ui": true,
				"quit_and_restart": true,
			},
			"build": {
				"commit_sha": commit_sha,
				"executable_sha256": executable_sha,
				"pck_sha256": pck_sha,
			},
		},
		"hardware_qualification": hardware,
		"strict_soak": {
			"schema_version": 2,
			"exact_final_package_reused": true,
			"evidence_source": source,
			"requested_seconds": 600,
			"elapsed_seconds": 600,
			"reference_only": reference_only,
			"target_hardware": false,
			"cycle_count": 5,
			"completed_routes": 5,
			"profile_count": 5,
			"profiles": profiles.duplicate(),
			"qualification_policy": _soak_policy_snapshot(policy),
			"fatal_diagnostics_count": 0,
			"post_spawn_transport_count": 0,
			"player_transform_writes": 0,
			"working_set_first_p95_mib": 100.0,
			"working_set_last_p95_mib": 110.0,
			"memory_growth_percent": 10.0,
			"authoritative_cycle_lifecycle_count": 5,
			"lifecycle": _clean_lifecycle_summary(),
			"clean_exit": true,
			"crash_count": 0,
			"timed_out": false,
			"result": "pass",
			"executable_sha256": executable_sha,
			"pck_sha256": pck_sha,
			"lifecycle_report_sha256": _hash_char("3"),
			"soak_report_sha256": _hash_char("4"),
			"progress_journal_sha256": _hash_char("5"),
		},
		"fault_lab": {
			"operator_id": "fault-operator",
			"result": "pass",
			"scenarios": scenarios,
		},
		"findings": [],
	}


func _qualification_policy() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ContractScript.QUALIFICATION_POLICY_PATH)
	)
	var policy: Dictionary = parsed
	policy["_sha256"] = FileAccess.get_sha256(ContractScript.QUALIFICATION_POLICY_PATH).to_lower()
	return policy


func _hardware_policy_snapshot(policy: Dictionary, tier: String) -> Dictionary:
	return {
		"schema_version": int(policy["schema_version"]),
		"sha256": str(policy["_sha256"]),
		"product": str(policy["product"]),
		"platform": str(policy["platform"]),
		"rendering_method": str(policy["rendering_method"]),
		"resolution": policy["resolution"].duplicate(),
		"tier": tier,
		"metrics": policy["tiers"][tier]["metrics"].duplicate(true),
	}


func _soak_policy_snapshot(policy: Dictionary) -> Dictionary:
	return {
		"schema_version": int(policy["schema_version"]),
		"sha256": str(policy["_sha256"]),
		"duration_seconds_min": int(policy["soak"]["duration_seconds_min"]),
		"all_profiles_required": bool(policy["soak"]["all_profiles_required"]),
		"minimum_completed_routes": int(policy["soak"]["minimum_completed_routes"]),
		"fatal_diagnostics_max": int(policy["soak"]["fatal_diagnostics_max"]),
		"memory_growth_percent_max": float(policy["soak"]["memory_growth_percent_max"]),
		"route_transport_after_spawn_max": int(policy["soak"]["route_transport_after_spawn_max"]),
	}


func _passing_metric_profile(profile_id: String, metrics: Dictionary) -> Dictionary:
	return {
		"profile_id": profile_id,
		"avg_fps": float(metrics["avg_fps_min"]) + 10.0,
		"one_percent_low_fps": float(metrics["one_percent_low_fps_min"]) + 5.0,
		"frame_ms_p95": float(metrics["frame_ms_p95_max"]) * 0.8,
		"frame_ms_p99": float(metrics["frame_ms_p99_max"]) * 0.8,
		"frame_budget_miss_30fps_percent": float(metrics["frame_budget_miss_30fps_percent_max"]) * 0.5,
		"world_start_ms": float(metrics["profile_load_ms_max"]) * 0.8,
		"working_set_p95_mib": float(metrics["working_set_p95_mib_max"]) * 0.8,
		"assertions": {
			"avg_fps_min": true,
			"one_percent_low_fps_min": true,
			"frame_ms_p95_max": true,
			"frame_ms_p99_max": true,
			"frame_budget_miss_30fps_percent_max": true,
			"profile_load_ms_max": true,
			"working_set_p95_mib_max": true,
		},
		"pass": true,
	}


func _clean_lifecycle_summary() -> Dictionary:
	return {
		"schema_version": 1,
		"release_build": true,
		"engine_version": "4.7.fixture",
		"captured_unix": 1500,
		"first_world_profile_id": "star_continent",
		"first_world_id": "fixture-world",
		"first_save_success": true,
		"first_save_world_id": "fixture-world",
		"first_save_bytes": 1024,
		"world_save_identity_matches": true,
		"timings_monotonic": true,
		"quit_attempt_count": 1,
		"quit_source": "release_smoke",
		"quit_prepared": true,
		"termination_reason": "prepared_quit",
		"service_hub_request_count": 1,
		"service_hub_success_count": 1,
		"service_hub_failure_count": 0,
		"game_request_count": 1,
		"game_success_count": 1,
		"game_failure_count": 0,
		"authoritative_clean_quit": true,
	}


func _attest_real_package(package: Dictionary) -> void:
	var policy := _qualification_policy()
	package["evidence_source"] = "target_hardware"
	package["reference_only"] = false
	package["hosted_runner"] = false
	for entry: Dictionary in package["hardware_qualification"]:
		entry["evidence_source"] = "target_hardware"
		entry["reference_only"] = false
		entry["operator_attested"] = true
	package["strict_soak"]["evidence_source"] = "target_hardware"
	package["strict_soak"]["requested_seconds"] = int(policy["soak"]["duration_seconds_min"])
	package["strict_soak"]["elapsed_seconds"] = int(policy["soak"]["duration_seconds_min"])
	package["strict_soak"]["cycle_count"] = int(policy["soak"]["minimum_completed_routes"])
	package["strict_soak"]["completed_routes"] = int(policy["soak"]["minimum_completed_routes"])
	package["strict_soak"]["authoritative_cycle_lifecycle_count"] = int(policy["soak"]["minimum_completed_routes"])
	package["strict_soak"]["reference_only"] = false
	package["strict_soak"]["target_hardware"] = true
	for scenario: Dictionary in package["fault_lab"]["scenarios"]:
		scenario["evidence_source"] = "target_hardware"
		scenario["reference_only"] = false
		scenario["attested_real"] = true
	package["release_owner_attestation"] = {
		"owner_id": "release-owner",
		"signed_at_unix": 3000,
		"all_artifacts_attached": true,
		"approved_for_release": true,
	}


func _check_invalid(
	contract: RefCounted,
	package: Dictionary,
	expected_error_fragment: String,
	description: String
) -> void:
	var result: Dictionary = contract.call("validate_package", package)
	var joined := " | ".join(result.get("errors", []))
	_check(
		not bool(result.get("contract_valid", true))
		and not bool(result.get("release_gate_passed", true))
		and joined.contains(expected_error_fragment),
		description
	)


func _hash_char(value: String) -> String:
	return value.repeat(64)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
