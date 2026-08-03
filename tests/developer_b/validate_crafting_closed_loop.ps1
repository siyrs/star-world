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

$journey = Read-RepoFile 'tests/qa/crafting_desktop_acceptance.gd'
$panel = Read-RepoFile 'src/ui/crafting_panel.gd'
$service = Read-RepoFile 'src/crafting/crafting_service.gd'
$inventory = Read-RepoFile 'src/inventory/inventory_service.gd'
$gameUi = Read-RepoFile 'src/ui/game_ui.gd'
$workflow = Read-RepoFile '.github/workflows/player-crafting-closed-loop-tests.yml'
$contentMatrix = Read-RepoFile 'qa/content-journey-matrix.md'

Require-Contains $journey 'GameScene.instantiate()' 'Crafting evidence must load the production game scene'
Require-Contains $journey 'await _tap_key(KEY_C)' 'Hand crafting must open through the production keyboard binding'
Require-Contains $journey '_click_control(planks_button)' 'Crafting success must come from a real recipe-button click'
Require-Contains $journey '_right_click_center()' 'Workbench crafting must open through a real secondary-action click'
Require-Contains $journey '"crafting_table"' 'Workbench journey must use the production crafting-table block'
Require-Contains $journey 'get_meta("output_item_id"' 'Recipe lookup must use stable identity instead of localized text order'
Require-Contains $journey 'pickaxe_button.disabled' 'Journey must retain a visible insufficient-material failure state'
Require-Contains $journey 'clicking a disabled recipe cannot mutate inventory' 'Disabled hand recipe must prove zero inventory mutation'
Require-Contains $journey 'failed pointer crafting is atomic and preserves every slot' 'Enabled stale-UI failure must prove atomic inventory behavior'
Require-Contains $journey 'service failure publishes exact recipe error feedback' 'Enabled failure must prove visible player feedback'
Require-Contains $journey 'disabled workbench recipe cannot consume remaining sticks' 'Disabled workbench recipe must prove zero inventory mutation'
Require-Contains $journey 'hub.call("save_current")' 'Crafted inventory must join the authoritative save transaction'
Require-Contains $journey 'load_world(_world_id)' 'Crafted inventory must be loaded from the real save service'
Require-Contains $journey 'reload restores crafted items without loss or duplication' 'Journey must verify exact save/reload restoration'
Require-Contains $journey 'reopening after reload clears stale success and failure feedback' 'Reloaded panel must not retain stale result state'
Require-Contains $journey '_save_image(image)' 'Desktop journey must retain visual evidence'
Require-Contains $journey 'quit(0)' 'Early and normal success paths must terminate the desktop runner'
Require-Contains $journey 'quit(1)' 'Failure paths must terminate the desktop runner with a non-zero status'
Require-NotContains $journey 'crafting.call("craft"' 'Desktop journey may not bypass recipe-button input with a direct service call'
Require-NotContains $journey 'crafting.craft(' 'Desktop journey may not bypass recipe-button input with a direct service call'

Require-Contains $panel 'button.disabled = not can_craft' 'Crafting UI must keep unavailable recipes visible and disabled'
Require-Contains $panel 'button.set_meta("recipe_id", recipe_id)' 'Crafting buttons must expose a stable recipe identity'
Require-Contains $panel 'button.set_meta("output_item_id", output_item_id)' 'Crafting buttons must expose a stable output identity'
Require-Contains $panel 'button.pressed.connect(func() -> void: crafting.craft(recipe_id))' 'Recipe buttons must retain the production service bridge'
Require-Contains $panel 'crafting.craft_failed.connect(_on_craft_failed)' 'Crafting panel must subscribe to production failure signals'
Require-Contains $panel 'func _on_craft_failed(recipe_id: String, reason: String)' 'Crafting panel must translate service failures into UI state'
Require-Contains $panel '"result_kind": _last_result_kind' 'Crafting feedback must remain observable in visual snapshots'
Require-Contains $panel '"inventory_full"' 'Crafting feedback must explain full-inventory failures'
Require-Contains $panel 'item_crafted.emit(recipe_id)' 'Successful crafting must retain player-facing UI feedback'
Require-Contains $service 'inventory.call(' 'Crafting service must retain atomic inventory integration'
Require-Contains $service 'transact_items' 'Crafting success must use the inventory transaction boundary'
Require-Contains $service 'craft_failed.emit' 'Crafting service must retain explicit failure reasons'
Require-Contains $inventory 'func serialize() -> Dictionary:' 'Inventory must retain an authoritative serialization contract'
Require-Contains $inventory 'func deserialize(data: Dictionary) -> bool:' 'Inventory must retain an authoritative reload contract'
Require-Contains $gameUi 'event_toggles_crafting' 'Game UI must retain the production crafting input action'
Require-Contains $gameUi 'open_workbench()' 'Game UI must retain a distinct workbench station entrypoint'

Require-Contains $workflow 'crafting_desktop_acceptance.gd' 'Crafting desktop journey must run in GitHub Actions'
Require-Contains $workflow 'validate_crafting_closed_loop.ps1' 'Architecture contract must run in GitHub Actions'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Crafting gate must reuse the authoritative Godot runner'
Require-Contains $workflow 'pull_request:' 'Crafting gate must run for relevant pull requests'
Require-Contains $workflow 'push:' 'Crafting gate must re-run after merge to master'
Require-Contains $workflow 'desktop_script:' 'Crafting gate must own real desktop evidence'
Require-Contains $workflow 'adjacent-content-desktop:' 'Content review must rerun adjacent real desktop journeys'
Require-Contains $workflow 'stonecutter_machine_desktop_acceptance.gd' 'Adjacent gate must retain stonecutter evidence'
Require-Contains $workflow 'husbandry_desktop_acceptance.gd' 'Adjacent gate must retain husbandry evidence'
Require-Contains $workflow 'ranch_products_desktop_acceptance.gd' 'Adjacent gate must retain ranch-product evidence'
Require-Contains $workflow 'repair_desktop_acceptance.gd' 'Adjacent gate must retain repair evidence'

Require-Contains $contentMatrix '| 合成 |' 'Content matrix must contain an explicit crafting row'
Require-Contains $contentMatrix '真实 C 键' 'Content matrix must record the production hand-crafting input'
Require-Contains $contentMatrix '真实右键工作台' 'Content matrix must record the production workbench interaction'
Require-Contains $contentMatrix '完整返回菜单并重载' 'Content matrix must distinguish full reload from save-file inspection'
Require-Contains $contentMatrix '仍未关闭' 'Content matrix must not overclaim all content as release-complete'

if ($failures.Count -gt 0) {
    Write-Host 'PLAYER CRAFTING CLOSED LOOP CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'PLAYER CRAFTING CLOSED LOOP CONTRACT PASS'
Write-Host '  - hand crafting opens through real C input'
Write-Host '  - workbench crafting opens through real voxel interaction'
Write-Host '  - stable recipe identities are independent of translated button text'
Write-Host '  - available, disabled and stale-UI failure paths are exercised'
Write-Host '  - service calls are reached only through production UI controls'
Write-Host '  - successful and failed crafting provide visible feedback'
Write-Host '  - exact crafted inventory survives save, menu return and reload'
Write-Host '  - adjacent content journeys and the evidence matrix are reviewed'
Write-Host '  - desktop visual evidence and permanent CI wiring are present'
exit 0
