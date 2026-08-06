param(
    [Parameter(Mandatory = $true)][string]$PromotionBundleDirectory,
    [string]$ExpectedPinId = '',
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$promotionRoot = [System.IO.Path]::GetFullPath($PromotionBundleDirectory)
if (-not (Test-Path -LiteralPath $promotionRoot -PathType Container)) { throw "Promotion bundle directory not found: $promotionRoot" }
if ($RequireReleaseGate -and [string]::IsNullOrWhiteSpace($ExpectedPinId)) { throw '-RequireReleaseGate requires an externally retained -ExpectedPinId.' }
function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Get-PromotionPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw 'Promotion relative path is blank.' }
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized.Contains(':') -or $normalized -match '(^|/)\.\.(/|$)') { throw "Unsafe promotion path: $RelativePath" }
    $full = [System.IO.Path]::GetFullPath((Join-Path $promotionRoot $normalized))
    $prefix = $promotionRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Promotion path escapes the root: $RelativePath" }
    return $full
}
function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Label)
    if ($Expected -ne $Actual) { throw "$Label mismatch: expected $Expected, got $Actual" }
}
function Assert-AllowedPayloadPath {
    param([string]$RelativePath)
    $fixed = @(
        'promotion-pin.json',
        'contracts/data/release_qualification.json',
        'contracts/project.godot',
        'contracts/export_presets.cfg'
    )
    if ($RelativePath -in $fixed) { return }
    if ($RelativePath.StartsWith('candidate-chain/', [System.StringComparison]::Ordinal)) { return }
    throw "Promotion manifest contains unexpected path: $RelativePath"
}

$manifestPath = Join-Path $promotionRoot 'promotion-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Promotion manifest not found: $manifestPath" }
$requiredPaths = @(
    'promotion-pin.json',
    'contracts/data/release_qualification.json',
    'contracts/project.godot',
    'contracts/export_presets.cfg',
    'candidate-chain/bundle-manifest.json',
    'candidate-chain/release-candidate.json',
    'candidate-chain/qualification-package.json',
    'candidate-chain/binary/StarWorld.exe',
    'candidate-chain/binary/StarWorld.pck'
)
foreach ($relative in $requiredPaths) {
    $path = Get-PromotionPath -RelativePath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required promotion file is missing: $relative" }
}
$reparsePoints = @(Get-ChildItem -LiteralPath $promotionRoot -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
if ($reparsePoints.Count -gt 0) { throw 'Promotion bundle must not contain symbolic links or reparse points.' }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
if ([int]$manifest.schema_version -ne 1) { throw 'Promotion manifest schema_version must equal 1.' }
if ([string]$manifest.promotion_id -cnotmatch '^[0-9a-f]{64}$') { throw 'promotion_id must be a lowercase SHA-256 digest.' }
if ([long]$manifest.created_at_unix -le 0) { throw 'Promotion manifest created_at_unix must be positive.' }
$entries = @($manifest.files)
if ([int]$manifest.file_count -ne $entries.Count) { throw 'Promotion manifest file_count does not match files.' }
$seen = @{}
$canonicalEntries = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $entries) {
    $relative = ([string]$entry.path).Replace('\', '/')
    if ($seen.ContainsKey($relative)) { throw "Promotion manifest contains duplicate path: $relative" }
    $seen[$relative] = $true
    $path = Get-PromotionPath -RelativePath $relative
    Assert-AllowedPayloadPath -RelativePath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Promotion manifest references a missing file: $relative" }
    $item = Get-Item -LiteralPath $path -Force
    $hash = Get-Sha256 $path
    if ([string]$entry.sha256 -ne $hash) { throw "Promotion file hash mismatch: $relative" }
    if ([long]$entry.length_bytes -ne [long]$item.Length) { throw "Promotion file length mismatch: $relative" }
    $canonicalEntries.Add("$relative|$hash|$([long]$item.Length)")
}
foreach ($required in $requiredPaths) {
    if (-not $seen.ContainsKey($required)) { throw "Promotion manifest is missing required path: $required" }
}
$actualRelativeFiles = @(
    Get-ChildItem -LiteralPath $promotionRoot -Recurse -File -Force |
        ForEach-Object { [System.IO.Path]::GetRelativePath($promotionRoot, $_.FullName).Replace('\', '/') } |
        Where-Object { $_ -ne 'promotion-manifest.json' } |
        Sort-Object
)
$manifestRelativeFiles = @($entries | ForEach-Object { ([string]$_.path).Replace('\', '/') } | Sort-Object)
if (($actualRelativeFiles -join '|') -ne ($manifestRelativeFiles -join '|')) { throw 'Promotion bundle contains missing or unexpected physical files.' }

$pinPath = Get-PromotionPath 'promotion-pin.json'
$pinValidator = Join-Path $PSScriptRoot 'validate_release_promotion_pin.ps1'
if ([string]::IsNullOrWhiteSpace($ExpectedPinId)) {
    $pinResultText = (& $pinValidator -PinPath $pinPath | Out-String).Trim()
} else {
    $pinResultText = (& $pinValidator -PinPath $pinPath -ExpectedPinId $ExpectedPinId | Out-String).Trim()
}
$pinResult = $pinResultText | ConvertFrom-Json
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -Depth 30

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("star-world-promotion-contracts-" + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'data') | Out-Null
    Copy-Item -LiteralPath (Get-PromotionPath 'contracts/data/release_qualification.json') -Destination (Join-Path $tempRoot 'data\release_qualification.json')
    Copy-Item -LiteralPath (Get-PromotionPath 'contracts/project.godot') -Destination (Join-Path $tempRoot 'project.godot')
    Copy-Item -LiteralPath (Get-PromotionPath 'contracts/export_presets.cfg') -Destination (Join-Path $tempRoot 'export_presets.cfg')
    $chainRoot = Get-PromotionPath 'candidate-chain'
    $chainValidator = Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1'
    if ($RequireReleaseGate) {
        $chainResultText = (& $chainValidator -ProjectRoot $tempRoot -BundleDirectory $chainRoot -RequireReleaseGate | Out-String).Trim()
    } else {
        $chainResultText = (& $chainValidator -ProjectRoot $tempRoot -BundleDirectory $chainRoot | Out-String).Trim()
    }
    $chainResult = $chainResultText | ConvertFrom-Json
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$candidate = Get-Content -LiteralPath (Get-PromotionPath 'candidate-chain/release-candidate.json') -Raw | ConvertFrom-Json -Depth 30
$chainManifest = Get-Content -LiteralPath (Get-PromotionPath 'candidate-chain/bundle-manifest.json') -Raw | ConvertFrom-Json -Depth 50
$package = Get-Content -LiteralPath (Get-PromotionPath 'candidate-chain/qualification-package.json') -Raw | ConvertFrom-Json -Depth 100
Assert-Equal ([string]$pin.pin_id) ([string]$manifest.pin_id) 'promotion pin_id'
Assert-Equal ([string]$candidate.candidate_id) ([string]$manifest.candidate_id) 'promotion candidate_id'
Assert-Equal ([string]$chainManifest.bundle_id) ([string]$manifest.chain_bundle_id) 'promotion chain bundle_id'
Assert-Equal ([string]$package.package_id) ([string]$manifest.package_id) 'promotion package_id'
Assert-Equal ([string]$pin.candidate_id) ([string]$candidate.candidate_id) 'pin candidate_id'
Assert-Equal ([string]$pin.bundle_id) ([string]$chainManifest.bundle_id) 'pin bundle_id'
Assert-Equal ([string]$pin.package_id) ([string]$package.package_id) 'pin package_id'
Assert-Equal ([string]$pin.commit_sha) ([string]$candidate.build.commit_sha) 'pin commit'
Assert-Equal ([string]$pin.version) ([string]$candidate.build.version) 'pin version'
Assert-Equal ([string]$pin.executable_sha256) ([string]$candidate.build.executable.sha256) 'pin executable'
Assert-Equal ([string]$pin.pck_sha256) ([string]$candidate.build.pck.sha256) 'pin PCK'
Assert-Equal ([string]$package.evidence_source) ([string]$manifest.evidence_source) 'promotion evidence source'
Assert-Equal ([string][bool]$package.reference_only) ([string][bool]$manifest.reference_only) 'promotion reference flag'

$canonical = @(
    'star-world-release-promotion-bundle-v1',
    "pin_id=$($pin.pin_id)",
    "candidate_id=$($candidate.candidate_id)",
    "bundle_id=$($chainManifest.bundle_id)",
    "package_id=$($package.package_id)"
) + @($canonicalEntries | Sort-Object)
$expectedPromotionId = Get-StringSha256 -Value ($canonical -join "`n")
Assert-Equal $expectedPromotionId ([string]$manifest.promotion_id) 'promotion_id'

[ordered]@{
    schema_version = 1
    valid = $true
    offline_contract_validation = $true
    identity_pinned = -not [string]::IsNullOrWhiteSpace($ExpectedPinId)
    promotion_id = [string]$manifest.promotion_id
    pin_id = [string]$pinResult.pin_id
    candidate_id = [string]$chainResult.candidate_id
    chain_bundle_id = [string]$chainResult.bundle_id
    package_id = [string]$chainResult.package_id
    release_gate_passed = [bool]$chainResult.release_gate_passed -and (-not [string]::IsNullOrWhiteSpace($ExpectedPinId))
    file_count = $entries.Count
} | ConvertTo-Json -Depth 5
