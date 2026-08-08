class_name ExternalQualificationContract
extends RefCounted

const SCHEMA_VERSION := 2
const STRICT_SOAK_SECONDS := 7200
const QUALIFICATION_POLICY_PATH := "res://data/release_qualification.json"
const MAX_TEXT_LENGTH := 256
const REQUIRED_PROFILES: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]
const REQUIRED_TIERS: Array[String] = ["minimum", "recommended"]
const REQUIRED_FAULT_SCENARIOS: Array[String] = ["hdd", "antivirus", "power_loss"]
const ALLOWED_EVIDENCE_SOURCES: Array[String] = [
	"target_hardware",
	"hosted_reference",
	"fixture",
]
const ALLOWED_STORAGE_TYPES: Array[String] = ["hdd", "ssd", "nvme"]
const REQUIRED_REVIEW_CHECKS: Array[String] = [
	"fresh_install",
	"new_world",
	"save_reload",
	"five_profiles",
	"input_and_ui",
	"quit_and_restart",
]


func validate_package(package: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if int(package.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("schema_version must equal %d" % SCHEMA_VERSION)
	_require_text(errors, package, "package_id")

	var fixture_mode := bool(package.get("fixture_mode", false))
	var reference_only := bool(package.get("reference_only", false))
	var source := str(package.get("evidence_source", "")).strip_edges()
	var hosted_runner := bool(package.get("hosted_runner", false))
	if not ALLOWED_EVIDENCE_SOURCES.has(source):
		errors.append("evidence_source is unsupported")
	if source == "target_hardware" and hosted_runner:
		errors.append("target_hardware evidence cannot be produced by a hosted runner")
	if source == "target_hardware" and reference_only:
		errors.append("target_hardware evidence cannot be reference_only")
	if source != "target_hardware" and not reference_only:
		errors.append("non-target evidence must be reference_only")
	if fixture_mode != (source == "fixture"):
		errors.append("fixture_mode and fixture evidence_source must be used together")

	var build := _dictionary(package.get("build", {}))
	var review := _dictionary(package.get("experiential_review", {}))
	var hardware := _array(package.get("hardware_qualification", []))
	var soak := _dictionary(package.get("strict_soak", {}))
	var fault_lab := _dictionary(package.get("fault_lab", {}))
	var require_real := source == "target_hardware"
	var policy := _load_qualification_policy(errors)

	_validate_build(build, errors)
	_validate_review(review, errors)
	_validate_hardware(hardware, errors, require_real, policy)
	_validate_soak(soak, errors, warnings, require_real, policy)
	_validate_fault_lab(fault_lab, errors, require_real)
	_validate_findings(_array(package.get("findings", [])), errors)
	_validate_release_owner(
		_dictionary(package.get("release_owner_attestation", {})), errors, require_real
	)
	_validate_evidence_consistency(
		source, reference_only, hardware, soak, fault_lab, errors
	)
	_validate_build_bindings(build, review, hardware, soak, fault_lab, errors)

	if source == "hosted_reference":
		warnings.append("hosted reference evidence cannot close commercial release gates")
	if fixture_mode:
		warnings.append("fixture evidence exercises the contract only")

	var contract_valid := errors.is_empty()
	var release_gate_passed := (
		contract_valid
		and source == "target_hardware"
		and not hosted_runner
		and not reference_only
		and not fixture_mode
	)
	var status := "invalid"
	if release_gate_passed:
		status = "external_evidence_complete"
	elif contract_valid and fixture_mode:
		status = "fixture_contract_complete"
	elif contract_valid:
		status = "reference_only"
	return {
		"schema_version": SCHEMA_VERSION,
		"contract_valid": contract_valid,
		"release_gate_passed": release_gate_passed,
		"status": status,
		"errors": errors,
		"warnings": warnings,
		"error_count": errors.size(),
		"warning_count": warnings.size(),
	}


func _validate_build(build: Dictionary, errors: Array[String]) -> void:
	_require_hash(errors, build, "commit_sha", 40)
	_require_hash(errors, build, "executable_sha256", 64)
	_require_hash(errors, build, "pck_sha256", 64)
	_require_text(errors, build, "version")


func _validate_review(review: Dictionary, errors: Array[String]) -> void:
	_require_text(errors, review, "reviewer_id")
	_require_text(errors, review, "implementer_id")
	var reviewer := str(review.get("reviewer_id", "")).strip_edges()
	var implementer := str(review.get("implementer_id", "")).strip_edges()
	if not reviewer.is_empty() and reviewer == implementer:
		errors.append("experiential reviewer must be independent from the implementer")
	if not bool(review.get("independent", false)):
		errors.append("experiential review must attest independence")
	if int(review.get("signed_at_unix", 0)) <= 0:
		errors.append("experiential review signed_at_unix must be positive")
	if str(review.get("result", "")) != "pass":
		errors.append("experiential review result must be pass")
	var checklist := _dictionary(review.get("checklist", {}))
	for key: String in REQUIRED_REVIEW_CHECKS:
		if not bool(checklist.get(key, false)):
			errors.append("experiential review checklist is incomplete: %s" % key)
	if not _array(review.get("blockers", [])).is_empty():
		errors.append("experiential review contains unresolved blockers")


func _validate_hardware(
	entries: Array, errors: Array[String], require_real: bool, policy: Dictionary
) -> void:
	var seen: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary:
			errors.append("hardware qualification entries must be dictionaries")
			continue
		var entry: Dictionary = value
		var tier := str(entry.get("tier", ""))
		if not REQUIRED_TIERS.has(tier):
			errors.append("hardware tier is unsupported: %s" % tier)
			continue
		if seen.has(tier):
			errors.append("hardware tier is duplicated: %s" % tier)
		seen[tier] = true
		if int(entry.get("schema_version", 0)) != 2:
			errors.append("hardware %s schema_version must equal 2" % tier)
		if not bool(entry.get("exact_final_package_reused", false)):
			errors.append("hardware %s must attest exact final package reuse" % tier)
		_validate_hardware_policy_and_metrics(entry, tier, policy, errors)
		_require_text(errors, entry, "operator_id")
		_require_hash(errors, entry, "machine_fingerprint_sha256", 64)
		_require_text(errors, entry, "cpu")
		_require_text(errors, entry, "gpu")
		_require_text(errors, entry, "os")
		if float(entry.get("ram_gib", 0.0)) <= 0.0:
			errors.append("hardware %s ram_gib must be positive" % tier)
		var started := int(entry.get("started_at_unix", 0))
		var completed := int(entry.get("completed_at_unix", 0))
		if started <= 0 or completed < started:
			errors.append("hardware %s timestamps are invalid" % tier)
		if str(entry.get("result", "")) != "pass":
			errors.append("hardware %s result must be pass" % tier)
		if require_real and not bool(entry.get("operator_attested", false)):
			errors.append("hardware %s requires real operator attestation" % tier)
		var storage := _dictionary(entry.get("storage", {}))
		if not ALLOWED_STORAGE_TYPES.has(str(storage.get("drive_type", ""))):
			errors.append("hardware %s storage drive_type is invalid" % tier)
		_require_text(errors, storage, "model")
		var profiles := _string_set(_array(entry.get("profiles", [])))
		for profile_id: String in REQUIRED_PROFILES:
			if not profiles.has(profile_id):
				errors.append("hardware %s is missing profile %s" % [tier, profile_id])
	for tier: String in REQUIRED_TIERS:
		if not seen.has(tier):
			errors.append("hardware qualification is missing tier: %s" % tier)


func _load_qualification_policy(errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(QUALIFICATION_POLICY_PATH):
		errors.append("qualification policy is missing")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUALIFICATION_POLICY_PATH))
	if not parsed is Dictionary:
		errors.append("qualification policy is not valid JSON")
		return {}
	var policy: Dictionary = parsed
	if int(policy.get("schema_version", 0)) <= 0:
		errors.append("qualification policy schema_version must be positive")
	policy["_sha256"] = FileAccess.get_sha256(QUALIFICATION_POLICY_PATH).to_lower()
	return policy


func _validate_hardware_policy_and_metrics(
	entry: Dictionary, tier: String, policy: Dictionary, errors: Array[String]
) -> void:
	var snapshot := _dictionary(entry.get("qualification_policy", {}))
	var tier_policy := _dictionary(_dictionary(policy.get("tiers", {})).get(tier, {}))
	var expected_metrics := _dictionary(tier_policy.get("metrics", {}))
	if int(snapshot.get("schema_version", 0)) != int(policy.get("schema_version", -1)):
		errors.append("hardware %s qualification policy schema_version does not match repository policy" % tier)
	for key: String in ["product", "platform", "rendering_method"]:
		if str(snapshot.get(key, "")) != str(policy.get(key, "")):
			errors.append("hardware %s qualification policy %s does not match repository policy" % [tier, key])
	if str(snapshot.get("sha256", "")).to_lower() != str(policy.get("_sha256", "")):
		errors.append("hardware %s qualification policy sha256 does not match repository policy" % tier)
	if str(snapshot.get("tier", "")) != tier:
		errors.append("hardware %s qualification policy tier does not match repository policy" % tier)
	if _array(snapshot.get("resolution", [])) != _array(policy.get("resolution", [])):
		errors.append("hardware %s qualification policy resolution does not match repository policy" % tier)
	var recorded_metrics := _dictionary(snapshot.get("metrics", {}))
	var metric_keys: Array[String] = [
		"avg_fps_min",
		"one_percent_low_fps_min",
		"frame_ms_p95_max",
		"frame_ms_p99_max",
		"frame_budget_miss_30fps_percent_max",
		"profile_load_ms_max",
		"working_set_p95_mib_max",
	]
	for key: String in metric_keys:
		if (
			not _is_finite_number(recorded_metrics.get(key, null))
			or not _is_finite_number(expected_metrics.get(key, null))
			or not is_equal_approx(float(recorded_metrics.get(key)), float(expected_metrics.get(key)))
		):
			errors.append("hardware %s qualification policy metric %s does not match repository policy" % [tier, key])
	_validate_metric_evaluation(
		_dictionary(entry.get("metric_evaluation", {})), expected_metrics, tier, errors
	)


func _validate_metric_evaluation(
	evaluation: Dictionary, metric_policy: Dictionary, tier: String, errors: Array[String]
) -> void:
	var records := _array(evaluation.get("profiles", []))
	var rules: Array[Dictionary] = [
		{"evidence":"avg_fps", "policy":"avg_fps_min", "minimum":true},
		{"evidence":"one_percent_low_fps", "policy":"one_percent_low_fps_min", "minimum":true},
		{"evidence":"frame_ms_p95", "policy":"frame_ms_p95_max", "minimum":false},
		{"evidence":"frame_ms_p99", "policy":"frame_ms_p99_max", "minimum":false},
		{"evidence":"frame_budget_miss_30fps_percent", "policy":"frame_budget_miss_30fps_percent_max", "minimum":false},
		{"evidence":"world_start_ms", "policy":"profile_load_ms_max", "minimum":false},
		{"evidence":"working_set_p95_mib", "policy":"working_set_p95_mib_max", "minimum":false},
	]
	var computed_failures := 0
	var evaluated_profiles := 0
	for profile_id: String in REQUIRED_PROFILES:
		var matches: Array = []
		for value: Variant in records:
			if value is Dictionary and str(value.get("profile_id", "")) == profile_id:
				matches.append(value)
		if matches.size() != 1:
			computed_failures += 1
			errors.append("hardware %s metric threshold failed: expected one %s record" % [tier, profile_id])
			continue
		evaluated_profiles += 1
		var record: Dictionary = matches[0]
		var assertions := _dictionary(record.get("assertions", {}))
		var profile_pass := true
		for rule: Dictionary in rules:
			var evidence_key := str(rule.get("evidence", ""))
			var policy_key := str(rule.get("policy", ""))
			var actual: Variant = record.get(evidence_key, null)
			var threshold: Variant = metric_policy.get(policy_key, null)
			var passed := false
			if _is_finite_number(actual) and _is_finite_number(threshold):
				passed = (
					float(actual) >= 0.0
					and (
						float(actual) >= float(threshold)
						if bool(rule.get("minimum", false))
						else float(actual) <= float(threshold)
					)
				)
			if not passed:
				computed_failures += 1
				profile_pass = false
				errors.append("hardware %s metric threshold failed: %s.%s" % [tier, profile_id, evidence_key])
			if bool(assertions.get(policy_key, not passed)) != passed:
				errors.append("hardware %s metric assertion does not match recomputed evidence: %s.%s" % [tier, profile_id, policy_key])
		if bool(record.get("pass", not profile_pass)) != profile_pass:
			errors.append("hardware %s metric profile result does not match recomputed evidence: %s" % [tier, profile_id])
	var computed_pass := computed_failures == 0 and evaluated_profiles == REQUIRED_PROFILES.size()
	if int(evaluation.get("profile_count", -1)) != evaluated_profiles:
		errors.append("hardware %s metric evaluation profile_count does not match recomputed evidence" % tier)
	if int(evaluation.get("assertion_count", -1)) != evaluated_profiles * rules.size():
		errors.append("hardware %s metric evaluation assertion_count does not match recomputed evidence" % tier)
	if int(evaluation.get("failure_count", -1)) != computed_failures:
		errors.append("hardware %s metric evaluation failure_count does not match recomputed evidence" % tier)
	if bool(evaluation.get("passed", not computed_pass)) != computed_pass:
		errors.append("hardware %s metric evaluation passed does not match recomputed evidence" % tier)
	if _array(evaluation.get("violations", [])).size() != computed_failures:
		errors.append("hardware %s metric evaluation violations do not match recomputed evidence" % tier)


func _validate_soak_policy_snapshot(
	soak: Dictionary, policy: Dictionary, errors: Array[String]
) -> void:
	var snapshot := _dictionary(soak.get("qualification_policy", {}))
	var expected := _dictionary(policy.get("soak", {}))
	if int(snapshot.get("schema_version", 0)) != int(policy.get("schema_version", -1)):
		errors.append("strict soak policy schema_version does not match repository policy")
	if str(snapshot.get("sha256", "")).to_lower() != str(policy.get("_sha256", "")):
		errors.append("strict soak policy sha256 does not match repository policy")
	if bool(snapshot.get("all_profiles_required", false)) != bool(expected.get("all_profiles_required", false)):
		errors.append("strict soak policy all_profiles_required does not match repository policy")
	for key: String in [
		"duration_seconds_min",
		"minimum_completed_routes",
		"fatal_diagnostics_max",
		"memory_growth_percent_max",
		"route_transport_after_spawn_max",
	]:
		if (
			not _is_finite_number(snapshot.get(key, null))
			or not _is_finite_number(expected.get(key, null))
			or not is_equal_approx(float(snapshot.get(key)), float(expected.get(key)))
		):
			errors.append("strict soak policy %s does not match repository policy" % key)


func _validate_lifecycle_summary(summary: Dictionary, errors: Array[String]) -> void:
	if int(summary.get("schema_version", 0)) != 1:
		errors.append("strict soak lifecycle schema_version must equal 1")
	if not bool(summary.get("release_build", false)):
		errors.append("strict soak lifecycle must come from a release build")
	if int(summary.get("captured_unix", 0)) <= 0 or str(summary.get("engine_version", "")).is_empty():
		errors.append("strict soak lifecycle capture identity is invalid")
	if not REQUIRED_PROFILES.has(str(summary.get("first_world_profile_id", ""))):
		errors.append("strict soak lifecycle first world profile is not formal")
	var world_id := str(summary.get("first_world_id", "")).strip_edges()
	if world_id.is_empty():
		errors.append("strict soak lifecycle first world id is required")
	if (
		not bool(summary.get("first_save_success", false))
		or int(summary.get("first_save_bytes", 0)) <= 0
		or not bool(summary.get("world_save_identity_matches", false))
		or str(summary.get("first_save_world_id", "")) != world_id
	):
		errors.append("strict soak lifecycle first save must match the playable world")
	if not bool(summary.get("timings_monotonic", false)):
		errors.append("strict soak lifecycle timings must be monotonic")
	if int(summary.get("quit_attempt_count", 0)) < 1 or str(summary.get("quit_source", "")).is_empty():
		errors.append("strict soak lifecycle authoritative quit must be attempted")
	if not bool(summary.get("quit_prepared", false)):
		errors.append("strict soak lifecycle authoritative quit must be prepared")
	if str(summary.get("termination_reason", "")) != "prepared_quit":
		errors.append("strict soak lifecycle termination_reason must equal prepared_quit")
	for prefix: String in ["service_hub", "game"]:
		if (
			int(summary.get("%s_request_count" % prefix, 0)) < 1
			or int(summary.get("%s_success_count" % prefix, 0)) < 1
			or int(summary.get("%s_failure_count" % prefix, -1)) != 0
		):
			errors.append("strict soak lifecycle %s quit counts are invalid" % prefix)
	if not bool(summary.get("authoritative_clean_quit", false)):
		errors.append("strict soak lifecycle authoritative_clean_quit must be true")


func _validate_soak(
	soak: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	require_target: bool,
	policy: Dictionary
) -> void:
	var soak_policy := _dictionary(policy.get("soak", {}))
	var duration_min := int(soak_policy.get("duration_seconds_min", STRICT_SOAK_SECONDS))
	var route_min := int(soak_policy.get("minimum_completed_routes", 10))
	var fatal_max := int(soak_policy.get("fatal_diagnostics_max", 0))
	var memory_growth_max := float(soak_policy.get("memory_growth_percent_max", 25.0))
	var transport_max := int(soak_policy.get("route_transport_after_spawn_max", 0))
	if int(soak.get("schema_version", 0)) != 2:
		errors.append("strict soak schema_version must equal 2")
	if not bool(soak.get("exact_final_package_reused", false)):
		errors.append("strict soak must attest exact final package reuse")
	_validate_soak_policy_snapshot(soak, policy, errors)
	var requested := int(soak.get("requested_seconds", 0))
	var elapsed := int(soak.get("elapsed_seconds", 0))
	var reference_only := bool(soak.get("reference_only", false))
	if requested <= 0 or elapsed <= 0:
		errors.append("strict soak durations must be positive")
	if require_target:
		if requested < duration_min or elapsed < duration_min:
			errors.append("target-hardware soak must run for at least %d seconds" % duration_min)
		if reference_only:
			errors.append("target-hardware soak cannot be reference_only")
		if not bool(soak.get("target_hardware", false)):
			errors.append("strict soak must attest target_hardware")
	else:
		if not reference_only:
			errors.append("non-target soak must be reference_only")
		if requested < duration_min:
			warnings.append("reference soak is shorter than the commercial %d-second gate" % duration_min)
	var profiles := _string_set(_array(soak.get("profiles", [])))
	for profile_id: String in REQUIRED_PROFILES:
		if not profiles.has(profile_id):
			errors.append("strict soak is missing profile %s" % profile_id)
	if profiles.size() != REQUIRED_PROFILES.size() or int(soak.get("profile_count", 0)) != REQUIRED_PROFILES.size():
		errors.append("strict soak must cover exactly %d formal profiles" % REQUIRED_PROFILES.size())
	var completed_routes := int(soak.get("completed_routes", 0))
	if completed_routes <= 0 or int(soak.get("cycle_count", 0)) != completed_routes:
		errors.append("strict soak completed_routes must be positive and equal cycle_count")
	if require_target and completed_routes < route_min:
		errors.append("target-hardware soak must complete at least %d routes" % route_min)
	elif not require_target and completed_routes < REQUIRED_PROFILES.size():
		errors.append("reference soak must complete at least %d routes" % REQUIRED_PROFILES.size())
	elif not require_target and completed_routes < route_min:
		warnings.append("reference soak completed fewer than the commercial %d-route gate" % route_min)
	var fatal_count := int(soak.get("fatal_diagnostics_count", -1))
	if fatal_count < 0 or fatal_count > fatal_max:
		errors.append("strict soak fatal diagnostics exceed policy")
	var transport_count := int(soak.get("post_spawn_transport_count", -1))
	if transport_count < 0 or transport_count > transport_max:
		errors.append("strict soak post-spawn transport exceeds policy")
	if int(soak.get("player_transform_writes", -1)) != 0:
		errors.append("strict soak player_transform_writes must be zero")
	var first_working_set: Variant = soak.get("working_set_first_p95_mib", null)
	var last_working_set: Variant = soak.get("working_set_last_p95_mib", null)
	var recorded_growth: Variant = soak.get("memory_growth_percent", null)
	if (
		not _is_finite_number(first_working_set)
		or float(first_working_set) <= 0.0
		or not _is_finite_number(last_working_set)
		or float(last_working_set) <= 0.0
		or not _is_finite_number(recorded_growth)
	):
		errors.append("strict soak Working Set growth evidence must be finite and positive")
	else:
		var computed_growth := snappedf(
			((float(last_working_set) - float(first_working_set)) / float(first_working_set)) * 100.0,
			0.0001
		)
		if absf(computed_growth - float(recorded_growth)) > 0.0001:
			errors.append("strict soak memory_growth_percent does not match Working Set evidence")
		if float(recorded_growth) > memory_growth_max:
			errors.append("strict soak Working Set growth exceeds policy")
	_validate_lifecycle_summary(_dictionary(soak.get("lifecycle", {})), errors)
	if int(soak.get("authoritative_cycle_lifecycle_count", -1)) != completed_routes:
		errors.append("strict soak authoritative cycle lifecycle count must equal completed routes")
	if not bool(soak.get("clean_exit", false)):
		errors.append("strict soak must end with a clean exit")
	if int(soak.get("crash_count", -1)) != 0:
		errors.append("strict soak crash_count must be zero")
	if bool(soak.get("timed_out", true)):
		errors.append("strict soak must not time out")
	if str(soak.get("result", "")) != "pass":
		errors.append("strict soak result must be pass")
	_require_hash(errors, soak, "lifecycle_report_sha256", 64)
	_require_hash(errors, soak, "soak_report_sha256", 64)
	_require_hash(errors, soak, "progress_journal_sha256", 64)


func _validate_fault_lab(fault_lab: Dictionary, errors: Array[String], require_real: bool) -> void:
	_require_text(errors, fault_lab, "operator_id")
	var operator_id := str(fault_lab.get("operator_id", "")).strip_edges()
	if str(fault_lab.get("result", "")) != "pass":
		errors.append("fault lab result must be pass")
	var seen: Dictionary = {}
	for value: Variant in _array(fault_lab.get("scenarios", [])):
		if not value is Dictionary:
			errors.append("fault lab scenarios must be dictionaries")
			continue
		var scenario: Dictionary = value
		var scenario_type := str(scenario.get("type", ""))
		if not REQUIRED_FAULT_SCENARIOS.has(scenario_type):
			errors.append("fault scenario is unsupported: %s" % scenario_type)
			continue
		if seen.has(scenario_type):
			errors.append("fault scenario is duplicated: %s" % scenario_type)
		seen[scenario_type] = true
		_require_text(errors, scenario, "operator_id")
		if str(scenario.get("operator_id", "")).strip_edges() != operator_id:
			errors.append("fault scenario operator does not match fault lab: %s" % scenario_type)
		if not bool(scenario.get("interruption_observed", false)):
			errors.append("fault scenario did not observe interruption: %s" % scenario_type)
		if not bool(scenario.get("recovery_verified", false)):
			errors.append("fault scenario did not verify recovery: %s" % scenario_type)
		if not bool(scenario.get("world_integrity_verified", false)):
			errors.append("fault scenario did not verify world integrity: %s" % scenario_type)
		if require_real and not bool(scenario.get("attested_real", false)):
			errors.append("fault scenario requires real attestation: %s" % scenario_type)
		_require_hash(errors, scenario, "before_world_sha256", 64)
		_require_hash(errors, scenario, "after_world_sha256", 64)
	for scenario_type: String in REQUIRED_FAULT_SCENARIOS:
		if not seen.has(scenario_type):
			errors.append("fault lab is missing scenario: %s" % scenario_type)


func _validate_evidence_consistency(
	source: String,
	reference_only: bool,
	hardware: Array,
	soak: Dictionary,
	fault_lab: Dictionary,
	errors: Array[String]
) -> void:
	for value: Variant in hardware:
		if value is Dictionary:
			_validate_child_source(value, source, reference_only, "hardware", errors)
	_validate_child_source(soak, source, reference_only, "strict soak", errors)
	for value: Variant in _array(fault_lab.get("scenarios", [])):
		if value is Dictionary:
			_validate_child_source(value, source, reference_only, "fault scenario", errors)


func _validate_child_source(
	child: Dictionary,
	source: String,
	reference_only: bool,
	label: String,
	errors: Array[String]
) -> void:
	if str(child.get("evidence_source", "")) != source:
		errors.append("%s evidence_source does not match package" % label)
	if bool(child.get("reference_only", not reference_only)) != reference_only:
		errors.append("%s reference_only does not match package" % label)


func _validate_build_bindings(
	build: Dictionary,
	review: Dictionary,
	hardware: Array,
	soak: Dictionary,
	fault_lab: Dictionary,
	errors: Array[String]
) -> void:
	var commit_sha := str(build.get("commit_sha", ""))
	var executable_sha := str(build.get("executable_sha256", ""))
	var pck_sha := str(build.get("pck_sha256", ""))
	var review_build := _dictionary(review.get("build", {}))
	_expect_equal(errors, str(review_build.get("commit_sha", "")), commit_sha, "review commit")
	_expect_equal(
		errors,
		str(review_build.get("executable_sha256", "")),
		executable_sha,
		"review executable"
	)
	_expect_equal(errors, str(review_build.get("pck_sha256", "")), pck_sha, "review PCK")
	for value: Variant in hardware:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var tier := str(entry.get("tier", "unknown"))
		var entry_build := _dictionary(entry.get("build", {}))
		_expect_equal(
			errors,
			str(entry_build.get("executable_sha256", "")),
			executable_sha,
			"hardware %s executable" % tier
		)
		_expect_equal(
			errors,
			str(entry_build.get("pck_sha256", "")),
			pck_sha,
			"hardware %s PCK" % tier
		)
	_expect_equal(
		errors, str(soak.get("executable_sha256", "")), executable_sha, "strict soak executable"
	)
	_expect_equal(errors, str(soak.get("pck_sha256", "")), pck_sha, "strict soak PCK")
	for value: Variant in _array(fault_lab.get("scenarios", [])):
		if not value is Dictionary:
			continue
		var scenario: Dictionary = value
		var scenario_type := str(scenario.get("type", "unknown"))
		var scenario_build := _dictionary(scenario.get("build", {}))
		_expect_equal(
			errors,
			str(scenario_build.get("executable_sha256", "")),
			executable_sha,
			"fault %s executable" % scenario_type
		)
		_expect_equal(
			errors,
			str(scenario_build.get("pck_sha256", "")),
			pck_sha,
			"fault %s PCK" % scenario_type
		)


func _validate_findings(findings: Array, errors: Array[String]) -> void:
	for value: Variant in findings:
		if not value is Dictionary:
			errors.append("findings must be dictionaries")
			continue
		var finding: Dictionary = value
		if (
			str(finding.get("severity", "")) == "blocker"
			and str(finding.get("state", "open")) != "closed"
		):
			errors.append("qualification package contains an unresolved blocker")


func _validate_release_owner(attestation: Dictionary, errors: Array[String], required: bool) -> void:
	if not required and attestation.is_empty():
		return
	_require_text(errors, attestation, "owner_id")
	if int(attestation.get("signed_at_unix", 0)) <= 0:
		errors.append("release owner signed_at_unix must be positive")
	if not bool(attestation.get("all_artifacts_attached", false)):
		errors.append("release owner must attest that all artifacts are attached")
	if not bool(attestation.get("approved_for_release", false)):
		errors.append("release owner must explicitly approve the evidence package")


func _expect_equal(errors: Array[String], actual: String, expected: String, label: String) -> void:
	if actual != expected or actual.is_empty():
		errors.append("%s does not match package build" % label)


func _require_text(errors: Array[String], source: Dictionary, key: String) -> void:
	var text := str(source.get(key, "")).strip_edges()
	if text.is_empty():
		errors.append("%s is required" % key)
	elif text.length() > MAX_TEXT_LENGTH:
		errors.append("%s exceeds the maximum length" % key)


func _require_hash(
	errors: Array[String], source: Dictionary, key: String, expected_length: int
) -> void:
	var value := str(source.get(key, "")).strip_edges().to_lower()
	if value.length() != expected_length or not _is_hex(value):
		errors.append("%s must be a %d-character hexadecimal digest" % [key, expected_length])


func _is_hex(value: String) -> bool:
	for index: int in value.length():
		if not "0123456789abcdef".contains(value[index]):
			return false
	return true


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		var text := str(value).strip_edges()
		if not text.is_empty():
			result[text] = true
	return result


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []
