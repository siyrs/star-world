class_name ResumableHttpDownloader
extends Node

signal progress_changed(downloaded_bytes: int, expected_bytes: int)
signal download_completed(package_path: String, sha256: String)
signal download_failed(reason: String)

const Policy = preload("res://src/update/resumable_download_policy.gd")
const ReleasePolicy = preload("res://src/update/github_release_policy.gd")
const USER_AGENT := "StarWorldUpdater/1"
const FLUSH_INTERVAL_BYTES := 256 * 1024
const MAX_RESTARTS := 2

var _client := HTTPClient.new()
var _request: Dictionary = {}
var _state: Dictionary = {}
var _current_url := ""
var _partial_path := ""
var _state_path := ""
var _file: FileAccess
var _offset := 0
var _downloaded := 0
var _expected_size := 0
var _response_started := false
var _request_sent := false
var _response_action := ""
var _redirect_count := 0
var _restart_count := 0
var _bytes_since_flush := 0
var _active := false
var _failed := false
var _allow_local_test_urls := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start(request: Dictionary, partial_path: String, state_path: String) -> bool:
	# Preserve an interrupted transfer until the requested release identity has
	# been compared.  Calling cancel(false) here would silently delete the bytes
	# that make an in-process retry resumable.
	cancel(true)
	_allow_local_test_urls = bool(request.get("allow_local_test_urls", false))
	_request = Policy.normalize_state(request)
	_expected_size = int(_request.get("expected_size", 0))
	if (
		str(_request.get("asset_url", "")).is_empty()
		or _expected_size <= 0
		or str(_request.get("expected_sha256", "")).is_empty()
	):
		download_failed.emit("invalid_download_request")
		return false
	_partial_path = partial_path
	_state_path = state_path
	DirAccess.make_dir_recursive_absolute(_partial_path.get_base_dir())
	var existing_state := _read_state(_state_path)
	var partial_size := _file_size(_partial_path)
	if not Policy.can_resume(existing_state, _request, partial_size):
		_remove_file(_partial_path)
		_remove_file(_state_path)
		partial_size = 0
		existing_state = {}
	_state = _request.duplicate(true)
	_state["etag"] = str(existing_state.get("etag", ""))
	_state["downloaded_bytes"] = partial_size
	_state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	_downloaded = partial_size
	_offset = partial_size
	_current_url = str(_request.get("asset_url", ""))
	_redirect_count = 0
	_restart_count = 0
	_failed = false
	if not ReleasePolicy.is_trusted_url(_current_url, _allow_local_test_urls):
		download_failed.emit("untrusted_asset_url")
		return false
	_active = true
	_write_state()
	if Policy.completion_ready(_downloaded, _expected_size):
		return _verify_and_finish()
	if not _open_partial_file(_offset > 0):
		_fail("partial_file_unavailable")
		return false
	if not _connect_current_url():
		return false
	set_process(true)
	progress_changed.emit(_downloaded, _expected_size)
	return true


func cancel(keep_partial: bool = true) -> void:
	set_process(false)
	_active = false
	_request_sent = false
	_response_started = false
	_response_action = ""
	_client.close()
	_close_file(true)
	if not keep_partial:
		_remove_file(_partial_path)
		_remove_file(_state_path)


func is_active() -> bool:
	return _active


func get_snapshot() -> Dictionary:
	return {
		"active": _active,
		"failed": _failed,
		"downloaded_bytes": _downloaded,
		"expected_bytes": _expected_size,
		"partial_path": _partial_path,
		"state_path": _state_path,
		"current_url": _current_url,
		"etag": str(_state.get("etag", "")),
		"redirect_count": _redirect_count,
		"restart_count": _restart_count,
		"allow_local_test_urls": _allow_local_test_urls,
	}


func _process(_delta: float) -> void:
	if not _active:
		return
	var poll_error := _client.poll()
	if poll_error != OK:
		_fail("network_poll_%d" % poll_error)
		return
	var status := _client.get_status()
	if status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail("network_status_%d" % status)
		return
	if status == HTTPClient.STATUS_CONNECTED and not _request_sent:
		_send_request()
		return
	if _request_sent and not _response_started and _client.has_response():
		_handle_response_headers()
		if not _active:
			return
	status = _client.get_status()
	if status == HTTPClient.STATUS_BODY and _response_started:
		_read_available_body()
		return
	if _response_started and status == HTTPClient.STATUS_CONNECTED:
		_finalize_response()
	elif _response_started and status == HTTPClient.STATUS_DISCONNECTED:
		if Policy.completion_ready(_downloaded, _expected_size):
			_finalize_response()
		else:
			_fail("connection_closed_early")


func _connect_current_url() -> bool:
	_client.close()
	_request_sent = false
	_response_started = false
	_response_action = ""
	if not ReleasePolicy.is_trusted_url(_current_url, _allow_local_test_urls):
		_fail("untrusted_redirect_url")
		return false
	var parsed := _parse_url(_current_url)
	if not bool(parsed.get("success", false)):
		_fail("invalid_asset_url")
		return false
	var scheme := str(parsed.get("scheme", ""))
	var host := str(parsed.get("host", ""))
	var port := int(parsed.get("port", 443 if scheme == "https" else 80))
	var tls: TLSOptions = TLSOptions.client() if scheme == "https" else null
	var error := _client.connect_to_host(host, port, tls)
	if error != OK:
		_fail("connect_%d" % error)
		return false
	return true


func _send_request() -> void:
	var parsed := _parse_url(_current_url)
	if not bool(parsed.get("success", false)):
		_fail("invalid_asset_url")
		return
	var headers := Policy.build_headers(
		_offset,
		str(_state.get("etag", "")),
		USER_AGENT
	)
	var error := _client.request(
		HTTPClient.METHOD_GET,
		str(parsed.get("path", "/")),
		headers
	)
	if error != OK:
		_fail("request_%d" % error)
		return
	_request_sent = true


func _handle_response_headers() -> void:
	var code := _client.get_response_code()
	var headers: Dictionary = _lowercase_headers(
		_client.get_response_headers_as_dictionary()
	)
	var decision := Policy.evaluate_response(
		code,
		_offset,
		_expected_size,
		str(headers.get("content-range", ""))
	)
	if not bool(decision.get("success", false)):
		_fail(str(decision.get("reason", "invalid_response")))
		return
	var action := str(decision.get("action", ""))
	if action == "redirect":
		var location := str(headers.get("location", ""))
		if location.is_empty() or _redirect_count >= Policy.MAX_REDIRECTS:
			_fail("redirect_invalid")
			return
		var redirected_url := _resolve_redirect(_current_url, location)
		if not ReleasePolicy.is_trusted_url(redirected_url, _allow_local_test_urls):
			_fail("untrusted_redirect_url")
			return
		_redirect_count += 1
		_current_url = redirected_url
		_connect_current_url()
		return
	if action == "restart":
		if _restart_count >= MAX_RESTARTS:
			_fail("range_ignored_repeatedly")
			return
		_restart_count += 1
		_close_file(false)
		_remove_file(_partial_path)
		_offset = 0
		_downloaded = 0
		_state["etag"] = ""
		_state["downloaded_bytes"] = 0
		_write_state()
		if not _open_partial_file(false):
			_fail("partial_file_unavailable")
			return
		_connect_current_url()
		return
	if action == "already_complete":
		_finalize_response()
		return
	_response_action = action
	var etag := str(headers.get("etag", "")).strip_edges()
	if not etag.is_empty():
		_state["etag"] = etag
	_response_started = true


func _read_available_body() -> void:
	while _client.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _client.read_response_body_chunk()
		if chunk.is_empty():
			break
		if _file == null:
			_fail("partial_file_closed")
			return
		_file.store_buffer(chunk)
		_downloaded += chunk.size()
		_bytes_since_flush += chunk.size()
		if _downloaded > _expected_size:
			_fail("download_exceeds_expected_size")
			return
		if _bytes_since_flush >= FLUSH_INTERVAL_BYTES:
			_file.flush()
			_bytes_since_flush = 0
			_state["downloaded_bytes"] = _downloaded
			_state["updated_at_unix"] = int(Time.get_unix_time_from_system())
			_write_state()
		progress_changed.emit(_downloaded, _expected_size)


func _finalize_response() -> void:
	_close_file(true)
	if not Policy.completion_ready(_downloaded, _expected_size):
		_fail("download_size_mismatch")
		return
	_verify_and_finish()


func _verify_and_finish() -> bool:
	var actual := _sha256_file(_partial_path)
	var expected := str(_request.get("expected_sha256", "")).to_lower()
	if actual.is_empty() or actual != expected:
		_remove_file(_partial_path)
		_remove_file(_state_path)
		_fail("checksum_mismatch")
		return false
	_active = false
	_failed = false
	set_process(false)
	_remove_file(_state_path)
	download_completed.emit(_partial_path, actual)
	return true


func _open_partial_file(append: bool) -> bool:
	_close_file(false)
	if append and FileAccess.file_exists(_partial_path):
		_file = FileAccess.open(_partial_path, FileAccess.READ_WRITE)
		if _file != null:
			_file.seek_end()
	else:
		_file = FileAccess.open(_partial_path, FileAccess.WRITE_READ)
	_bytes_since_flush = 0
	return _file != null


func _close_file(flush: bool) -> void:
	if _file != null:
		if flush:
			_file.flush()
		_file.close()
		_file = null


func _fail(reason: String) -> void:
	if not _active and _failed:
		return
	_active = false
	_failed = true
	set_process(false)
	_client.close()
	_close_file(true)
	_state["downloaded_bytes"] = _file_size(_partial_path)
	_state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	_write_state()
	download_failed.emit(reason)


func _write_state() -> void:
	if _state_path.is_empty():
		return
	var file := FileAccess.open(_state_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(Policy.normalize_state(_state), "  "))
	file.flush()


func _read_state(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return Policy.normalize_state(parsed) if parsed is Dictionary else {}


func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(1024 * 1024, remaining)))
	return context.finish().hex_encode()


func _parse_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile("^(https?)://([^/:]+)(?::([0-9]+))?(/.*)?$") != OK:
		return {"success": false}
	var match := regex.search(url.strip_edges())
	if match == null:
		return {"success": false}
	var scheme := match.get_string(1).to_lower()
	var port_text := match.get_string(3)
	return {
		"success": true,
		"scheme": scheme,
		"host": match.get_string(2),
		"port": int(port_text) if port_text.is_valid_int() else (443 if scheme == "https" else 80),
		"path": match.get_string(4) if not match.get_string(4).is_empty() else "/",
	}


func _resolve_redirect(base_url: String, location: String) -> String:
	if location.begins_with("http://") or location.begins_with("https://"):
		return location
	var parsed := _parse_url(base_url)
	if not bool(parsed.get("success", false)):
		return location
	var origin := "%s://%s" % [parsed.get("scheme", "https"), parsed.get("host", "")]
	var port := int(parsed.get("port", 443))
	if not ((str(parsed.get("scheme", "")) == "https" and port == 443) or (str(parsed.get("scheme", "")) == "http" and port == 80)):
		origin += ":%d" % port
	return origin + (location if location.begins_with("/") else "/" + location)


func _lowercase_headers(headers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in headers.keys():
		result[str(key).to_lower()] = str(headers[key])
	return result


func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	return int(file.get_length()) if file != null else 0


func _remove_file(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
