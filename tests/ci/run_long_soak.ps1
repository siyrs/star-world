param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$ProjectRoot = '.',
    [string]$OutputDirectory = 'build/claude-soak',
    [int]$SoakSeconds = 600
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

$reportPath = (Join-Path $outputFullPath 'soak-report.json').Replace('\', '/')
$stdoutPath = Join-Path $outputFullPath 'soak.stdout.log'
$stderrPath = Join-Path $outputFullPath 'soak.stderr.log'
$memoryPath = Join-Path $outputFullPath 'soak.memory.json'

# This runner is intentionally self-contained: a fresh checkout has no .godot
# import cache, so importing first is part of the long-soak contract rather than
# an accidental responsibility of a calling workflow.
$invokeGodotPath = Join-Path $PSScriptRoot 'Invoke-Godot.ps1'
& $invokeGodotPath `
    -Godot $Godot `
    -WorkingDirectory $projectFullPath `
    -Arguments '--headless --path . --editor --quit' `
    -TimeoutMilliseconds 600000

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectFullPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in @(
    '--path', $projectFullPath,
    '--rendering-method', 'gl_compatibility',
    '--script', 'res://tests/qa/long_soak_journey.gd',
    '--',
    "--soak-seconds=$SoakSeconds",
    "--soak-output=$reportPath"
)) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw 'Unable to start soak'
}
Write-Host "soak launched pid=$($process.Id) target=${SoakSeconds}s -> $outputFullPath"

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

$samples = [System.Collections.Generic.List[object]]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$nextSampleMs = 1000
$workloadProcess = $null
$workloadLogged = $false
$timeoutMs = ($SoakSeconds + 300) * 1000
while (-not $process.WaitForExit(500)) {
    if ($stopwatch.ElapsedMilliseconds -gt $timeoutMs) {
        Write-Host "soak exceeded timeout, killing"
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
            Write-Host "soak memory sampling targets workload pid=$($workloadProcess.Id)"
            $workloadLogged = $true
        }
        $nextSampleMs = $stopwatch.ElapsedMilliseconds + 1000
    }
}
$process.WaitForExit()
$stopwatch.Stop()
if ($workloadProcess -ne $null -and $workloadProcess.Id -ne $process.Id -and -not $workloadProcess.HasExited) {
    try { $workloadProcess.WaitForExit(5000) | Out-Null } catch {}
    if (-not $workloadProcess.HasExited) { $workloadProcess.Kill($true) }
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8

# Surface cycle lines as they arrive in the log.
$stdout -split "`n" | Where-Object { $_ -match 'SOAK_CYCLE|SOAK_COMPLETE|PASS|FAIL' } | ForEach-Object { Write-Host $_ }

function Get-MemorySummary {
    param([object[]]$Samples, [string]$PropertyName)
    if ($Samples.Count -eq 0) { return [ordered]@{ sample_count = 0 } }
    $values = @($Samples | ForEach-Object { [long]$_.$PropertyName } | Sort-Object)
    $mib = $values | ForEach-Object { [math]::Round($_ / 1MB, 1) }
    $p50 = $mib[[math]::Min($mib.Count - 1, [int][math]::Ceiling(0.50 * $mib.Count) - 1)]
    $p95 = $mib[[math]::Min($mib.Count - 1, [int][math]::Ceiling(0.95 * $mib.Count) - 1)]
    [ordered]@{ sample_count = $mib.Count; min_mib = $mib[0]; p50_mib = $p50; p95_mib = $p95; max_mib = $mib[$mib.Count - 1] }
}

$memoryEvidence = [ordered]@{
    schema_version = 1
    sample_interval_ms = 1000
    soak_seconds_target = $SoakSeconds
    duration_ms = [long]$stopwatch.ElapsedMilliseconds
    samples = @($samples)
    working_set_mib = Get-MemorySummary -Samples @($samples) -PropertyName 'working_set_bytes'
    private_bytes_mib = Get-MemorySummary -Samples @($samples) -PropertyName 'private_bytes'
}
$memoryEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $memoryPath -Encoding utf8

# Memory trend: first-quarter vs last-quarter p50 must not grow without bound.
$ws = @($samples | ForEach-Object { [long]$_.working_set_bytes })
$trend = 'insufficient-samples'
if ($ws.Count -ge 8) {
    $quarter = [int][math]::Max(2, $ws.Count / 4)
    $firstQ = ($ws[0..($quarter - 1)] | Measure-Object -Average).Average
    $lastQ = ($ws[($ws.Count - $quarter)..($ws.Count - 1)] | Measure-Object -Average).Average
    $growthPct = if ($firstQ -gt 0) { [math]::Round((($lastQ - $firstQ) / $firstQ) * 100, 1) } else { 0 }
    $trend = "firstQ_avg=$([math]::Round($firstQ/1MB,1))MiB lastQ_avg=$([math]::Round($lastQ/1MB,1))MiB growth=${growthPct}%"
    Write-Host "soak memory trend: $trend"
    if ($growthPct -gt 25) {
        throw "Unexplained memory growth during soak: $trend"
    }
}

$fatalPatterns = @('SCRIPT ERROR', 'Parse Error', 'ObjectDB instances were leaked', 'Leaked instance:', 'Resources still in use at exit')
$hits = @()
foreach ($path in @($stdoutPath, $stderrPath)) {
    if (Test-Path -LiteralPath $path) {
        $hits += @(Select-String -LiteralPath $path -Pattern $fatalPatterns -SimpleMatch)
    }
}
if ($hits.Count -gt 0) {
    throw "Fatal Godot diagnostics during soak:`n$(($hits | ForEach-Object { $_.Line }) -join "`n")"
}
if ($process.ExitCode -ne 0) {
    throw "Soak failed with exit $($process.ExitCode); see $stdoutPath"
}

Write-Host "LONG SOAK PASS | target=${SoakSeconds}s | ws_p95=$($memoryEvidence.working_set_mib.p95_mib) MiB | trend=$trend | evidence=$outputFullPath"
