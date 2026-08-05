param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDirectory = '',
    [int]$RunnerTimeoutMilliseconds = 60000,
    [string]$ProfileId = 'star_continent',
    [int]$Seed = 24681357,
    [switch]$RouteProbe,
    [switch]$SkipExport,
    [string]$ExecutablePath = ''
)

$ErrorActionPreference = 'Stop'

# This script requires PowerShell 7+ (pwsh). Windows PowerShell 5.1 is not
# supported because its .NET Framework version lacks ProcessStartInfo.ArgumentList.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw @'
PowerShell 7 (pwsh) or later is required to run this script.
Windows PowerShell 5.1 detected — it lacks .NET APIs used for safe argument
passing and process termination.

Install pwsh from https://github.com/PowerShell/PowerShell and run:
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\release\run_windows_export_smoke.ps1 -Godot <path> -OutputDirectory <path>
'@
}
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not $SkipExport) {
    if ([string]::IsNullOrWhiteSpace($Godot)) {
        foreach ($commandName in @('godot4', 'godot')) {
            $command = Get-Command $commandName -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                $Godot = $command.Source
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path -LiteralPath $Godot)) {
        throw 'Godot 4 executable not found. Pass -Godot <path> or set GODOT_BIN.'
    }
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot 'build\release-smoke'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$validProfiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
if ($ProfileId -notin $validProfiles) {
    throw "Unknown release-smoke profile: $ProfileId"
}
if ($RouteProbe -and $RunnerTimeoutMilliseconds -lt 600000) {
    $RunnerTimeoutMilliseconds = 600000
}

if ($SkipExport) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        throw '-ExecutablePath is required when -SkipExport is used.'
    }
    $exePath = [System.IO.Path]::GetFullPath($ExecutablePath)
    $binaryDirectory = Split-Path -Parent $exePath
    $consolePath = Join-Path $binaryDirectory 'StarWorld.console.exe'
    $pckPath = Join-Path $binaryDirectory 'StarWorld.pck'
} else {
    $exePath = Join-Path $OutputDirectory 'StarWorld.exe'
    $binaryDirectory = $OutputDirectory
    $consolePath = Join-Path $OutputDirectory 'StarWorld.console.exe'
    $pckPath = Join-Path $OutputDirectory 'StarWorld.pck'
}
$reportPath = Join-Path $OutputDirectory 'release-smoke.json'
$screenshotPath = Join-Path $OutputDirectory 'release-smoke.png'
$exportStdoutPath = Join-Path $OutputDirectory 'export.stdout.log'
$exportStderrPath = Join-Path $OutputDirectory 'export.stderr.log'
$stdoutPath = Join-Path $OutputDirectory 'release-smoke.stdout.log'
$stderrPath = Join-Path $OutputDirectory 'release-smoke.stderr.log'
$driverLogPath = Join-Path $OutputDirectory 'release-smoke.driver.log'
$memoryEvidencePath = Join-Path $OutputDirectory 'release-smoke.memory.json'

$evidenceFiles = @(
    $reportPath, $screenshotPath, $exportStdoutPath, $exportStderrPath,
    $stdoutPath, $stderrPath, $driverLogPath, $memoryEvidencePath
)
if (-not $SkipExport) {
    $evidenceFiles += @($exePath, $consolePath, $pckPath)
}
Remove-Item -Force -ErrorAction SilentlyContinue $evidenceFiles

function Write-DriverLog {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -LiteralPath $driverLogPath -Value $line
    Write-Host $line
}

function Show-LogFile {
    param([string]$Title, [string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Host "--- $Title ---"
        Get-Content -LiteralPath $Path | Write-Host
    }
}

function Invoke-WaitedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StandardOutputPath,
        [Parameter(Mandatory = $true)][string]$StandardErrorPath,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start process: $FilePath"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "Process timed out after $TimeoutMilliseconds ms: $FilePath"
    }
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -LiteralPath $StandardOutputPath -Value $stdout -Encoding utf8
    Set-Content -LiteralPath $StandardErrorPath -Value $stderr -Encoding utf8
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        ProcessId = $process.Id
    }
}

function Get-MemoryPercentile {
    param(
        [Parameter(Mandatory = $true)][long[]]$Values,
        [Parameter(Mandatory = $true)][double]$Percentile
    )

    if ($Values.Count -eq 0) {
        throw 'Cannot calculate a percentile without samples.'
    }
    $sorted = [long[]]($Values | Sort-Object)
    $index = [int][Math]::Ceiling(($sorted.Count - 1) * $Percentile)
    $index = [Math]::Max(0, [Math]::Min($index, $sorted.Count - 1))
    return $sorted[$index]
}

function Get-MemorySummary {
    param(
        [Parameter(Mandatory = $true)][object[]]$Samples,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $values = [System.Collections.Generic.List[long]]::new()
    foreach ($sample in $Samples) {
        $values.Add([long]$sample.$PropertyName)
    }
    if ($values.Count -eq 0) {
        return [ordered]@{ sample_count = 0 }
    }

    $asArray = $values.ToArray()
    return [ordered]@{
        sample_count = $asArray.Count
        min_mib = [Math]::Round((($asArray | Measure-Object -Minimum).Minimum / 1MB), 1)
        p50_mib = [Math]::Round((Get-MemoryPercentile -Values $asArray -Percentile 0.50) / 1MB, 1)
        p95_mib = [Math]::Round((Get-MemoryPercentile -Values $asArray -Percentile 0.95) / 1MB, 1)
        max_mib = [Math]::Round((($asArray | Measure-Object -Maximum).Maximum / 1MB), 1)
    }
}

function Invoke-SampledProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StandardOutputPath,
        [Parameter(Mandatory = $true)][string]$StandardErrorPath,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
        [int]$SampleIntervalMilliseconds = 1000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start process: $FilePath"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $samples = [System.Collections.Generic.List[object]]::new()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextSampleAt = 0
    $timedOut = $false

    while (-not $process.HasExited) {
        $elapsedMilliseconds = [int]$watch.ElapsedMilliseconds
        if ($elapsedMilliseconds -ge $TimeoutMilliseconds) {
            $timedOut = $true
            $process.Kill($true)
            break
        }
        if ($elapsedMilliseconds -ge $nextSampleAt) {
            $process.Refresh()
            $samples.Add([pscustomobject][ordered]@{
                elapsed_ms = $elapsedMilliseconds
                working_set_bytes = [long]$process.WorkingSet64
                private_bytes = [long]$process.PrivateMemorySize64
            })
            $nextSampleAt += $SampleIntervalMilliseconds
        }
        $remaining = [Math]::Max(1, $TimeoutMilliseconds - $elapsedMilliseconds)
        $process.WaitForExit([Math]::Min(250, $remaining)) | Out-Null
    }

    $process.WaitForExit()
    $watch.Stop()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -LiteralPath $StandardOutputPath -Value $stdout -Encoding utf8
    Set-Content -LiteralPath $StandardErrorPath -Value $stderr -Encoding utf8
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        ProcessId = $process.Id
        TimedOut = $timedOut
        DurationMilliseconds = [int]$watch.ElapsedMilliseconds
        Samples = $samples.ToArray()
    }
}

function Show-ReleaseSmokeLogs {
    Show-LogFile -Title 'export stdout' -Path $exportStdoutPath
    Show-LogFile -Title 'export stderr' -Path $exportStderrPath
    Show-LogFile -Title 'exported game stdout' -Path $stdoutPath
    Show-LogFile -Title 'exported game stderr' -Path $stderrPath
}

function Assert-NoFatalGodotLog {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $fatalPatterns = @(
        'SCRIPT ERROR',
        'Parse Error',
        'ObjectDB instances were leaked',
        'Leaked instance:',
        'Resources still in use at exit'
    )
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $matches = @(Select-String -LiteralPath $path -Pattern $fatalPatterns -SimpleMatch)
        if ($matches.Count -le 0) {
            continue
        }
        $details = ($matches | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line)" }) -join [Environment]::NewLine
        throw "Fatal Godot runtime diagnostics were found:$([Environment]::NewLine)$details"
    }
}

Write-DriverLog "project_root=$ProjectRoot"
Write-DriverLog "godot=$Godot"
Write-DriverLog "output_directory=$OutputDirectory"

try {
    if (-not $SkipExport) {
        Write-DriverLog "export_begin=$exePath"
        $exportResult = Invoke-WaitedProcess `
            -FilePath $Godot `
            -Arguments @('--headless', '--path', $ProjectRoot, '--export-release', 'Windows Desktop', $exePath) `
            -WorkingDirectory $ProjectRoot `
            -StandardOutputPath $exportStdoutPath `
            -StandardErrorPath $exportStderrPath `
            -TimeoutMilliseconds 120000
        Write-DriverLog "export_process_id=$($exportResult.ProcessId)"
        Write-DriverLog "export_exit_code=$($exportResult.ExitCode)"
        if ($exportResult.ExitCode -ne 0) {
            throw "Windows release export failed with exit code $($exportResult.ExitCode)"
        }
    } else {
        Set-Content -LiteralPath $exportStdoutPath -Value 'export skipped; reusing verified binary' -Encoding utf8
        Set-Content -LiteralPath $exportStderrPath -Value '' -Encoding utf8
        Write-DriverLog "export_skipped=true"
    }
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Windows release executable missing: $exePath"
    }
    if (-not (Test-Path -LiteralPath $pckPath)) {
        throw "Windows release PCK missing: $pckPath"
    }
    Write-DriverLog "export_sizes=exe:$((Get-Item $exePath).Length),pck:$((Get-Item $pckPath).Length)"

    $runnerPath = if (Test-Path -LiteralPath $consolePath) { $consolePath } else { $exePath }
    $reportArgumentPath = ([System.IO.Path]::GetFullPath($reportPath)).Replace('\', '/')
    Write-DriverLog "runner=$runnerPath"
    Write-DriverLog "report_argument=$reportArgumentPath"
    Write-DriverLog "profile_id=$ProfileId seed=$Seed route_probe=$([bool]$RouteProbe)"
    # Collect timestamped external process evidence because release builds may
    # not expose engine-internal allocation counters. Keep the raw samples so
    # release review can distinguish a real percentile from a summary bug.
    $memArgs = @(
        '--verbose', '--', '--release-smoke', '--smoke-soak-frames=180',
        "--smoke-output=$reportArgumentPath", "--smoke-profile=$ProfileId", "--smoke-seed=$Seed"
    )
    if ($RouteProbe) { $memArgs += '--smoke-route-probe' }
    $runnerResult = Invoke-SampledProcess `
        -FilePath $runnerPath `
        -Arguments $memArgs `
        -WorkingDirectory $binaryDirectory `
        -StandardOutputPath $stdoutPath `
        -StandardErrorPath $stderrPath `
        -TimeoutMilliseconds $RunnerTimeoutMilliseconds
    $memoryEvidence = [ordered]@{
        schema_version = 1
        sample_interval_ms = 1000
        timeout_ms = $RunnerTimeoutMilliseconds
        duration_ms = $runnerResult.DurationMilliseconds
        timed_out = $runnerResult.TimedOut
        samples = @($runnerResult.Samples)
        working_set_mib = Get-MemorySummary -Samples @($runnerResult.Samples) -PropertyName 'working_set_bytes'
        private_bytes_mib = Get-MemorySummary -Samples @($runnerResult.Samples) -PropertyName 'private_bytes'
    }
    $memoryEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $memoryEvidencePath -Encoding utf8
    if ($runnerResult.TimedOut) {
        throw "Exported Windows release smoke timed out after $RunnerTimeoutMilliseconds ms. See $memoryEvidencePath"
    }
    if ($memoryEvidence['working_set_mib']['sample_count'] -eq 0 -or $memoryEvidence['private_bytes_mib']['sample_count'] -eq 0) {
        throw "Exported Windows release smoke produced no external memory samples. See $memoryEvidencePath"
    }
    if ($memoryEvidence['working_set_mib']['p95_mib'] -le 0 -or $memoryEvidence['private_bytes_mib']['p95_mib'] -le 0) {
        throw "Exported Windows release smoke produced invalid external memory percentiles. See $memoryEvidencePath"
    }
    $memorySummary = [ordered]@{
        duration_ms = $memoryEvidence['duration_ms']
        timed_out = $memoryEvidence['timed_out']
        working_set_mib = $memoryEvidence['working_set_mib']
        private_bytes_mib = $memoryEvidence['private_bytes_mib']
    }
    Write-DriverLog "external_memory_mib=$($memorySummary | ConvertTo-Json -Compress)"
    Write-DriverLog "runner_process_id=$($runnerResult.ProcessId)"
    Write-DriverLog "runner_exit_code=$($runnerResult.ExitCode)"
    Show-ReleaseSmokeLogs
    Assert-NoFatalGodotLog -Paths @($exportStdoutPath, $exportStderrPath, $stdoutPath, $stderrPath)
    if ($runnerResult.ExitCode -ne 0) {
        throw "Exported Windows release smoke failed with exit code $($runnerResult.ExitCode)"
    }
    if (-not (Test-Path -LiteralPath $reportPath)) {
        throw "Release smoke report missing: $reportPath"
    }
    if (-not (Test-Path -LiteralPath $screenshotPath)) {
        throw "Release smoke screenshot missing: $screenshotPath"
    }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if (-not [bool]$report.ok) {
        $failureText = ($report.failures -join ', ')
        throw "Release smoke report failed: $failureText"
    }
    if (-not [bool]$report.soak.ok) {
        throw 'Release smoke soak report is not healthy.'
    }
    if ([string]$report.profile_id -ne $ProfileId -or [int]$report.seed -ne $Seed) {
        throw "Release smoke report identity mismatch: expected $ProfileId/$Seed, got $($report.profile_id)/$($report.seed)"
    }
    if ($RouteProbe) {
        if (-not [bool]$report.route_probe_enabled -or -not [bool]$report.route.ok) {
            throw "Release route probe failed for $ProfileId"
        }
        if ([int]$report.route.player_transform_writes -ne 0 -or [bool]$report.route.transport_after_spawn) {
            throw "Release route probe used forbidden post-spawn transport for $ProfileId"
        }
        if ([int]$report.route.successful_steps -lt 20 -or [double]$report.route.horizontal_displacement -lt 14.0 -or [int]$report.route.unique_chunks -lt 2) {
            throw "Release route evidence is below the commercial reference floor for $ProfileId"
        }
    }
    if ([int64](Get-Item -LiteralPath $exePath).Length -le 0) {
        throw 'Exported executable is empty.'
    }
    if ([int64](Get-Item -LiteralPath $pckPath).Length -le 0) {
        throw 'Exported PCK is empty.'
    }
    if ([int64](Get-Item -LiteralPath $screenshotPath).Length -le 0) {
        throw 'Release smoke screenshot is empty.'
    }

    Write-DriverLog "release_smoke_pass=profile:$ProfileId,checks:$($report.checks),soak_frames:$($report.soak.frames),route:$([bool]$RouteProbe)"
    Write-Host "PASS: exported Windows release smoke | profile=$ProfileId | checks=$($report.checks) | output=$OutputDirectory"
}
catch {
    Show-ReleaseSmokeLogs
    Write-DriverLog "failure=$($_.Exception.Message)"
    Write-DriverLog "failure_detail=$($_ | Out-String)"
    throw
}
