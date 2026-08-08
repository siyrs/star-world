$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'qualification_policy_helpers.ps1')
$policyContext = Get-ReleaseQualificationPolicyContext -ProjectRoot $root
$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { throw $Message }
}

foreach ($tier in @('minimum', 'recommended')) {
    $snapshot = New-HardwareQualificationPolicySnapshot -PolicyContext $policyContext -Tier $tier
    Assert-True (@(Get-HardwarePolicySnapshotErrors -Snapshot $snapshot -Expected $snapshot).Count -eq 0) "$tier policy snapshot did not self-validate"
    $records = foreach ($profile in $profiles) {
        [pscustomobject][ordered]@{
            profile_id = $profile
            avg_fps = [double]$snapshot.metrics.avg_fps_min + 10.0
            one_percent_low_fps = [double]$snapshot.metrics.one_percent_low_fps_min + 5.0
            frame_ms_p95 = [double]$snapshot.metrics.frame_ms_p95_max * 0.8
            frame_ms_p99 = [double]$snapshot.metrics.frame_ms_p99_max * 0.8
            frame_budget_miss_30fps_percent = [double]$snapshot.metrics.frame_budget_miss_30fps_percent_max * 0.5
            world_start_ms = [double]$snapshot.metrics.profile_load_ms_max * 0.8
            working_set_p95_mib = [double]$snapshot.metrics.working_set_p95_mib_max * 0.8
        }
    }
    $passing = Get-HardwareMetricEvaluation -ProfileRecords @($records) -MetricPolicy $snapshot.metrics -RequiredProfiles $profiles
    Assert-True ([bool]$passing.passed -and [int]$passing.assertion_count -eq 35) "$tier passing metrics did not produce 35 passing assertions"

    foreach ($metric in @(
        @{ Name = 'avg_fps'; Value = 0.0 },
        @{ Name = 'one_percent_low_fps'; Value = 0.0 },
        @{ Name = 'frame_ms_p95'; Value = 100000.0 },
        @{ Name = 'frame_ms_p99'; Value = 100000.0 },
        @{ Name = 'frame_budget_miss_30fps_percent'; Value = 100.0 },
        @{ Name = 'world_start_ms'; Value = 100000.0 },
        @{ Name = 'working_set_p95_mib'; Value = 100000.0 }
    )) {
        $mutated = @($records | ForEach-Object { $_ | Select-Object * })
        $mutated[0].($metric.Name) = [double]$metric.Value
        $failed = Get-HardwareMetricEvaluation -ProfileRecords $mutated -MetricPolicy $snapshot.metrics -RequiredProfiles $profiles
        Assert-True (-not [bool]$failed.passed) "$tier policy accepted a failing $($metric.Name) value"
    }

    $forgedSnapshot = $snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $forgedSnapshot.sha256 = 'f' * 64
    Assert-True (@(Get-HardwarePolicySnapshotErrors -Snapshot $forgedSnapshot -Expected $snapshot).Count -gt 0) "$tier policy hash forgery was accepted"
}

$soakSnapshot = New-StrictSoakPolicySnapshot -PolicyContext $policyContext
$forgedSoakSnapshot = $soakSnapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
$forgedSoakSnapshot.minimum_completed_routes = 1
Assert-True (@(Get-StrictSoakPolicySnapshotErrors -Snapshot $forgedSoakSnapshot -Expected $soakSnapshot).Count -gt 0) 'Loosened strict-soak route policy was accepted'

$fixtureRoot = Join-Path $root 'build\qualification-policy-helper-fixture'
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$lifecyclePath = Join-Path $fixtureRoot 'release-lifecycle-report.json'
$lifecycle = [ordered]@{
    schema_version = 1
    captured_at = 'fixture'
    captured_unix = 1000
    engine_version = '4.7.fixture'
    release_build = $true
    timings = [ordered]@{
        service_ready_milliseconds = 1.0
        scene_ready_milliseconds = 2.0
        first_world_playable_milliseconds = 3.0
        first_save_milliseconds = 4.0
        quit_requested_milliseconds = 5.0
        quit_completed_milliseconds = 6.0
    }
    first_world = [ordered]@{ profile_id = 'star_continent'; seed = 1; world_id = 'fixture-world' }
    first_save = [ordered]@{ success = $true; bytes = 1024; world_id = 'fixture-world' }
    quit = [ordered]@{
        attempt_count = 1
        source = 'release_smoke'
        prepared = $true
        termination_reason = 'prepared_quit'
        service_hub = [ordered]@{ request_count = 1; success_count = 1; failure_count = 0 }
        game = [ordered]@{ request_count = 1; success_count = 1; failure_count = 0 }
    }
}
$lifecycle | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lifecyclePath -Encoding utf8
$validLifecycle = Get-AuthoritativeLifecycleEvidence -Path $lifecyclePath
Assert-True ([bool]$validLifecycle.Valid -and [bool]$validLifecycle.Summary.authoritative_clean_quit) 'Prepared lifecycle fixture was rejected'

$lifecycle.quit.prepared = $false
$lifecycle.quit.termination_reason = 'scene_exit_without_prepared_quit'
$lifecycle | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lifecyclePath -Encoding utf8
$dirtyLifecycle = Get-AuthoritativeLifecycleEvidence -Path $lifecyclePath
Assert-True (-not [bool]$dirtyLifecycle.Valid -and (($dirtyLifecycle.Errors -join ' | ') -match 'prepared_quit')) 'Dirty lifecycle fixture was accepted'

Write-Host "QUALIFICATION POLICY HELPERS PASS | checks=$checks | tiers=2 | assertions=70 | lifecycle=authoritative | dirty-lifecycle-rejected=true"
