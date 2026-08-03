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
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not $Content.Contains($Needle)) {
        $script:failures.Add("$Description (missing: $Needle)")
    }
}

function Require-NotContains {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if ($Content.Contains($Needle)) {
        $script:failures.Add("$Description (forbidden: $Needle)")
    }
}

function Require-MinimumOccurrences {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][int]$Minimum,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $count = ([regex]::Matches($Content, [regex]::Escape($Needle))).Count
    if ($count -lt $Minimum) {
        $script:failures.Add("$Description (expected >= $Minimum, found ${count}: $Needle)")
    }
}

$panel = Read-RepoFile 'src/ui/stonecutter_panel.gd'
$desktop = Read-RepoFile 'tests/qa/stonecutter_machine_desktop_acceptance.gd'
$domain = Read-RepoFile 'tests/qa/stonecutter_machine_regression.gd'
$workflow = Read-RepoFile '.github/workflows/player-stonecutter-closed-loop-tests.yml'
$matrix = Read-RepoFile 'qa/content-journey-matrix.md'
$issues = Read-RepoFile 'qa/issues-found.md'

Require-Contains $panel 'func get_visual_snapshot() -> Dictionary:' 'Stonecutter UI must expose auditable visual state'
Require-Contains $panel 'func get_machine_slot_button(slot_name: String) -> Button:' 'Stonecutter UI must expose stable machine controls'
Require-Contains $panel 'func get_inventory_button(index: int) -> Button:' 'Stonecutter UI must expose stable inventory controls'
Require-Contains $panel 'button.set_meta("target_id", _machine_slot_target_id(slot_name))' 'Machine slots must publish stable target identity'
Require-Contains $panel 'slot.set_meta("target_id", _inventory_target_id(index))' 'Inventory controls must publish stable target identity'
Require-Contains $panel 'stonecutter_service.item_transferred.connect(_on_item_transferred)' 'Successful transfers must use the production signal feedback path'
Require-Contains $panel 'stonecutter_service.item_processed.connect(_on_item_processed)' 'Processing completion must use the production signal feedback path'
Require-Contains $panel 'stonecutter_service.transfer_rejected.connect(_on_transfer_rejected)' 'Rejected transfers must use the production signal feedback path'
Require-Contains $panel 'if not transferred and _feedback_revision == revision_before:' 'Generic fallback may only run when the service emitted no exact result'
Require-Contains $panel '"inventory_full": "背包空间不足，切割产出仍安全保留在机器中"' 'Full inventory feedback must explicitly promise output conservation'
Require-Contains $panel '_pending_action_target_id' 'Exact rejection feedback must retain the clicked target identity'
Require-NotContains $panel '_status.text = "该物品不能切割，或原料槽没有空间"' 'Generic input failure must not overwrite exact service feedback'
Require-NotContains $panel '_status.text = "槽位为空，或背包没有足够空间"' 'Generic output failure must not overwrite exact service feedback'

Require-Contains $desktop 'GameScene.instantiate()' 'Stonecutter desktop evidence must load the production game scene'
Require-Contains $desktop 'world.call("set_block", cutter_position, "stonecutter")' 'Stonecutter desktop evidence must place a real production voxel'
Require-Contains $desktop 'await _right_click_center()' 'Stonecutter entry must use a real secondary-action click'
Require-Contains $desktop '_focus_hits_block(player, cutter_position)' 'Stonecutter entry must resolve the production center ray'
Require-Contains $desktop 'await _click_control(apple_button)' 'Unsupported-item failure must use a real pointer control'
Require-Contains $desktop 'unsupported real pointer input cannot mutate either machine slot' 'Unsupported input must prove machine atomicity'
Require-Contains $desktop 'exact service rejection remains visible instead of being overwritten by generic UI text' 'Desktop evidence must catch the feedback-overwrite defect'
Require-Contains $desktop 'full-inventory output failure keeps all slabs safely inside the machine' 'Full inventory failure must prove output conservation'
Require-Contains $desktop 'world.json retains the uncollected slab output exactly once' 'Pending machine output must enter the authoritative save'
Require-Contains $desktop 'return to menu clears the machine session and stops shared scheduling' 'Stonecutter journey must close the original runtime session'
Require-Contains $desktop 'saved pending-output world reloads through production composition' 'Stonecutter journey must fully reload pending output'
Require-Contains $desktop 'moving streaming focus beyond the unload radius removes the real machine chunk' 'Stonecutter journey must exercise a real chunk unload'
Require-Contains $desktop 'chunk unload preserves authoritative machine identity and pending output' 'Chunk unload must preserve machine state'
Require-Contains $desktop 'chunk reload restores the real voxel while retaining exact machine output' 'Chunk reload must restore the voxel without state drift'
Require-Contains $desktop 'two complete reloads never replay the original processing or summary events' 'Reload must not replay historical completion events'
Require-Contains $desktop 'collected-result world completes a second production reload' 'Collected output must receive a second no-duplication reload'
Require-Contains $desktop 'second reload preserves slab conservation without duplicated output or resurrected stone' 'Final reload must prove exact conservation'
Require-Contains $desktop '_save_image(image)' 'Stonecutter journey must retain visual evidence'
Require-Contains $desktop 'quit(0)' 'Successful desktop journey must terminate cleanly'
Require-Contains $desktop 'quit(1)' 'Failed desktop journey must terminate non-zero'
Require-NotContains $desktop 'block_interaction.interact(' 'Desktop journey may not bypass player focus and right-click entry'

Require-Contains $domain 'stonecutter loads three production recipes' 'Stonecutter domain regression must retain recipe coverage'
Require-Contains $domain 'stonecutter snapshot exposes deterministic queue ETA' 'Stonecutter domain regression must retain deterministic queue telemetry'
Require-Contains $domain 'one scheduler tick advances both production machine domains' 'Shared scheduler regression must retain cross-domain advancement'
Require-Contains $domain 'production save preserves stonecutter state' 'Stonecutter domain regression must retain save integration'

Require-Contains $workflow 'validate_stonecutter_closed_loop.ps1' 'Stonecutter contract must run in dedicated CI'
Require-Contains $workflow 'stonecutter_machine_regression.gd' 'Stonecutter domain regression must run in dedicated CI'
Require-Contains $workflow 'stonecutter_machine_desktop_acceptance.gd' 'Stonecutter desktop journey must run in dedicated CI'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Stonecutter gate must reuse the authoritative runner'
Require-Contains $workflow 'furnace_desktop_acceptance.gd' 'Shared machine changes must re-review the adjacent furnace journey'
Require-Contains $workflow 'permissions:' 'Stonecutter gate must declare explicit permissions'
Require-Contains $workflow 'contents: read' 'Stonecutter gate must remain read-only'
Require-Contains $workflow 'cancel-in-progress: true' 'Stonecutter gate must cancel stale branch runs'
Require-Contains $workflow 'pull_request:' 'Stonecutter gate must run for relevant pull requests'
Require-Contains $workflow 'push:' 'Stonecutter gate must rerun after merge to master'
Require-MinimumOccurrences $workflow "      - 'src/machine/**'" 2 'Shared machine changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'src/ui/**'" 2 'Shared UI changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'scenes/ui/**'" 2 'Shared UI scenes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'tests/ci/run_godot_desktop_test.ps1'" 2 'Desktop runner changes must trigger both pull-request and master-push gates'

Require-Contains $matrix '| 切石机 | 是 | **真实中心射线与右键切石机**' 'Content matrix must record the real stonecutter player entry'
Require-Contains $matrix '**E3 闭环**' 'Content matrix must classify stonecutter without claiming final-export E4'
Require-Contains $matrix 'BUG-QA-CONTENT-001` 仍未关闭' 'Completing stonecutter must not overclaim all content as complete'
Require-Contains $issues 'BUG-QA-CONTENT-STONECUTTER-001' 'Issue register must retain the stonecutter evidence defect and fix'

if ($failures.Count -gt 0) {
    Write-Host 'PLAYER STONECUTTER CLOSED LOOP CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'PLAYER STONECUTTER CLOSED LOOP CONTRACT PASS'
Write-Host '  - real voxel focus, right-click entry and pointer controls are retained'
Write-Host '  - stable machine and inventory target identities are retained'
Write-Host '  - production signals remain the single exact feedback source'
Write-Host '  - unsupported input and full-inventory output failures remain atomic'
Write-Host '  - pending and collected output survive authoritative save and double reload'
Write-Host '  - chunk unload/reload cannot lose or duplicate machine state'
Write-Host '  - adjacent furnace and symmetric permanent CI coverage are retained'
exit 0
