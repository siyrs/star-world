extends SceneTree

const DownloaderScript = preload("res://src/update/resumable_http_downloader.gd")
const AppVersion = preload("res://src/update/app_version.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ready_path := _argument_value("--range-ready=")
	var work_directory := _argument_value("--range-work-dir=")
	_check(not ready_path.is_empty(), "range server ready-file argument is provided")
	_check(not work_directory.is_empty(), "range download work directory is provided")
	if ready_path.is_empty() or work_directory.is_empty():
		_finish()
		return
	var ready := await _wait_for_json(ready_path, 600)
	_check(not ready.is_empty(), "local Range server reports its deterministic fixture")
	if ready.is_empty():
		_finish()
		return
	var url := str(ready.get("url", ""))
	var expected_size := int(ready.get("size", 0))
	var expected_sha256 := str(ready.get("sha256", ""))
	var expected_etag := str(ready.get("etag", ""))
	var server_log := str(ready.get("log_path", ""))
	_check(url.begins_with("http://127.0.0.1:"), "acceptance uses an isolated localhost HTTP server")
	_check(expected_size > 1024 * 1024 and expected_sha256.length() == 64, "fixture exposes a non-trivial size and SHA-256")
	DirAccess.make_dir_recursive_absolute(work_directory)
	var partial_path := work_directory.path_join("StarWorld-Windows-x86_64.zip.part")
	var state_path := work_directory.path_join("download-state.json")
	_remove_file(partial_path)
	_remove_file(state_path)
	var request := {
		"tag_name":"v1.1.0",
		"asset_url":url,
		"asset_name":AppVersion.PACKAGE_ASSET_NAME,
		"expected_size":expected_size,
		"expected_sha256":expected_sha256,
		"allow_local_test_urls":true,
	}

	# First process: the server advertises the complete body but deliberately
	# closes the socket after a prefix.  The downloader must persist the prefix.
	var first = DownloaderScript.new()
	root.add_child(first)
	await process_frame
	var first_result := await _run_downloader(first, request, partial_path, state_path, 2400)
	_check(not bool(first_result.get("completed", false)), "forced connection loss does not report a complete package")
	_check(bool(first_result.get("failed", false)), "forced connection loss produces a bounded failure")
	var partial_size := _file_size(partial_path)
	_check(partial_size > 256 * 1024 and partial_size < expected_size, "interrupted transfer preserves a useful partial file")
	_check(FileAccess.file_exists(state_path), "interrupted transfer persists resume metadata")
	var persisted_state := _read_json(state_path)
	_check(int(persisted_state.get("downloaded_bytes", -1)) == partial_size, "resume state matches the flushed partial length")
	_check(str(persisted_state.get("etag", "")) == expected_etag, "resume state preserves the server ETag")
	first.queue_free()
	await process_frame
	await process_frame

	# Second process: a fresh downloader instance simulates restarting the game
	# after power/network loss.  It must send Range + If-Range and append safely.
	var second = DownloaderScript.new()
	root.add_child(second)
	await process_frame
	var second_result := await _run_downloader(second, request, partial_path, state_path, 3600)
	_check(bool(second_result.get("completed", false)), "fresh downloader resumes and completes the same release asset")
	_check(not bool(second_result.get("failed", false)), "resumed transfer completes without a second failure")
	_check(_file_size(partial_path) == expected_size, "resumed file has the exact expected size")
	_check(_sha256_file(partial_path) == expected_sha256, "resumed file matches the authoritative SHA-256")
	_check(not FileAccess.file_exists(state_path), "successful verification removes transient resume state")
	var events := _read_json_lines(server_log)
	var forced_disconnect := false
	var resume_event: Dictionary = {}
	for event: Dictionary in events:
		if str(event.get("action", "")) == "forced_disconnect":
			forced_disconnect = true
		elif str(event.get("action", "")) == "resume":
			resume_event = event
	_check(forced_disconnect, "server confirms the first response was physically interrupted")
	_check(not resume_event.is_empty(), "server confirms a real HTTP 206 resume request")
	if not resume_event.is_empty():
		_check(str(resume_event.get("range", "")) == "bytes=%d-" % partial_size, "resumed request starts at the persisted byte boundary")
		_check(str(resume_event.get("if_range", "")) == expected_etag, "resumed request binds the byte range to the ETag")
	second.queue_free()
	await process_frame
	_remove_file(partial_path)
	_remove_file(state_path)
	_finish()


func _run_downloader(
	downloader: Node,
	request: Dictionary,
	partial_path: String,
	state_path: String,
	frame_limit: int
) -> Dictionary:
	var result := {"completed":false, "failed":false, "reason":""}
	downloader.download_completed.connect(
		func(_path: String, _sha256: String) -> void: result["completed"] = true,
		CONNECT_ONE_SHOT
	)
	downloader.download_failed.connect(
		func(reason: String) -> void:
			result["failed"] = true
			result["reason"] = reason,
		CONNECT_ONE_SHOT
	)
	if not bool(downloader.start(request, partial_path, state_path)):
		result["failed"] = true
		if str(result.get("reason", "")).is_empty():
			result["reason"] = "start_failed"
		return result
	for _frame in frame_limit:
		await process_frame
		if bool(result.get("completed", false)) or bool(result.get("failed", false)):
			return result
	downloader.cancel(true)
	result["failed"] = true
	result["reason"] = "timeout"
	return result


func _wait_for_json(path: String, frame_limit: int) -> Dictionary:
	for _frame in frame_limit:
		if FileAccess.file_exists(path):
			var parsed := _read_json(path)
			if not parsed.is_empty():
				return parsed
		await process_frame
	return {}


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _read_json_lines(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	for line: String in file.get_as_text().split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			result.append(parsed)
	return result


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	return context.finish().hex_encode()


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return int(file.get_length()) if file != null else 0


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("QA RESUMABLE DOWNLOAD PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA RESUMABLE DOWNLOAD FAILURE: %s" % failure)
		print("QA RESUMABLE DOWNLOAD FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
