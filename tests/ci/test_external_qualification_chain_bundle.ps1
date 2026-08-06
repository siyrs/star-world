$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixtureRoot = Join-Path $root 'build\external-qualification-assembler-fixture'
$bundleRoot = Join-Path $root 'build\release-candidate-chain-fixture'
$assemblerTest = Join-Path $PSScriptRoot 'test_external_qualification_package_assembler.ps1'
& $assemblerTest

function Write-Json {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$exe = Join-Path $fixtureRoot 'StarWorld.exe'
$pck = Join-Path $fixtureRoot 'StarWorld.pck'
$packagePath = Join-Path $fixtureRoot 'qualification-package.json'
$candidatePath = Join-Path $fixtureRoot 'release-candidate.json'
$reviewPath = Join-Path $fixtureRoot 'review.json'
$minimumPath = Join-Path $fixtureRoot 'hardware-minimum.json'
$recommendedPath = Join-Path $fixtureRoot 'hardware-recommended.json'
$soakPath = Join-Path $fixtureRoot 'strict-soak.json'
$hddPath = Join-Path $fixtureRoot 'fault-hdd.json'
$antivirusPath = Join-Path $fixtureRoot 'fault-antivirus.json'
$powerLossPath = Join-Path $fixtureRoot 'fault-power-loss.json'
$minimumMatrixPath = Join-Path $fixtureRoot 'hardware-minimum-journey-matrix.json'
$recommendedMatrixPath = Join-Path $fixtureRoot 'hardware-recommended-journey-matrix.json'
$lifecyclePath = Join-Path $fixtureRoot 'release-lifecycle-report.json'
$soakReportPath = Join-Path $fixtureRoot 'strict-soak-cycles.json'
$soakProgressPath = Join-Path $fixtureRoot 'strict-soak.progress.jsonl'
$hddRecoveryPath = Join-Path $fixtureRoot 'fault-hdd-recovery.json'
$antivirusRecoveryPath = Join-Path $fixtureRoot 'fault-antivirus-recovery.json'
$powerLossRecoveryPath = Join-Path $fixtureRoot 'fault-power-loss-recovery.json'
$commit = 'a' * 40

Write-Json $minimumMatrixPath ([ordered]@{ schema_version = 2; tier = 'minimum'; profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world') })
Write-Json $recommendedMatrixPath ([ordered]@{ schema_version = 2; tier = 'recommended'; profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world') })
Write-Json $lifecyclePath ([ordered]@{ schema_version = 1; clean_exit = $true; fixture = $true })
Write-Json $soakReportPath ([ordered]@{ schema_version = 1; cycle_count = 5; profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world') })
Set-Content -LiteralPath $soakProgressPath -Value '{"elapsed_seconds":120,"completed_cycles":5}' -Encoding utf8
Write-Json $hddRecoveryPath ([ordered]@{ schema_version = 1; scenario = 'hdd'; recovered = $true })
Write-Json $antivirusRecoveryPath ([ordered]@{ schema_version = 1; scenario = 'antivirus'; recovered = $true })
Write-Json $powerLossRecoveryPath ([ordered]@{ schema_version = 1; scenario = 'power_loss'; recovered = $true })

$minimum = Get-Content -LiteralPath $minimumPath -Raw | ConvertFrom-Json -Depth 100
$minimum | Add-Member -NotePropertyName journey_matrix -NotePropertyValue ([pscustomobject]@{
    path = 'hardware-minimum-journey-matrix.json'
    sha256 = Get-Sha256 $minimumMatrixPath
}) -Force
Write-Json $minimumPath $minimum
$recommended = Get-Content -LiteralPath $recommendedPath -Raw | ConvertFrom-Json -Depth 100
$recommended | Add-Member -NotePropertyName journey_matrix -NotePropertyValue ([pscustomobject]@{
    path = 'hardware-recommended-journey-matrix.json'
    sha256 = Get-Sha256 $recommendedMatrixPath
}) -Force
Write-Json $recommendedPath $recommended
$soak = Get-Content -LiteralPath $soakPath -Raw | ConvertFrom-Json -Depth 100
$soak.lifecycle_report_sha256 = Get-Sha256 $lifecyclePath
$soak.soak_report_sha256 = Get-Sha256 $soakReportPath
$soak | Add-Member -NotePropertyName progress_journal_sha256 -NotePropertyValue (Get-Sha256 $soakProgressPath) -Force
Write-Json $soakPath $soak
foreach ($pair in @(
    @{ Path = $hddPath; Recovery = $hddRecoveryPath },
    @{ Path = $antivirusPath; Recovery = $antivirusRecoveryPath },
    @{ Path = $powerLossPath; Recovery = $powerLossRecoveryPath }
)) {
    $fault = Get-Content -LiteralPath $pair.Path -Raw | ConvertFrom-Json -Depth 100
    $fault.recovery_evidence_sha256 = Get-Sha256 $pair.Recovery
    Write-Json $pair.Path $fault
}

& (Join-Path $PSScriptRoot 'new_external_qualification_package.ps1') `
    -CommitSha $commit `
    -Version 'fixture-version' `
    -ReleaseExecutable $exe `
    -ReleasePck $pck `
    -ExperienceReviewPath $reviewPath `
    -MinimumHardwarePath $minimumPath `
    -RecommendedHardwarePath $recommendedPath `
    -StrictSoakPath $soakPath `
    -HddFaultPath $hddPath `
    -AntivirusFaultPath $antivirusPath `
    -PowerLossFaultPath $powerLossPath `
    -OutputPath $packagePath `
    -ReferenceOnly

& (Join-Path $PSScriptRoot 'new_release_candidate_manifest.ps1') `
    -ProjectRoot $root `
    -CommitSha $commit `
    -Version 'fixture-version' `
    -ReleaseExecutable $exe `
    -ReleasePck $pck `
    -OutputPath $candidatePath

function New-TestBundle {
    Remove-Item -LiteralPath $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'new_external_qualification_chain_bundle.ps1') `
        -ProjectRoot $root `
        -CandidateManifestPath $candidatePath `
        -QualificationPackagePath $packagePath `
        -ReleaseExecutable $exe `
        -ReleasePck $pck `
        -ExperienceReviewPath $reviewPath `
        -MinimumHardwarePath $minimumPath `
        -RecommendedHardwarePath $recommendedPath `
        -StrictSoakPath $soakPath `
        -HddFaultPath $hddPath `
        -AntivirusFaultPath $antivirusPath `
        -PowerLossFaultPath $powerLossPath `
        -MinimumJourneyMatrixPath $minimumMatrixPath `
        -RecommendedJourneyMatrixPath $recommendedMatrixPath `
        -LifecycleReportPath $lifecyclePath `
        -StrictSoakReportPath $soakReportPath `
        -StrictSoakProgressPath $soakProgressPath `
        -HddRecoveryEvidencePath $hddRecoveryPath `
        -AntivirusRecoveryEvidencePath $antivirusRecoveryPath `
        -PowerLossRecoveryEvidencePath $powerLossRecoveryPath `
        -OutputDirectory $bundleRoot
}
function Assert-Rejected {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Expected, [Parameter(Mandatory = $true)][string]$Name)
    $rejected = $false
    try { & $Action } catch {
        $rejected = $_.Exception.Message.Contains($Expected)
        if (-not $rejected) { throw "$Name failed for the wrong reason: $($_.Exception.Message)" }
    }
    if (-not $rejected) { throw "$Name was not rejected." }
}

New-TestBundle
$resultText = (& (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-String).Trim()
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.valid -or [int]$result.file_count -ne 19) { throw 'Fresh qualification chain bundle did not validate.' }
if ([bool]$result.release_gate_passed) { throw 'Reference chain bundle incorrectly closed the release gate.' }

Add-Content -LiteralPath (Join-Path $bundleRoot 'evidence\hardware-minimum.json') -Value 'tampered'
Assert-Rejected -Name 'Evidence tamper' -Expected 'Bundle file hash mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
Add-Content -LiteralPath (Join-Path $bundleRoot 'support\release-lifecycle-report.json') -Value 'tampered support'
Assert-Rejected -Name 'Supporting evidence tamper' -Expected 'Bundle file hash mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
$candidateCopyPath = Join-Path $bundleRoot 'release-candidate.json'
$candidate = Get-Content -LiteralPath $candidateCopyPath -Raw | ConvertFrom-Json -Depth 30
$candidate.candidate_id = 'f' * 64
Write-Json $candidateCopyPath $candidate
$manifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 30
$candidateEntry = @($manifest.files | Where-Object { [string]$_.path -eq 'release-candidate.json' })[0]
$candidateEntry.sha256 = Get-Sha256 $candidateCopyPath
$candidateEntry.length_bytes = (Get-Item -LiteralPath $candidateCopyPath).Length
Write-Json $manifestPath $manifest
Assert-Rejected -Name 'Candidate identity tamper' -Expected 'candidate_id does not match' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
Set-Content -LiteralPath (Join-Path $bundleRoot 'unexpected.txt') -Value 'not part of the evidence chain' -Encoding utf8
Assert-Rejected -Name 'Unexpected file injection' -Expected 'missing or unexpected files' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
$hiddenPath = Join-Path $bundleRoot 'hidden-unexpected.txt'
Set-Content -LiteralPath $hiddenPath -Value 'hidden file must still be enumerated' -Encoding utf8
$hiddenItem = Get-Item -LiteralPath $hiddenPath
$hiddenItem.Attributes = $hiddenItem.Attributes -bor [System.IO.FileAttributes]::Hidden
Assert-Rejected -Name 'Hidden unexpected file injection' -Expected 'missing or unexpected files' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'bundle-manifest.json') -Raw | ConvertFrom-Json -Depth 30
$manifest.files[0].path = '../escape.json'
Write-Json (Join-Path $bundleRoot 'bundle-manifest.json') $manifest
Assert-Rejected -Name 'Bundle path traversal' -Expected 'Unsafe bundle path' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
Write-Host "RELEASE CANDIDATE CHAIN BUNDLE PASS | candidate=$($result.candidate_id) | bundle=$($result.bundle_id) | files=19 | tamper_cases=6 | output=$bundleRoot"
