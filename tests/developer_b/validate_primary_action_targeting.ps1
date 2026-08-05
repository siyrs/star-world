$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepoFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $repoRoot ($RelativePath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path)) {
        $script:failures.Add("Missing required file: $RelativePath")
        return ''
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Require-Contains {
    param([string]$Content, [string]$Needle, [string]$Description)
    if (-not $Content.Contains($Needle)) {
        $script:failures.Add("$Description (missing: $Needle)")
    }
}

function Require-NotContains {
    param([string]$Content, [string]$Needle, [string]$Description)
    if ($Content.Contains($Needle)) {
        $script:failures.Add("$Description (forbidden: $Needle)")
    }
}

$harvestPlayer = Read-RepoFile 'src/player/harvest_enabled_player.gd'
$precisionPlayer = Read-RepoFile 'src/player/precision_interaction_player.gd'
$controllerPlayer = Read-RepoFile 'src/player/controller_exploration_player.gd'
$tutorialJourney = Read-RepoFile 'tests/qa/tutorial_placement_stable_desktop_acceptance.gd'

Require-Contains $harvestPlayer 'func set_primary_action_active(' 'Mouse and controller input must share one held primary-action state machine'
Require-Contains $harvestPlayer 'var target := _resolve_harvest_target()' 'Primary-action startup must use the virtual authoritative target resolver'
Require-Contains $harvestPlayer 'if _refresh_interaction_ray():' 'Physical ray targeting must remain available for entity attacks'
Require-Contains $harvestPlayer 'collider.has_method("take_damage")' 'Entity attacks must remain gated by a live physics collider'
Require-Contains $harvestPlayer '_advance_resolved_harvest(target, 0.0)' 'A resolved voxel target must start the production harvest transaction without a second target lookup'
Require-NotContains $harvestPlayer "if not _refresh_interaction_ray():\n\t\t_primary_action_held = false\n\t\t_cancel_harvest(\"no_target\")" 'A transiently empty physics ray must not reject a valid virtual voxel target'

Require-Contains $precisionPlayer 'target_resolver.call("resolve", interaction_ray, world)' 'Precision player must retain deterministic grid-ray fallback targeting'
Require-Contains $precisionPlayer 'func _resolve_harvest_target() -> Dictionary:' 'Precision player must override the harvest target policy'
Require-Contains $controllerPlayer 'set_primary_action_active(true)' 'Controller press must enter the shared production primary-action state'
Require-Contains $controllerPlayer 'set_primary_action_active(false, reason)' 'Controller release must cancel the shared production action state'
Require-NotContains $controllerPlayer '_primary_action_held = true' 'Controller code must not mutate a parallel inherited held-state directly'

Require-Contains $tutorialJourney 'Input.action_press(InputActions.PRIMARY_ACTION' 'Cross-session tutorial evidence must start mining through the production primary action'
Require-Contains $tutorialJourney 'root.get_camera_3d()' 'Reloaded tutorial targeting must resolve the active production camera/player identity'
Require-Contains $tutorialJourney 'Time.get_ticks_msec() + HARVEST_TIMEOUT_MILLISECONDS' 'Held mining evidence must use an elapsed-time bound rather than a CI-frame-count assumption'

if ($failures.Count -gt 0) {
    Write-Host 'PRIMARY ACTION TARGETING CONTRACT FAIL'
    foreach ($failure in $failures) { Write-Host "  - $failure" }
    exit 1
}

Write-Host 'PRIMARY ACTION TARGETING CONTRACT PASS'
Write-Host '  - mouse and controller share one primary-action lifecycle'
Write-Host '  - entity attacks remain physics-collider based'
Write-Host '  - valid precision voxel targets survive transient chunk-collision rebuild gaps'
Write-Host '  - the cross-session tutorial exercises the production action path'
exit 0
