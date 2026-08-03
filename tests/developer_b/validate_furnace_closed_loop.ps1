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

function Require-CountAtLeast {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][int]$Minimum,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $count = [regex]::Matches($Content, [regex]::Escape($Needle)).Count
    if ($count -lt $Minimum) {
        $script:failures.Add(
            "$Description (found: $count, expected at least: $Minimum, token: $Needle)"
        )
    }
}

$panel = Read-RepoFile 'src/ui/furnace_panel.gd'
$desktop = Read-RepoFile 'tests/qa/furnace_desktop_acceptance.gd'
$domain = Read-RepoFile 'tests/qa/furnace_machine_regression.gd'
$workflow = Read-RepoFile '.github/workflows/player-furnace-closed-loop-tests.yml'
$matrix = Read-RepoFile 'qa/content-journey-matrix.md'

Require-Contains $panel 'func get_visual_snapshot() -> Dictionary:' 'Furnace UI must expose auditable visual state'
Require-Contains $panel 'func get_machine_slot_button(slot_name: String) -> Button:' 'Furnace UI must expose stable machine controls'
Require-Contains $panel 'func get_inventory_button(index: int) -> Button:' 'Furnace UI must expose stable inventory controls'
Require-Contains $panel 'button.set_meta("target_id", _machine_slot_target_id(slot_name))' 'Machine slots must publish stable target identity'
Require-Contains $panel 'slot.set_meta("target_id", _inventory_target_id(index))' 'Inventory controls must publish stable target identity'
Require-Contains $panel 'furnace_service.item_transferred.connect(_on_item_transferred)' 'Successful transfers must use the production signal feedback path'
Require-Contains $panel 'furnace_service.item_smelted.connect(_on_item_smelted)' 'Smelting completion must use the production signal feedback path'
Require-Contains $panel 'furnace_service.transfer_rejected.connect(_on_transfer_rejected)' 'Rejected transfers must use the production signal feedback path'
Require-Contains $panel 'if not transferred and _feedback_revision == revision_before:' 'Generic fallback may only run when the service emitted no exact result'
Require-Contains $panel '"inventory_full": "背包空间不足，产出仍安全保留在熔炉中"' 'Full inventory feedback must explicitly promise output conservation'
Require-NotContains $panel '_status.text = "该物品不能投入，或目标槽位没有空间"' 'Generic input failure must not overwrite exact service feedback'
Require-NotContains $panel '_status.text = "槽位为空，或背包没有足够空间"' 'Generic output failure must not overwrite exact service feedback'

Require-Contains $desktop 'GameScene.instantiate()' 'Furnace desktop evidence must load the production game scene'
Require-Contains $desktop 'world.call("set_block", furnace_position, "furnace")' 'Furnace desktop evidence must place a real production voxel'
Require-Contains $desktop 'await _right_click_center()' 'Furnace entry must use a real secondary-action click'
Require-Contains $desktop '_focus_hits_block(player, furnace_position)' 'Furnace entry must resolve the production center ray'
Require-Contains $desktop 'await _click_control(apple_button)' 'Unsupported-item failure must use a real pointer control'
Require-Contains $desktop 'unsupported real pointer input cannot mutate any machine slot' 'Unsupported input must prove machine atomicity'
Require-Contains $desktop 'service rejection remains visible instead of being overwritten by generic UI text' 'Desktop evidence must catch the original feedback-overwrite defect'
Require-Contains $desktop 'full-inventory output failure keeps the ingot safely inside the furnace' 'Full inventory failure must prove output conservation'
Require-Contains $desktop 'world.json retains the uncollected furnace output exactly once' 'Pending machine output must enter the authoritative save'
Require-Contains $desktop 'return to menu clears the furnace session and stops machine scheduling' 'Furnace journey must close the original runtime session'
Require-Contains $desktop 'saved pending-output world reloads through production composition' 'Furnace journey must fully reload pending output'
Require-Contains $desktop 'reload does not replay historical smelting completion feedback' 'Reload must not replay historical completion events'
Require-Contains $desktop 'collected-result world completes a second production reload' 'Collected output must receive a second no-duplication reload'
Require-Contains $desktop 'second reload preserves conservation without duplicated output or resurrected inputs' 'Final reload must prove exact conservation'
Require-Contains $desktop '_save_image(image)' 'Furnace journey must retain visual evidence'
Require-Contains $desktop 'quit(0)' 'Successful desktop journey must terminate cleanly'
Require-Contains $desktop 'quit(1)' 'Failed desktop journey must terminate non-zero'
Require-NotContains $desktop 'block_interaction.interact(' 'Desktop journey may not bypass player focus and right-click entry'

Require-Contains $domain 'one coal processes eight iron items through elapsed-time simulation' 'Furnace domain regression must retain batch-processing conservation'
Require-Contains $domain 'a full output slot pauses work without consuming input or fuel' 'Furnace domain regression must retain blocked-output atomicity'
Require-Contains $domain 'service hub saves furnace state in the world transaction' 'Furnace domain regression must retain save integration'

Require-Contains $workflow 'validate_furnace_closed_loop.ps1' 'Furnace contract must run in dedicated CI'
Require-Contains $workflow 'furnace_machine_regression.gd' 'Furnace domain regression must run in dedicated CI'
Require-Contains $workflow 'furnace_desktop_acceptance.gd' 'Furnace desktop journey must run in dedicated CI'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Furnace gate must reuse the authoritative runner'
Require-Contains $workflow 'stonecutter_machine_desktop_acceptance.gd' 'Shared machine changes must re-review the adjacent stonecutter journey'
Require-Contains $workflow 'pull_request:' 'Furnace gate must run for relevant pull requests'
Require-Contains $workflow 'push:' 'Furnace gate must rerun after merge to master'
Require-Contains $workflow 'permissions:' 'Furnace workflow must declare an explicit permission boundary'
Require-Contains $workflow 'contents: read' 'Furnace workflow must remain read-only'
Require-Contains $workflow 'cancel-in-progress: true' 'Furnace workflow must cancel superseded branch runs'
foreach ($pathToken in @(
    "'.github/workflows/reusable-godot-quality-gate.yml'",
    "'data/items.json'",
    "'scenes/game/**'",
    "'scenes/ui/**'",
    "'src/input/**'",
    "'src/interaction/**'",
    "'src/inventory/**'",
    "'src/machine/**'",
    "'src/save/**'",
    "'src/ui/**'",
    "'src/world/**'",
    "'tests/ci/Invoke-Godot.ps1'",
    "'tests/ci/run_godot_headless_test.ps1'",
    "'tests/ci/run_godot_desktop_test.ps1'",
    "'tests/qa/furnace_machine_regression.gd'",
    "'tests/qa/furnace_desktop_acceptance.gd'",
    "'tests/qa/stonecutter_machine_desktop_acceptance.gd'"
)) {
    Require-CountAtLeast `
        $workflow `
        $pathToken `
        2 `
        "Pull-request and master-push triggers must both cover shared dependency $pathToken"
}

Require-Contains $matrix '| 熔炉 | 是 | **真实中心射线与右键熔炉**' 'Content matrix must record the real furnace player entry'
Require-Contains $matrix '**E3 闭环**' 'Content matrix must classify furnace without claiming final-export E4'
Require-Contains $matrix 'BUG-QA-CONTENT-001` 仍未关闭' 'Completing furnace must not overclaim all content as complete'

if ($failures.Count -gt 0) {
    Write-Host 'PLAYER FURNACE CLOSED LOOP CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'PLAYER FURNACE CLOSED LOOP CONTRACT PASS'
Write-Host '  - real voxel focus, right-click entry and pointer controls are retained'
Write-Host '  - stable machine and inventory target identities are retained'
Write-Host '  - production signals remain the single exact feedback source'
Write-Host '  - unsupported input and full-inventory output failures remain atomic'
Write-Host '  - pending and collected output survive authoritative save and full reload'
Write-Host '  - historical completion feedback cannot replay on reload'
Write-Host '  - pull-request and master-push dependency boundaries stay aligned'
Write-Host '  - adjacent stonecutter and permanent CI coverage are retained'
exit 0
