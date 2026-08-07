param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$weatherValidator = Join-Path $root 'tests\developer_b\validate_weather_climate_iteration_66.ps1'
$iteration65Runner = Join-Path $root 'tests\ci\run_iteration_65_full_regression.ps1'
$invokeGodot = Join-Path $root 'tests\ci\Invoke-Godot.ps1'
$diagnosticDirectory = Join-Path $root 'build\iteration66-full-regression'
$baselineStdout = Join-Path $diagnosticDirectory 'iteration65-baseline.stdout.log'
$baselineStderr = Join-Path $diagnosticDirectory 'iteration65-baseline.stderr.log'

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

New-Item -ItemType Directory -Path $diagnosticDirectory -Force | Out-Null
Remove-Item -LiteralPath $baselineStdout, $baselineStderr -Force -ErrorAction SilentlyContinue

Write-Host 'ITERATION 66 STAGE 1/3 | weather static contract'
& $weatherValidator

Write-Host 'ITERATION 66 STAGE 2/3 | weather runtime regression'
& $invokeGodot -Godot $Godot -Arguments '--headless --path . --script res://tests/qa/weather_climate_regression.gd -- --disable-update-check'

Write-Host 'ITERATION 66 STAGE 3/3 | inherited Iteration 65 + full repository regression'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$baselineProcess = Start-Process `
    -FilePath $pwsh `
    -ArgumentList @('-NoLogo', '-NoProfile', '-File', "`"$iteration65Runner`"", '-Godot', "`"$Godot`"") `
    -RedirectStandardOutput $baselineStdout `
    -RedirectStandardError $baselineStderr `
    -NoNewWindow `
    -Wait `
    -PassThru

if (Test-Path -LiteralPath $baselineStdout) {
    Write-Host '--- Iteration 65 baseline stdout ---'
    Get-Content -LiteralPath $baselineStdout | ForEach-Object { Write-Host $_ }
}
if (Test-Path -LiteralPath $baselineStderr) {
    $stderrLines = @(Get-Content -LiteralPath $baselineStderr)
    if ($stderrLines.Count -gt 0) {
        Write-Host '--- Iteration 65 baseline stderr ---'
        $stderrLines | ForEach-Object { Write-Host $_ }
    }
}

if ($baselineProcess.ExitCode -ne 0) {
    throw "Baseline full repository regression failed with exit code $($baselineProcess.ExitCode). Diagnostic logs: $diagnosticDirectory"
}

Write-Host 'ITERATION 66 FULL REGRESSION PASS | weather-domain=true | lifecycle=true | iteration65-baseline=true | run_all=true'
