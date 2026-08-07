param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$validator = Join-Path $testsRoot 'developer_b\validate_task_workspace_governance_iteration_65.ps1'
$runAll = Join-Path $testsRoot 'run_all.ps1'

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw 'Iteration 65 governance validator is missing.' }
if (-not (Test-Path -LiteralPath $runAll -PathType Leaf)) { throw 'Repository full regression runner is missing.' }

& $validator

if ([string]::IsNullOrWhiteSpace($Godot)) {
    foreach ($commandName in @('godot4', 'godot')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $Godot = $command.Source
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Godot)) { throw 'Godot executable not found for Iteration 65 full regression.' }

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
& $pwsh -NoLogo -NoProfile -File $runAll -Godot $Godot
$runAllExit = $LASTEXITCODE
if ($runAllExit -ne 0) { throw "Repository full regression failed with exit code $runAllExit." }

Write-Host 'ITERATION 65 FULL REGRESSION PASS | governance=true | run_all=true'
