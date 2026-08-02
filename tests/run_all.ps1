param(
    [string]$Godot = $env:GODOT_BIN
)

$ErrorActionPreference = 'Continue'
$failedTests = [System.Collections.Generic.List[string]]::new()
$passedTests = 0

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
& "$PSScriptRoot\developer_b\validate_world_catalog.ps1"
& "$PSScriptRoot\developer_b\validate_save_recovery.ps1"
& "$PSScriptRoot\developer_b\validate_crash_safe_session_recovery.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_multi_world_recovery.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_catalog_rebuild.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_authoritative_reads.ps1"
& "$PSScriptRoot\developer_b\validate_transient_catalog_stage.ps1"
& "$PSScriptRoot\developer_b\validate_virtualized_save_browser.ps1"
& "$PSScriptRoot\developer_b\validate_indexed_save_browser.ps1"
& "$PSScriptRoot\developer_b\validate_protected_save_deletion.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_trash_manager.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_autosave.ps1"
& "$PSScriptRoot\developer_b\validate_autosave_long_session.ps1"
& "$PSScriptRoot\developer_b\validate_save_checkpoint_timeline.ps1"
& "$PSScriptRoot\developer_b\validate_world_scoped_save_checkpoint_sessions.ps1"
& "$PSScriptRoot\developer_b\validate_runtime_health_report.ps1"
& "$PSScriptRoot\developer_b\validate_runtime_health_sources.ps1"
& "$PSScriptRoot\developer_b\validate_ui_design_system.ps1"
& "$PSScriptRoot\developer_b\validate_ui_accessibility.ps1"
& "$PSScriptRoot\developer_b\validate_controller_gameplay.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_ranged_combat.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_firearms.ps1"
& "$PSScriptRoot\developer_b\validate_machine_base.ps1"
& "$PSScriptRoot\developer_b\validate_stonecutter_machine.ps1"
& "$PSScriptRoot\developer_b\validate_machine_capability.ps1"
& "$PSScriptRoot\developer_b\validate_machine_automation.ps1"
& "$PSScriptRoot\developer_b\validate_machine_scale.ps1"
& "$PSScriptRoot\developer_b\validate_auto_update.ps1"
& "$PSScriptRoot\developer_b\validate_resource_distribution.ps1"
& "$PSScriptRoot\developer_b\validate_world_decoration_registry.ps1"
& "$PSScriptRoot\developer_b\validate_world_decoration_hot_path.ps1"
& "$PSScriptRoot\developer_b\validate_prospecting.ps1"
& "$PSScriptRoot\developer_b\validate_ecology_danger.ps1"
& "$PSScriptRoot\developer_b\validate_multi_hostile_danger.ps1"
& "$PSScriptRoot\developer_b\validate_multi_hostile_arena_batch.ps1"
& "$PSScriptRoot\developer_b\validate_pickup_stacks.ps1"
& "$PSScriptRoot\developer_b\validate_pickup_shared_runtime.ps1"
& "$PSScriptRoot\developer_b\validate_hostile_attacks.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_hostile_ranged.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_hostile_encounters.ps1"
& "$PSScriptRoot\developer_b\validate_bounded_encounter_rewards.ps1"
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
& "$PSScriptRoot\developer_b\validate_structural_integrity.ps1"
& "$PSScriptRoot\developer_b\validate_structural_single_flush.ps1"
& "$PSScriptRoot\developer_b\validate_world_mutation_batch.ps1"
& "$PSScriptRoot\developer_b\validate_recent_chunk_cache.ps1"
& "$PSScriptRoot\developer_b\validate_fertilizers.ps1"
& "$PSScriptRoot\developer_b\validate_rest.ps1"
& "$PSScriptRoot\developer_b\validate_repair.ps1"
& "$PSScriptRoot\developer_b\validate_husbandry.ps1"
& "$PSScriptRoot\developer_b\validate_husbandry_lifecycle.ps1"
& "$PSScriptRoot\developer_b\validate_ranch.ps1"
& "$PSScriptRoot\developer_b\validate_ranch_lifecycle.ps1"

$script:failedTests = [System.Collections.Generic.List[string]]::new()
$script:passedCount = 0
$script:failedCount = 0

function Invoke-GodotTest {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    try {
        & "$PSScriptRoot\ci\Invoke-Godot.ps1" -Godot $Godot -Arguments "--headless --path . --script $ScriptPath -- --disable-update-check"
        $script:passedCount++
        Write-Host "PASS $name"
    } catch {
        $script:failedCount++
        $script:failedTests.Add("$name : $($_.Exception.Message)")
        Write-Host "FAIL $name : $($_.Exception.Message)"
    }
}

function Report-TestSummary {
    $total = $script:passedCount + $script:failedCount
    Write-Host ''
    Write-Host "============================================"
    Write-Host "RUN_ALL SUMMARY: $script:passedCount / $total passed"
    if ($script:failedTests.Count -gt 0) {
        Write-Host ''
        Write-Host "FAILURES:"
        foreach ($f in $script:failedTests) {
            Write-Host "  - $f"
        }
        Write-Host ''
        Write-Host "EXIT: 1 ($($script:failedTests.Count) test(s) failed)"
        exit 1
    }
    Write-Host "EXIT: 0 (all tests passed)"
    exit 0
}

Invoke-GodotTest 'res://tests/developer_a/core_smoke_test.gd'
Invoke-GodotTest 'res://tests/developer_b/run_tests.gd'
Invoke-GodotTest 'res://tests/qa/integration_regression.gd'
Invoke-GodotTest 'res://tests/qa/input_interaction_regression.gd'
Invoke-GodotTest 'res://tests/qa/movement_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/controller_gameplay_regression.gd'
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
Invoke-GodotTest 'res://tests/qa/world_decoration_registry_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_decoration_hot_path_regression.gd'
Invoke-GodotTest 'res://tests/qa/prospecting_regression.gd'
Invoke-GodotTest 'res://tests/qa/ecology_danger_regression.gd'
Invoke-GodotTest 'res://tests/qa/multi_hostile_arena_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/multi_hostile_danger_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/exploration_journal_regression.gd'
Invoke-GodotTest 'res://tests/qa/exploration_milestone_reward_regression.gd'
Invoke-GodotTest 'res://tests/qa/map_signature_prospecting_regression.gd'
Invoke-GodotTest 'res://tests/qa/service_hub_feature_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/bounded_autosave_runtime_regression.gd'
Invoke-GodotTest 'res://tests/qa/autosave_deferred_pause_race_regression.gd'
Invoke-GodotTest 'res://tests/qa/autosave_long_session_endurance_regression.gd'
Invoke-GodotTest 'res://tests/qa/save_checkpoint_timeline_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_scoped_save_checkpoint_session_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_session_recovery_regression.gd'
Invoke-GodotTest 'res://tests/qa/graceful_application_quit_regression.gd'
Invoke-GodotTest 'res://tests/qa/session_recovery_ui_regression.gd'
Invoke-GodotTest 'res://tests/qa/agriculture_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/agriculture_scale_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/husbandry_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/ranch_runtime_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/glass_pane_regression.gd'
Invoke-GodotTest 'res://tests/qa/connected_block_shapes_regression.gd'
Invoke-GodotTest 'res://tests/qa/double_door_regression.gd'
Invoke-GodotTest 'res://tests/qa/directional_ladder_regression.gd'
Invoke-GodotTest 'res://tests/qa/structural_integrity_desktop_import_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_mutation_pre_flush_regression.gd'
Invoke-GodotTest 'res://tests/qa/structural_integrity_batched_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_mutation_batch_regression.gd'
Invoke-GodotTest 'res://tests/qa/recent_chunk_snapshot_cache_regression.gd'
Invoke-GodotTest 'res://tests/qa/world_catalog_regression.gd'
Invoke-GodotTest 'res://tests/qa/save_recovery_regression.gd'
Invoke-GodotTest 'res://tests/qa/save_load_matrix_regression.gd'
Invoke-GodotTest 'res://tests/qa/bounded_multi_world_recovery_regression.gd'
Invoke-GodotTest 'res://tests/qa/bounded_catalog_rebuild_regression.gd'
Invoke-GodotTest 'res://tests/qa/bounded_authoritative_read_regression.gd'
Invoke-GodotTest 'res://tests/qa/catalog_stage_invalidation_regression.gd'
Invoke-GodotTest 'res://tests/qa/save_browser_virtualization_regression.gd'
Invoke-GodotTest 'res://tests/qa/save_browser_query_policy_regression.gd'
Invoke-GodotTest 'res://tests/qa/indexed_save_browser_regression.gd'
Invoke-GodotTest 'res://tests/qa/protected_save_service_regression.gd'
Invoke-GodotTest 'res://tests/qa/protected_save_browser_regression.gd'
Invoke-GodotTest 'res://tests/qa/trash_manager_service_regression.gd'
Invoke-GodotTest 'res://tests/qa/trash_manager_panel_regression.gd'
Invoke-GodotTest 'res://tests/qa/block_texture_regression.gd'
Invoke-GodotTest 'res://tests/qa/non_cube_block_geometry_regression.gd'
Invoke-GodotTest 'res://tests/qa/directional_stair_regression.gd'
Invoke-GodotTest 'res://tests/qa/first_person_viewmodel_regression.gd'
Invoke-GodotTest 'res://tests/qa/mining_crack_feedback_regression.gd'
Invoke-GodotTest 'res://tests/qa/furnace_machine_regression.gd'
Invoke-GodotTest 'res://tests/qa/tool_harvest_regression.gd'
Invoke-GodotTest 'res://tests/qa/equipment_combat_regression.gd'
Invoke-GodotTest 'res://tests/qa/combat_cadence_regression.gd'
Invoke-GodotTest 'res://tests/qa/ranged_combat_registry_regression.gd'
Invoke-GodotTest 'res://tests/qa/ranged_combat_runtime_regression.gd'
Invoke-GodotTest 'res://tests/qa/firearm_registry_regression.gd'
Invoke-GodotTest 'res://tests/qa/firearm_runtime_regression.gd'
Invoke-GodotTest 'res://tests/qa/hostile_attack_windup_regression.gd'
Invoke-GodotTest 'res://tests/qa/hostile_ranged_encounter_regression.gd'
Invoke-GodotTest 'res://tests/qa/hostile_encounter_director_regression.gd'
Invoke-GodotTest 'res://tests/qa/encounter_reward_economy_regression.gd'
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
Invoke-GodotTest 'res://tests/qa/spawn_experience_regression.gd'
Invoke-GodotTest 'res://tests/qa/collision_seam_probe_regression.gd'
Invoke-GodotTest 'res://tests/qa/profile_release_journey_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_health_source_projection_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_health_report_policy_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_health_report_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_health_failed_return_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_diagnostics_regression.gd'
Invoke-GodotTest 'res://tests/qa/player_experience_regression.gd'
Invoke-GodotTest 'res://tests/qa/ui_layout_regression.gd'
Invoke-GodotTest 'res://tests/qa/ui_design_system_regression.gd'
Invoke-GodotTest 'res://tests/qa/menu_keyboard_navigation_regression.gd'
Invoke-GodotTest 'res://tests/qa/ui_accessibility_regression.gd'
Invoke-GodotTest 'res://tests/qa/visual_acceptance_regression.gd'
Invoke-GodotTest 'res://tests/qa/adaptive_streaming_regression.gd'
Invoke-GodotTest 'res://tests/qa/audio_lifecycle_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_stability_regression.gd'
Invoke-GodotTest 'res://tests/qa/runtime_soak_regression.gd'
Invoke-GodotTest 'res://tests/qa/settings_retest.gd'

Report-TestSummary
