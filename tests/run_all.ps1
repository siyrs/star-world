param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Godot)) {
    foreach ($commandName in @('godot4', 'godot')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $Godot = $command.Source
            break
        }
    }
}

$verifiedLocalGodot = 'C:\Users\sirius\.codex\toolchains\godot\4.7\Godot_v4.7-stable_win64_console.exe'
if ([string]::IsNullOrWhiteSpace($Godot) -and (Test-Path -LiteralPath $verifiedLocalGodot)) {
    $Godot = $verifiedLocalGodot
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Godot 4 executable not found. Pass -Godot <path> or set GODOT_BIN.'
}

& "$PSScriptRoot\developer_b\validate_data.ps1"
& "$PSScriptRoot\developer_b\validate_block_visuals.ps1"
& "$PSScriptRoot\developer_b\validate_fertilizers.ps1"
& "$PSScriptRoot\developer_b\validate_rest.ps1"
& "$PSScriptRoot\developer_b\validate_repair.ps1"
& "$PSScriptRoot\developer_b\validate_husbandry.ps1"
& "$PSScriptRoot\developer_b\validate_ranch.ps1"

function Invoke-GodotTest {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    & $Godot --headless --path "$PSScriptRoot\.." --script $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Godot test failed: $ScriptPath (exit $LASTEXITCODE)"
    }
}

Invoke-GodotTest 'res://tests/developer_a/core_smoke_test.gd'
Invoke-GodotTest 'res://tests/developer_b/run_tests.gd'
Invoke-GodotTest 'res://tests/qa/integration_regression.gd'
Invoke-GodotTest 'res://tests/qa/input_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/movement_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/physics_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/block_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/block_texture_regression.gd'
Invoke-GodotTest 'res://tests/qa/first_person_viewmodel_regression.gd'
Invoke-GodotTest 'res://tests/qa/furnace_machine_regression.gd'
Invoke-GodotTest 'res://tests/qa/tool_harvest_regression.gd'
Invoke-GodotTest 'res://tests/qa/equipment_combat_regression.gd'
Invoke-GodotTest 'res://tests/qa/combat_cadence_regression.gd'
Invoke-GodotTest 'res://tests/qa/agriculture_regression.gd'
Invoke-GodotTest 'res://tests/qa/irrigation_multicrop_regression.gd'
Invoke-GodotTest 'res://tests/qa/fertilizer_regression.gd'
Invoke-GodotTest 'res://tests/qa/rest_respawn_regression.gd'
Invoke-GodotTest 'res://tests/qa/repair_regression.gd'
Invoke-GodotTest 'res://tests/qa/husbandry_regression.gd'
Invoke-GodotTest 'res://tests/qa/ranch_products_regression.gd'
Invoke-GodotTest 'res://tests/qa/tutorial_placement_regression.gd'
Invoke-GodotTest 'res://tests/qa/placement_preview_regression.gd'
Invoke-GodotTest 'res://tests/qa/desktop_input_contract_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_diagnostics_regression.gd'
Invoke-GodotTest 'res://tests/qa/player_experience_regression.gd'
Invoke-GodotTest 'res://tests/qa/ui_layout_regression.gd'
Invoke-GodotTest 'res://tests/qa/visual_acceptance_regression.gd'
Invoke-GodotTest 'res://tests/qa/adaptive_streaming_regression.gd'
Invoke-GodotTest 'res://tests/qa/audio_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_stability_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_soak_regression.gd'
Invoke-GodotTest 'res://tests/qa/settings_retest.gd'

Write-Host 'PASS: data registry + block visuals + first-person viewmodel + Godot runtime checks'
