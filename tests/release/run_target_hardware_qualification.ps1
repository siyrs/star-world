param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDirectory = 'build/target-hardware-qualification',
    [ValidateSet('minimum', 'recommended')]
    [string]$QualificationTier = 'minimum',
    [string]$Operator = '',
    [int]$DurationSeconds = 7200,
    [int]$Seed = 112358,
    [switch]$HostedReference
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
if (-not $HostedReference -and [string]::IsNullOrWhiteSpace($Operator)) {
    throw '-Operator is required for target-hardware qualification.'
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$policyPath = Join-Path $ProjectRoot 'data\release_qualification.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw "Qualification policy missing: $policyPath" }
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$soakPolicy = $policy.soak
if (-not $HostedReference -and $DurationSeconds -lt [int]$soakPolicy.duration_seconds_min) {
    throw "Target-hardware evidence requires at least $($soakPolicy.duration_seconds_min) seconds."
}
if ($HostedReference) { $DurationSeconds = [math]::Max(120, $DurationSeconds) }

$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputDirectory))
$cyclesRoot = Join-Path $outputRoot 'cycles'
$summaryPath = Join-Path $outputRoot 'qualification-summary.json'
New-Item -ItemType Directory -Force -Path $cyclesRoot | Out-Null
$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$tierPolicy = $policy.tiers.$QualificationTier
$metricPolicy = $tierPolicy.metrics

function Get-SafeCimValue {
    param([string]$ClassName, [string]$PropertyName)
    try {
        return @(
            Get-CimInstance $ClassName -ErrorAction Stop |
                ForEach-Object { $_.$PropertyName } |
                Where-Object { $_ -ne $null } |
                ForEach-Object { [string]$_ }
        )
    } catch { return @() }
}

function Get-HardwareSnapshot {
    $memory = 0L
    try { $memory = [long](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1).TotalPhysicalMemory } catch {}
    [ordered]@{
        captured_at = (Get-Date).ToString('o')
        os = Get-SafeCimValue Win32_OperatingSystem Caption
        os_version = Get-SafeCimValue Win32_OperatingSystem Version
        cpu = Get-SafeCimValue Win32_Processor Name
        cpu_cores = Get-SafeCimValue Win32_Processor NumberOfCores
        gpu = Get-SafeCimValue Win32_VideoController Name
        gpu_driver = Get-SafeCimValue Win32_VideoController DriverVersion
        physical_memory_gib = if ($memory -gt 0) { [math]::Round($memory / 1GB, 1) } else { 0 }
        github_actions = [bool]($env:GITHUB_ACTIONS -eq 'true')
        runner_name = [string]$env:RUNNER_NAME
    }
}

$records = [System.Collections.Generic.List[object]]::new()
$startedAt = Get-Date
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$cycle = 0
$executable = ''
while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds -or $records.Count -lt $profiles.Count) {
    $profile = $profiles[$cycle % $profiles.Count]
    $cycleOutput = Join-Path $cyclesRoot ('{0:D3}-{1}' -f $cycle, $profile)
    New-Item -ItemType Directory -Force -Path $cycleOutput | Out-Null
    $invoke = @{
        OutputDirectory = $cycleOutput
        RunnerTimeoutMilliseconds = 1200000
        ProfileId = $profile
        Seed = ($Seed + $cycle)
        RouteProbe = $true
    }
    if ($cycle -eq 0) {
        $invoke['Godot'] = $Godot
    } else {
        $invoke['SkipExport'] = $true
        $invoke['ExecutablePath'] = $executable
    }
    & (Join-Path $PSScriptRoot 'run_windows_export_smoke.ps1') @invoke
    if ($cycle -eq 0) { $executable = Join-Path $cycleOutput 'StarWorld.exe' }

    $report = Get-Content -LiteralPath (Join-Path $cycleOutput 'release-smoke.json') -Raw | ConvertFrom-Json
    $memory = Get-Content -LiteralPath (Join-Path $cycleOutput 'release-smoke.memory.json') -Raw | ConvertFrom-Json
    $frame = $report.soak.frame_metrics
    $record = [pscustomobject][ordered]@{
        cycle = $cycle
        profile_id = $profile
        seed = [int]$report.seed
        world_start_ms = [int]$report.world_start_ms
        avg_fps = [double]$frame.avg_fps
        one_percent_low_fps = [double]$frame.one_percent_low_fps
        frame_ms_p95 = [double]$frame.frame_ms_p95
        frame_ms_p99 = [double]$frame.frame_ms_p99
        frame_budget_miss_30fps_percent = [double]$frame.frame_budget_miss_30fps_percent
        working_set_p95_mib = [double]$memory.working_set_mib.p95_mib
        private_bytes_p95_mib = [double]$memory.private_bytes_mib.p95_mib
        successful_steps = [int]$report.route.successful_steps
        displacement = [double]$report.route.horizontal_displacement
        unique_chunks = [int]$report.route.unique_chunks
        post_spawn_transport = [bool]$report.route.transport_after_spawn
        player_transform_writes = [int]$report.route.player_transform_writes
        elapsed_seconds = [int]$stopwatch.Elapsed.TotalSeconds
        evidence_directory = [System.IO.Path]::GetRelativePath($outputRoot, $cycleOutput).Replace('\', '/')
    }
    $records.Add($record)

    if (-not $HostedReference) {
        if ($record.avg_fps -lt [double]$metricPolicy.avg_fps_min) { throw "${profile}: avg FPS below $($metricPolicy.avg_fps_min)" }
        if ($record.one_percent_low_fps -lt [double]$metricPolicy.one_percent_low_fps_min) { throw "${profile}: 1% low below $($metricPolicy.one_percent_low_fps_min)" }
        if ($record.frame_ms_p95 -gt [double]$metricPolicy.frame_ms_p95_max) { throw "${profile}: p95 frame time above $($metricPolicy.frame_ms_p95_max)ms" }
        if ($record.frame_ms_p99 -gt [double]$metricPolicy.frame_ms_p99_max) { throw "${profile}: p99 frame time above $($metricPolicy.frame_ms_p99_max)ms" }
        if ($record.frame_budget_miss_30fps_percent -gt [double]$metricPolicy.frame_budget_miss_30fps_percent_max) { throw "${profile}: 30 FPS budget misses exceed policy" }
        if ($record.world_start_ms -gt [int]$metricPolicy.profile_load_ms_max) { throw "${profile}: load time exceeds policy" }
        if ($record.working_set_p95_mib -gt [double]$metricPolicy.working_set_p95_mib_max) { throw "${profile}: working set exceeds policy" }
    }
    if ($record.post_spawn_transport -or $record.player_transform_writes -ne 0) {
        throw "${profile}: forbidden post-spawn transport detected"
    }
    $cycle += 1
}
$stopwatch.Stop()

$profileIds = @($records | Select-Object -ExpandProperty profile_id -Unique)
$ws = @($records | Select-Object -ExpandProperty working_set_p95_mib)
$growthPercent = 0.0
if ($ws.Count -ge 4 -and [double]$ws[0] -gt 0) {
    $growthPercent = [math]::Round((([double]$ws[-1] - [double]$ws[0]) / [double]$ws[0]) * 100.0, 2)
}
$qualificationOk = (
    $profileIds.Count -eq 5 -and
    $records.Count -ge $(if ($HostedReference) { 5 } else { [int]$soakPolicy.minimum_completed_routes }) -and
    $growthPercent -le [double]$soakPolicy.memory_growth_percent_max -and
    @($records | Where-Object { $_.post_spawn_transport -or $_.player_transform_writes -ne 0 }).Count -eq 0
)

$summary = [ordered]@{
    schema_version = 1
    evidence_class = if ($HostedReference) { 'hosted_ci_reference' } else { 'target_hardware_candidate' }
    qualification_tier = $QualificationTier
    operator = $Operator
    started_at = $startedAt.ToString('o')
    completed_at = (Get-Date).ToString('o')
    duration_seconds_target = $DurationSeconds
    duration_seconds_actual = [int]$stopwatch.Elapsed.TotalSeconds
    policy = $tierPolicy
    soak_policy = $soakPolicy
    hardware = Get-HardwareSnapshot
    profile_count = $profileIds.Count
    completed_routes = $records.Count
    memory_growth_percent = $growthPercent
    qualification_ok = $qualificationOk
    records = @($records)
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
if (-not $qualificationOk) { throw "Qualification contract failed. See $summaryPath" }

if ($HostedReference) {
    Write-Host "HOSTED QUALIFICATION MECHANISM PASS | duration=$([int]$stopwatch.Elapsed.TotalSeconds)s | routes=$($records.Count) | evidence=$summaryPath"
    Write-Host 'NOTE: this does not sign off minimum or recommended hardware.'
} else {
    Write-Host "TARGET HARDWARE CANDIDATE PASS | tier=$QualificationTier | duration=$([int]$stopwatch.Elapsed.TotalSeconds)s | routes=$($records.Count) | evidence=$summaryPath"
    Write-Host 'Release-owner review and approval of the captured hardware identity remains required.'
}
