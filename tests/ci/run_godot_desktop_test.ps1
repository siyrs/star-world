param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RenderingMethod = 'gl_compatibility'
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputPath))
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue

# Use an explicit ASCII-safe absolute output path. The Godot test keeps a user://
# fallback for local runs, while CI never needs to infer a localized app-data path.
$outputArgumentPath = $outputFullPath.Replace('\', '/')
$arguments = @(
    '--path', $projectFullPath,
    '--rendering-method', $RenderingMethod,
    '--script', $ScriptPath,
    '--',
    "--capture-output=$outputArgumentPath"
)

$processOutput = @(& $Godot @arguments 2>&1)
$exitCode = $LASTEXITCODE
$processOutput | ForEach-Object { Write-Host ([string]$_) }

if ($exitCode -ne 0) {
    throw "Godot desktop test failed: $ScriptPath (exit $exitCode)"
}
if (-not (Test-Path -LiteralPath $outputFullPath)) {
    throw "Desktop test did not create its requested screenshot: $outputFullPath"
}
if ((Get-Item -LiteralPath $outputFullPath).Length -le 0) {
    throw "Desktop test created an empty screenshot: $outputFullPath"
}

Write-Host "PASS desktop evidence | script=$ScriptPath | capture=$outputFullPath"
