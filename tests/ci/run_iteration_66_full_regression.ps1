param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$weatherValidator = Join-Path $root 'tests\developer_b\validate_weather_climate_iteration_66.ps1'
$iteration65Runner = Join-Path $root 'tests\ci\run_iteration_65_full_regression.ps1'
$invokeGodot = Join-Path $root 'tests\ci\Invoke-Godot.ps1'

foreach ($path in @($weatherValidator, $iteration65Runner, $invokeGodot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 66 regression dependency is missing: $path" }
}

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
    throw 'Godot executable not found for Iteration 66 full regression.'
}

& $weatherValidator
& $invokeGodot -Godot $Godot -Arguments '--headless --path . --script res://tests/qa/weather_climate_regression.gd -- --disable-update-check'

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
& $pwsh -NoLogo -NoProfile -File $iteration65Runner -Godot $Godot
$baselineExit = $LASTEXITCODE
if ($baselineExit -ne 0) { throw "Baseline full repository regression failed with exit code $baselineExit." }

Write-Host 'ITERATION 66 FULL REGRESSION PASS | weather-domain=true | lifecycle=true | iteration65-baseline=true | run_all=true'
