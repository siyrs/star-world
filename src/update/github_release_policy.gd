class_name GitHubReleasePolicy
extends RefCounted

const SemVer = preload("res://src/update/semantic_version_policy.gd")
const TRUSTED_HTTPS_HOSTS := [
	"github.com",
	"api.github.com",
	"objects.githubusercontent.com",
	"release-assets.githubusercontent.com",
]


static func select_update(
	payload: Dictionary,
	current_version: String,
	package_asset_name: String,
	checksum_asset_name: String,
	allow_local_test_urls: bool = false
) -> Dictionary:
	if bool(payload.get("draft", false)):
		return _failure("draft_release")
	if bool(payload.get("prerelease", false)):
		return _failure("prerelease_ignored")
	var tag_name := str(payload.get("tag_name", "")).strip_edges()
	var parsed := SemVer.parse(tag_name)
	if not bool(parsed.get("success", false)):
		return _failure("invalid_release_version")
	var version := str(parsed.get("normalized", ""))
	if not SemVer.is_newer(version, current_version):
		return {
			"success": true,
			"update_available": false,
			"version": version,
			"tag_name": tag_name,
		}
	var raw_assets: Variant = payload.get("assets", [])
	if raw_assets is not Array:
		return _failure("invalid_assets")
	var package_asset: Dictionary = {}
	var checksum_asset: Dictionary = {}
	for raw_asset: Variant in raw_assets:
		if raw_asset is not Dictionary:
			continue
		var asset: Dictionary = raw_asset
		var name := str(asset.get("name", ""))
		if name == package_asset_name:
			package_asset = _normalize_asset(asset, allow_local_test_urls)
		elif name == checksum_asset_name:
			checksum_asset = _normalize_asset(asset, allow_local_test_urls)
	if package_asset.is_empty():
		return _failure("package_asset_missing")
	if checksum_asset.is_empty():
		return _failure("checksum_asset_missing")
	if int(package_asset.get("size", 0)) <= 0:
		return _failure("invalid_package_size")
	return {
		"success": true,
		"update_available": true,
		"version": version,
		"tag_name": tag_name,
		"name": str(payload.get("name", tag_name)),
		"notes": _bounded_text(str(payload.get("body", "")), 6000),
		"published_at": str(payload.get("published_at", "")),
		"html_url": str(payload.get("html_url", "")),
		"package_asset": package_asset,
		"checksum_asset": checksum_asset,
	}


static func parse_checksum(body: String, expected_asset_name: String) -> Dictionary:
	var text := body.strip_edges()
	if text.is_empty():
		return _failure("checksum_empty")
	for line: String in text.split("\n", false):
		var normalized := line.strip_edges().replace("\t", " ")
		while normalized.contains("  "):
			normalized = normalized.replace("  ", " ")
		var parts := normalized.split(" ", false)
		if parts.size() < 1:
			continue
		var digest := str(parts[0]).strip_edges().to_lower()
		var file_name := str(parts[parts.size() - 1]).trim_prefix("*").strip_edges()
		if not expected_asset_name.is_empty() and not file_name.is_empty() and file_name != expected_asset_name:
			continue
		if _is_sha256(digest):
			return {"success": true, "sha256": digest, "file_name": file_name}
	return _failure("checksum_invalid")


static func is_trusted_url(url: String, allow_local_test_urls: bool = false) -> bool:
	var parsed := _parse_url(url)
	if not bool(parsed.get("success", false)):
		return false
	var scheme := str(parsed.get("scheme", ""))
	var host := str(parsed.get("host", "")).to_lower()
	if allow_local_test_urls and scheme == "http" and host in ["127.0.0.1", "localhost", "::1"]:
		return true
	return scheme == "https" and host in TRUSTED_HTTPS_HOSTS


static func _normalize_asset(asset: Dictionary, allow_local_test_urls: bool) -> Dictionary:
	var url := str(asset.get("browser_download_url", "")).strip_edges()
	if not is_trusted_url(url, allow_local_test_urls):
		return {}
	return {
		"id": int(asset.get("id", 0)),
		"name": str(asset.get("name", "")),
		"size": maxi(0, int(asset.get("size", 0))),
		"url": url,
		"content_type": str(asset.get("content_type", "")),
	}


static func _parse_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("^(https?)://([^/:]+)(?::([0-9]+))?(/.*)?$") != OK:
		return _failure("url_parser")
	var result := regex.search(url.strip_edges())
	if result == null:
		return _failure("invalid_url")
	return {
		"success": true,
		"scheme": result.get_string(1).to_lower(),
		"host": result.get_string(2),
		"port": result.get_string(3),
		"path": result.get_string(4),
	}


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _bounded_text(value: String, max_length: int) -> String:
	return value if value.length() <= max_length else value.left(max_length)


static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
