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

$product = Read-RepoFile 'src/husbandry/reliable_animal_product_service.gd'
$ranchRuntime = Read-RepoFile 'src/husbandry/ranch_runtime_participant.gd'
$ranchRegression = Read-RepoFile 'tests/qa/ranch_product_conservation_regression.gd'
$husbandryDesktop = Read-RepoFile 'tests/qa/husbandry_closed_loop_desktop_acceptance.gd'
$ranchDesktop = Read-RepoFile 'tests/qa/ranch_products_closed_loop_desktop_acceptance.gd'
$agricultureDesktop = Read-RepoFile 'tests/qa/agriculture_closed_loop_desktop_acceptance.gd'
$restDesktop = Read-RepoFile 'tests/qa/rest_closed_loop_desktop_acceptance.gd'
$workflow = Read-RepoFile '.github/workflows/remaining-player-journeys-tests.yml'

Require-Contains $product 'class_name ReliableAnimalProductService' 'Production must expose the reliable product service'
Require-Contains $product 'record["pending_count"] = maxi(' 'Collection must commit the authoritative pending count'
Require-Contains $product 'if not _restoring_pickups:' 'Reloaded pickups must not replay new-product feedback'
Require-Contains $product 'var missing_count := maxi(0, pending - current_count)' 'Active pickups must merge only unmaterialized pending products'
Require-NotContains $product 'record["pending_count"] = 0' 'Pickup materialization must not erase pending product state'
Require-NotContains $product 'const ItemPickupScript' 'Reliable subclass must inherit the parent pickup script without shadowing it'
Require-Contains $ranchRuntime 'reliable_animal_product_service.gd' 'Production ranch composition must install reliable persistence'
Require-Contains $ranchRegression 'zero-acceptance collection leaves authoritative product state untouched' 'Domain evidence must cover full-inventory-style zero acceptance'
Require-Contains $ranchRegression 'restoring an existing product does not replay production feedback' 'Domain evidence must cover reload event suppression'

Require-Contains $husbandryDesktop 'first reload restores all three live creatures' 'Husbandry journey must restore live parents and baby'
Require-Contains $husbandryDesktop 'cooldown failure cannot consume player wheat' 'Husbandry journey must prove atomic cooldown failure'
Require-Contains $husbandryDesktop 'second real breeding creates one additional baby' 'Husbandry journey must cover multiple generations'
Require-Contains $husbandryDesktop 'defeated first-generation baby does not respawn' 'Husbandry journey must prove death survives reload'
Require-Contains $husbandryDesktop 'second reload does not replay birth, death or feed feedback' 'Husbandry journey must suppress historical feedback replay'
Require-Contains $husbandryDesktop 'COW_COOLDOWN_ADVANCE_SECONDS := 241.0' 'Husbandry journey must use the production cow cooldown instead of a guessed timer'
Require-Contains $husbandryDesktop '_attack_until_removed(player, husbandry, first_baby_id, 3)' 'Husbandry death evidence must retain real player attacks'
Require-Contains $husbandryDesktop '_save_image(image)' 'Husbandry journey must retain visual evidence'

Require-Contains $ranchDesktop 'offline elapsed time creates exactly one persisted pending egg' 'Ranch journey must advance a saved timer across a session boundary'
Require-Contains $ranchDesktop 'full-inventory pickup contact cannot partially mutate any player slot' 'Ranch journey must prove full-inventory failure atomicity'
Require-Contains $ranchDesktop 'second world.json preserves exactly one uncollected egg' 'Ranch journey must save pending products authoritatively'
Require-Contains $ranchDesktop 'accepted collection commits the authoritative pending count' 'Ranch journey must commit only accepted collection'
Require-Contains $ranchDesktop 'final reload cannot resurrect a world pickup' 'Ranch journey must prevent pickup resurrection'
Require-Contains $ranchDesktop '"fixture_slot":"slot_%02d" % index' 'Ranch fixture metadata must remain canonical across JSON'
Require-Contains $ranchDesktop '_save_image(image)' 'Ranch journey must retain visual evidence'

Require-Contains $agricultureDesktop 'blocked tilling cannot consume hoe durability or materials' 'Agriculture journey must prove blocked-space failure atomicity'
Require-Contains $agricultureDesktop 'early harvest failure cannot mutate crop state' 'Agriculture journey must prove growing-crop failure atomicity'
Require-Contains $agricultureDesktop 'first reload restores the exact crop stage and elapsed state' 'Agriculture journey must reload mid-growth state'
Require-Contains $agricultureDesktop 'full-inventory harvest cannot partially add seeds or wheat' 'Agriculture journey must prove full-inventory harvest atomicity'
Require-Contains $agricultureDesktop 'successful harvest auto-replants canonical stage zero' 'Agriculture journey must retain the production harvest lifecycle'
Require-Contains $agricultureDesktop 'final reload cannot resurrect the mature crop' 'Agriculture journey must prove mature-state non-resurrection'
Require-Contains $agricultureDesktop '_save_image(image)' 'Agriculture journey must retain visual evidence'
Require-NotContains $agricultureDesktop 'FakeWorld' 'Agriculture closed-loop evidence must not use a fake world'

Require-Contains $restDesktop 'obstructed-bed failure cannot overwrite the existing custom spawn' 'Rest journey must prove obstructed-bed failure atomicity'
Require-Contains $restDesktop 'real death and respawn returns the player to the persisted bed' 'Rest journey must use the real death-panel respawn action'
Require-Contains $restDesktop 'real held primary action removes the active bed' 'Rest journey must remove the bed through production mining input'
Require-Contains $restDesktop 'bed removal emits the exact bed_removed reason' 'Rest journey must retain exact spawn-clear feedback'
Require-Contains $restDesktop 'fallback respawn returns to the production world spawn' 'Rest journey must verify safe fallback after bed removal'
Require-Contains $restDesktop '_save_image(image)' 'Rest journey must retain visual evidence'
Require-NotContains $restDesktop 'world.call("remove_block"' 'Rest journey may not bypass production mining to remove the bed'

Require-Contains $workflow 'ranch_product_conservation_regression.gd' 'Permanent CI must run product conservation'
Require-Contains $workflow 'husbandry_closed_loop_desktop_acceptance.gd' 'Permanent CI must run the husbandry closed loop'
Require-Contains $workflow 'ranch_products_closed_loop_desktop_acceptance.gd' 'Permanent CI must run the ranch closed loop'
Require-Contains $workflow 'agriculture_closed_loop_desktop_acceptance.gd' 'Permanent CI must run the agriculture closed loop'
Require-Contains $workflow 'rest_closed_loop_desktop_acceptance.gd' 'Permanent CI must run the rest closed loop'
Require-Contains $workflow 'strategy:' 'Desktop journeys must use a bounded independent matrix'
Require-Contains $workflow 'fail-fast: false' 'One journey failure must not hide the other evidence result'
Require-Contains $workflow 'permissions:' 'Remaining journey workflow must declare permissions'
Require-Contains $workflow 'contents: read' 'Remaining journey workflow must remain read-only'
Require-Contains $workflow 'pull_request:' 'Remaining journey workflow must run on pull requests'
Require-Contains $workflow 'push:' 'Remaining journey workflow must rerun after merge to master'
Require-Contains $workflow 'cancel-in-progress: true' 'Remaining journey workflow must cancel stale runs'
Require-MinimumOccurrences $workflow "      - 'src/husbandry/**'" 2 'Husbandry changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'src/agriculture/**'" 2 'Agriculture changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'src/rest/**'" 2 'Rest changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'src/inventory/**'" 2 'Inventory changes must trigger both pull-request and master-push gates'
Require-MinimumOccurrences $workflow "      - 'tests/ci/run_godot_desktop_test.ps1'" 2 'Desktop runner changes must trigger both pull-request and master-push gates'

if ($failures.Count -gt 0) {
    Write-Host 'REMAINING PLAYER JOURNEYS CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'REMAINING PLAYER JOURNEYS CONTRACT PASS'
Write-Host '  - ranch products remain authoritative until accepted collection'
Write-Host '  - zero-acceptance, reload and offline materialization are covered'
Write-Host '  - husbandry live reload, cooldown, death and multigeneration are covered'
Write-Host '  - ranch timer, full inventory and exact collection reload are covered'
Write-Host '  - agriculture failure, growth, harvest and exact reload are covered'
Write-Host '  - bed spawn, real respawn, removal fallback and exact reload are covered'
Write-Host '  - production composition and permanent read-only CI are wired'
exit 0
