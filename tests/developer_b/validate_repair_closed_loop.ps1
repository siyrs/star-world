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

$panel = Read-RepoFile 'src/ui/repair_panel.gd'
$inventory = Read-RepoFile 'src/inventory/inventory_service.gd'
$canonicalRegression = Read-RepoFile 'tests/qa/inventory_canonical_roundtrip_regression.gd'
$desktop = Read-RepoFile 'tests/qa/repair_desktop_acceptance.gd'
$workflow = Read-RepoFile '.github/workflows/player-repair-closed-loop-tests.yml'
$matrix = Read-RepoFile 'qa/content-journey-matrix.md'

Require-Contains $panel 'func get_visual_snapshot() -> Dictionary:' 'Repair UI must expose auditable visual state'
Require-Contains $panel 'button.set_meta("target_id", target_id)' 'Repair buttons must publish stable target identity'
Require-Contains $panel 'button.set_meta("item_id"' 'Repair buttons must publish stable item identity'
Require-Contains $panel 'repair_service.call("repair_target", target)' 'Repair action must use the production service'
Require-NotContains $panel 'var result: Dictionary = repair_service.call("repair_target", target)' 'Repair panel must not duplicate synchronous result handling and signal handling'

Require-Contains $inventory 'INTEGER_METADATA_KEYS := ["durability", "magazine_rounds"]' 'Persisted integer metadata keys must have one canonical policy'
Require-Contains $inventory 'func _canonicalize_metadata(raw_metadata: Variant) -> Dictionary:' 'Inventory must normalize metadata at the persistence boundary'
Require-Contains $inventory 'value_type == TYPE_INT or value_type == TYPE_FLOAT' 'JSON floating integer metadata must be accepted and normalized'
Require-Contains $canonicalRegression 'JSON.parse_string(JSON.stringify(serialized))' 'Canonical regression must cross the real JSON value boundary'
Require-Contains $canonicalRegression 'JSON save-load boundary preserves exact canonical metadata types' 'Canonical regression must assert exact JSON roundtrip shape'
Require-Contains $canonicalRegression 'known floating metadata keys normalize to exact integer shape' 'Legacy floating metadata normalization must remain covered'

Require-Contains $desktop 'GameScene.instantiate()' 'Desktop repair must use the production game scene'
Require-Contains $desktop '.create_world(' 'Desktop repair must create an authoritative world'
Require-Contains $desktop 'game.call("begin_world_state", state)' 'Desktop repair must enter through production world composition'
Require-Contains $desktop '"repair_station"' 'Desktop repair must place and interact with the production station block'
Require-Contains $desktop 'await _right_click_center()' 'Desktop repair must use a real pointer interaction'
Require-Contains $desktop 'await _click_control(repair_button)' 'Desktop repair success must come from the real UI control'
Require-Contains $desktop 'ReadOnlyRepairInventory.new()' 'Desktop repair must exercise an enabled stale-service failure without mutating production inventory'
Require-Contains $desktop 'stale service failure is atomic' 'Desktop repair must assert failure atomicity'
Require-Contains $desktop 'bool(hub.call("save_current"))' 'Desktop repair must enter the authoritative save'
Require-Contains $desktop 'hub.call("return_to_menu")' 'Desktop repair must close the original world session'
Require-Contains $desktop 'game.call("begin_world_state", saved_state)' 'Desktop repair must fully reload the saved world'
Require-Contains $desktop 'reload preserves the repaired durability exactly' 'Desktop repair must verify durability across reload'
Require-Contains $desktop 'reload restores the real repair station world override' 'Desktop repair must verify the station across reload'

Require-Contains $workflow 'validate_repair_closed_loop.ps1' 'Repair closed-loop validator must be wired into CI'
Require-Contains $workflow 'repair_regression.gd' 'Repair domain regression must remain in the dedicated gate'
Require-Contains $workflow 'repair_desktop_acceptance.gd' 'Repair desktop journey must remain in the dedicated gate'
Require-Contains $workflow 'inventory_canonical_roundtrip_regression.gd' 'Repair gate must retain JSON inventory canonicalization regression'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Repair gate must reuse the authoritative runner'

Require-Contains $matrix '| 修理 | **E3 闭环** |' 'Content matrix must classify repair as a completed production-scene journey'
Require-Contains $matrix '商业正式发布继续 HOLD' 'Content matrix must retain external E4 and hardware release boundaries'

if ($failures.Count -gt 0) {
    Write-Host 'PLAYER REPAIR CLOSED LOOP CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'PLAYER REPAIR CLOSED LOOP CONTRACT PASS'
Write-Host '  - production repair station and real pointer interactions are retained'
Write-Host '  - stable target identities and exact visible feedback are retained'
Write-Host '  - disabled and stale-service failure paths remain atomic'
Write-Host '  - persisted integer metadata remains canonical across real JSON'
Write-Host '  - repaired durability, metadata, materials and station survive save/reload'
Write-Host '  - dedicated permanent CI wiring is present'
exit 0