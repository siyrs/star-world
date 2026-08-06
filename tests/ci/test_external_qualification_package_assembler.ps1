$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixtureRoot = Join-Path $root 'build\external-qualification-assembler-fixture'
Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

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
Set-Content -LiteralPath $exe -Value 'fixture executable bytes' -Encoding utf8
Set-Content -LiteralPath $pck -Value 'fixture pck bytes' -Encoding utf8
$exeHash = Get-Sha256 $exe
$pckHash = Get-Sha256 $pck
$commit = 'a' * 40
$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')

$reviewPath = Join-Path $fixtureRoot 'review.json'
Write-Json $reviewPath ([ordered]@{
    reviewer_id = 'fixture-reviewer'
    implementer_id = 'fixture-implementer'
    independent = $true
    signed_at_unix = 1000
    result = 'pass'
    blockers = @()
    checklist = [ordered]@{
        fresh_install = $true; new_world = $true; save_reload = $true
        five_profiles = $true; input_and_ui = $true; quit_and_restart = $true
    }
    build = [ordered]@{ commit_sha = $commit; executable_sha256 = $exeHash; pck_sha256 = $pckHash }
})

function New-HardwareRecord {
    param([string]$Tier, [string]$Fingerprint)
    return [ordered]@{
        schema_version = 1
        tier = $Tier
        evidence_source = 'hosted_reference'
        reference_only = $true
        operator_id = "fixture-$Tier"
        operator_attested = $false
        machine_fingerprint_sha256 = $Fingerprint
        cpu = 'fixture cpu'
        gpu = 'fixture gpu'
        ram_gib = 16
        os = 'fixture os'
        storage = [ordered]@{ drive_type = 'ssd'; model = 'fixture storage' }
        profiles = @($profiles)
        started_at_unix = 1000
        completed_at_unix = 1100
        result = 'pass'
        build = [ordered]@{ executable_sha256 = $exeHash; pck_sha256 = $pckHash }
    }
}
$minimumPath = Join-Path $fixtureRoot 'hardware-minimum.json'
$recommendedPath = Join-Path $fixtureRoot 'hardware-recommended.json'
Write-Json $minimumPath (New-HardwareRecord 'minimum' ('b' * 64))
Write-Json $recommendedPath (New-HardwareRecord 'recommended' ('c' * 64))

$soakPath = Join-Path $fixtureRoot 'strict-soak.json'
Write-Json $soakPath ([ordered]@{
    schema_version = 1
    evidence_source = 'hosted_reference'
    reference_only = $true
    target_hardware = $false
    operator_id = 'fixture-soak'
    operator_attested = $false
    requested_seconds = 600
    elapsed_seconds = 600
    clean_exit = $true
    crash_count = 0
    timed_out = $false
    result = 'pass'
    executable_sha256 = $exeHash
    pck_sha256 = $pckHash
    lifecycle_report_sha256 = '3' * 64
    soak_report_sha256 = '4' * 64
})

function New-FaultRecord {
    param([string]$Type)
    return [ordered]@{
        schema_version = 1
        type = $Type
        phase = 'completed'
        evidence_source = 'hosted_reference'
        reference_only = $true
        operator_id = 'fixture-fault-operator'
        attested_real = $false
        prepared_at_unix = 1000
        completed_at_unix = 1100
        world_id = 'fixture-world'
        before_world_sha256 = 'd' * 64
        after_world_sha256 = 'e' * 64
        recovery_evidence_sha256 = 'f' * 64
        interruption_observed = $true
        recovery_verified = $true
        world_integrity_verified = $true
        result = 'pass'
    }
}
$hddPath = Join-Path $fixtureRoot 'fault-hdd.json'
$antivirusPath = Join-Path $fixtureRoot 'fault-antivirus.json'
$powerLossPath = Join-Path $fixtureRoot 'fault-power-loss.json'
Write-Json $hddPath (New-FaultRecord 'hdd')
Write-Json $antivirusPath (New-FaultRecord 'antivirus')
Write-Json $powerLossPath (New-FaultRecord 'power_loss')

$outputPath = Join-Path $fixtureRoot 'qualification-package.json'
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
    -OutputPath $outputPath `
    -ReferenceOnly

$resultText = (& (Join-Path $PSScriptRoot 'validate_external_qualification_package.ps1') -PackagePath $outputPath | Out-String).Trim()
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.contract_valid) { throw "Assembled reference package is invalid: $($result.errors -join '; ')" }
if ([bool]$result.release_gate_passed -or [string]$result.status -ne 'reference_only') {
    throw "Assembled fixture incorrectly qualified: $($result.status)"
}
$package = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
if ([string]$package.build.executable_sha256 -ne $exeHash -or [string]$package.build.pck_sha256 -ne $pckHash) {
    throw 'Assembler did not bind the final executable and PCK digests.'
}
if ([string]$package.build.commit_sha -ne $commit) { throw 'Assembler did not bind the requested commit.' }
Write-Host "EXTERNAL QUALIFICATION ASSEMBLER PASS | source=reference_only | gate=false | package=$outputPath"
