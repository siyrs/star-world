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
  TrustPolicy = Join-Path $root 'src\update\update_trust_policy.gd'
  TrustPolicyData = Join-Path $root 'data\update_trust_policy.json'
  TrustValidator = Join-Path $root 'src\update\windows_update_trust_validator.ps1'
  Service = Join-Path $root 'src\update\update_service.gd'
  Helper = Join-Path $root 'src\update\windows_update_helper.ps1'
  Prompt = Join-Path $root 'src\ui\update_prompt_panel.gd'
  Menu = Join-Path $root 'src\ui\main_menu.gd'
  Project = Join-Path $root 'project.godot'
  Export = Join-Path $root 'export_presets.cfg'
  ManifestBuilder = Join-Path $root 'tools\new_update_manifest.ps1'
  ManifestSigner = Join-Path $root 'tools\sign_update_manifest.ps1'
  Builder = Join-Path $root 'tools\build_update_release.ps1'
  SignedPublisher = Join-Path $root 'tools\publish_signed_update_release.ps1'
  Publish = Join-Path $root '.github\workflows\publish-windows-release.yml'
  Tests = Join-Path $root '.github\workflows\auto-update-tests.yml'
  CryptoAcceptance = Join-Path $root 'tests\qa\windows_update_publisher_trust_acceptance.ps1'
  RangeServer = Join-Path $root 'tests\ci\resumable_range_server.py'
  RangeAcceptance = Join-Path $root 'tests\qa\resumable_download_acceptance.gd'
  RunAll = Join-Path $root 'tests\run_all.ps1'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Auto-update file is missing: $($entry.Key) $($entry.Value)" }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -eq 'TrustPolicyData') { continue }
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}
foreach ($scriptPath in @($paths.TrustValidator,$paths.Helper,$paths.ManifestBuilder,$paths.ManifestSigner,$paths.Builder,$paths.SignedPublisher,$paths.CryptoAcceptance)) {
  $tokens = $null; $parseErrors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
  if (@($parseErrors).Count -gt 0) { throw "PowerShell parse failure in $scriptPath`: $((@($parseErrors | ForEach-Object Message) -join ' | '))" }
}

if ($text.Version -notmatch 'CURRENT_VERSION\s*:=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') { throw 'CURRENT_VERSION must be stable semantic version' }
$version = $Matches[1]
if ($text.Project -notmatch ('config/version="' + [regex]::Escape($version) + '"')) { throw 'project.godot version must match AppVersion' }
if ($text.Version -notmatch 'api\.github\.com/repos/%s/releases/latest') { throw 'Updater must query the GitHub latest-release API' }
foreach ($asset in @('StarWorld-Windows-x86_64.zip','StarWorld-Windows-x86_64.zip.sha256','update-manifest.json','update-manifest.p7s')) {
  if ($text.Version -notmatch [regex]::Escape($asset)) { throw "Pinned updater identity is missing: $asset" }
}
if ($text.Version -notmatch 'UPDATER_PROTOCOL_VERSION\s*:=\s*2') { throw 'Updater protocol must be 2 for publisher-signed manifests.' }

foreach ($method in @('normalize','parse','compare','is_newer')) { if ($text.SemVer -notmatch "static\s+func\s+$method\s*\(") { throw "Semantic version policy missing: $method" } }
foreach ($token in @('draft_release','prerelease_ignored','package_asset_missing','checksum_asset_missing','TRUSTED_HTTPS_HOSTS')) { if ($text.Release -notmatch $token) { throw "GitHub Release trust policy missing: $token" } }
foreach ($token in @('Range: bytes=%d-','If-Range: %s','etag','already_complete','range_mismatch')) { if ($text.ResumePolicy -notmatch [regex]::Escape($token)) { throw "Resume policy missing: $token" } }
foreach ($token in @('FLUSH_INTERVAL_BYTES','download-state.json','checksum_mismatch','HTTPClient','\.part','untrusted_redirect_url','cancel\(true\)')) { if (($text.Downloader + "`n" + $text.Service) -notmatch $token) { throw "Resumable downloader contract missing: $token" } }
if ($text.Downloader -notmatch 'HashingContext\.HASH_SHA256') { throw 'Downloaded package must be SHA-256 verified' }

foreach ($token in @('schema_version not in \[1, 2\]','manifest_signature_missing','manifest_signature_format','UPDATE_MANIFEST_SIGNATURE_NAME','publisher_signed_manifest','manifest_unlisted_file')) {
  if ($text.Package -notmatch $token) { throw "Signed package policy missing: $token" }
}
foreach ($token in @('max_active_pins','trust_policy_pin_budget','manifest_signer_pin_missing','publisher_pin_missing','helper_payload')) { if ($text.TrustPolicy -notmatch $token) { throw "Updater trust policy missing: $token" } }
$trustData = Get-Content -Raw -Encoding UTF8 $paths.TrustPolicyData | ConvertFrom-Json -Depth 20
if ([int]$trustData.schema_version -ne 1 -or [int]$trustData.max_active_pins -ne 4) { throw 'Updater trust data schema/budget drifted.' }
if (-not [bool]$trustData.rotation.overlap_required -or -not [bool]$trustData.rotation.target_package_cannot_add_trust -or -not [bool]$trustData.rotation.pins_are_loaded_from_current_install) { throw 'Updater certificate rotation contract drifted.' }
if (@($trustData.manifest_signature.trusted_signer_certificate_sha256).Count -ne 0 -or @($trustData.executable_authenticode.trusted_publisher_certificate_sha256).Count -ne 0) { throw 'Repository defaults must not invent real publisher certificate pins.' }

foreach ($token in @('SignedCms','CheckSignature','Get-AuthenticodeSignature','TimeStamperCertificate','trusted_signer_certificate_sha256','trusted_publisher_certificate_sha256','Code Signing EKU','Time Stamping EKU')) { if ($text.TrustValidator -notmatch [regex]::Escape($token)) { throw "Windows updater trust validator missing: $token" } }
foreach ($token in @('TrustPolicy','TRUST_VALIDATOR_RESOURCE_PATH','publisher_manifest_required','TrustPolicyBase64','TrustValidatorPath','publisher_trust_ready','test_allow_unsigned_reference_update')) { if ($text.Service -notmatch [regex]::Escape($token)) { throw "Update service publisher trust contract missing: $token" } }
foreach ($token in @('TrustValidatorPath','TrustPolicyBase64','authenticating_publisher','publisher_authenticated','update-manifest.p7s','Reference-only updater trust evidence cannot authorize an install')) { if ($text.Helper -notmatch [regex]::Escape($token)) { throw "Windows helper trust boundary missing: $token" } }
$trustIndex = $text.Helper.IndexOf("phase = 'authenticating_publisher'",[StringComparison]::Ordinal)
$swapIndex = $text.Helper.IndexOf('Move-Item -LiteralPath $installFull -Destination $backupDirectory',[StringComparison]::Ordinal)
if ($trustIndex -lt 0 -or $swapIndex -lt 0 -or $trustIndex -ge $swapIndex) { throw 'Publisher authentication must occur before the install directory swap.' }
foreach ($token in @('Move-Item -LiteralPath $installFull -Destination $backupDirectory','rolled_back','update-ack','Get-Sha256','Archive entry escapes','Updated application did not acknowledge startup','Archive contains an unlisted payload file')) { if ($text.Helper -notmatch [regex]::Escape($token)) { throw "Windows helper safety contract missing: $token" } }
if ($text.Helper -match 'Get-FileHash') { throw 'Windows helper must use its own .NET SHA-256 implementation for broad compatibility' }

if ($text.Project -notmatch 'StarWorldUpdateService=.*update_service\.gd' -or $text.Project -notmatch 'StarWorldUpdateMenuBridge=.*update_menu_bridge\.gd') { throw 'Update service and menu bridge must be autoloaded' }
if ($text.Menu -notmatch '检查更新' -or $text.Menu -notmatch 'AppVersion\.display_version') { throw 'Main menu must expose dynamic version and manual update check' }
if ($text.Prompt -notmatch '下载并自动更新' -or $text.Prompt -notmatch '断网或断电后会从当前进度继续') { throw 'Update prompt must explain automatic install and resume' }
if ($text.Service -notmatch 'OS\.has_feature\("editor"\)' -or $text.Service -notmatch 'OS\.has_feature\("headless"\)' -or $text.Service -notmatch '--disable-update-check') { throw 'Editor, headless and explicit smoke runs must skip automatic public network checks' }
if ($text.Export -notmatch 'include_filter="src/update/\*\.ps1"') { throw 'Updater PowerShell trust validators must be included in the exported PCK' }

foreach ($token in @('schema_version = 2','updater_protocol = 2','cms-detached','update-manifest.p7s')) { if ($text.ManifestBuilder -notmatch [regex]::Escape($token)) { throw "Signed manifest builder missing: $token" } }
foreach ($token in @('SignedCms','ComputeSignature','CertificateThumbprint','ExpectedCertificateSha256','Code Signing EKU')) { if ($text.ManifestSigner -notmatch [regex]::Escape($token)) { throw "Manifest signer missing: $token" } }
foreach ($token in @('RequirePublisherSignature','Publisher-signed update manifest','Signed manifest SHA-256 mismatch','UPDATE_PUBLISHER_SIGNED')) { if ($text.Builder -notmatch [regex]::Escape($token)) { throw "Release builder signed mode missing: $token" } }
foreach ($token in @('validate_windows_publisher_signature.ps1','new_update_manifest.ps1','sign_update_manifest.ps1','windows_update_trust_validator.ps1','RequireTrustedTimestamp','gh.Source release')) { if ($text.SignedPublisher -notmatch [regex]::Escape($token)) { throw "External signed publisher missing: $token" } }
if ($text.Publish -match 'gh release (create|upload)' -or $text.Publish -match 'contents:\s*write') { throw 'Hosted CI must not publish unsigned commercial update assets.' }
foreach ($token in @('REFERENCE_ONLY_PUBLICATION_BLOCKED','REFERENCE_ONLY=true','contents: read','publish_signed_update_release.ps1')) { if ($text.Publish -notmatch [regex]::Escape($token)) { throw "Reference-only CI publication boundary missing: $token" } }

foreach ($script in @('auto_update_regression.gd','auto_update_desktop_acceptance.gd','windows_update_helper_acceptance.ps1','resumable_download_acceptance.gd','resumable_range_server.py')) { if ($text.Tests -notmatch [regex]::Escape($script)) { throw "Auto-update workflow is missing test: $script" } }
foreach ($token in @('New-SelfSignedCertificate','Find-TrustedTimestampedFixture','Manifest byte tamper','Detached signature tamper','PCK tamper should fail before installation','publisher_authenticated')) { if ($text.CryptoAcceptance -notmatch [regex]::Escape($token)) { throw "Publisher-pinned crypto acceptance missing: $token" } }
foreach ($token in @('forced_disconnect','Content-Range','ETag','If-Range')) { if ($text.RangeServer -notmatch [regex]::Escape($token)) { throw "Range server fixture is missing: $token" } }
foreach ($token in @('fresh downloader','HTTP 206','persisted byte boundary','authoritative SHA-256')) { if ($text.RangeAcceptance -notmatch [regex]::Escape($token)) { throw "Real resume acceptance is missing: $token" } }
if ($text.RunAll -notmatch 'validate_auto_update.ps1' -or $text.RunAll -notmatch 'auto_update_regression.gd') { throw 'Auto-update tests must be wired into tests/run_all.ps1' }

Write-Host "PASS auto_update version=$version protocol=2 resumable=real-http sha256=1 publisher-pins=2 cms=1 authenticode=1 timestamp=1 rollback=1 unsigned-publication=blocked"
