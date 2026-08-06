param(
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][string]$LifecycleReportPath,
    [Parameter(Mandatory = $true)][string]$OperatorId,
    [string]$OutputDirectory = 'build/external-qualification/strict-soak',
    [ValidateSet('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')]
    [string]$ProfileId = 'star_continent',
    [int]$Seed = 112358,
    [int]$SoakSeconds = 7200,
    [int]$GraceSeconds = 900,
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

$exePath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckPath = [System.IO.Path]::GetFullPath($ReleasePck)
$lifecyclePath = [System.IO.Path]::GetFullPath($LifecycleReportPath)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
foreach ($path in @($exePath, $pckPath, $lifecyclePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence file not found: $path" }
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-NoFatalGodotLog {
    param([string[]]$Paths)
    $patterns = @('SCRIPT ERROR', 'Parse Error', 'ObjectDB instances were leaked', 'Leaked instance:', 'Resources still in use at exit')
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $matches = @(Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch)
        if ($matches.Count -gt 0) {
            throw "Fatal Godot diagnostics found in $path`: $((@($matches | ForEach-Object Line) -join ' | '))"
        }
    }
}

$binaryDirectory = Split-Path -Parent $exePath
$consolePath = Join-Path $binaryDirectory 'StarWorld.console.exe'
$runnerPath = if (Test-Path -LiteralPath $consolePath) { $consolePath } else { $exePath }
$reportPath = Join-Path $outputRoot 'release-smoke.json'
$stdoutPath = Join-Path $outputRoot 'strict-soak.stdout.log'
$stderrPath = Join-Path $outputRoot 'strict-soak.stderr.log'
$progressPath = Join-Path $outputRoot 'strict-soak.progress.jsonl'
$memoryPath = Join-Path $outputRoot 'strict-soak.memory.json'
$resultPath = Join-Path $outputRoot 'strict-soak.json'
Remove-Item -Force -ErrorAction SilentlyContinue $reportPath, $stdoutPath, $stderrPath, $progressPath, $memoryPath, $resultPath

# The final package runs its production ReleaseSmokeRunner for a wall-clock-qualified
# duration. A generous frame target keeps the process alive; wall time, not frames,
# is the acceptance clock.
$soakFrames = [Math]::Max(180, $SoakSeconds * 120)
$reportArgument = $reportPath.Replace('\', '/')
$arguments = @(
    '--verbose', '--', '--release-smoke', "--smoke-soak-frames=$soakFrames",
    "--smoke-output=$reportArgument", "--smoke-profile=$ProfileId", "--smoke-seed=$Seed",
    '--smoke-route-probe'
)
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $runnerPath
$startInfo.WorkingDirectory = $binaryDirectory
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if (-not $process.Start()) { throw "Unable to start final package: $runnerPath" }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$samples = [System.Collections.Generic.List[object]]::new()
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$nextSampleMs = 0L
$nextProgressMs = 0L
$timedOut = $false
$timeoutMs = ([long]$SoakSeconds + [Math]::Max(60, $GraceSeconds)) * 1000L

while (-not $process.HasExited) {
    $elapsedMs = [long]$watch.ElapsedMilliseconds
    if ($elapsedMs -ge $timeoutMs) {
        $timedOut = $true
        $process.Kill($true)
        break
    }
    if ($elapsedMs -ge $nextSampleMs) {
        $process.Refresh()
        $samples.Add([pscustomobject][ordered]@{
            elapsed_ms = $elapsedMs
            working_set_bytes = [long]$process.WorkingSet64
            private_bytes = [long]$process.PrivateMemorySize64
        })
        $nextSampleMs = $elapsedMs + 1000
    }
    if ($elapsedMs -ge $nextProgressMs) {
        [ordered]@{
            captured_at = (Get-Date).ToString('o')
            elapsed_seconds = [math]::Floor($elapsedMs / 1000)
            requested_seconds = $SoakSeconds
            pid = $process.Id
            still_running = $true
        } | ConvertTo-Json -Compress | Add-Content -LiteralPath $progressPath -Encoding utf8
        $nextProgressMs = $elapsedMs + 60000
    }
    $process.WaitForExit(250) | Out-Null
}
$process.WaitForExit()
$watch.Stop()
$completedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8

$elapsedSeconds = [int][math]::Floor($watch.Elapsed.TotalSeconds)
$memoryEvidence = [ordered]@{
    schema_version = 1
    sample_interval_ms = 1000
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    samples = @($samples)
}
$memoryEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $memoryPath -Encoding utf8

Assert-NoFatalGodotLog -Paths @($stdoutPath, $stderrPath)
if ($timedOut) { throw "Final package exceeded the strict soak timeout after $elapsedSeconds seconds." }
if ($process.ExitCode -ne 0) { throw "Final package exited with code $($process.ExitCode)." }
if ($elapsedSeconds -lt $SoakSeconds) {
    throw "Final package exited before the requested wall-clock soak: $elapsedSeconds/$SoakSeconds seconds."
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Release smoke report missing: $reportPath" }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 20
if (-not [bool]$report.ok -or -not [bool]$report.soak.ok) { throw 'Final package release-smoke report is not healthy.' }
if (-not [bool]$report.route.ok -or [bool]$report.route.transport_after_spawn -or [int]$report.route.player_transform_writes -ne 0) {
    throw 'Final package route evidence failed or used forbidden post-spawn transport.'
}

$result = [ordered]@{
    schema_version = 1
    evidence_source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }
    reference_only = [bool]$ReferenceOnly
    target_hardware = -not [bool]$ReferenceOnly
    operator_id = $OperatorId.Trim()
    operator_attested = [bool]$OperatorAttested -and -not [bool]$ReferenceOnly
    profile_id = $ProfileId
    seed = $Seed
    requested_seconds = $SoakSeconds
    elapsed_seconds = $elapsedSeconds
    started_at_unix = $startedAt
    completed_at_unix = $completedAt
    clean_exit = $true
    crash_count = 0
    timed_out = $false
    result = 'pass'
    executable_sha256 = Get-Sha256 -Path $exePath
    pck_sha256 = Get-Sha256 -Path $pckPath
    lifecycle_report_sha256 = Get-Sha256 -Path $lifecyclePath
    soak_report_sha256 = Get-Sha256 -Path $reportPath
    memory_report_sha256 = Get-Sha256 -Path $memoryPath
    progress_journal_sha256 = Get-Sha256 -Path $progressPath
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Host "STRICT TARGET HARDWARE SOAK PASS | requested=$SoakSeconds | elapsed=$elapsedSeconds | reference_only=$([bool]$ReferenceOnly) | evidence=$resultPath"
