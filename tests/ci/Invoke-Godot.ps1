# Runs the Godot editor binary and waits for it reliably.
#
# The Windows Godot editor is a GUI-subsystem executable: PowerShell does not
# wait for such processes, so a plain `godot ...` call returns immediately and
# leaves $LASTEXITCODE stale (CI steps then report success without Godot ever
# finishing). This wrapper uses System.Diagnostics.Process with an explicit
# WaitForExit, relays captured output, and throws on failure so CI steps fail
# for real.
#
# Usage:
#   .\tests\ci\Invoke-Godot.ps1 -Arguments '--headless --path . --editor --quit'
#   .\tests\ci\Invoke-Godot.ps1 -Arguments '--headless --path . --script res://tests/qa/foo.gd -- --user-flag'
param(
    # Raw command line passed to Godot verbatim (quote inner values with double quotes).
    [Parameter(Mandatory = $true)][string]$Arguments,
    # Godot executable; defaults to the one on PATH (CI) but accepts an explicit path.
    [string]$Godot = 'godot',
    # Fail if Godot does not exit within this budget.
    [int]$TimeoutMilliseconds = 600000
)

$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

# A bare name (e.g. 'godot') must be resolved through PowerShell first:
# System.Diagnostics.Process does not find the extension-less symlink that
# chickensoft/setup-godot creates on PATH, while Get-Command does.
if (-not [System.IO.Path]::IsPathRooted($Godot)) {
    $command = Get-Command $Godot -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $Godot = $command.Source
    }
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.Arguments = $Arguments

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
    if (-not $process.Start()) {
        throw "Unable to start Godot: $Godot"
    }
} catch {
    throw "Unable to start Godot '$Godot': $($_.Exception.Message)"
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = -not $process.WaitForExit($TimeoutMilliseconds)
if ($timedOut) {
    $process.Kill($true)
}
$process.WaitForExit()

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    Write-Host '--- Godot stdout ---'
    Write-Host $stdout
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    Write-Host '--- Godot stderr ---'
    Write-Host $stderr
}

if ($timedOut) {
    throw "Godot timed out after $TimeoutMilliseconds ms: $Arguments"
}
if ($process.ExitCode -ne 0) {
    throw "Godot failed with exit $($process.ExitCode): $Arguments"
}
