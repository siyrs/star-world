class_name ExternalQualificationContract
extends RefCounted

const SCHEMA_VERSION := 2
const STRICT_SOAK_SECONDS := 7200
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

	_validate_build(build, errors)
	_validate_review(review, errors)
	_validate_hardware(hardware, errors, require_real)
	_validate_soak(soak, errors, warnings, require_real)
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


func _validate_hardware(entries: Array, errors: Array[String], require_real: bool) -> void:
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


func _validate_soak(
	soak: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	require_target: bool
) -> void:
	var requested := int(soak.get("requested_seconds", 0))
	var elapsed := int(soak.get("elapsed_seconds", 0))
	var reference_only := bool(soak.get("reference_only", false))
	if requested <= 0 or elapsed <= 0:
		errors.append("strict soak durations must be positive")
	if elapsed > requested + 600:
		errors.append("strict soak elapsed_seconds exceeds the requested window unexpectedly")
	if require_target:
		if requested < STRICT_SOAK_SECONDS or elapsed < STRICT_SOAK_SECONDS:
			errors.append("target-hardware soak must run for at least 7200 seconds")
		if reference_only:
			errors.append("target-hardware soak cannot be reference_only")
		if not bool(soak.get("target_hardware", false)):
			errors.append("strict soak must attest target_hardware")
	else:
		if not reference_only:
			errors.append("non-target soak must be reference_only")
		if requested < STRICT_SOAK_SECONDS:
			warnings.append("reference soak is shorter than the commercial 7200-second gate")
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
