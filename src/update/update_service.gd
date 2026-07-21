class_name StarWorldUpdateService
extends Node

signal update_available(release: Dictionary)
signal no_update_available(current_version: String)
signal update_status_changed(state: StringName, message: String)
signal update_progress_changed(downloaded_bytes: int, total_bytes: int)
signal update_ready(release: Dictionary, package_path: String)
signal update_failed(reason: String, message: String)
signal update_install_started(version: String)

const AppVersion = preload("res://src/update/app_version.gd")
const ReleasePolicy = preload("res://src/update/github_release_policy.gd")
const PackagePolicy = preload("res://src/update/update_package_policy.gd")
const DownloaderScript = preload("res://src/update/resumable_http_downloader.gd")

const UPDATE_DIRECTORY := "user://updates"
const HELPER_RESOURCE_PATH := "res://src/update/windows_update_helper.ps1"
const API_HEADERS := PackedStringArray([
	"Accept: application/vnd.github+json",
	"X-GitHub-Api-Version: 2022-11-28",
	"User-Agent: StarWorldUpdater/1",
	"Cache-Control: no-cache",
])
const MAX_METADATA_BYTES := 1024 * 1024

var current_version := AppVersion.CURRENT_VERSION
var release_api_url := AppVersion.RELEASE_API_URL
var allow_local_test_urls := false
var automatic_check_enabled := true
var automatic_install_enabled := true
var test_install_directory := ""
var test_launch_executable := ""
var test_launch_arguments: Array[String] = []
var test_keep_process_alive := false

var _release_request: HTTPRequest
var _checksum_request: HTTPRequest
var _downloader: Node
var _state: StringName = &"idle"
var _current_release: Dictionary = {}
var _package_path := ""
var _download_state_path := ""
var _startup_check_started := false
var _startup_notice := ""
var _last_error := ""
var _check_count := 0
var _download_start_count := 0
var _install_launch_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DIRECTORY))
	_release_request = HTTPRequest.new()
	_release_request.name = "ReleaseMetadataRequest"
	_release_request.max_redirects = 4
	add_child(_release_request)
	_release_request.request_completed.connect(_on_release_request_completed)
	_checksum_request = HTTPRequest.new()
	_checksum_request.name = "ReleaseChecksumRequest"
	_checksum_request.max_redirects = 6
	add_child(_checksum_request)
	_checksum_request.request_completed.connect(_on_checksum_request_completed)
	_downloader = DownloaderScript.new()
	_downloader.name = "ResumableReleaseDownloader"
	add_child(_downloader)
	_downloader.progress_changed.connect(_on_download_progress)
	_downloader.download_completed.connect(_on_download_completed)
	_downloader.download_failed.connect(_on_download_failed)
	_acknowledge_update_relaunch()


func check_on_startup() -> void:
	if _startup_check_started or not automatic_check_enabled or not _startup_check_allowed():
		return
	_startup_check_started = true
	call_deferred("check_for_updates", false)


func check_for_updates(force: bool = true) -> bool:
	if _state in [&"checking", &"downloading", &"installing"]:
		return false
	if not force and not _startup_check_allowed():
		return false
	_check_count += 1
	_current_release.clear()
	_set_state(&"checking", "正在检查 GitHub Release…")
	var error := _release_request.request(
		release_api_url,
		API_HEADERS,
		HTTPClient.METHOD_GET
	)
	if error != OK:
		_fail("release_request_%d" % error, "无法连接 GitHub 检查更新。")
		return false
	return true


func ingest_release_payload(payload: Dictionary) -> Dictionary:
	var selection := ReleasePolicy.select_update(
		payload,
		current_version,
		AppVersion.PACKAGE_ASSET_NAME,
		AppVersion.CHECKSUM_ASSET_NAME,
		allow_local_test_urls
	)
	if not bool(selection.get("success", false)):
		_fail(
			str(selection.get("reason", "release_invalid")),
			"GitHub Release 缺少可信的 Windows 更新包或校验文件。"
		)
		return selection
	if not bool(selection.get("update_available", false)):
		_current_release.clear()
		_set_state(&"idle", "当前已是最新版本。")
		no_update_available.emit(current_version)
		return selection
	_current_release = selection.duplicate(true)
	_set_state(
		&"available",
		"发现新版本 v%s。" % str(_current_release.get("version", ""))
	)
	update_available.emit(_current_release.duplicate(true))
	return selection


func download_and_install() -> bool:
	if _state not in [&"available", &"failed", &"ready"] or _current_release.is_empty():
		return false
	if _state == &"ready" and FileAccess.file_exists(_package_path):
		return install_downloaded_update()
	var checksum_asset: Dictionary = _current_release.get("checksum_asset", {})
	var checksum_url := str(checksum_asset.get("url", ""))
	if not ReleasePolicy.is_trusted_url(checksum_url, allow_local_test_urls):
		_fail("checksum_url_untrusted", "更新校验文件地址不可信。")
		return false
	_download_start_count += 1
	_set_state(&"checksum", "正在获取 Release 校验信息…")
	var error := _checksum_request.request(
		checksum_url,
		PackedStringArray([
			"Accept: text/plain",
			"User-Agent: StarWorldUpdater/1",
			"Cache-Control: no-cache",
		]),
		HTTPClient.METHOD_GET
	)
	if error != OK:
		_fail("checksum_request_%d" % error, "无法获取更新包校验信息。")
		return false
	return true


func install_downloaded_update() -> bool:
	if _current_release.is_empty() or _package_path.is_empty() or not FileAccess.file_exists(_package_path):
		_fail("package_not_ready", "更新包尚未准备完成。")
		return false
	var version := str(_current_release.get("version", ""))
	var inspection := PackagePolicy.inspect_package(_package_path, version)
	if not bool(inspection.get("success", false)):
		_fail(str(inspection.get("reason", "package_invalid")), "更新包结构校验失败。")
		return false
	if OS.get_name() != "Windows":
		_fail("unsupported_platform", "自动更新当前仅支持 Windows 发行包。")
		return false
	var install_directory := _resolve_install_directory()
	if install_directory.is_empty():
		_fail("install_directory_unavailable", "无法确定可写的游戏安装目录。")
		return false
	var helper_path := ProjectSettings.globalize_path(
		"%s/starworld-update-helper.ps1" % UPDATE_DIRECTORY
	)
	var helper_source := FileAccess.get_file_as_string(HELPER_RESOURCE_PATH)
	if helper_source.is_empty():
		_fail("update_helper_missing", "发行包缺少更新安装助手。")
		return false
	var helper_file := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper_file == null:
		_fail("update_helper_write_failed", "无法准备更新安装助手。")
		return false
	helper_file.store_string(helper_source)
	helper_file.flush()
	var result_path := ProjectSettings.globalize_path(
		"%s/install-result.json" % UPDATE_DIRECTORY
	)
	var launch_args_base64 := Marshalls.utf8_to_base64(
		JSON.stringify(test_launch_arguments)
	)
	var arguments := PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", helper_path,
		"-ParentProcessId", str(0 if test_keep_process_alive else OS.get_process_id()),
		"-PackagePath", _package_path,
		"-ExpectedPackageSha256", str(_current_release.get("sha256", "")),
		"-InstallDirectory", install_directory,
		"-ExecutableName", AppVersion.EXECUTABLE_NAME,
		"-TargetVersion", version,
		"-ResultPath", result_path,
		"-LaunchArgumentsBase64", launch_args_base64,
	])
	if not test_launch_executable.is_empty():
		arguments.append("-LaunchExecutable")
		arguments.append(test_launch_executable)
	var pid := OS.create_process("powershell.exe", arguments)
	if pid <= 0:
		_fail("helper_launch_failed", "无法启动更新安装助手。")
		return false
	_install_launch_count += 1
	_set_state(&"installing", "更新包已验证，正在退出并安装 v%s…" % version)
	update_install_started.emit(version)
	if not test_keep_process_alive:
		get_tree().quit()
	return true


func dismiss_update() -> void:
	if _state in [&"available", &"failed"]:
		_set_state(&"idle", "已暂缓更新；下次启动会继续提示。")


func get_current_release() -> Dictionary:
	return _current_release.duplicate(true)


func get_state() -> StringName:
	return _state


func get_startup_notice() -> String:
	return _startup_notice


func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"current_version": current_version,
		"release_version": str(_current_release.get("version", "")),
		"package_path": _package_path,
		"last_error": _last_error,
		"check_count": _check_count,
		"download_start_count": _download_start_count,
		"install_launch_count": _install_launch_count,
		"downloader": _downloader.get_snapshot() if _downloader != null else {},
		"startup_notice": _startup_notice,
	}


func _on_release_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("release_network_%d" % result, "检查更新时网络连接失败。")
		return
	if response_code == 404:
		_set_state(&"idle", "仓库尚未发布 Release。")
		no_update_available.emit(current_version)
		return
	if response_code != 200 or body.size() > MAX_METADATA_BYTES:
		_fail("release_http_%d" % response_code, "GitHub Release 响应无效。")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is not Dictionary:
		_fail("release_json", "GitHub Release 数据无法解析。")
		return
	ingest_release_payload(parsed)


func _on_checksum_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.size() > 64 * 1024:
		_fail("checksum_http_%d_%d" % [result, response_code], "更新校验文件下载失败。")
		return
	var parsed := ReleasePolicy.parse_checksum(
		body.get_string_from_utf8(),
		AppVersion.PACKAGE_ASSET_NAME
	)
	if not bool(parsed.get("success", false)):
		_fail(str(parsed.get("reason", "checksum_invalid")), "更新包 SHA-256 校验信息无效。")
		return
	_current_release["sha256"] = str(parsed.get("sha256", ""))
	_start_resumable_download()


func _start_resumable_download() -> void:
	var package_asset: Dictionary = _current_release.get("package_asset", {})
	var version := str(_current_release.get("version", ""))
	var safe_tag := version.replace("/", "_").replace("\\", "_")
	_package_path = ProjectSettings.globalize_path(
		"%s/%s-%s.part" % [UPDATE_DIRECTORY, AppVersion.PACKAGE_ASSET_NAME, safe_tag]
	)
	_download_state_path = ProjectSettings.globalize_path(
		"%s/download-state.json" % UPDATE_DIRECTORY
	)
	var request := {
		"tag_name": str(_current_release.get("tag_name", "")),
		"asset_url": str(package_asset.get("url", "")),
		"asset_name": str(package_asset.get("name", "")),
		"expected_size": int(package_asset.get("size", 0)),
		"expected_sha256": str(_current_release.get("sha256", "")),
	}
	_set_state(&"downloading", "正在下载 v%s；中断后可从已完成位置继续。" % version)
	if not bool(_downloader.start(request, _package_path, _download_state_path)):
		_fail("download_start_failed", "无法创建更新下载任务。")


func _on_download_progress(downloaded: int, total: int) -> void:
	update_progress_changed.emit(downloaded, total)


func _on_download_completed(path: String, sha256: String) -> void:
	_package_path = path
	_current_release["sha256"] = sha256
	var inspection := PackagePolicy.inspect_package(
		path,
		str(_current_release.get("version", ""))
	)
	if not bool(inspection.get("success", false)):
		_fail(str(inspection.get("reason", "package_invalid")), "下载完成，但更新包结构不可信。")
		return
	_set_state(&"ready", "下载与校验完成，正在准备安装…")
	update_ready.emit(_current_release.duplicate(true), path)
	if automatic_install_enabled:
		call_deferred("install_downloaded_update")


func _on_download_failed(reason: String) -> void:
	_fail(reason, "更新下载中断；已下载部分会保留，重试或下次启动可继续。")


func _set_state(value: StringName, message: String) -> void:
	_state = value
	if value != &"failed":
		_last_error = ""
	update_status_changed.emit(_state, message)


func _fail(reason: String, message: String) -> void:
	_state = &"failed"
	_last_error = reason
	update_status_changed.emit(_state, message)
	update_failed.emit(reason, message)


func _startup_check_allowed() -> bool:
	var arguments := OS.get_cmdline_user_args()
	for argument: String in arguments:
		if argument == "--disable-update-check" or argument.begins_with("--release-smoke"):
			return false
	if OS.has_feature("editor") or OS.has_feature("headless"):
		return false
	return true


func _resolve_install_directory() -> String:
	if not test_install_directory.is_empty():
		return ProjectSettings.globalize_path(test_install_directory)
	var executable_path := OS.get_executable_path()
	if executable_path.is_empty() or executable_path.get_file().to_lower() != AppVersion.EXECUTABLE_NAME.to_lower():
		return ""
	var directory := executable_path.get_base_dir()
	var probe_path := directory.path_join(".starworld-update-write-test")
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return ""
	probe.store_string("ok")
	probe.close()
	DirAccess.remove_absolute(probe_path)
	return directory


func _acknowledge_update_relaunch() -> void:
	var ack_path := ""
	var requested_version := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--starworld-update-ack="):
			ack_path = argument.trim_prefix("--starworld-update-ack=")
		elif argument.begins_with("--starworld-update-version="):
			requested_version = argument.trim_prefix("--starworld-update-version=")
	if ack_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ack_path.get_base_dir())
	var file := FileAccess.open(ack_path, FileAccess.WRITE)
	if file == null:
		return
	var matches := requested_version == current_version
	file.store_string(JSON.stringify({
		"ok": matches,
		"version": current_version,
		"requested_version": requested_version,
		"pid": OS.get_process_id(),
	}, "  "))
	file.flush()
	_startup_notice = (
		"更新成功，当前版本为 v%s。" % current_version
		if matches
		else "更新启动确认失败：版本不匹配。"
	)
