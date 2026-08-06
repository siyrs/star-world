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
	var hardware: Array[Dictionary] = []
	for index: int in ContractScript.REQUIRED_TIERS.size():
		hardware.append({
			"tier": ContractScript.REQUIRED_TIERS[index],
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
		})
	var scenarios: Array[Dictionary] = []
	for scenario_type: String in ContractScript.REQUIRED_FAULT_SCENARIOS:
		scenarios.append({
			"type": scenario_type,
			"attested_real": false,
			"interruption_observed": true,
			"recovery_verified": true,
			"world_integrity_verified": true,
			"before_world_sha256": _hash_char("d"),
			"after_world_sha256": _hash_char("e"),
		})
	return {
		"schema_version": ContractScript.SCHEMA_VERSION,
		"package_id": "qualification-fixture",
		"fixture_mode": fixture_mode,
		"reference_only": reference_only,
		"evidence_source": source,
		"hosted_runner": source == "hosted_reference",
		"build": {
			"commit_sha": "a".repeat(40),
			"executable_sha256": _hash_char("1"),
			"pck_sha256": _hash_char("2"),
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
		},
		"hardware_qualification": hardware,
		"strict_soak": {
			"requested_seconds": 600,
			"elapsed_seconds": 600,
			"reference_only": true,
			"target_hardware": false,
			"clean_exit": true,
			"crash_count": 0,
			"timed_out": false,
			"result": "pass",
			"lifecycle_report_sha256": _hash_char("3"),
			"soak_report_sha256": _hash_char("4"),
		},
		"fault_lab": {
			"operator_id": "fault-operator",
			"result": "pass",
			"scenarios": scenarios,
		},
		"findings": [],
	}


func _attest_real_package(package: Dictionary) -> void:
	package["hosted_runner"] = false
	for entry: Dictionary in package["hardware_qualification"]:
		entry["operator_attested"] = true
	package["strict_soak"]["requested_seconds"] = ContractScript.STRICT_SOAK_SECONDS
	package["strict_soak"]["elapsed_seconds"] = ContractScript.STRICT_SOAK_SECONDS
	package["strict_soak"]["reference_only"] = false
	package["strict_soak"]["target_hardware"] = true
	for scenario: Dictionary in package["fault_lab"]["scenarios"]:
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
