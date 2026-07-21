$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Version = Join-Path $root 'src\update\app_version.gd'
  SemVer = Join-Path $root 'src\update\semantic_version_policy.gd'
  Release = Join-Path $root 'src\update\github_release_policy.gd'
  ResumePolicy = Join-Path $root 'src\update\resumable_download_policy.gd'
  Downloader = Join-Path $root 'src\update\resumable_http_downloader.gd'
  Package = Join-Path $root 'src\update\update_package_policy.gd'
  Service = Join-Path $root 'src\update\update_service.gd'
  Helper = Join-Path $root 'src\update\windows_update_helper.ps1'
  Prompt = Join-Path $root 'src\ui\update_prompt_panel.gd'
  Menu = Join-Path $root 'src\ui\main_menu.gd'
  Project = Join-Path $root 'project.godot'
  Export = Join-Path $root 'export_presets.cfg'
  Builder = Join-Path $root 'tools\build_update_release.ps1'
  Publish = Join-Path $root '.github\workflows\publish-windows-release.yml'
  Tests = Join-Path $root '.github\workflows\auto-update-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Auto-update file is missing: $($entry.Key) $($entry.Value)" }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) { $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value }

if ($text.Version -notmatch 'CURRENT_VERSION\s*:=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') { throw 'CURRENT_VERSION must be stable semantic version' }
$version = $Matches[1]
if ($text.Project -notmatch ('config/version="' + [regex]::Escape($version) + '"')) { throw 'project.godot version must match AppVersion' }
if ($text.Version -notmatch 'api\.github\.com/repos/%s/releases/latest') { throw 'Updater must query the GitHub latest-release API' }
foreach ($asset in @('StarWorld-Windows-x86_64.zip','StarWorld-Windows-x86_64.zip.sha256')) {
  if ($text.Version -notmatch [regex]::Escape($asset)) { throw "Pinned release asset is missing: $asset" }
}

foreach ($method in @('normalize','parse','compare','is_newer')) {
  if ($text.SemVer -notmatch "static\s+func\s+$method\s*\(") { throw "Semantic version policy missing: $method" }
}
foreach ($token in @('draft_release','prerelease_ignored','package_asset_missing','checksum_asset_missing','TRUSTED_HTTPS_HOSTS')) {
  if ($text.Release -notmatch $token) { throw "GitHub Release trust policy missing: $token" }
}
foreach ($token in @('Range: bytes=%d-','If-Range: %s','etag','already_complete','range_mismatch')) {
  if ($text.ResumePolicy -notmatch [regex]::Escape($token)) { throw "Resume policy missing: $token" }
}
foreach ($token in @('FLUSH_INTERVAL_BYTES','download-state.json','checksum_mismatch','HTTPClient','\.part')) {
  if (($text.Downloader + "`n" + $text.Service) -notmatch $token) { throw "Resumable downloader contract missing: $token" }
}
if ($text.Downloader -notmatch 'HashingContext\.HASH_SHA256') { throw 'Downloaded package must be SHA-256 verified' }
if ($text.Package -notmatch 'UPDATE_MANIFEST_NAME' -or $text.Package -notmatch 'StarWorld\.pck') { throw 'Package manifest must use the authoritative name and require EXE/PCK' }

foreach ($token in @('Move-Item -LiteralPath $installFull -Destination $backupDirectory','rolled_back','update-ack','Get-Sha256','Archive entry escapes','Updated application did not acknowledge startup')) {
  if ($text.Helper -notmatch [regex]::Escape($token)) { throw "Windows helper safety contract missing: $token" }
}
if ($text.Helper -notmatch 'Stop-Process' -or $text.Helper -notmatch 'Move-Item -LiteralPath $backupDirectory -Destination $installFull') {
  throw 'Windows helper must stop failed launch and restore the backup'
}

if ($text.Project -notmatch 'StarWorldUpdateService=.*update_service\.gd' -or $text.Project -notmatch 'StarWorldUpdateMenuBridge=.*update_menu_bridge\.gd') {
  throw 'Update service and menu bridge must be autoloaded'
}
if ($text.Menu -notmatch '检查更新' -or $text.Menu -notmatch 'AppVersion\.display_version') { throw 'Main menu must expose dynamic version and manual update check' }
if ($text.Prompt -notmatch '下载并自动更新' -or $text.Prompt -notmatch '断网或断电后会从当前进度继续') { throw 'Update prompt must explain automatic install and resume' }
if ($text.Service -notmatch 'OS\.has_feature\("editor"\)' -or $text.Service -notmatch 'OS\.has_feature\("headless"\)' -or $text.Service -notmatch '--disable-update-check') {
  throw 'Editor, headless and explicit smoke runs must skip automatic public network checks'
}
if ($text.Export -notmatch 'include_filter="src/update/\*\.ps1"') { throw 'Updater helper must be included in the exported PCK' }

foreach ($token in @('update-manifest.json','Compress-Archive','Get-FileHash -Algorithm SHA256','StarWorld-Windows-x86_64.zip.sha256')) {
  if ($text.Builder -notmatch [regex]::Escape($token)) { throw "Release builder missing: $token" }
}
foreach ($token in @('permissions:','contents: write','gh release create','gh release upload','--disable-update-check')) {
  if ($text.Publish -notmatch [regex]::Escape($token)) { throw "Publish workflow missing: $token" }
}
foreach ($script in @('auto_update_regression.gd','auto_update_desktop_acceptance.gd','windows_update_helper_acceptance.ps1')) {
  if ($text.Tests -notmatch [regex]::Escape($script)) { throw "Auto-update workflow is missing test: $script" }
}
if ($text.RunAll -notmatch 'validate_auto_update.ps1' -or $text.RunAll -notmatch 'auto_update_regression.gd') {
  throw 'Auto-update tests must be wired into tests/run_all.ps1'
}

Write-Host "PASS auto_update version=$version resumable=1 sha256=1 rollback=1 relaunch_ack=1"
