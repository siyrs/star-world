param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$CandidateManifestPath,
    [Parameter(Mandatory = $true)][string]$QualificationPackagePath,
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][string]$ExperienceReviewPath,
    [Parameter(Mandatory = $true)][string]$MinimumHardwarePath,
    [Parameter(Mandatory = $true)][string]$RecommendedHardwarePath,
    [Parameter(Mandatory = $true)][string]$StrictSoakPath,
    [Parameter(Mandatory = $true)][string]$HddFaultPath,
    [Parameter(Mandatory = $true)][string]$AntivirusFaultPath,
    [Parameter(Mandatory = $true)][string]$PowerLossFaultPath,
    [Parameter(Mandatory = $true)][string]$MinimumJourneyMatrixPath,
    [Parameter(Mandatory = $true)][string]$RecommendedJourneyMatrixPath,
    [Parameter(Mandatory = $true)][string]$LifecycleReportPath,
    [Parameter(Mandatory = $true)][string]$StrictSoakReportPath,
    [Parameter(Mandatory = $true)][string]$StrictSoakProgressPath,
    [Parameter(Mandatory = $true)][string]$HddRecoveryEvidencePath,
    [Parameter(Mandatory = $true)][string]$AntivirusRecoveryEvidencePath,
    [Parameter(Mandatory = $true)][string]$PowerLossRecoveryEvidencePath,
    [string]$OutputDirectory = 'build/external-qualification/chain-bundle',
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
function Resolve-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = Resolve-ProjectPath $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Required bundle source not found: $resolved" }
    return $resolved
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
function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Label)
    if ($Expected -ne $Actual) { throw "$Label mismatch: expected $Expected, got $Actual" }
}
function Copy-BundleFile {
    param([string]$Source, [string]$RelativeDestination)
    $destination = Join-Path $outputRoot $RelativeDestination
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $destination
    if ((Get-Sha256 $Source) -ne (Get-Sha256 $destination)) { throw "Copied bundle file changed: $RelativeDestination" }
}

$candidatePath = Resolve-RequiredFile $CandidateManifestPath
$packagePath = Resolve-RequiredFile $QualificationPackagePath
$exePath = Resolve-RequiredFile $ReleaseExecutable
$pckPath = Resolve-RequiredFile $ReleasePck
$reviewPath = Resolve-RequiredFile $ExperienceReviewPath
$minimumPath = Resolve-RequiredFile $MinimumHardwarePath
$recommendedPath = Resolve-RequiredFile $RecommendedHardwarePath
$soakPath = Resolve-RequiredFile $StrictSoakPath
$hddPath = Resolve-RequiredFile $HddFaultPath
$antivirusPath = Resolve-RequiredFile $AntivirusFaultPath
$powerLossPath = Resolve-RequiredFile $PowerLossFaultPath
$minimumMatrixPath = Resolve-RequiredFile $MinimumJourneyMatrixPath
$recommendedMatrixPath = Resolve-RequiredFile $RecommendedJourneyMatrixPath
$lifecyclePath = Resolve-RequiredFile $LifecycleReportPath
$soakReportPath = Resolve-RequiredFile $StrictSoakReportPath
$soakProgressPath = Resolve-RequiredFile $StrictSoakProgressPath
$hddRecoveryPath = Resolve-RequiredFile $HddRecoveryEvidencePath
$antivirusRecoveryPath = Resolve-RequiredFile $AntivirusRecoveryEvidencePath
$powerLossRecoveryPath = Resolve-RequiredFile $PowerLossRecoveryEvidencePath
$outputRoot = Resolve-ProjectPath $OutputDirectory
if (Test-Path -LiteralPath $outputRoot) {
    if (@(Get-ChildItem -LiteralPath $outputRoot -Force).Count -gt 0) {
        throw "OutputDirectory must be absent or empty to prevent stale evidence: $outputRoot"
    }
} else {
    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
}

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
$minimum = Get-Content -LiteralPath $minimumPath -Raw | ConvertFrom-Json -Depth 50
$recommended = Get-Content -LiteralPath $recommendedPath -Raw | ConvertFrom-Json -Depth 50
$soak = Get-Content -LiteralPath $soakPath -Raw | ConvertFrom-Json -Depth 50
$hdd = Get-Content -LiteralPath $hddPath -Raw | ConvertFrom-Json -Depth 50
$antivirus = Get-Content -LiteralPath $antivirusPath -Raw | ConvertFrom-Json -Depth 50
$powerLoss = Get-Content -LiteralPath $powerLossPath -Raw | ConvertFrom-Json -Depth 50
Assert-Equal ([string]$candidate.build.commit_sha) ([string]$package.build.commit_sha) 'candidate/package commit'
Assert-Equal ([string]$candidate.build.version) ([string]$package.build.version) 'candidate/package version'
Assert-Equal ([string]$candidate.build.executable.sha256) ([string]$package.build.executable_sha256) 'candidate/package executable'
Assert-Equal ([string]$candidate.build.pck.sha256) ([string]$package.build.pck_sha256) 'candidate/package PCK'

$sourceMap = [ordered]@{
    experience_review_sha256 = $reviewPath
    minimum_hardware_sha256 = $minimumPath
    recommended_hardware_sha256 = $recommendedPath
    strict_soak_sha256 = $soakPath
    hdd_fault_sha256 = $hddPath
    antivirus_fault_sha256 = $antivirusPath
    power_loss_fault_sha256 = $powerLossPath
}
foreach ($entry in $sourceMap.GetEnumerator()) {
    Assert-Equal ([string]$package.artifact_manifest.($entry.Key)) (Get-Sha256 $entry.Value) "qualification package artifact $($entry.Key)"
}
Assert-Equal ([string]$minimum.journey_matrix.sha256) (Get-Sha256 $minimumMatrixPath) 'minimum journey matrix'
Assert-Equal ([string]$recommended.journey_matrix.sha256) (Get-Sha256 $recommendedMatrixPath) 'recommended journey matrix'
Assert-Equal ([string]$soak.lifecycle_report_sha256) (Get-Sha256 $lifecyclePath) 'soak lifecycle report'
Assert-Equal ([string]$soak.soak_report_sha256) (Get-Sha256 $soakReportPath) 'soak cycles report'
Assert-Equal ([string]$soak.progress_journal_sha256) (Get-Sha256 $soakProgressPath) 'soak progress journal'
Assert-Equal ([string]$hdd.recovery_evidence_sha256) (Get-Sha256 $hddRecoveryPath) 'HDD recovery evidence'
Assert-Equal ([string]$antivirus.recovery_evidence_sha256) (Get-Sha256 $antivirusRecoveryPath) 'antivirus recovery evidence'
Assert-Equal ([string]$powerLoss.recovery_evidence_sha256) (Get-Sha256 $powerLossRecoveryPath) 'power-loss recovery evidence'

$copyMap = [ordered]@{
    'release-candidate.json' = $candidatePath
    'qualification-package.json' = $packagePath
    'binary/StarWorld.exe' = $exePath
    'binary/StarWorld.pck' = $pckPath
    'evidence/e4-h-review.json' = $reviewPath
    'evidence/hardware-minimum.json' = $minimumPath
    'evidence/hardware-recommended.json' = $recommendedPath
    'evidence/strict-soak.json' = $soakPath
    'evidence/fault-hdd.json' = $hddPath
    'evidence/fault-antivirus.json' = $antivirusPath
    'evidence/fault-power-loss.json' = $powerLossPath
    'support/hardware-minimum-journey-matrix.json' = $minimumMatrixPath
    'support/hardware-recommended-journey-matrix.json' = $recommendedMatrixPath
    'support/release-lifecycle-report.json' = $lifecyclePath
    'support/strict-soak-cycles.json' = $soakReportPath
    'support/strict-soak.progress.jsonl' = $soakProgressPath
    'support/fault-hdd-recovery.json' = $hddRecoveryPath
    'support/fault-antivirus-recovery.json' = $antivirusRecoveryPath
    'support/fault-power-loss-recovery.json' = $powerLossRecoveryPath
}
foreach ($entry in $copyMap.GetEnumerator()) { Copy-BundleFile -Source $entry.Value -RelativeDestination $entry.Key }

$fileRecords = [System.Collections.Generic.List[object]]::new()
$canonicalEntries = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in @($copyMap.Keys | Sort-Object)) {
    $path = Join-Path $outputRoot $relativePath
    $item = Get-Item -LiteralPath $path
    $hash = Get-Sha256 -Path $path
    $fileRecords.Add([ordered]@{ path = $relativePath; length_bytes = [long]$item.Length; sha256 = $hash })
    $canonicalEntries.Add("$relativePath|$hash|$([long]$item.Length)")
}
$packageHash = Get-Sha256 -Path (Join-Path $outputRoot 'qualification-package.json')
$canonical = @(
    'star-world-qualification-chain-bundle-v1',
    "candidate_id=$($candidate.candidate_id)",
    "package_sha256=$packageHash"
) + @($canonicalEntries)
$bundleId = Get-StringSha256 -Value ($canonical -join "`n")
$bundleManifest = [ordered]@{
    schema_version = 1
    bundle_id = $bundleId
    candidate_id = [string]$candidate.candidate_id
    package_id = [string]$package.package_id
    evidence_source = [string]$package.evidence_source
    reference_only = [bool]$package.reference_only
    qualification_package_sha256 = $packageHash
    created_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    files = @($fileRecords)
}
$bundleManifestPath = Join-Path $outputRoot 'bundle-manifest.json'
$tempPath = "$bundleManifestPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $bundleManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $bundleManifestPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

$bundleValidator = Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1'
if ($RequireReleaseGate) {
    & $bundleValidator -ProjectRoot $projectFullPath -BundleDirectory $outputRoot -RequireReleaseGate | Out-Null
} else {
    & $bundleValidator -ProjectRoot $projectFullPath -BundleDirectory $outputRoot | Out-Null
}
Write-Host "EXTERNAL QUALIFICATION CHAIN BUNDLE PASS | bundle=$bundleId | candidate=$($candidate.candidate_id) | source=$($package.evidence_source) | files=$($fileRecords.Count) | output=$outputRoot"
