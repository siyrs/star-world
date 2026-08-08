param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][string]$LifecycleReportPath,
    [Parameter(Mandatory = $true)][string]$OperatorId,
    [string]$OutputDirectory = 'build/external-qualification/strict-soak',
    [int]$Seed = 112358,
    [int]$SoakSeconds = 7200,
    [int]$CycleTimeoutMilliseconds = 1200000,
    [switch]$ReferenceOnly,
    [switch]$OperatorAttested
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($SoakSeconds -le 0) { throw 'SoakSeconds must be positive.' }
if (-not $ReferenceOnly -and -not $OperatorAttested) {
    throw 'Real target-hardware soak requires -OperatorAttested.'
}
if (-not $ReferenceOnly -and $env:GITHUB_ACTIONS -eq 'true') {
    throw 'GitHub-hosted runners cannot create target-hardware soak evidence.'
}
if ([string]::IsNullOrWhiteSpace($OperatorId)) { throw 'OperatorId must not be blank.' }

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$policyHelpers = Join-Path $PSScriptRoot 'qualification_policy_helpers.ps1'
if (-not (Test-Path -LiteralPath $policyHelpers -PathType Leaf)) {
    throw "Qualification policy helpers not found: $policyHelpers"
}
. $policyHelpers
$policyContext = Get-ReleaseQualificationPolicyContext -ProjectRoot $projectFullPath
$soakPolicy = New-StrictSoakPolicySnapshot -PolicyContext $policyContext
if (-not $ReferenceOnly -and $SoakSeconds -lt [int]$soakPolicy.duration_seconds_min) {
    throw "Commercial target-hardware soak cannot be shorter than $($soakPolicy.duration_seconds_min) seconds."
}
$exePath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckPath = [System.IO.Path]::GetFullPath($ReleasePck)
$lifecyclePath = [System.IO.Path]::GetFullPath($LifecycleReportPath)
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
foreach ($path in @($exePath, $pckPath, $lifecyclePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence file not found: $path" }
}
$expectedPckPath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $exePath) 'StarWorld.pck'))
if ($pckPath -ne $expectedPckPath) {
    throw 'ReleasePck must be StarWorld.pck beside the supplied final executable.'
}
$lifecycleEvidence = Get-AuthoritativeLifecycleEvidence -Path $lifecyclePath
if (-not [bool]$lifecycleEvidence.Valid) {
    throw "Lifecycle report does not prove a clean authoritative quit: $($lifecycleEvidence.Errors -join ' | ')"
}
$releaseRunner = Join-Path $projectFullPath 'tests/release/run_windows_export_smoke.ps1'
if (-not (Test-Path -LiteralPath $releaseRunner -PathType Leaf)) { throw "Release runner not found: $releaseRunner" }
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FatalDiagnosticCount {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    $patterns = @(
        'SCRIPT ERROR',
        'Parse Error',
        'ObjectDB instances were leaked',
        'Leaked instance:',
        'Resources still in use at exit',
        'Unhandled exception',
        'FATAL:'
    )
    $hits = @()
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hits += @(Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch)
        }
    }
    return @($hits).Count
}

$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$progressPath = Join-Path $outputRoot 'strict-soak.progress.jsonl'
$cyclesPath = Join-Path $outputRoot 'strict-soak-cycles.json'
$resultPath = Join-Path $outputRoot 'strict-soak.json'
Remove-Item -Force -ErrorAction SilentlyContinue $progressPath, $cyclesPath, $resultPath

$records = [System.Collections.Generic.List[object]]::new()
$minimumRoutes = if ($ReferenceOnly) { $profiles.Count } else { [int]$soakPolicy.minimum_completed_routes }
$exeHashBefore = Get-Sha256 -Path $exePath
$pckHashBefore = Get-Sha256 -Path $pckPath
$startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$cycle = 0
while ($watch.Elapsed.TotalSeconds -lt $SoakSeconds -or $cycle -lt $minimumRoutes) {
    $profile = $profiles[$cycle % $profiles.Count]
    $cycleOutput = Join-Path $outputRoot ("cycle-{0:D4}-{1}" -f $cycle, $profile)
    New-Item -ItemType Directory -Force -Path $cycleOutput | Out-Null
    $cycleStarted = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    & $releaseRunner `
        -SkipExport `
        -ExecutablePath $exePath `
        -OutputDirectory $cycleOutput `
        -ProfileId $profile `
        -Seed ($Seed + $cycle) `
        -RouteProbe `
        -RunnerTimeoutMilliseconds $CycleTimeoutMilliseconds

    $reportPath = Join-Path $cycleOutput 'release-smoke.json'
    $memoryPath = Join-Path $cycleOutput 'release-smoke.memory.json'
    $stdoutPath = Join-Path $cycleOutput 'release-smoke.stdout.log'
    $stderrPath = Join-Path $cycleOutput 'release-smoke.stderr.log'
    $cycleLifecyclePath = Join-Path $cycleOutput 'release-lifecycle-report.json'
    foreach ($path in @($reportPath, $memoryPath, $stdoutPath, $stderrPath, $cycleLifecyclePath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Soak cycle evidence missing: $path" }
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 20
    $memory = Get-Content -LiteralPath $memoryPath -Raw | ConvertFrom-Json -Depth 20
    if (-not [bool]$report.ok -or -not [bool]$report.soak.ok -or -not [bool]$report.route.ok) {
        throw "Final package cycle failed for profile $profile."
    }
    if ([bool]$report.route.transport_after_spawn -or [int]$report.route.player_transform_writes -ne 0) {
        throw "Final package cycle used forbidden post-spawn transport for profile $profile."
    }
    $fatalDiagnosticCount = Get-FatalDiagnosticCount -Paths @($stdoutPath, $stderrPath)
    if ($fatalDiagnosticCount -gt [int]$soakPolicy.fatal_diagnostics_max) {
        throw "Final package cycle emitted $fatalDiagnosticCount fatal diagnostics for profile $profile."
    }
    $workingSetP95 = [double](Get-QualificationField (Get-QualificationField $memory 'working_set_mib' $null) 'p95_mib' 0.0)
    if (-not [double]::IsFinite($workingSetP95) -or $workingSetP95 -le 0.0) {
        throw "Final package cycle produced invalid Working Set p95 for profile $profile."
    }
    $cycleLifecycle = Get-AuthoritativeLifecycleEvidence -Path $cycleLifecyclePath
    if (-not [bool]$cycleLifecycle.Valid) {
        throw "Final package cycle did not complete a clean authoritative quit for $profile`: $($cycleLifecycle.Errors -join ' | ')"
    }
    if ([string]$cycleLifecycle.Summary.quit_source -ne 'release_smoke') {
        throw "Final package cycle lifecycle source is not release_smoke for $profile."
    }
    $cycleCompleted = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $record = [pscustomobject][ordered]@{
        cycle = $cycle
        profile_id = $profile
        seed = $Seed + $cycle
        started_at_unix = $cycleStarted
        completed_at_unix = $cycleCompleted
        elapsed_seconds = [Math]::Max(0, $cycleCompleted - $cycleStarted)
        report_sha256 = Get-Sha256 -Path $reportPath
        memory_sha256 = Get-Sha256 -Path $memoryPath
        stdout_sha256 = Get-Sha256 -Path $stdoutPath
        stderr_sha256 = Get-Sha256 -Path $stderrPath
        checks = [int]$report.checks
        successful_steps = [int]$report.route.successful_steps
        horizontal_displacement = [double]$report.route.horizontal_displacement
        unique_chunks = [int]$report.route.unique_chunks
        fatal_diagnostics_count = $fatalDiagnosticCount
        working_set_p95_mib = $workingSetP95
        post_spawn_transport = [bool]$report.route.transport_after_spawn
        player_transform_writes = [int]$report.route.player_transform_writes
        lifecycle_report_sha256 = [string]$cycleLifecycle.Sha256
        lifecycle = $cycleLifecycle.Summary
        clean_exit = $true
    }
    $records.Add($record)
    [ordered]@{
        captured_at = (Get-Date).ToString('o')
        elapsed_seconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        requested_seconds = $SoakSeconds
        completed_cycles = $records.Count
        last_profile = $profile
        last_report_sha256 = $record.report_sha256
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath $progressPath -Encoding utf8
    $cycle++
}
$watch.Stop()
$completedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
if ($elapsedSeconds -lt $SoakSeconds) { throw "Strict soak did not reach wall-clock target: $elapsedSeconds/$SoakSeconds seconds." }

$coveredProfiles = @($records | ForEach-Object profile_id | Sort-Object -Unique)
foreach ($profile in $profiles) {
    if ($profile -notin $coveredProfiles) { throw "Strict soak did not cover profile: $profile" }
}
$completedRoutes = $records.Count
if (-not $ReferenceOnly -and $completedRoutes -lt [int]$soakPolicy.minimum_completed_routes) {
    throw "Strict soak completed $completedRoutes routes; policy requires $($soakPolicy.minimum_completed_routes)."
}
$fatalDiagnostics = [int](($records | Measure-Object -Property fatal_diagnostics_count -Sum).Sum)
if ($fatalDiagnostics -gt [int]$soakPolicy.fatal_diagnostics_max) {
    throw "Strict soak fatal diagnostics exceed policy: $fatalDiagnostics/$($soakPolicy.fatal_diagnostics_max)."
}
$postSpawnTransportCount = @($records | Where-Object { [bool]$_.post_spawn_transport }).Count
if ($postSpawnTransportCount -gt [int]$soakPolicy.route_transport_after_spawn_max) {
    throw "Strict soak post-spawn transport exceeds policy: $postSpawnTransportCount/$($soakPolicy.route_transport_after_spawn_max)."
}
$playerTransformWrites = [int](($records | Measure-Object -Property player_transform_writes -Sum).Sum)
if ($playerTransformWrites -ne 0) { throw "Strict soak recorded forbidden player transform writes: $playerTransformWrites." }
$workingSetFirst = [double]$records[0].working_set_p95_mib
$workingSetLast = [double]$records[$records.Count - 1].working_set_p95_mib
$memoryGrowthPercent = [math]::Round((($workingSetLast - $workingSetFirst) / $workingSetFirst) * 100.0, 4)
if (-not [double]::IsFinite($memoryGrowthPercent) -or $memoryGrowthPercent -gt [double]$soakPolicy.memory_growth_percent_max) {
    throw "Strict soak Working Set growth exceeds policy: $memoryGrowthPercent%/$($soakPolicy.memory_growth_percent_max)%."
}
$exeHashAfter = Get-Sha256 -Path $exePath
$pckHashAfter = Get-Sha256 -Path $pckPath
if ($exeHashAfter -ne $exeHashBefore -or $pckHashAfter -ne $pckHashBefore) {
    throw 'The supplied final EXE/PCK changed during the strict soak.'
}
$cycleEvidence = [ordered]@{
    schema_version = 2
    qualification_policy = $soakPolicy
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    cycle_count = $completedRoutes
    completed_routes = $completedRoutes
    profiles = @($coveredProfiles)
    fatal_diagnostics_count = $fatalDiagnostics
    post_spawn_transport_count = $postSpawnTransportCount
    player_transform_writes = $playerTransformWrites
    working_set_first_p95_mib = $workingSetFirst
    working_set_last_p95_mib = $workingSetLast
    memory_growth_percent = $memoryGrowthPercent
    authoritative_lifecycle_count = @($records | Where-Object { [bool]$_.lifecycle.authoritative_clean_quit }).Count
    cycles = @($records)
}
$cycleEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cyclesPath -Encoding utf8

$result = [ordered]@{
    schema_version = 2
    evidence_source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }
    reference_only = [bool]$ReferenceOnly
    target_hardware = -not [bool]$ReferenceOnly
    exact_final_package_reused = $true
    operator_id = $OperatorId.Trim()
    operator_attested = [bool]$OperatorAttested -and -not [bool]$ReferenceOnly
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    started_at_unix = $startedAt
    completed_at_unix = $completedAt
    cycle_count = $completedRoutes
    completed_routes = $completedRoutes
    profile_count = $coveredProfiles.Count
    profiles = @($coveredProfiles)
    qualification_policy = $soakPolicy
    fatal_diagnostics_count = $fatalDiagnostics
    post_spawn_transport_count = $postSpawnTransportCount
    player_transform_writes = $playerTransformWrites
    working_set_first_p95_mib = $workingSetFirst
    working_set_last_p95_mib = $workingSetLast
    memory_growth_percent = $memoryGrowthPercent
    lifecycle = $lifecycleEvidence.Summary
    authoritative_cycle_lifecycle_count = @($records | Where-Object { [bool]$_.lifecycle.authoritative_clean_quit }).Count
    clean_exit = $true
    crash_count = 0
    timed_out = $false
    result = 'pass'
    executable_sha256 = $exeHashAfter
    pck_sha256 = $pckHashAfter
    lifecycle_report_sha256 = [string]$lifecycleEvidence.Sha256
    soak_report_sha256 = Get-Sha256 -Path $cyclesPath
    progress_journal_sha256 = Get-Sha256 -Path $progressPath
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Host "STRICT TARGET HARDWARE SOAK PASS | requested=$SoakSeconds | elapsed=$elapsedSeconds | cycles=$($records.Count) | profiles=$($coveredProfiles.Count) | reference_only=$([bool]$ReferenceOnly) | evidence=$resultPath"
