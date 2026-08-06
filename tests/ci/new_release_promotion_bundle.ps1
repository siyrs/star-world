param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$ChainBundleDirectory,
    [Parameter(Mandatory = $true)][string]$PromotionPinPath,
    [string]$OutputDirectory = 'build/external-qualification/release-promotion-bundle',
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $Path))
}
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
function Copy-VerifiedFile {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-Sha256 $Source) -ne (Get-Sha256 $Destination)) { throw "Copied promotion file changed: $Destination" }
}
function Is-UnderRoot {
    param([string]$Path, [string]$Root)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    return $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

$chainRoot = Resolve-ProjectPath $ChainBundleDirectory
$pinPath = Resolve-ProjectPath $PromotionPinPath
$outputRoot = Resolve-ProjectPath $OutputDirectory
if (-not (Test-Path -LiteralPath $chainRoot -PathType Container)) { throw "Chain bundle directory not found: $chainRoot" }
if (-not (Test-Path -LiteralPath $pinPath -PathType Leaf)) { throw "Promotion pin not found: $pinPath" }
if (Is-UnderRoot -Path $outputRoot -Root $chainRoot) { throw 'OutputDirectory must not be inside the source chain bundle.' }
if (Test-Path -LiteralPath $outputRoot) {
    if (@(Get-ChildItem -LiteralPath $outputRoot -Force).Count -gt 0) { throw "OutputDirectory must be absent or empty to prevent stale promotion evidence: $outputRoot" }
} else {
    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
}
$sourceReparsePoints = @(Get-ChildItem -LiteralPath $chainRoot -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
if ($sourceReparsePoints.Count -gt 0) { throw 'Source chain bundle must not contain symbolic links or reparse points.' }

$chainValidator = Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1'
if ($RequireReleaseGate) {
    $chainResultText = (& $chainValidator -ProjectRoot $projectFullPath -BundleDirectory $chainRoot -RequireReleaseGate | Out-String).Trim()
} else {
    $chainResultText = (& $chainValidator -ProjectRoot $projectFullPath -BundleDirectory $chainRoot | Out-String).Trim()
}
$chainResult = $chainResultText | ConvertFrom-Json
$pinValidator = Join-Path $PSScriptRoot 'validate_release_promotion_pin.ps1'
$pinResultText = (& $pinValidator -PinPath $pinPath | Out-String).Trim()
$pinResult = $pinResultText | ConvertFrom-Json
$candidate = Get-Content -LiteralPath (Join-Path $chainRoot 'release-candidate.json') -Raw | ConvertFrom-Json -Depth 30
$chainManifest = Get-Content -LiteralPath (Join-Path $chainRoot 'bundle-manifest.json') -Raw | ConvertFrom-Json -Depth 50
$package = Get-Content -LiteralPath (Join-Path $chainRoot 'qualification-package.json') -Raw | ConvertFrom-Json -Depth 100
if ([string]$pinResult.candidate_id -ne [string]$candidate.candidate_id) { throw 'Promotion pin candidate_id does not match the chain bundle.' }
if ([string]$pinResult.bundle_id -ne [string]$chainManifest.bundle_id) { throw 'Promotion pin bundle_id does not match the chain bundle.' }
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -Depth 30
if ([string]$pin.package_id -ne [string]$package.package_id) { throw 'Promotion pin package_id does not match the qualification package.' }
if ([string]$pin.commit_sha -ne [string]$candidate.build.commit_sha -or [string]$pin.version -ne [string]$candidate.build.version) { throw 'Promotion pin commit/version does not match the candidate.' }
if ([string]$pin.executable_sha256 -ne [string]$candidate.build.executable.sha256 -or [string]$pin.pck_sha256 -ne [string]$candidate.build.pck.sha256) { throw 'Promotion pin binary hashes do not match the candidate.' }

$candidateDestination = Join-Path $outputRoot 'candidate-chain'
foreach ($source in @(Get-ChildItem -LiteralPath $chainRoot -Recurse -File -Force)) {
    $relative = [System.IO.Path]::GetRelativePath($chainRoot, $source.FullName)
    Copy-VerifiedFile -Source $source.FullName -Destination (Join-Path $candidateDestination $relative)
}
$contractMap = [ordered]@{
    'contracts/data/release_qualification.json' = (Join-Path $projectFullPath 'data\release_qualification.json')
    'contracts/project.godot' = (Join-Path $projectFullPath 'project.godot')
    'contracts/export_presets.cfg' = (Join-Path $projectFullPath 'export_presets.cfg')
}
foreach ($entry in $contractMap.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) { throw "Promotion contract snapshot source not found: $($entry.Value)" }
    Copy-VerifiedFile -Source $entry.Value -Destination (Join-Path $outputRoot $entry.Key)
}
Copy-VerifiedFile -Source $pinPath -Destination (Join-Path $outputRoot 'promotion-pin.json')

$fileRecords = [System.Collections.Generic.List[object]]::new()
$canonicalEntries = [System.Collections.Generic.List[string]]::new()
$payloadFiles = @(
    Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Force |
        Where-Object { $_.Name -ne 'promotion-manifest.json' } |
        Sort-Object FullName
)
foreach ($file in $payloadFiles) {
    $relative = [System.IO.Path]::GetRelativePath($outputRoot, $file.FullName).Replace('\', '/')
    $hash = Get-Sha256 $file.FullName
    $fileRecords.Add([ordered]@{ path = $relative; length_bytes = [long]$file.Length; sha256 = $hash })
    $canonicalEntries.Add("$relative|$hash|$([long]$file.Length)")
}
$canonical = @(
    'star-world-release-promotion-bundle-v1',
    "pin_id=$($pin.pin_id)",
    "candidate_id=$($candidate.candidate_id)",
    "bundle_id=$($chainManifest.bundle_id)",
    "package_id=$($package.package_id)"
) + @($canonicalEntries | Sort-Object)
$promotionId = Get-StringSha256 -Value ($canonical -join "`n")
$manifest = [ordered]@{
    schema_version = 1
    promotion_id = $promotionId
    created_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    pin_id = [string]$pin.pin_id
    candidate_id = [string]$candidate.candidate_id
    chain_bundle_id = [string]$chainManifest.bundle_id
    package_id = [string]$package.package_id
    evidence_source = [string]$package.evidence_source
    reference_only = [bool]$package.reference_only
    file_count = $fileRecords.Count
    files = @($fileRecords)
}
$manifestPath = Join-Path $outputRoot 'promotion-manifest.json'
$tempPath = "$manifestPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $manifestPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}
$promotionValidator = Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1'
if ($RequireReleaseGate) {
    & $promotionValidator -PromotionBundleDirectory $outputRoot -ExpectedPinId ([string]$pin.pin_id) -RequireReleaseGate | Out-Null
} else {
    & $promotionValidator -PromotionBundleDirectory $outputRoot -ExpectedPinId ([string]$pin.pin_id) | Out-Null
}
Write-Host "RELEASE PROMOTION BUNDLE PASS | promotion=$promotionId | pin=$($pin.pin_id) | candidate=$($candidate.candidate_id) | chain=$($chainManifest.bundle_id) | files=$($fileRecords.Count) | source=$($package.evidence_source) | output=$outputRoot"
