class_name UpdatePackagePolicy
extends RefCounted

const AppVersion = preload("res://src/update/app_version.gd")


static func inspect_package(package_path: String, expected_version: String) -> Dictionary:
	if package_path.is_empty() or not FileAccess.file_exists(package_path):
		return _failure("package_missing")
	var reader := ZIPReader.new()
	var open_error := reader.open(package_path)
	if open_error != OK:
		return _failure("package_open_%d" % open_error)
	var files := reader.get_files()
	if AppVersion.UPDATE_MANIFEST_NAME not in files:
		reader.close()
		return _failure("manifest_missing")
	var manifest_bytes := reader.read_file(AppVersion.UPDATE_MANIFEST_NAME)
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if parsed is not Dictionary:
		reader.close()
		return _failure("manifest_invalid")
	var result := validate_manifest(parsed, expected_version, files)
	if bool(result.get("success", false)):
		result["manifest_bytes"] = manifest_bytes
	reader.close()
	return result


static func validate_manifest(
	manifest: Dictionary,
	expected_version: String,
	archive_files: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var schema_version := int(manifest.get("schema_version", 0))
	if schema_version not in [1, 2]:
		return _failure("manifest_schema")
	if str(manifest.get("platform", "")) != "windows-x86_64":
		return _failure("manifest_platform")
	var updater_protocol := int(manifest.get("updater_protocol", 0))
	if updater_protocol <= 0 or updater_protocol > AppVersion.UPDATER_PROTOCOL_VERSION:
		return _failure("updater_too_old")
	if schema_version == 2 and updater_protocol != 2:
		return _failure("manifest_protocol")
	var version := str(manifest.get("version", "")).strip_edges()
	if version != expected_version.strip_edges():
		return _failure("manifest_version")
	var executable := str(manifest.get("executable", "")).strip_edges()
	if executable != AppVersion.EXECUTABLE_NAME:
		return _failure("manifest_executable")
	var signature := {}
	if schema_version == 2:
		var raw_signature: Variant = manifest.get("signature", {})
		if raw_signature is not Dictionary:
			return _failure("manifest_signature")
		signature = raw_signature.duplicate(true)
		if str(signature.get("format", "")) != "cms-detached":
			return _failure("manifest_signature_format")
		if str(signature.get("digest", "")) != "sha256":
			return _failure("manifest_signature_digest")
		if str(signature.get("path", "")) != AppVersion.UPDATE_MANIFEST_SIGNATURE_NAME:
			return _failure("manifest_signature_path")
		if not archive_files.is_empty() and AppVersion.UPDATE_MANIFEST_SIGNATURE_NAME not in archive_files:
			return _failure("manifest_signature_missing")
	var raw_files: Variant = manifest.get("files", [])
	if raw_files is not Array or raw_files.is_empty() or raw_files.size() > 64:
		return _failure("manifest_files")
	var required: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_file: Variant in raw_files:
		if raw_file is not Dictionary:
			return _failure("manifest_file_entry")
		var path := str(raw_file.get("path", "")).replace("\\", "/").strip_edges()
		var digest := str(raw_file.get("sha256", "")).to_lower().strip_edges()
		var size := int(raw_file.get("size", -1))
		if not _is_safe_relative_path(path) or seen.has(path):
			return _failure("manifest_file_path")
		if path in [AppVersion.UPDATE_MANIFEST_NAME, AppVersion.UPDATE_MANIFEST_SIGNATURE_NAME]:
			return _failure("manifest_metadata_listed")
		if not _is_sha256(digest) or size < 0:
			return _failure("manifest_file_hash")
		if not archive_files.is_empty() and path not in archive_files:
			return _failure("manifest_file_missing")
		seen[path] = true
		required.append({"path": path, "sha256": digest, "size": size})
	if AppVersion.EXECUTABLE_NAME not in seen or "StarWorld.pck" not in seen:
		return _failure("required_payload_missing")
	if not archive_files.is_empty():
		for raw_archive_path: String in archive_files:
			var archive_path := raw_archive_path.replace("\\", "/").strip_edges()
			if archive_path.is_empty() or archive_path.ends_with("/"):
				continue
			if archive_path in [AppVersion.UPDATE_MANIFEST_NAME, AppVersion.UPDATE_MANIFEST_SIGNATURE_NAME]:
				continue
			if not seen.has(archive_path):
				return _failure("manifest_unlisted_file")
	return {
		"success": true,
		"schema_version": schema_version,
		"updater_protocol": updater_protocol,
		"version": version,
		"executable": executable,
		"files": required,
		"signature": signature,
		"publisher_signed_manifest": schema_version == 2,
	}


static func _is_safe_relative_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.contains(":")
		and ".." not in path.split("/", false)
		and not path.ends_with("/")
	)


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
