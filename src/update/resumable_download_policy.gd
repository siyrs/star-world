class_name ResumableDownloadPolicy
extends RefCounted

const STATE_VERSION := 1
const MAX_REDIRECTS := 6


static func normalize_state(raw: Dictionary) -> Dictionary:
	var result := {
		"version": STATE_VERSION,
		"tag_name": _bounded(str(raw.get("tag_name", "")), 128),
		"asset_url": _bounded(str(raw.get("asset_url", "")), 4096),
		"asset_name": _bounded(str(raw.get("asset_name", "")), 256),
		"expected_size": maxi(0, int(raw.get("expected_size", 0))),
		"expected_sha256": _normalize_digest(str(raw.get("expected_sha256", ""))),
		"etag": _bounded(str(raw.get("etag", "")), 512),
		"downloaded_bytes": maxi(0, int(raw.get("downloaded_bytes", 0))),
		"updated_at_unix": maxi(0, int(raw.get("updated_at_unix", 0))),
	}
	if int(result.expected_size) > 0:
		result.downloaded_bytes = mini(int(result.downloaded_bytes), int(result.expected_size))
	return result


static func can_resume(existing: Dictionary, requested: Dictionary, partial_size: int) -> bool:
	var a := normalize_state(existing)
	var b := normalize_state(requested)
	return (
		partial_size > 0
		and str(a.tag_name) == str(b.tag_name)
		and str(a.asset_url) == str(b.asset_url)
		and str(a.asset_name) == str(b.asset_name)
		and int(a.expected_size) == int(b.expected_size)
		and str(a.expected_sha256) == str(b.expected_sha256)
		and partial_size <= int(b.expected_size)
	)


static func build_headers(offset: int, etag: String, user_agent: String) -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/octet-stream",
		"User-Agent: %s" % user_agent,
		"Cache-Control: no-cache",
	])
	if offset > 0:
		headers.append("Range: bytes=%d-" % offset)
		if not etag.strip_edges().is_empty():
			headers.append("If-Range: %s" % etag.strip_edges())
	return headers


static func evaluate_response(
	response_code: int,
	offset: int,
	expected_size: int,
	content_range: String = ""
) -> Dictionary:
	if response_code in [301, 302, 303, 307, 308]:
		return {"success": true, "action": "redirect"}
	if response_code == 206:
		if offset <= 0:
			return _failure("unexpected_partial_response")
		var range_start := _content_range_start(content_range)
		if range_start >= 0 and range_start != offset:
			return _failure("range_mismatch")
		return {"success": true, "action": "append"}
	if response_code == 200:
		return {
			"success": true,
			"action": "write" if offset <= 0 else "restart",
		}
	if response_code == 416 and expected_size > 0 and offset == expected_size:
		return {"success": true, "action": "already_complete"}
	return _failure("http_%d" % response_code)


static func completion_ready(downloaded_bytes: int, expected_size: int) -> bool:
	return expected_size > 0 and downloaded_bytes == expected_size


static func _content_range_start(value: String) -> int:
	var text := value.strip_edges().to_lower()
	if not text.begins_with("bytes ") or not text.contains("-"):
		return -1
	var range_text := text.trim_prefix("bytes ").get_slice("/", 0)
	var start_text := range_text.get_slice("-", 0)
	return int(start_text) if start_text.is_valid_int() else -1


static func _normalize_digest(value: String) -> String:
	var digest := value.strip_edges().to_lower()
	if digest.length() != 64:
		return ""
	for index in digest.length():
		var code := digest.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return ""
	return digest


static func _bounded(value: String, maximum: int) -> String:
	return value if value.length() <= maximum else value.left(maximum)


static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
