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
$stdoutPath = Join-Path $OutputDirectory 'release-smoke.stdout.log'
$stderrPath = Join-Path $OutputDirectory 'release-smoke.stderr.log'
$driverLogPath = Join-Path $OutputDirectory 'release-smoke.driver.log'

Remove-Item -Force -ErrorAction SilentlyContinue `
    $exePath, $consolePath, $pckPath, $reportPath, $screenshotPath, $stdoutPath, $stderrPath, $driverLogPath

function Write-DriverLog {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -LiteralPath $driverLogPath -Value $line
    Write-Host $line
}

function Show-ReleaseSmokeLogs {
    if (Test-Path -LiteralPath $stdoutPath) {
        Write-Host '--- exported game stdout ---'
        Get-Content -LiteralPath $stdoutPath | Write-Host
    }
    if (Test-Path -LiteralPath $stderrPath) {
        Write-Host '--- exported game stderr ---'
        Get-Content -LiteralPath $stderrPath | Write-Host
    }
}

Write-DriverLog "project_root=$ProjectRoot"
Write-DriverLog "godot=$Godot"
Write-DriverLog "output_directory=$OutputDirectory"

try {
    Write-DriverLog "export_begin=$exePath"
    & $Godot --headless --path $ProjectRoot --export-release 'Windows Desktop' $exePath
    Write-DriverLog "export_exit_code=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) {
        throw "Windows release export failed with exit code $LASTEXITCODE"
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
    $process = Start-Process `
        -FilePath $runnerPath `
        -WorkingDirectory $OutputDirectory `
        -ArgumentList @('--', '--release-smoke', "--smoke-output=$reportArgumentPath") `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    if (-not $process.WaitForExit(60000)) {
        $process.Kill($true)
        throw 'Exported Windows release smoke timed out after 60 seconds.'
    }
    $process.Refresh()
    Write-DriverLog "runner_exit_code=$($process.ExitCode)"
    Show-ReleaseSmokeLogs
    if ($process.ExitCode -ne 0) {
        throw "Exported Windows release smoke failed with exit code $($process.ExitCode)"
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
