param(
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][string]$ExperienceReviewPath,
    [Parameter(Mandatory = $true)][string]$MinimumHardwarePath,
    [Parameter(Mandatory = $true)][string]$RecommendedHardwarePath,
    [Parameter(Mandatory = $true)][string]$StrictSoakPath,
    [Parameter(Mandatory = $true)][string]$HddFaultPath,
    [Parameter(Mandatory = $true)][string]$AntivirusFaultPath,
    [Parameter(Mandatory = $true)][string]$PowerLossFaultPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$PackageId = '',
    [string]$ReleaseOwnerId = '',
    [switch]$ReleaseOwnerApproved,
    [switch]$AllArtifactsAttached,
    [switch]$ReferenceOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($CommitSha -cnotmatch '^[0-9a-f]{40}$') { throw 'CommitSha must be a 40-character lowercase hexadecimal SHA.' }
if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Version must not be blank.' }
if (-not $ReferenceOnly) {
    if ([string]::IsNullOrWhiteSpace($ReleaseOwnerId)) { throw 'ReleaseOwnerId is required for a real package.' }
    if (-not $ReleaseOwnerApproved -or -not $AllArtifactsAttached) {
        throw 'A real package requires -ReleaseOwnerApproved and -AllArtifactsAttached.'
    }
    if ($env:GITHUB_ACTIONS -eq 'true') {
        throw 'GitHub-hosted runners cannot assemble a target-hardware release-acceptance package.'
    }
}

function Resolve-RequiredFile {
    param([string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Required file not found: $resolved" }
    return $resolved
}
function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Description)
    if ($Expected -ne $Actual) { throw "$Description mismatch: expected $Expected, got $Actual" }
}

$exePath = Resolve-RequiredFile $ReleaseExecutable
$pckPath = Resolve-RequiredFile $ReleasePck
$reviewPath = Resolve-RequiredFile $ExperienceReviewPath
$minimumPath = Resolve-RequiredFile $MinimumHardwarePath
$recommendedPath = Resolve-RequiredFile $RecommendedHardwarePath
$soakPath = Resolve-RequiredFile $StrictSoakPath
$hddPath = Resolve-RequiredFile $HddFaultPath
$antivirusPath = Resolve-RequiredFile $AntivirusFaultPath
$powerLossPath = Resolve-RequiredFile $PowerLossFaultPath
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)

$exeHash = Get-Sha256 $exePath
$pckHash = Get-Sha256 $pckPath
$review = Read-JsonFile $reviewPath
$minimum = Read-JsonFile $minimumPath
$recommended = Read-JsonFile $recommendedPath
$soak = Read-JsonFile $soakPath
$hdd = Read-JsonFile $hddPath
$antivirus = Read-JsonFile $antivirusPath
$powerLoss = Read-JsonFile $powerLossPath
$source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }

Assert-Equal $CommitSha ([string]$review.build.commit_sha) 'E4-H review commit'
Assert-Equal $exeHash ([string]$review.build.executable_sha256) 'E4-H review executable'
Assert-Equal $pckHash ([string]$review.build.pck_sha256) 'E4-H review PCK'
foreach ($hardware in @($minimum, $recommended)) {
    Assert-Equal $source ([string]$hardware.evidence_source) "hardware $($hardware.tier) evidence source"
    Assert-Equal ([string][bool]$ReferenceOnly) ([string][bool]$hardware.reference_only) "hardware $($hardware.tier) reference flag"
    Assert-Equal $exeHash ([string]$hardware.build.executable_sha256) "hardware $($hardware.tier) executable"
    Assert-Equal $pckHash ([string]$hardware.build.pck_sha256) "hardware $($hardware.tier) PCK"
}
Assert-Equal $source ([string]$soak.evidence_source) 'strict soak evidence source'
Assert-Equal ([string][bool]$ReferenceOnly) ([string][bool]$soak.reference_only) 'strict soak reference flag'
Assert-Equal $exeHash ([string]$soak.executable_sha256) 'strict soak executable'
Assert-Equal $pckHash ([string]$soak.pck_sha256) 'strict soak PCK'

if ([string]$minimum.tier -ne 'minimum') { throw 'MinimumHardwarePath does not contain the minimum tier.' }
if ([string]$recommended.tier -ne 'recommended') { throw 'RecommendedHardwarePath does not contain the recommended tier.' }
foreach ($pair in @(
    @{ Expected = 'hdd'; Record = $hdd },
    @{ Expected = 'antivirus'; Record = $antivirus },
    @{ Expected = 'power_loss'; Record = $powerLoss }
)) {
    $record = $pair.Record
    if ([string]$record.type -ne [string]$pair.Expected) {
        throw "Fault record mismatch: expected $($pair.Expected), got $($record.type)"
    }
    if ([string]$record.phase -ne 'completed' -or [string]$record.result -ne 'pass') {
        throw "Fault record is not complete: $($pair.Expected)"
    }
    Assert-Equal $source ([string]$record.evidence_source) "fault $($pair.Expected) evidence source"
    Assert-Equal ([string][bool]$ReferenceOnly) ([string][bool]$record.reference_only) "fault $($pair.Expected) reference flag"
    Assert-Equal $exeHash ([string]$record.build.executable_sha256) "fault $($pair.Expected) executable"
    Assert-Equal $pckHash ([string]$record.build.pck_sha256) "fault $($pair.Expected) PCK"
}
$faultOperator = ([string]$hdd.operator_id).Trim()
if ([string]::IsNullOrWhiteSpace($faultOperator)) { throw 'Fault-lab operator identity must not be blank.' }
if ($faultOperator -ne ([string]$antivirus.operator_id).Trim() -or $faultOperator -ne ([string]$powerLoss.operator_id).Trim()) {
    throw 'All fault-lab records must use one non-empty operator identity.'
}

if ([string]::IsNullOrWhiteSpace($PackageId)) {
    $PackageId = "star-world-$Version-$($CommitSha.Substring(0, 12))"
}
$package = [ordered]@{
    schema_version = 2
    package_id = $PackageId.Trim()
    fixture_mode = $false
    reference_only = [bool]$ReferenceOnly
    evidence_source = $source
    hosted_runner = [bool]($env:GITHUB_ACTIONS -eq 'true')
    build = [ordered]@{
        commit_sha = $CommitSha
        version = $Version.Trim()
        executable_sha256 = $exeHash
        pck_sha256 = $pckHash
    }
    experiential_review = [ordered]@{
        reviewer_id = [string]$review.reviewer_id
        implementer_id = [string]$review.implementer_id
        independent = [bool]$review.independent
        signed_at_unix = [long]$review.signed_at_unix
        result = [string]$review.result
        blockers = @($review.blockers)
        checklist = $review.checklist
        build = $review.build
        evidence_sha256 = Get-Sha256 $reviewPath
    }
    hardware_qualification = @($minimum, $recommended)
    strict_soak = $soak
    fault_lab = [ordered]@{
        operator_id = $faultOperator
        result = 'pass'
        scenarios = @($hdd, $antivirus, $powerLoss)
    }
    findings = @()
    artifact_manifest = [ordered]@{
        experience_review_sha256 = Get-Sha256 $reviewPath
        minimum_hardware_sha256 = Get-Sha256 $minimumPath
        recommended_hardware_sha256 = Get-Sha256 $recommendedPath
        strict_soak_sha256 = Get-Sha256 $soakPath
        hdd_fault_sha256 = Get-Sha256 $hddPath
        antivirus_fault_sha256 = Get-Sha256 $antivirusPath
        power_loss_fault_sha256 = Get-Sha256 $powerLossPath
    }
}
if (-not $ReferenceOnly) {
    $package.release_owner_attestation = [ordered]@{
        owner_id = $ReleaseOwnerId.Trim()
        signed_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        all_artifacts_attached = [bool]$AllArtifactsAttached
        approved_for_release = [bool]$ReleaseOwnerApproved
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$package | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $outputFullPath -Encoding utf8
$validator = Join-Path $PSScriptRoot 'validate_external_qualification_package.ps1'
if ($ReferenceOnly) {
    & $validator -PackagePath $outputFullPath
} else {
    & $validator -PackagePath $outputFullPath -RequireReleaseGate
}
Write-Host "EXTERNAL QUALIFICATION PACKAGE ASSEMBLED | schema=2 | source=$source | commit=$CommitSha | executable=$exeHash | pck=$pckHash | output=$outputFullPath"
