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
& "$PSScriptRoot\developer_b\validate_catalog_integrity.ps1"
& "$PSScriptRoot\developer_b\validate_reusable_ci_workflows.ps1"
& "$PSScriptRoot\developer_b\validate_machine_base.ps1"
& "$PSScriptRoot\developer_b\validate_stonecutter_machine.ps1"
& "$PSScriptRoot\developer_b\validate_machine_capability.ps1"
& "$PSScriptRoot\developer_b\validate_machine_automation.ps1"
& "$PSScriptRoot\developer_b\validate_machine_scale.ps1"
& "$PSScriptRoot\developer_b\validate_auto_update.ps1"
& "$PSScriptRoot\developer_b\validate_resource_distribution.ps1"
& "$PSScriptRoot\developer_b\validate_prospecting.ps1"
& "$PSScriptRoot\developer_b\validate_ecology_danger.ps1"
& "$PSScriptRoot\developer_b\validate_multi_hostile_danger.ps1"
& "$PSScriptRoot\developer_b\validate_pickup_stacks.ps1"
& "$PSScriptRoot\developer_b\validate_pickup_shared_runtime.ps1"
& "$PSScriptRoot\developer_b\validate_hostile_attacks.ps1"
& "$PSScriptRoot\developer_b\validate_abyss_elite.ps1"
& "$PSScriptRoot\developer_b\validate_exploration_journal.ps1"
& "$PSScriptRoot\developer_b\validate_exploration_rewards.ps1"
& "$PSScriptRoot\developer_b\validate_map_signature_prospecting.ps1"
& "$PSScriptRoot\developer_b\validate_service_hub_lifecycle.ps1"
& "$PSScriptRoot\developer_b\validate_agriculture_runtime.ps1"
& "$PSScriptRoot\developer_b\validate_agriculture_scale.ps1"
& "$PSScriptRoot\developer_b\validate_block_visuals.ps1"
& "$PSScriptRoot\developer_b\validate_connected_block_shapes.ps1"
& "$PSScriptRoot\developer_b\validate_double_doors.ps1"
& "$PSScriptRoot\developer_b\validate_directional_ladders.ps1"
& "$PSScriptRoot\developer_b\validate_world_mutation_batch.ps1"
& "$PSScriptRoot\developer_b\validate_recent_chunk_cache.ps1"
& "$PSScriptRoot\developer_b\validate_fertilizers.ps1"
& "$PSScriptRoot\developer_b\validate_rest.ps1"
& "$PSScriptRoot\developer_b\validate_repair.ps1"
& "$PSScriptRoot\developer_b\validate_husbandry.ps1"
& "$PSScriptRoot\developer_b\validate_husbandry_lifecycle.ps1"
& "$PSScriptRoot\developer_b\validate_ranch.ps1"
& "$PSScriptRoot\developer_b\validate_ranch_lifecycle.ps1"

function Invoke-GodotTest {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    # Route through Invoke-Godot.ps1: GUI-subsystem Godot binaries are not
    # awaited by PowerShell, which would fake-pass this suite (and would also
    # drop the user-arg flag unless it follows a literal `--`).
    & "$PSScriptRoot\ci\Invoke-Godot.ps1" -Godot $Godot -Arguments "--headless --path . --script $ScriptPath -- --disable-update-check"
}

Invoke-GodotTest 'res://tests/developer_a/core_smoke_test.gd'
Invoke-GodotTest 'res://tests/developer_b/run_tests.gd'
Invoke-GodotTest 'res://tests/qa/integration_regression.gd'
Invoke-GodotTest 'res://tests/qa/input_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/movement_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/physics_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/pickup_stack_regression.gd'
Invoke-GodotTest 'res://tests/qa/pickup_shared_runtime_regression.gd'
Invoke-GodotTest 'res://tests/qa/block_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/inventory_transaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/machine_base_regression.gd'
Invoke-GodotTest 'res://tests/qa/stonecutter_machine_regression.gd'
Invoke-GodotTest 'res://tests/qa/machine_capability_regression.gd'
Invoke-GodotTest 'res://tests/qa/machine_automation_regression.gd'
Invoke-GodotTest 'res://tests/qa/machine_scale_runtime_regression.gd'
Invoke-GodotTest 'res://tests/qa/auto_update_regression.gd'
Invoke-GodotTest 'res://tests/qa/resource_distribution_regression.gd'
Invoke-GodotTest 'res://tests/qa/prospecting_regression.gd'
Invoke-GodotTest 'res://tests/qa/ecology_danger_regression.gd'
Invoke-GodotTest 'res://tests/qa/multi_hostile_danger_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/exploration_journal_regression.gd'
Invoke-GodotTest 'res://tests/qa/exploration_milestone_reward_regression.gd'
Invoke-GodotTest 'res://tests/qa/map_signature_prospecting_regression.gd'
Invoke-GodotTest 'res://tests/qa/service_hub_feature_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/agriculture_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/agriculture_scale_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/husbandry_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/ranch_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/glass_pane_regression.gd'
Invoke-GodotTest 'res://tests/qa/connected_block_shapes_regression.gd'
Invoke-GodotTest 'res://tests/qa/double_door_regression.gd'
Invoke-GodotTest 'res://tests/qa/directional_ladder_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_mutation_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/recent_chunk_snapshot_cache_regression.gd'
Invoke-GodotTest 'res://tests/qa/block_texture_regression.gd'
Invoke-GodotTest 'res://tests/qa/non_cube_block_geometry_regression.gd'
Invoke-GodotTest 'res://tests/qa/directional_stair_regression.gd'
Invoke-GodotTest 'res://tests/qa/first_person_viewmodel_regression.gd'
Invoke-GodotTest 'res://tests/qa/mining_crack_feedback_regression.gd'
Invoke-GodotTest 'res://tests/qa/furnace_machine_regression.gd'
Invoke-GodotTest 'res://tests/qa/tool_harvest_regression.gd'
Invoke-GodotTest 'res://tests/qa/equipment_combat_regression.gd'
Invoke-GodotTest 'res://tests/qa/combat_cadence_regression.gd'
Invoke-GodotTest 'res://tests/qa/hostile_attack_windup_regression.gd'
Invoke-GodotTest 'res://tests/qa/abyss_elite_regression.gd'
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

Write-Host 'PASS: reusable Godot CI + shared pickup runtime + bounded stacks + recent chunk snapshots + machine scale + agriculture scale + bounded world mutations + directional building + lifecycle + release-safe runtime checks'
