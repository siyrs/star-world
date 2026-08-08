$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'qualification_policy_helpers.ps1')
$policyContext = Get-ReleaseQualificationPolicyContext -ProjectRoot $root
$soakPolicy = New-StrictSoakPolicySnapshot -PolicyContext $policyContext
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
    $tierPolicy = New-HardwareQualificationPolicySnapshot -PolicyContext $policyContext -Tier $Tier
    $metricProfiles = foreach ($profile in $profiles) {
        [pscustomobject][ordered]@{
            profile_id = $profile
            avg_fps = [double]$tierPolicy.metrics.avg_fps_min + 10.0
            one_percent_low_fps = [double]$tierPolicy.metrics.one_percent_low_fps_min + 5.0
            frame_ms_p95 = [double]$tierPolicy.metrics.frame_ms_p95_max * 0.8
            frame_ms_p99 = [double]$tierPolicy.metrics.frame_ms_p99_max * 0.8
            frame_budget_miss_30fps_percent = [double]$tierPolicy.metrics.frame_budget_miss_30fps_percent_max * 0.5
            world_start_ms = [double]$tierPolicy.metrics.profile_load_ms_max * 0.8
            working_set_p95_mib = [double]$tierPolicy.metrics.working_set_p95_mib_max * 0.8
        }
    }
    return [ordered]@{
        schema_version = 2
        exact_final_package_reused = $true
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
        qualification_policy = $tierPolicy
        metric_evaluation = Get-HardwareMetricEvaluation -ProfileRecords @($metricProfiles) -MetricPolicy $tierPolicy.metrics -RequiredProfiles $profiles
        build = [ordered]@{ executable_sha256 = $exeHash; pck_sha256 = $pckHash }
    }
}
$minimumPath = Join-Path $fixtureRoot 'hardware-minimum.json'
$recommendedPath = Join-Path $fixtureRoot 'hardware-recommended.json'
Write-Json $minimumPath (New-HardwareRecord 'minimum' ('b' * 64))
Write-Json $recommendedPath (New-HardwareRecord 'recommended' ('c' * 64))

$soakPath = Join-Path $fixtureRoot 'strict-soak.json'
Write-Json $soakPath ([ordered]@{
    schema_version = 2
    exact_final_package_reused = $true
    evidence_source = 'hosted_reference'
    reference_only = $true
    target_hardware = $false
    operator_id = 'fixture-soak'
    operator_attested = $false
    requested_seconds = 600
    elapsed_seconds = 600
    cycle_count = 5
    completed_routes = 5
    profile_count = 5
    profiles = @($profiles)
    qualification_policy = $soakPolicy
    fatal_diagnostics_count = 0
    post_spawn_transport_count = 0
    player_transform_writes = 0
    working_set_first_p95_mib = 100.0
    working_set_last_p95_mib = 110.0
    memory_growth_percent = 10.0
    authoritative_cycle_lifecycle_count = 5
    lifecycle = [ordered]@{
        schema_version = 1; release_build = $true; engine_version = '4.7.fixture'; captured_unix = 1200
        first_world_profile_id = 'star_continent'; first_world_id = 'fixture-world'
        first_save_success = $true; first_save_world_id = 'fixture-world'; first_save_bytes = 1024
        world_save_identity_matches = $true; timings_monotonic = $true
        quit_attempt_count = 1; quit_source = 'release_smoke'; quit_prepared = $true
        termination_reason = 'prepared_quit'; service_hub_request_count = 1
        service_hub_success_count = 1; service_hub_failure_count = 0
        game_request_count = 1; game_success_count = 1; game_failure_count = 0
        authoritative_clean_quit = $true
    }
    clean_exit = $true
    crash_count = 0
    timed_out = $false
    result = 'pass'
    executable_sha256 = $exeHash
    pck_sha256 = $pckHash
    lifecycle_report_sha256 = '3' * 64
    soak_report_sha256 = '4' * 64
    progress_journal_sha256 = '5' * 64
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
        build = [ordered]@{ executable_sha256 = $exeHash; pck_sha256 = $pckHash }
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

$validator = Join-Path $PSScriptRoot 'validate_external_qualification_package.ps1'
$resultText = (& $validator -PackagePath $outputPath | Out-String).Trim()
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.contract_valid) { throw "Assembled reference package is invalid: $($result.errors -join '; ')" }
if ([bool]$result.release_gate_passed -or [string]$result.status -ne 'reference_only') {
    throw "Assembled fixture incorrectly qualified: $($result.status)"
}
$package = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
if ([int]$package.schema_version -ne 2) { throw 'Assembler did not emit schema version 2.' }
if ([string]$package.build.executable_sha256 -ne $exeHash -or [string]$package.build.pck_sha256 -ne $pckHash) {
    throw 'Assembler did not bind the final executable and PCK digests.'
}
if ([string]$package.build.commit_sha -ne $commit) { throw 'Assembler did not bind the requested commit.' }
if ([string]$package.experiential_review.build.commit_sha -ne $commit) { throw 'Assembler omitted the E4-H build binding.' }
foreach ($scenario in @($package.fault_lab.scenarios)) {
    if ([string]$scenario.build.executable_sha256 -ne $exeHash -or [string]$scenario.build.pck_sha256 -ne $pckHash) {
        throw "Assembler omitted the $($scenario.type) fault build binding."
    }
}

$tamperedPath = Join-Path $fixtureRoot 'qualification-package-tampered.json'
$tampered = $package | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
$tampered.hardware_qualification[0].build.executable_sha256 = 'f' * 64
Write-Json $tamperedPath $tampered
$rejected = $false
try {
    & $validator -PackagePath $tamperedPath | Out-Null
} catch {
    $rejected = $_.Exception.Message -match 'hardware minimum executable'
}
if (-not $rejected) { throw 'Standalone validator accepted a package with a rebound hardware executable.' }

$tamperedMetricPath = Join-Path $fixtureRoot 'qualification-package-tampered-metric.json'
$tamperedMetric = $package | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
$tamperedMetric.hardware_qualification[1].metric_evaluation.profiles[0].avg_fps = 0.0
Write-Json $tamperedMetricPath $tamperedMetric
$metricRejected = $false
try {
    & $validator -PackagePath $tamperedMetricPath | Out-Null
} catch {
    $metricRejected = $_.Exception.Message -match 'hardware metric threshold failed'
}
if (-not $metricRejected) { throw 'Standalone validator accepted forged passing performance metrics.' }

$tamperedLifecyclePath = Join-Path $fixtureRoot 'qualification-package-tampered-lifecycle.json'
$tamperedLifecycle = $package | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
$tamperedLifecycle.strict_soak.lifecycle.termination_reason = 'scene_exit_without_prepared_quit'
$tamperedLifecycle.strict_soak.lifecycle.quit_prepared = $false
$tamperedLifecycle.strict_soak.lifecycle.authoritative_clean_quit = $false
Write-Json $tamperedLifecyclePath $tamperedLifecycle
$lifecycleRejected = $false
try {
    & $validator -PackagePath $tamperedLifecyclePath | Out-Null
} catch {
    $lifecycleRejected = $_.Exception.Message -match 'termination_reason must equal prepared_quit'
}
if (-not $lifecycleRejected) { throw 'Standalone validator accepted a non-authoritative lifecycle report.' }

Write-Host "EXTERNAL QUALIFICATION ASSEMBLER PASS | schema=2 | source=reference_only | gate=false | rebinding-rejected=true | metric-forgery-rejected=true | dirty-lifecycle-rejected=true | package=$outputPath"
