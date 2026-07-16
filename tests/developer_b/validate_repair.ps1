$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..\..'
$items = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$recipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json).recipes)
$harvestRules = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\block_harvest.json') | ConvertFrom-Json).rules)
$repairData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\repair_profiles.json') | ConvertFrom-Json
$profiles = @($repairData.profiles)

if ([int]$repairData.schema_version -lt 1) { throw 'Repair schema version must be >= 1' }
if ([string]::IsNullOrWhiteSpace([string]$repairData.station_block)) { throw 'Repair station block is empty' }
if ($profiles.Count -lt 6) { throw "Expected at least 6 repair profiles, got $($profiles.Count)" }

$itemById = @{}
$durableItems = @{}
foreach ($item in $items) {
    $itemId = [string]$item.id
    $itemById[$itemId] = $item
    if ($null -ne $item.durability -and [int]$item.durability -gt 0) {
        $durableItems[$itemId] = $true
    }
}

$stationBlock = [string]$repairData.station_block
if (-not $itemById.ContainsKey($stationBlock)) { throw "Missing repair station item: $stationBlock" }
if ([string]$itemById[$stationBlock].block_id -ne $stationBlock) { throw 'Repair station item does not map to its block' }

$recipe = $recipes | Where-Object { [string]$_.output.id -eq $stationBlock } | Select-Object -First 1
if ($null -eq $recipe) { throw 'Repair station crafting recipe is missing' }
if ([string]$recipe.station -ne 'workbench') { throw 'Repair station must require a workbench' }
if ([int]$recipe.output.count -ne 1) { throw 'Repair station recipe must output exactly one block' }

$harvest = $harvestRules | Where-Object { [string]$_.block_id -eq $stationBlock } | Select-Object -First 1
if ($null -eq $harvest) { throw 'Repair station harvest rule is missing' }
if ([string]$harvest.required_tool -ne 'pickaxe') { throw 'Repair station must require a pickaxe' }
if ([int]$harvest.minimum_power -lt 1) { throw 'Repair station minimum power must be at least one' }

$profileIds = @{}
$coveredItems = @{}
foreach ($profile in $profiles) {
    $profileId = [string]$profile.id
    if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'Repair profile id is empty' }
    if ($profileIds.ContainsKey($profileId)) { throw "Duplicate repair profile id: $profileId" }
    $profileIds[$profileId] = $true

    $materialItem = [string]$profile.material_item
    if (-not $itemById.ContainsKey($materialItem)) { throw "Unknown repair material $materialItem in $profileId" }
    if ([int]$profile.material_count -lt 1) { throw "Invalid material count in $profileId" }
    $restoreRatio = [double]$profile.restore_ratio
    if ($restoreRatio -le 0 -or $restoreRatio -gt 1) { throw "Invalid restore ratio in $profileId" }

    $profileItems = @($profile.items)
    if ($profileItems.Count -lt 1) { throw "Repair profile has no items: $profileId" }
    foreach ($itemIdValue in $profileItems) {
        $itemId = [string]$itemIdValue
        if (-not $itemById.ContainsKey($itemId)) { throw "Unknown repair target $itemId in $profileId" }
        if (-not $durableItems.ContainsKey($itemId)) { throw "Repair target is not durable: $itemId" }
        if ($coveredItems.ContainsKey($itemId)) { throw "Repair target is assigned twice: $itemId" }
        $coveredItems[$itemId] = $profileId
    }
}

foreach ($durableItemId in $durableItems.Keys) {
    if (-not $coveredItems.ContainsKey($durableItemId)) {
        throw "Durable item has no repair profile: $durableItemId"
    }
}

Write-Host "PASS repair_profiles=$($profiles.Count) durable_targets=$($coveredItems.Count) station=$stationBlock"
