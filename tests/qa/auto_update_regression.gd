extends SceneTree

const SemVer = preload("res://src/update/semantic_version_policy.gd")
const ReleasePolicy = preload("res://src/update/github_release_policy.gd")
const ResumePolicy = preload("res://src/update/resumable_download_policy.gd")
const PackagePolicy = preload("res://src/update/update_package_policy.gd")
const UpdateServiceScript = preload("res://src/update/update_service.gd")
const UpdatePanelScript = preload("res://src/ui/update_prompt_panel.gd")
const AppVersion = preload("res://src/update/app_version.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_semantic_versions()
	_test_release_selection()
	_test_resume_policy()
	_test_package_manifest()
	await _test_service_and_prompt()
	if failures.is_empty():
		print("QA AUTO UPDATE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA AUTO UPDATE FAILURE: %s" % failure)
		print("QA AUTO UPDATE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_semantic_versions() -> void:
	_check(SemVer.normalize("v1.2.3") == "1.2.3", "v-prefixed versions normalize")
	_check(SemVer.compare("1.2.3", "1.2.2") > 0, "patch versions compare")
	_check(SemVer.compare("2.0.0", "1.99.99") > 0, "major versions compare")
	_check(SemVer.compare("1.0.0-beta.2", "1.0.0-beta.10") < 0, "numeric prereleases compare numerically")
	_check(SemVer.compare("1.0.0", "1.0.0-rc.1") > 0, "stable release exceeds prerelease")
	_check(not bool(SemVer.parse("1.02.0").get("success", false)), "leading zero versions are rejected")


func _test_release_selection() -> void:
	var payload := _release_payload("v1.1.0")
	var selection := ReleasePolicy.select_update(
		payload,
		"1.0.0",
		AppVersion.PACKAGE_ASSET_NAME,
		AppVersion.CHECKSUM_ASSET_NAME
	)
	_check(bool(selection.get("success", false)), "valid GitHub release is accepted")
	_check(bool(selection.get("update_available", false)), "newer GitHub release is selected")
	_check(str(selection.get("version", "")) == "1.1.0", "release version is normalized")
	_check(int(selection.get("package_asset", {}).get("size", 0)) == 4096, "package asset size is preserved")
	var same := ReleasePolicy.select_update(
		_release_payload("v1.0.0"),
		"1.0.0",
		AppVersion.PACKAGE_ASSET_NAME,
		AppVersion.CHECKSUM_ASSET_NAME
	)
	_check(bool(same.get("success", false)) and not bool(same.get("update_available", true)), "same version is not offered")
	var draft := _release_payload("v2.0.0")
	draft["draft"] = true
	_check(str(ReleasePolicy.select_update(draft, "1.0.0", AppVersion.PACKAGE_ASSET_NAME, AppVersion.CHECKSUM_ASSET_NAME).get("reason", "")) == "draft_release", "draft releases are rejected")
	var malicious := _release_payload("v2.0.0")
	malicious["assets"][0]["browser_download_url"] = "https://example.com/malware.zip"
	_check(str(ReleasePolicy.select_update(malicious, "1.0.0", AppVersion.PACKAGE_ASSET_NAME, AppVersion.CHECKSUM_ASSET_NAME).get("reason", "")) == "package_asset_missing", "untrusted asset hosts are rejected")
	_check(ReleasePolicy.is_trusted_url("https://release-assets.githubusercontent.com/github-production-release-asset/x"), "official GitHub release CDN is trusted")
	_check(not ReleasePolicy.is_trusted_url("http://github.com/siyrs/star-world/releases/x"), "unencrypted GitHub asset URL is rejected")
	var checksum := ReleasePolicy.parse_checksum("%s  %s" % ["a".repeat(64), AppVersion.PACKAGE_ASSET_NAME], AppVersion.PACKAGE_ASSET_NAME)
	_check(bool(checksum.get("success", false)), "release checksum line parses")
	_check(not bool(ReleasePolicy.parse_checksum("not-a-hash", AppVersion.PACKAGE_ASSET_NAME).get("success", false)), "invalid checksum is rejected")


func _test_resume_policy() -> void:
	var request := {
		"tag_name":"v1.1.0",
		"asset_url":"https://github.com/siyrs/star-world/releases/download/v1.1.0/%s" % AppVersion.PACKAGE_ASSET_NAME,
		"asset_name":AppVersion.PACKAGE_ASSET_NAME,
		"expected_size":1000,
		"expected_sha256":"b".repeat(64),
	}
	var existing := request.duplicate(true)
	existing["etag"] = "\"release-etag\""
	existing["downloaded_bytes"] = 400
	_check(ResumePolicy.can_resume(existing, request, 400), "matching partial download can resume after restart")
	var changed := request.duplicate(true)
	changed["expected_sha256"] = "c".repeat(64)
	_check(not ResumePolicy.can_resume(existing, changed, 400), "different release checksum cannot reuse partial bytes")
	var headers := ResumePolicy.build_headers(400, "\"release-etag\"", "test-agent")
	_check(_headers_contain(headers, "Range: bytes=400-"), "resume sends an HTTP Range header")
	_check(_headers_contain(headers, "If-Range: \"release-etag\""), "resume binds Range to the stored ETag")
	_check(str(ResumePolicy.evaluate_response(206, 400, 1000, "bytes 400-999/1000").get("action", "")) == "append", "matching 206 response appends")
	_check(str(ResumePolicy.evaluate_response(200, 400, 1000).get("action", "")) == "restart", "server ignoring Range triggers a safe restart")
	_check(str(ResumePolicy.evaluate_response(416, 1000, 1000).get("action", "")) == "already_complete", "fully downloaded Range state is accepted")
	_check(str(ResumePolicy.evaluate_response(206, 400, 1000, "bytes 500-999/1000").get("reason", "")) == "range_mismatch", "wrong Content-Range is rejected")


func _test_package_manifest() -> void:
	var directory := ProjectSettings.globalize_path("user://auto-update-regression")
	DirAccess.make_dir_recursive_absolute(directory)
	var package_path := directory.path_join("fixture.zip")
	var malicious_path := directory.path_join("fixture-with-extra-file.zip")
	var exe_bytes := "new-executable".to_utf8_buffer()
	var pck_bytes := "new-resource-pack".to_utf8_buffer()
	var manifest := {
		"schema_version":1,
		"updater_protocol":1,
		"version":"1.1.0",
		"platform":"windows-x86_64",
		"executable":AppVersion.EXECUTABLE_NAME,
		"files":[
			{"path":AppVersion.EXECUTABLE_NAME, "size":exe_bytes.size(), "sha256":_sha256(exe_bytes)},
			{"path":"StarWorld.pck", "size":pck_bytes.size(), "sha256":_sha256(pck_bytes)},
		],
	}
	var packer := ZIPPacker.new()
	_check(packer.open(package_path) == OK, "fixture update package opens")
	_packer_add(packer, AppVersion.EXECUTABLE_NAME, exe_bytes)
	_packer_add(packer, "StarWorld.pck", pck_bytes)
	_packer_add(packer, AppVersion.UPDATE_MANIFEST_NAME, JSON.stringify(manifest).to_utf8_buffer())
	packer.close()
	var inspection := PackagePolicy.inspect_package(package_path, "1.1.0")
	_check(bool(inspection.get("success", false)), "strict package manifest accepts EXE and PCK")
	packer = ZIPPacker.new()
	_check(packer.open(malicious_path) == OK, "extra-file package fixture opens")
	_packer_add(packer, AppVersion.EXECUTABLE_NAME, exe_bytes)
	_packer_add(packer, "StarWorld.pck", pck_bytes)
	_packer_add(packer, "side-load.dll", "unlisted-native-library".to_utf8_buffer())
	_packer_add(packer, AppVersion.UPDATE_MANIFEST_NAME, JSON.stringify(manifest).to_utf8_buffer())
	packer.close()
	var malicious_inspection := PackagePolicy.inspect_package(malicious_path, "1.1.0")
	_check(str(malicious_inspection.get("reason", "")) == "manifest_unlisted_file", "archive files not covered by the manifest are rejected")
	manifest["version"] = "9.9.9"
	_check(str(PackagePolicy.validate_manifest(manifest, "1.1.0").get("reason", "")) == "manifest_version", "package version mismatch is rejected")
	DirAccess.remove_absolute(package_path)
	DirAccess.remove_absolute(malicious_path)


func _test_service_and_prompt() -> void:
	var host := Control.new()
	var service = UpdateServiceScript.new()
	var panel = UpdatePanelScript.new()
	service.automatic_check_enabled = false
	service.automatic_install_enabled = false
	root.add_child(host)
	host.add_child(service)
	host.add_child(panel)
	await process_frame
	panel.setup(service)
	var offered_version := _next_patch_version(AppVersion.CURRENT_VERSION)
	var selection: Dictionary = service.ingest_release_payload(
		_release_payload("v%s" % offered_version)
	)
	await process_frame
	_check(bool(selection.get("update_available", false)), "production service exposes a newer release")
	_check(panel.visible, "update prompt becomes visible")
	_check(panel.get_release_version() == offered_version, "prompt displays the selected release")
	_check(panel.get_primary_button() != null and panel.get_primary_button().text.contains("自动更新"), "prompt exposes download-and-update action")
	panel.get_later_button().emit_signal("pressed")
	await process_frame
	_check(not panel.visible, "later action dismisses the prompt without mutating release state")
	host.queue_free()
	await process_frame
	await process_frame


func _next_patch_version(current: String) -> String:
	var parsed: Dictionary = SemVer.parse(current)
	return "%d.%d.%d" % [
		int(parsed.get("major", 0)),
		int(parsed.get("minor", 0)),
		int(parsed.get("patch", 0)) + 1,
	]


func _release_payload(tag: String) -> Dictionary:
	var base := "https://github.com/siyrs/star-world/releases/download/%s" % tag
	return {
		"tag_name":tag,
		"name":"Star World %s" % tag,
		"draft":false,
		"prerelease":false,
		"body":"Release notes",
		"published_at":"2026-07-21T00:00:00Z",
		"html_url":"https://github.com/siyrs/star-world/releases/tag/%s" % tag,
		"assets":[
			{"id":1, "name":AppVersion.PACKAGE_ASSET_NAME, "size":4096, "browser_download_url":"%s/%s" % [base, AppVersion.PACKAGE_ASSET_NAME]},
			{"id":2, "name":AppVersion.CHECKSUM_ASSET_NAME, "size":96, "browser_download_url":"%s/%s" % [base, AppVersion.CHECKSUM_ASSET_NAME]},
		],
	}


func _headers_contain(headers: PackedStringArray, expected: String) -> bool:
	for header: String in headers:
		if header == expected:
			return true
	return false


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _packer_add(packer: ZIPPacker, path: String, bytes: PackedByteArray) -> void:
	packer.start_file(path)
	packer.write_file(bytes)
	packer.close_file()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
