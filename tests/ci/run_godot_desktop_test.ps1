param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RenderingMethod = 'gl_compatibility',
    [int]$TimeoutMilliseconds = 60000
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputPath))
$outputDirectory = Split-Path -Parent $outputFullPath
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputFullPath)
$stdoutPath = Join-Path $outputDirectory "$outputBaseName.stdout.log"
$stderrPath = Join-Path $outputDirectory "$outputBaseName.stderr.log"

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $outputFullPath, $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

$outputArgumentPath = $outputFullPath.Replace('\', '/')
$arguments = @(
    '--path', $projectFullPath,
    '--rendering-method', $RenderingMethod,
    '--script', $ScriptPath,
    '--',
    "--capture-output=$outputArgumentPath"
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectFullPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $arguments) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Unable to start Godot desktop test: $ScriptPath"
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = -not $process.WaitForExit($TimeoutMilliseconds)
if ($timedOut) {
    $process.Kill($true)
    $process.WaitForExit()
} else {
    $process.WaitForExit()
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    Write-Host '--- Godot desktop stdout ---'
    Write-Host $stdout
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    Write-Host '--- Godot desktop stderr ---'
    Write-Host $stderr
}

if ($timedOut) {
    throw "Godot desktop test timed out after $TimeoutMilliseconds ms: $ScriptPath"
}
if ($process.ExitCode -ne 0) {
    throw "Godot desktop test failed: $ScriptPath (exit $($process.ExitCode)); logs=$stdoutPath,$stderrPath"
}
if (-not (Test-Path -LiteralPath $outputFullPath)) {
    throw "Desktop test did not create its requested screenshot: $outputFullPath"
}
if ((Get-Item -LiteralPath $outputFullPath).Length -le 0) {
    throw "Desktop test created an empty screenshot: $outputFullPath"
}

Write-Host "PASS desktop evidence | script=$ScriptPath | capture=$outputFullPath"
