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
if (-not $ReferenceOnly -and $SoakSeconds -lt 7200) {
    throw 'Commercial target-hardware soak cannot be shorter than 7200 seconds.'
}
if (-not $ReferenceOnly -and -not $OperatorAttested) {
    throw 'Real target-hardware soak requires -OperatorAttested.'
}
if (-not $ReferenceOnly -and $env:GITHUB_ACTIONS -eq 'true') {
    throw 'GitHub-hosted runners cannot create target-hardware soak evidence.'
}
if ([string]::IsNullOrWhiteSpace($OperatorId)) { throw 'OperatorId must not be blank.' }

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$exePath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckPath = [System.IO.Path]::GetFullPath($ReleasePck)
$lifecyclePath = [System.IO.Path]::GetFullPath($LifecycleReportPath)
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
foreach ($path in @($exePath, $pckPath, $lifecyclePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence file not found: $path" }
}
$releaseRunner = Join-Path $projectFullPath 'tests/release/run_windows_export_smoke.ps1'
if (-not (Test-Path -LiteralPath $releaseRunner -PathType Leaf)) { throw "Release runner not found: $releaseRunner" }
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$progressPath = Join-Path $outputRoot 'strict-soak.progress.jsonl'
$cyclesPath = Join-Path $outputRoot 'strict-soak-cycles.json'
$resultPath = Join-Path $outputRoot 'strict-soak.json'
Remove-Item -Force -ErrorAction SilentlyContinue $progressPath, $cyclesPath, $resultPath

$records = [System.Collections.Generic.List[object]]::new()
$startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$cycle = 0
while ($watch.Elapsed.TotalSeconds -lt $SoakSeconds -or $cycle -lt $profiles.Count) {
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
    foreach ($path in @($reportPath, $memoryPath, $stdoutPath, $stderrPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Soak cycle evidence missing: $path" }
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 20
    if (-not [bool]$report.ok -or -not [bool]$report.soak.ok -or -not [bool]$report.route.ok) {
        throw "Final package cycle failed for profile $profile."
    }
    if ([bool]$report.route.transport_after_spawn -or [int]$report.route.player_transform_writes -ne 0) {
        throw "Final package cycle used forbidden post-spawn transport for profile $profile."
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
$cycleEvidence = [ordered]@{
    schema_version = 1
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    cycle_count = $records.Count
    profiles = @($coveredProfiles)
    cycles = @($records)
}
$cycleEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cyclesPath -Encoding utf8

$result = [ordered]@{
    schema_version = 1
    evidence_source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }
    reference_only = [bool]$ReferenceOnly
    target_hardware = -not [bool]$ReferenceOnly
    operator_id = $OperatorId.Trim()
    operator_attested = [bool]$OperatorAttested -and -not [bool]$ReferenceOnly
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    started_at_unix = $startedAt
    completed_at_unix = $completedAt
    cycle_count = $records.Count
    profiles = @($coveredProfiles)
    clean_exit = $true
    crash_count = 0
    timed_out = $false
    result = 'pass'
    executable_sha256 = Get-Sha256 -Path $exePath
    pck_sha256 = Get-Sha256 -Path $pckPath
    lifecycle_report_sha256 = Get-Sha256 -Path $lifecyclePath
    soak_report_sha256 = Get-Sha256 -Path $cyclesPath
    progress_journal_sha256 = Get-Sha256 -Path $progressPath
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Host "STRICT TARGET HARDWARE SOAK PASS | requested=$SoakSeconds | elapsed=$elapsedSeconds | cycles=$($records.Count) | profiles=$($coveredProfiles.Count) | reference_only=$([bool]$ReferenceOnly) | evidence=$resultPath"
