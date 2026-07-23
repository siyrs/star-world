param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputBasePath,
    [int]$TimeoutMilliseconds = 600000
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputBaseFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputBasePath))
$outputDirectory = Split-Path -Parent $outputBaseFullPath
$stdoutPath = "$outputBaseFullPath.stdout.log"
$stderrPath = "$outputBaseFullPath.stderr.log"

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

if (-not [System.IO.Path]::IsPathRooted($Godot)) {
    $command = Get-Command $Godot -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $Godot = $command.Source
    }
}

$arguments = @(
    '--headless',
    '--path', $projectFullPath,
    '--script', $ScriptPath,
    '--',
    '--disable-update-check'
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectFullPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $arguments) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Unable to start Godot headless test: $ScriptPath"
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
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    Write-Host '--- Godot headless stdout ---'
    Write-Host $stdout
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    Write-Host '--- Godot headless stderr ---'
    Write-Host $stderr
}

if ($timedOut) {
    throw "Godot headless test timed out after $TimeoutMilliseconds ms: $ScriptPath"
}
if ($process.ExitCode -ne 0) {
    throw "Godot headless test failed: $ScriptPath (exit $($process.ExitCode)); logs=$stdoutPath,$stderrPath"
}

Write-Host "PASS headless evidence | script=$ScriptPath | stdout=$stdoutPath | stderr=$stderrPath"
