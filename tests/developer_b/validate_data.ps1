$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-OptionalProperty {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    $Default = $null
  )
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

$root = Resolve-Path "$PSScriptRoot\..\.."
$baseItems = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$baseRecipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json).recipes)
$extensionPaths = @(
  (Join-Path $root 'data\ranged_combat.json'),
  (Join-Path $root 'data\firearms.json')
)
$items = @($baseItems)
$recipes = @($baseRecipes)
foreach ($extensionPath in $extensionPaths) {
  if (-not (Test-Path -LiteralPath $extensionPath)) { throw "Missing content extension: $extensionPath" }
  $extension = Get-Content -Raw -Encoding UTF8 $extensionPath | ConvertFrom-Json
  $items += @($extension.items)
  $recipes += @($extension.recipes)
}
$furnaceRecipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\furnace_recipes.json') | ConvertFrom-Json).recipes)
$stonecutterRecipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\stonecutter_recipes.json') | ConvertFrom-Json).recipes)
$fuels = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\fuels.json') | ConvertFrom-Json).fuels)
$harvestRules = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\block_harvest.json') | ConvertFrom-Json).rules)
$cropData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\crops.json') | ConvertFrom-Json
$crops = @($cropData.crops)
$soilData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\soil_moisture.json') | ConvertFrom-Json
$equipmentData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\equipment.json') | ConvertFrom-Json
$equipmentSlots = @($equipmentData.slots)
$maps = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\map_profiles.json') | ConvertFrom-Json).maps)
$creatures = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creatures.json') | ConvertFrom-Json).creatures
$blockRegistryText = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\block\block_registry.gd')
$blockListMatch = [regex]::Match($blockRegistryText, '(?s)const BLOCK_IDS := \[(.*?)\]')
if (-not $blockListMatch.Success) { throw 'Unable to parse production BlockRegistry.BLOCK_IDS' }
$knownBlocks = @([regex]::Matches($blockListMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object {
  $_.Groups[1].Value
})

if ($baseItems.Count -lt 87) { throw "Expected >=87 base items, got $($baseItems.Count)" }
if ($items.Count -lt ($baseItems.Count + 8)) { throw "Content extensions were not composed into the global item closure: total=$($items.Count) base=$($baseItems.Count)" }
if ($baseRecipes.Count -lt 59) { throw "Expected >=59 base crafting recipes, got $($baseRecipes.Count)" }
if ($recipes.Count -lt ($baseRecipes.Count + 8)) { throw "Content extensions were not composed into the global recipe closure: total=$($recipes.Count) base=$($baseRecipes.Count)" }
if ($furnaceRecipes.Count -lt 8) { throw "Expected >=8 furnace recipes, got $($furnaceRecipes.Count)" }
if ($stonecutterRecipes.Count -ne 3) { throw "Expected 3 stonecutter recipes, got $($stonecutterRecipes.Count)" }
if ($fuels.Count -lt 2) { throw "Expected >=2 fuels, got $($fuels.Count)" }
if ($harvestRules.Count -lt 44) { throw "Expected >=44 harvest rules, got $($harvestRules.Count)" }
if ($crops.Count -lt 3) { throw "Expected >=3 crop definitions, got $($crops.Count)" }
if ($equipmentSlots.Count -ne 5) { throw "Expected 5 equipment slots, got $($equipmentSlots.Count)" }
if ($maps.Count -ne 5) { throw "Expected 5 map profiles, got $($maps.Count)" }
$creatureProperties = @($creatures.PSObject.Properties)
$creatureCount = $creatureProperties.Count
if ($creatureCount -ne 6) { throw "Expected 6 creatures, got $creatureCount" }
$creatureIds = @($creatureProperties.Name)

$slotAllowed = @{}
$slotOrders = @{}
foreach ($slot in $equipmentSlots) {
  $slotId = [string]$slot.id
  if ([string]::IsNullOrWhiteSpace($slotId)) { throw 'Equipment slot id is empty' }
  if ($slotAllowed.ContainsKey($slotId)) { throw "Duplicate equipment slot: $slotId" }
  $slotAllowed[$slotId] = @($slot.allowed)
  $order = [int]$slot.order
  if ($slotOrders.ContainsKey($order)) { throw "Duplicate equipment order: $order" }
  $slotOrders[$order] = $true
  if (@($slot.allowed).Count -eq 0) { throw "Equipment slot has no allowed categories: $slotId" }
}
foreach ($requiredSlot in @('main_hand','helmet','chestplate','leggings','boots')) {
  if (-not $slotAllowed.ContainsKey($requiredSlot)) { throw "Missing equipment slot: $requiredSlot" }
}
$knownAttributes = @($equipmentData.attributes.PSObject.Properties.Name)
foreach ($requiredAttribute in @('max_health','attack_damage','defense','movement_speed','mining_speed')) {
  if ($requiredAttribute -notin $knownAttributes) { throw "Missing character attribute: $requiredAttribute" }
}

$ids = @{}
$toolCount = 0
$armorCount = 0
$equippableCount = 0
$allowedToolTypes = @('pickaxe','axe','shovel','hoe','sword','bow','pistol','carbine','shotgun')
foreach ($item in $items) {
  $itemId = [string]$item.id
  if ([string]::IsNullOrWhiteSpace($itemId) -or $ids.ContainsKey($itemId)) { throw "Duplicate or empty item id: $itemId" }
  $ids[$itemId] = $true
  if ([int]$item.max_stack -lt 1) { throw "Invalid stack limit: $itemId" }
  if ($item.category -in @('tool', 'weapon')) {
    $toolCount += 1
    if ([string]::IsNullOrWhiteSpace([string]$item.tool_type)) { throw "Missing tool_type: $itemId" }
    if ([string]$item.tool_type -notin $allowedToolTypes) { throw "Unsupported tool_type $($item.tool_type): $itemId" }
    if ([int]$item.max_stack -ne 1) { throw "Durable item must not stack: $itemId" }
    if ([int]$item.durability -le 0) { throw "Invalid durability: $itemId" }
    if ([int]$item.power -lt 1) { throw "Invalid tool power: $itemId" }
    if ([double]$item.mining_speed -le 0) { throw "Invalid mining speed: $itemId" }
  }
  if ($item.category -eq 'armor') {
    $armorCount += 1
    if ([int]$item.max_stack -ne 1) { throw "Armor must not stack: $itemId" }
    if ([int]$item.durability -le 0) { throw "Invalid armor durability: $itemId" }
  }
  $equipment = Get-OptionalProperty -Object $item -Name 'equipment'
  if ($null -ne $equipment) {
    $equippableCount += 1
    $slotId = [string]$equipment.slot
    if (-not $slotAllowed.ContainsKey($slotId)) { throw "Unknown equipment slot '$slotId' for $itemId" }
    if ($item.category -notin @($slotAllowed[$slotId])) { throw "Category $($item.category) is not allowed in $slotId for $itemId" }
    if ([int]$item.max_stack -ne 1) { throw "Equippable item must not stack: $itemId" }
    $attributes = Get-OptionalProperty -Object $equipment -Name 'attributes' -Default ([pscustomobject]@{})
    foreach ($attributeId in @($attributes.PSObject.Properties.Name)) {
      if ($attributeId -notin $knownAttributes) { throw "Unknown equipment attribute $attributeId for $itemId" }
      if ([double]$attributes.$attributeId -eq 0) { throw "Zero equipment attribute $attributeId for $itemId" }
    }
  }
}
if ($armorCount -lt 8) { throw "Expected >=8 armor items, got $armorCount" }
if ($equippableCount -lt 17) { throw "Expected >=17 equippable items including ranged extensions, got $equippableCount" }
foreach ($requiredItem in @('wheat_seeds','wheat','carrot','potato','baked_potato','water_bucket','bucket','oak_bed','repair_station','glass_pane','stonecutter','prospecting_kit','wooden_shovel','diamond_shovel','wooden_hoe','diamond_hoe','bow','arrow','gunpowder','light_round','shotgun_shell','star_pistol','frontier_carbine','scattergun')) {
  if (-not $ids.ContainsKey($requiredItem)) { throw "Missing global item: $requiredItem" }
}

$recipeIds = @{}
foreach ($recipe in $recipes) {
  $recipeId = [string]$recipe.id
  if ([string]::IsNullOrWhiteSpace($recipeId) -or $recipeIds.ContainsKey($recipeId)) { throw "Duplicate or empty crafting recipe: $recipeId" }
  $recipeIds[$recipeId] = $true
  if ($recipe.station -in @('furnace','stonecutter')) { throw "Machine recipe leaked into crafting registry: $recipeId" }
  foreach ($ingredient in $recipe.ingredients.PSObject.Properties.Name) {
    if (-not $ids.ContainsKey($ingredient)) { throw "Unknown ingredient $ingredient in $recipeId" }
    if ([int]$recipe.ingredients.$ingredient -lt 1) { throw "Invalid ingredient count $ingredient in $recipeId" }
  }
  if (-not $ids.ContainsKey([string]$recipe.output.id)) { throw "Unknown output $($recipe.output.id)" }
  if ([int]$recipe.output.count -lt 1) { throw "Invalid crafting output count in $recipeId" }
}
foreach ($recipe in $furnaceRecipes) {
  if (-not $ids.ContainsKey([string]$recipe.input.id)) { throw "Unknown furnace input $($recipe.input.id) in $($recipe.id)" }
  if (-not $ids.ContainsKey([string]$recipe.output.id)) { throw "Unknown furnace output $($recipe.output.id) in $($recipe.id)" }
  if ([double]$recipe.duration_seconds -le 0) { throw "Invalid furnace duration in $($recipe.id)" }
}
$stonecutterInputs = @{}
foreach ($recipe in $stonecutterRecipes) {
  if (-not $ids.ContainsKey([string]$recipe.input.id)) { throw "Unknown stonecutter input $($recipe.input.id) in $($recipe.id)" }
  if (-not $ids.ContainsKey([string]$recipe.output.id)) { throw "Unknown stonecutter output $($recipe.output.id) in $($recipe.id)" }
  if ([double]$recipe.duration_seconds -le 0) { throw "Invalid stonecutter duration in $($recipe.id)" }
  $inputId = [string]$recipe.input.id
  if ($stonecutterInputs.ContainsKey($inputId)) { throw "Ambiguous stonecutter input: $inputId" }
  $stonecutterInputs[$inputId] = $true
}
foreach ($fuel in $fuels) {
  if (-not $ids.ContainsKey([string]$fuel.id)) { throw "Unknown fuel item $($fuel.id)" }
  if ([double]$fuel.burn_seconds -le 0) { throw "Invalid fuel duration for $($fuel.id)" }
}

$blockSet = @{}
foreach ($blockId in $knownBlocks) {
  if ($blockSet.ContainsKey($blockId)) { throw "Duplicate production block id: $blockId" }
  $blockSet[$blockId] = $true
}
$harvestIds = @{}
foreach ($rule in $harvestRules) {
  $blockId = [string]$rule.block_id
  if ($harvestIds.ContainsKey($blockId)) { throw "Duplicate harvest rule: $blockId" }
  $harvestIds[$blockId] = $true
  if (-not $blockSet.ContainsKey($blockId)) { throw "Unknown harvest block: $blockId" }
  foreach ($field in @('preferred_tool', 'required_tool')) {
    $toolType = [string](Get-OptionalProperty -Object $rule -Name $field -Default '')
    if (-not [string]::IsNullOrWhiteSpace($toolType) -and $toolType -notin @('pickaxe','axe','shovel','hoe')) { throw "Invalid $field '$toolType' for $blockId" }
  }
  $minimumPower = Get-OptionalProperty -Object $rule -Name 'minimum_power'
  if ($null -ne $minimumPower -and [int]$minimumPower -lt 0) { throw "Invalid minimum_power for $blockId" }
  $dropCount = Get-OptionalProperty -Object $rule -Name 'drop_count'
  if ($null -ne $dropCount -and [int]$dropCount -lt 0) { throw "Invalid drop count for $blockId" }
  $dropItem = [string](Get-OptionalProperty -Object $rule -Name 'drop_item' -Default '')
  if (-not [string]::IsNullOrWhiteSpace($dropItem) -and -not $ids.ContainsKey($dropItem)) { throw "Unknown harvest drop $dropItem for $blockId" }
  $wrongToolMultiplier = Get-OptionalProperty -Object $rule -Name 'wrong_tool_speed_multiplier'
  if ($null -ne $wrongToolMultiplier) {
    $multiplier = [double]$wrongToolMultiplier
    if ($multiplier -le 0 -or $multiplier -gt 1) { throw "Invalid wrong-tool speed for $blockId" }
  }
}

$cropIds = @{}
$cropSeeds = @{}
$cropStageBlocks = @{}
foreach ($crop in $crops) {
  $cropId = [string]$crop.id
  if ([string]::IsNullOrWhiteSpace($cropId)) { throw 'Crop id is empty' }
  if ($cropIds.ContainsKey($cropId)) { throw "Duplicate crop: $cropId" }
  $cropIds[$cropId] = $true
  $seedId = [string]$crop.seed_item
  if (-not $ids.ContainsKey($seedId)) { throw "Unknown crop seed $seedId for $cropId" }
  if ($cropSeeds.ContainsKey($seedId)) { throw "Duplicate crop seed mapping: $seedId" }
  $cropSeeds[$seedId] = $cropId
  if (-not $ids.ContainsKey([string]$crop.produce_item)) { throw "Unknown crop produce $($crop.produce_item) for $cropId" }
  $stageBlocks = @($crop.stage_blocks)
  $stageSeconds = @($crop.stage_seconds)
  if ($stageBlocks.Count -lt 2) { throw "Crop requires at least two stages: $cropId" }
  if ($stageSeconds.Count -ne $stageBlocks.Count - 1) { throw "Crop stage duration mismatch: $cropId" }
  foreach ($stageBlock in $stageBlocks) {
    if (-not $blockSet.ContainsKey([string]$stageBlock)) { throw "Unknown crop stage block $stageBlock for $cropId" }
    if ($cropStageBlocks.ContainsKey($stageBlock)) { throw "Crop stage block reused: $stageBlock" }
    $cropStageBlocks[$stageBlock] = $cropId
  }
  foreach ($seconds in $stageSeconds) {
    if ([double]$seconds -le 0) { throw "Invalid crop stage duration for $cropId" }
  }
  $outputs = @($crop.harvest.outputs)
  if ($outputs.Count -lt 1) { throw "Crop harvest outputs are empty: $cropId" }
  foreach ($output in $outputs) {
    if (-not $ids.ContainsKey([string]$output.item_id)) { throw "Unknown crop output $($output.item_id) for $cropId" }
    if ([int]$output.count -lt 1) { throw "Invalid crop output count for $cropId" }
  }
}
foreach ($requiredCrop in @('wheat','carrot','potato')) {
  if (-not $cropIds.ContainsKey($requiredCrop)) { throw "Missing required crop: $requiredCrop" }
}

foreach ($property in $creatureProperties) {
  $speciesId = [string]$property.Name
  $creature = $property.Value
  if ([string]::IsNullOrWhiteSpace($speciesId)) { throw 'Creature id is empty' }
  if ([double]$creature.max_health -le 0 -or [double]$creature.speed -lt 0 -or [double]$creature.damage -lt 0) { throw "Invalid creature numeric profile: $speciesId" }
  foreach ($dropProperty in $creature.drops.PSObject.Properties) {
    $dropId = [string]$dropProperty.Name
    if (-not $ids.ContainsKey($dropId)) { throw "Creature $speciesId references unknown drop item: $dropId" }
    $dropRange = @($dropProperty.Value)
    if ($dropRange.Count -ne 2 -or [int]$dropRange[0] -lt 0 -or [int]$dropRange[1] -lt [int]$dropRange[0]) { throw "Invalid creature drop range $dropId for $speciesId" }
  }
}
foreach ($requiredCreature in @('chicken','cow','pig','zombie','abyss_brute','abyss_marksman')) {
  if ($requiredCreature -notin $creatureIds) { throw "Missing required creature: $requiredCreature" }
}

foreach ($requiredField in @('dry_block','wet_block','water_blocks','horizontal_radius','vertical_radius','manual_hydration_seconds','dry_growth_multiplier','wet_growth_multiplier','refresh_interval_seconds','max_refresh_per_tick')) {
  if ($null -eq $soilData.PSObject.Properties[$requiredField]) { throw "Missing soil moisture field: $requiredField" }
}
if (-not $blockSet.ContainsKey([string]$soilData.dry_block)) { throw "Unknown dry soil block: $($soilData.dry_block)" }
if (-not $blockSet.ContainsKey([string]$soilData.wet_block)) { throw "Unknown wet soil block: $($soilData.wet_block)" }
if ([string]$soilData.dry_block -eq [string]$soilData.wet_block) { throw 'Dry and wet soil blocks must differ' }
foreach ($waterBlock in @($soilData.water_blocks)) {
  if (-not $blockSet.ContainsKey([string]$waterBlock)) { throw "Unknown irrigation water block: $waterBlock" }
}
if ([int]$soilData.horizontal_radius -lt 1 -or [int]$soilData.horizontal_radius -gt 8) { throw 'Invalid irrigation horizontal radius' }
if ([int]$soilData.vertical_radius -lt 0 -or [int]$soilData.vertical_radius -gt 3) { throw 'Invalid irrigation vertical radius' }
if ([double]$soilData.manual_hydration_seconds -le 0) { throw 'Invalid manual hydration duration' }
if ([double]$soilData.dry_growth_multiplier -lt 0 -or [double]$soilData.dry_growth_multiplier -gt 1) { throw 'Invalid dry growth multiplier' }
if ([double]$soilData.wet_growth_multiplier -le 0) { throw 'Invalid wet growth multiplier' }
if ([int]$soilData.max_refresh_per_tick -lt 1) { throw 'Invalid soil refresh budget' }

Write-Host "PASS base_items=$($baseItems.Count) global_items=$($items.Count) tools=$toolCount armor=$armorCount equippable=$equippableCount equipment_slots=$($equipmentSlots.Count) base_crafting=$($baseRecipes.Count) global_crafting=$($recipes.Count) furnace=$($furnaceRecipes.Count) stonecutter=$($stonecutterRecipes.Count) fuels=$($fuels.Count) blocks=$($knownBlocks.Count) harvest=$($harvestRules.Count) crops=$($crops.Count) soil_radius=$($soilData.horizontal_radius) maps=$($maps.Count) creatures=$creatureCount"
