param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

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
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot 'build\release-smoke'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$exePath = Join-Path $OutputDirectory 'StarWorld.exe'
$consolePath = Join-Path $OutputDirectory 'StarWorld.console.exe'
$pckPath = Join-Path $OutputDirectory 'StarWorld.pck'
$reportPath = Join-Path $OutputDirectory 'release-smoke.json'
$screenshotPath = Join-Path $OutputDirectory 'release-smoke.png'
$exportStdoutPath = Join-Path $OutputDirectory 'export.stdout.log'
$exportStderrPath = Join-Path $OutputDirectory 'export.stderr.log'
$stdoutPath = Join-Path $OutputDirectory 'release-smoke.stdout.log'
$stderrPath = Join-Path $OutputDirectory 'release-smoke.stderr.log'
$driverLogPath = Join-Path $OutputDirectory 'release-smoke.driver.log'

Remove-Item -Force -ErrorAction SilentlyContinue `
    $exePath, $consolePath, $pckPath, $reportPath, $screenshotPath, `
    $exportStdoutPath, $exportStderrPath, $stdoutPath, $stderrPath, $driverLogPath

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

function Show-ReleaseSmokeLogs {
    Show-LogFile -Title 'export stdout' -Path $exportStdoutPath
    Show-LogFile -Title 'export stderr' -Path $exportStderrPath
    Show-LogFile -Title 'exported game stdout' -Path $stdoutPath
    Show-LogFile -Title 'exported game stderr' -Path $stderrPath
}

Write-DriverLog "project_root=$ProjectRoot"
Write-DriverLog "godot=$Godot"
Write-DriverLog "output_directory=$OutputDirectory"

try {
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
    $runnerResult = Invoke-WaitedProcess `
        -FilePath $runnerPath `
        -Arguments @('--', '--release-smoke', "--smoke-output=$reportArgumentPath") `
        -WorkingDirectory $OutputDirectory `
        -StandardOutputPath $stdoutPath `
        -StandardErrorPath $stderrPath `
        -TimeoutMilliseconds 60000
    Write-DriverLog "runner_process_id=$($runnerResult.ProcessId)"
    Write-DriverLog "runner_exit_code=$($runnerResult.ExitCode)"
    Show-ReleaseSmokeLogs
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
    if ([int64](Get-Item -LiteralPath $exePath).Length -le 0) {
        throw 'Exported executable is empty.'
    }
    if ([int64](Get-Item -LiteralPath $pckPath).Length -le 0) {
        throw 'Exported PCK is empty.'
    }
    if ([int64](Get-Item -LiteralPath $screenshotPath).Length -le 0) {
        throw 'Release smoke screenshot is empty.'
    }

    Write-DriverLog "release_smoke_pass=checks:$($report.checks)"
    Write-Host "PASS: exported Windows release smoke | checks=$($report.checks) | output=$OutputDirectory"
}
catch {
    Show-ReleaseSmokeLogs
    Write-DriverLog "failure=$($_.Exception.Message)"
    Write-DriverLog "failure_detail=$($_ | Out-String)"
    throw
}
