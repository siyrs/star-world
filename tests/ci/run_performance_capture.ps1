param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$ProjectRoot = '.',
    [string]$OutputDirectory = 'build/claude-perf',
    [int]$TimeoutMilliseconds = 1800000
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

$capturePath = (Join-Path $outputFullPath 'perf-main.png').Replace('\', '/')
$reportPath = Join-Path $outputFullPath 'perf-report.json'
$stdoutPath = Join-Path $outputFullPath 'perf.stdout.log'
$stderrPath = Join-Path $outputFullPath 'perf.stderr.log'
$memoryPath = Join-Path $outputFullPath 'perf.memory.json'
$userDataFullPath = Join-Path $outputFullPath 'isolated-userdata'
$roamingPath = Join-Path $userDataFullPath 'Roaming'
$localPath = Join-Path $userDataFullPath 'Local'
if (Test-Path -LiteralPath $userDataFullPath) {
    Remove-Item -LiteralPath $userDataFullPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $roamingPath, $localPath | Out-Null

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectFullPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.Environment['APPDATA'] = $roamingPath
$startInfo.Environment['LOCALAPPDATA'] = $localPath
foreach ($argument in @(
    '--path', $projectFullPath,
    '--rendering-method', 'gl_compatibility',
    '--script', 'res://tests/qa/performance_scenario_capture.gd',
    '--',
    "--capture-output=$capturePath"
)) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw 'Unable to start performance capture'
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

# External memory sampling of the launched PID (Working Set / Private Bytes),
# 1s cadence, timestamped — the spec-mandated valid memory evidence.
$samples = [System.Collections.Generic.List[object]]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$nextSampleMs = 1000
# The Godot *console* binary is a thin launcher: it spawns the real
# (GUI-subsystem) engine as a child process and idles at ~6 MiB. Sampling the
# launcher alone would record a meaningless working set, so resolve the real
# workload process once it appears and sample that PID instead.
$workloadProcess = $null
$workloadLogged = $false
$timedOut = $false
while (-not $process.WaitForExit(200)) {
    if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
        $timedOut = $true
        $process.Kill($true)
        break
    }
    if ($workloadProcess -eq $null) {
        $children = @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $process.Id })
        foreach ($child in $children) {
            $candidate = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
            if ($candidate -ne $null -and $candidate.WorkingSet64 -gt 32MB) {
                $workloadProcess = $candidate
                break
            }
        }
        if ($workloadProcess -eq $null -and $process.WorkingSet64 -gt 32MB) {
            # Non-launcher binary (no child): sample the launched process itself.
            $workloadProcess = $process
        }
    }
    if ($stopwatch.ElapsedMilliseconds -ge $nextSampleMs) {
        $sampled = if ($workloadProcess -ne $null) { $workloadProcess } else { $process }
        $sampled.Refresh()
        $samples.Add([pscustomobject]@{
            elapsed_ms = [long]$stopwatch.ElapsedMilliseconds
            pid = [long]$sampled.Id
            working_set_bytes = [long]$sampled.WorkingSet64
            private_bytes = [long]$sampled.PrivateMemorySize64
        })
        if ($workloadProcess -ne $null -and -not $workloadLogged) {
            Write-Host "perf memory sampling targets workload pid=$($workloadProcess.Id) ($($workloadProcess.ProcessName))"
            $workloadLogged = $true
        }
        $nextSampleMs = $stopwatch.ElapsedMilliseconds + 1000
    }
}
# Ensure the workload child is not orphaned if the launcher exits first.
if ($workloadProcess -ne $null -and $workloadProcess.Id -ne $process.Id -and -not $workloadProcess.HasExited) {
    try { $workloadProcess.WaitForExit(5000) | Out-Null } catch {}
    if (-not $workloadProcess.HasExited) { $workloadProcess.Kill($true) }
}
$process.WaitForExit()
$stopwatch.Stop()

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8
Write-Host $stdout
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    Write-Host '--- stderr ---'
    Write-Host $stderr
}

function Get-MemorySummary {
    param([object[]]$Samples, [string]$PropertyName)
    if ($Samples.Count -eq 0) {
        return [ordered]@{ sample_count = 0 }
    }
    $values = @($Samples | ForEach-Object { [long]$_.$PropertyName } | Sort-Object)
    $mib = $values | ForEach-Object { [math]::Round($_ / 1MB, 1) }
    $p50 = $mib[[math]::Min($mib.Count - 1, [int][math]::Ceiling(0.50 * $mib.Count) - 1)]
    $p95 = $mib[[math]::Min($mib.Count - 1, [int][math]::Ceiling(0.95 * $mib.Count) - 1)]
    [ordered]@{
        sample_count = $mib.Count
        min_mib = $mib[0]
        p50_mib = $p50
        p95_mib = $p95
        max_mib = $mib[$mib.Count - 1]
    }
}

$memoryEvidence = [ordered]@{
    schema_version = 1
    sample_interval_ms = 1000
    duration_ms = [long]$stopwatch.ElapsedMilliseconds
    samples = @($samples)
    working_set_mib = Get-MemorySummary -Samples @($samples) -PropertyName 'working_set_bytes'
    private_bytes_mib = Get-MemorySummary -Samples @($samples) -PropertyName 'private_bytes'
}
$memoryEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $memoryPath -Encoding utf8

$fatalPatterns = @('SCRIPT ERROR', 'Parse Error', 'ObjectDB instances were leaked', 'Leaked instance:', 'Resources still in use at exit', 'Unhandled exception', 'FATAL:', 'Condition "!is_inside_tree()" is true')
$hits = @()
foreach ($path in @($stdoutPath, $stderrPath)) {
    if (Test-Path -LiteralPath $path) {
        $hits += @(Select-String -LiteralPath $path -Pattern $fatalPatterns -SimpleMatch)
    }
}
if ($hits.Count -gt 0) {
    throw "Fatal Godot diagnostics:`n$(($hits | ForEach-Object { $_.Line }) -join "`n")"
}
if ($timedOut) {
    throw "Performance capture timed out after $TimeoutMilliseconds ms"
}
if ($process.ExitCode -ne 0) {
    throw "Performance capture failed with exit $($process.ExitCode)"
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf) -or (Get-Item -LiteralPath $reportPath).Length -le 0) {
    throw "Performance capture did not create a non-empty report: $reportPath"
}
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 30
if ([int]$report.schema_version -lt 2 -or @($report.scenarios).Count -lt 13) {
    throw "Performance report is incomplete: schema=$($report.schema_version) scenarios=$(@($report.scenarios).Count)"
}
if ([int]$memoryEvidence.working_set_mib.sample_count -le 0) {
    throw 'Performance capture produced no workload memory samples.'
}

Write-Host "PERF CAPTURE PASS | report=$reportPath | scenarios=$(@($report.scenarios).Count) | memory=$memoryPath | ws_p95=$($memoryEvidence.working_set_mib.p95_mib) MiB"
