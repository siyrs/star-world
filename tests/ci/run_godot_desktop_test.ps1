param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$CaptureMarker,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RenderingMethod = 'gl_compatibility'
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputPath))
$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$processOutput = @(
    & $Godot `
        --path $projectFullPath `
        --rendering-method $RenderingMethod `
        --script $ScriptPath 2>&1
)
$exitCode = $LASTEXITCODE
$processOutput | ForEach-Object { Write-Host ([string]$_) }

if ($exitCode -ne 0) {
    throw "Godot desktop test failed: $ScriptPath (exit $exitCode)"
}

$pattern = [regex]::Escape($CaptureMarker) + '=(.+)$'
$captureLine = @(
    $processOutput |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -match $pattern } |
        Select-Object -Last 1
)
if ($captureLine.Count -eq 0) {
    throw "Desktop test did not report $CaptureMarker: $ScriptPath"
}

$captureMatch = [regex]::Match($captureLine[0], $pattern)
$sourcePath = $captureMatch.Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($sourcePath)) {
    throw "Desktop test reported an empty capture path: $ScriptPath"
}

$sourceFullPath = [System.IO.Path]::GetFullPath($sourcePath)
if (-not (Test-Path -LiteralPath $sourceFullPath)) {
    throw "Reported desktop screenshot does not exist: $sourceFullPath"
}
if ((Get-Item -LiteralPath $sourceFullPath).Length -le 0) {
    throw "Reported desktop screenshot is empty: $sourceFullPath"
}

if (-not [string]::Equals(
    $sourceFullPath,
    $outputFullPath,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    Copy-Item -LiteralPath $sourceFullPath -Destination $outputFullPath -Force
}

if (-not (Test-Path -LiteralPath $outputFullPath)) {
    throw "Desktop screenshot was not preserved: $outputFullPath"
}
if ((Get-Item -LiteralPath $outputFullPath).Length -le 0) {
    throw "Preserved desktop screenshot is empty: $outputFullPath"
}

Write-Host "PASS desktop evidence | script=$ScriptPath | capture=$outputFullPath"
