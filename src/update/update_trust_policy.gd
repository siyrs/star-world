class_name UpdateTrustPolicy
extends RefCounted

const POLICY_PATH := "res://data/update_trust_policy.json"
const SHA256_LENGTH := 64
const DEFAULT_MAX_ACTIVE_PINS := 4


static func load_policy() -> Dictionary:
	var text := FileAccess.get_file_as_string(POLICY_PATH)
	if text.is_empty():
		return _failure("trust_policy_missing")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return _failure("trust_policy_invalid_json")
	return normalize_policy(parsed)


static func normalize_policy(raw: Dictionary) -> Dictionary:
	if int(raw.get("schema_version", 0)) != 1:
		return _failure("trust_policy_schema")
	var max_pins := clampi(int(raw.get("max_active_pins", DEFAULT_MAX_ACTIVE_PINS)), 1, 8)
	var manifest_raw: Variant = raw.get("manifest_signature", {})
	var executable_raw: Variant = raw.get("executable_authenticode", {})
	if manifest_raw is not Dictionary or executable_raw is not Dictionary:
		return _failure("trust_policy_sections")
	var manifest_pins := _normalize_pins(manifest_raw.get("trusted_signer_certificate_sha256", []), max_pins)
	var publisher_pins := _normalize_pins(executable_raw.get("trusted_publisher_certificate_sha256", []), max_pins)
	if not bool(manifest_pins.get("success", false)):
		return manifest_pins
	if not bool(publisher_pins.get("success", false)):
		return publisher_pins
	var normalized := {
		"success": true,
		"schema_version": 1,
		"max_active_pins": max_pins,
		"manifest_signature": {
			"required_for_release": bool(manifest_raw.get("required_for_release", true)),
			"format": str(manifest_raw.get("format", "cms-detached")),
			"digest": str(manifest_raw.get("digest", "sha256")),
			"code_signing_eku_oid": str(manifest_raw.get("code_signing_eku_oid", "1.3.6.1.5.5.7.3.3")),
			"trusted_signer_certificate_sha256": manifest_pins.get("pins", []),
		},
		"executable_authenticode": {
			"required_for_release": bool(executable_raw.get("required_for_release", true)),
			"require_trusted_timestamp": bool(executable_raw.get("require_trusted_timestamp", true)),
			"code_signing_eku_oid": str(executable_raw.get("code_signing_eku_oid", "1.3.6.1.5.5.7.3.3")),
			"timestamp_eku_oid": str(executable_raw.get("timestamp_eku_oid", "1.3.6.1.5.5.7.3.8")),
			"trusted_publisher_certificate_sha256": publisher_pins.get("pins", []),
		},
		"rotation": raw.get("rotation", {}).duplicate(true) if raw.get("rotation", {}) is Dictionary else {},
	}
	if normalized.manifest_signature.format != "cms-detached" or normalized.manifest_signature.digest != "sha256":
		return _failure("trust_policy_manifest_algorithm")
	return normalized


static func validate_release_ready(policy: Dictionary) -> Dictionary:
	if not bool(policy.get("success", false)):
		return policy
	var manifest: Dictionary = policy.get("manifest_signature", {})
	var executable: Dictionary = policy.get("executable_authenticode", {})
	if bool(manifest.get("required_for_release", true)) and Array(manifest.get("trusted_signer_certificate_sha256", [])).is_empty():
		return _failure("manifest_signer_pin_missing")
	if bool(executable.get("required_for_release", true)) and Array(executable.get("trusted_publisher_certificate_sha256", [])).is_empty():
		return _failure("publisher_pin_missing")
	if str(manifest.get("code_signing_eku_oid", "")) != "1.3.6.1.5.5.7.3.3":
		return _failure("manifest_eku_drift")
	if str(executable.get("code_signing_eku_oid", "")) != "1.3.6.1.5.5.7.3.3":
		return _failure("publisher_eku_drift")
	if str(executable.get("timestamp_eku_oid", "")) != "1.3.6.1.5.5.7.3.8":
		return _failure("timestamp_eku_drift")
	return {"success": true}


static func helper_payload(policy: Dictionary) -> Dictionary:
	var copy := policy.duplicate(true)
	copy.erase("success")
	return copy


static func _normalize_pins(raw: Variant, max_pins: int) -> Dictionary:
	if raw is not Array:
		return _failure("trust_policy_pin_list")
	var result: Array[String] = []
	var seen := {}
	for item: Variant in raw:
		var pin := str(item).strip_edges().to_lower()
		if not _is_sha256(pin):
			return _failure("trust_policy_pin_invalid")
		if seen.has(pin):
			continue
		seen[pin] = true
		result.append(pin)
		if result.size() > max_pins:
			return _failure("trust_policy_pin_budget")
	return {"success": true, "pins": result}


static func _is_sha256(value: String) -> bool:
	if value.length() != SHA256_LENGTH:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
