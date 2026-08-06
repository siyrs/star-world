param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$bundleRoot = [System.IO.Path]::GetFullPath($BundleDirectory)
if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw "Bundle directory not found: $bundleRoot" }

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
function Get-BundlePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw 'Bundle relative path is blank.' }
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized.Contains(':') -or $normalized -match '(^|/)\.\.(/|$)') {
        throw "Unsafe bundle path: $RelativePath"
    }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $bundleRoot $normalized))
    $prefix = $bundleRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Bundle path escapes the root: $RelativePath"
    }
    return $fullPath
}
function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Label)
    if ($Expected -ne $Actual) { throw "$Label mismatch: expected $Expected, got $Actual" }
}

$requiredPaths = @(
    'release-candidate.json',
    'qualification-package.json',
    'binary/StarWorld.exe',
    'binary/StarWorld.pck',
    'evidence/e4-h-review.json',
    'evidence/hardware-minimum.json',
    'evidence/hardware-recommended.json',
    'evidence/strict-soak.json',
    'evidence/fault-hdd.json',
    'evidence/fault-antivirus.json',
    'evidence/fault-power-loss.json',
    'support/hardware-minimum-journey-matrix.json',
    'support/hardware-recommended-journey-matrix.json',
    'support/release-lifecycle-report.json',
    'support/strict-soak-cycles.json',
    'support/strict-soak.progress.jsonl',
    'support/fault-hdd-recovery.json',
    'support/fault-antivirus-recovery.json',
    'support/fault-power-loss-recovery.json'
)
$manifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Bundle manifest not found: $manifestPath" }
foreach ($relativePath in $requiredPaths) {
    $path = Get-BundlePath -RelativePath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required bundle file is missing: $relativePath" }
}
$reparsePoints = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
if ($reparsePoints.Count -gt 0) { throw 'Bundle must not contain symbolic links or reparse points.' }

$actualRelativeFiles = @(
    Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Force |
        ForEach-Object { [System.IO.Path]::GetRelativePath($bundleRoot, $_.FullName).Replace('\', '/') } |
        Where-Object { $_ -ne 'bundle-manifest.json' } |
        Sort-Object
)
$expectedRelativeFiles = @($requiredPaths | Sort-Object)
if (($actualRelativeFiles -join '|') -ne ($expectedRelativeFiles -join '|')) {
    throw "Bundle contains missing or unexpected files. Actual: $($actualRelativeFiles -join ', ')"
}

$bundleManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
if ([int]$bundleManifest.schema_version -ne 1) { throw 'Bundle schema_version must equal 1.' }
if ([string]$bundleManifest.bundle_id -cnotmatch '^[0-9a-f]{64}$') { throw 'bundle_id must be a lowercase SHA-256 digest.' }
if ([long]$bundleManifest.created_at_unix -le 0) { throw 'Bundle created_at_unix must be positive.' }
$entries = @($bundleManifest.files)
if ($entries.Count -ne $requiredPaths.Count) { throw 'Bundle manifest file count is incorrect.' }
$seen = @{}
$canonicalEntries = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $entries) {
    $relativePath = ([string]$entry.path).Replace('\', '/')
    if ($seen.ContainsKey($relativePath)) { throw "Bundle manifest contains duplicate path: $relativePath" }
    $seen[$relativePath] = $true
    $path = Get-BundlePath -RelativePath $relativePath
    if ($relativePath -notin $requiredPaths) { throw "Bundle manifest contains unexpected path: $relativePath" }
    $item = Get-Item -LiteralPath $path -Force
    $actualHash = Get-Sha256 -Path $path
    if ([string]$entry.sha256 -ne $actualHash) { throw "Bundle file hash mismatch: $relativePath" }
    if ([long]$entry.length_bytes -ne [long]$item.Length) { throw "Bundle file length mismatch: $relativePath" }
    $canonicalEntries.Add("$relativePath|$actualHash|$([long]$item.Length)")
}
foreach ($requiredPath in $requiredPaths) {
    if (-not $seen.ContainsKey($requiredPath)) { throw "Bundle manifest is missing path: $requiredPath" }
}

$candidatePath = Get-BundlePath 'release-candidate.json'
$packagePath = Get-BundlePath 'qualification-package.json'
$exePath = Get-BundlePath 'binary/StarWorld.exe'
$pckPath = Get-BundlePath 'binary/StarWorld.pck'
$candidateValidator = Join-Path $PSScriptRoot 'validate_release_candidate_manifest.ps1'
& $candidateValidator -ProjectRoot $projectFullPath -CandidateManifestPath $candidatePath -ReleaseExecutable $exePath -ReleasePck $pckPath | Out-Null
$packageValidator = Join-Path $PSScriptRoot 'validate_external_qualification_package.ps1'
if ($RequireReleaseGate) {
    & $packageValidator -PackagePath $packagePath -RequireReleaseGate | Out-Null
} else {
    & $packageValidator -PackagePath $packagePath | Out-Null
}

$candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json -Depth 30
$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json -Depth 100
$minimum = Get-Content -LiteralPath (Get-BundlePath 'evidence/hardware-minimum.json') -Raw | ConvertFrom-Json -Depth 50
$recommended = Get-Content -LiteralPath (Get-BundlePath 'evidence/hardware-recommended.json') -Raw | ConvertFrom-Json -Depth 50
$soak = Get-Content -LiteralPath (Get-BundlePath 'evidence/strict-soak.json') -Raw | ConvertFrom-Json -Depth 50
$hdd = Get-Content -LiteralPath (Get-BundlePath 'evidence/fault-hdd.json') -Raw | ConvertFrom-Json -Depth 50
$antivirus = Get-Content -LiteralPath (Get-BundlePath 'evidence/fault-antivirus.json') -Raw | ConvertFrom-Json -Depth 50
$powerLoss = Get-Content -LiteralPath (Get-BundlePath 'evidence/fault-power-loss.json') -Raw | ConvertFrom-Json -Depth 50
Assert-Equal ([string]$candidate.candidate_id) ([string]$bundleManifest.candidate_id) 'bundle candidate_id'
Assert-Equal ([string]$package.package_id) ([string]$bundleManifest.package_id) 'bundle package_id'
Assert-Equal ([string]$candidate.build.commit_sha) ([string]$package.build.commit_sha) 'package commit'
Assert-Equal ([string]$candidate.build.version) ([string]$package.build.version) 'package version'
Assert-Equal ([string]$candidate.build.executable.sha256) ([string]$package.build.executable_sha256) 'package executable'
Assert-Equal ([string]$candidate.build.pck.sha256) ([string]$package.build.pck_sha256) 'package PCK'
Assert-Equal ([string]$package.evidence_source) ([string]$bundleManifest.evidence_source) 'bundle evidence source'
Assert-Equal ([string][bool]$package.reference_only) ([string][bool]$bundleManifest.reference_only) 'bundle reference flag'

$artifactMap = [ordered]@{
    experience_review_sha256 = 'evidence/e4-h-review.json'
    minimum_hardware_sha256 = 'evidence/hardware-minimum.json'
    recommended_hardware_sha256 = 'evidence/hardware-recommended.json'
    strict_soak_sha256 = 'evidence/strict-soak.json'
    hdd_fault_sha256 = 'evidence/fault-hdd.json'
    antivirus_fault_sha256 = 'evidence/fault-antivirus.json'
    power_loss_fault_sha256 = 'evidence/fault-power-loss.json'
}
foreach ($property in $artifactMap.GetEnumerator()) {
    $path = Get-BundlePath -RelativePath $property.Value
    Assert-Equal ([string]$package.artifact_manifest.($property.Key)) (Get-Sha256 -Path $path) "artifact manifest $($property.Key)"
}

$supportMap = @(
    @{ Label = 'minimum journey matrix'; Expected = [string]$minimum.journey_matrix.sha256; Path = 'support/hardware-minimum-journey-matrix.json' },
    @{ Label = 'recommended journey matrix'; Expected = [string]$recommended.journey_matrix.sha256; Path = 'support/hardware-recommended-journey-matrix.json' },
    @{ Label = 'soak lifecycle report'; Expected = [string]$soak.lifecycle_report_sha256; Path = 'support/release-lifecycle-report.json' },
    @{ Label = 'soak cycles report'; Expected = [string]$soak.soak_report_sha256; Path = 'support/strict-soak-cycles.json' },
    @{ Label = 'soak progress journal'; Expected = [string]$soak.progress_journal_sha256; Path = 'support/strict-soak.progress.jsonl' },
    @{ Label = 'HDD recovery evidence'; Expected = [string]$hdd.recovery_evidence_sha256; Path = 'support/fault-hdd-recovery.json' },
    @{ Label = 'antivirus recovery evidence'; Expected = [string]$antivirus.recovery_evidence_sha256; Path = 'support/fault-antivirus-recovery.json' },
    @{ Label = 'power-loss recovery evidence'; Expected = [string]$powerLoss.recovery_evidence_sha256; Path = 'support/fault-power-loss-recovery.json' }
)
foreach ($support in $supportMap) {
    Assert-Equal ([string]$support.Expected) (Get-Sha256 -Path (Get-BundlePath -RelativePath $support.Path)) ([string]$support.Label)
}

$packageHash = Get-Sha256 -Path $packagePath
Assert-Equal $packageHash ([string]$bundleManifest.qualification_package_sha256) 'qualification package hash'
$canonical = @(
    'star-world-qualification-chain-bundle-v1',
    "candidate_id=$($candidate.candidate_id)",
    "package_sha256=$packageHash"
) + @($canonicalEntries | Sort-Object)
$expectedBundleId = Get-StringSha256 -Value ($canonical -join "`n")
Assert-Equal $expectedBundleId ([string]$bundleManifest.bundle_id) 'bundle_id'

$result = [ordered]@{
    schema_version = 1
    valid = $true
    bundle_id = [string]$bundleManifest.bundle_id
    candidate_id = [string]$candidate.candidate_id
    package_id = [string]$package.package_id
    release_gate_passed = (-not [bool]$package.reference_only) -and ([string]$package.evidence_source -eq 'target_hardware')
    file_count = $requiredPaths.Count
}
$result | ConvertTo-Json -Depth 5
