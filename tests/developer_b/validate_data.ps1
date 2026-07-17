$ErrorActionPreference = 'Stop'
$items = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\items.json" | ConvertFrom-Json).items
$recipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\recipes.json" | ConvertFrom-Json).recipes
$furnaceRecipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\furnace_recipes.json" | ConvertFrom-Json).recipes
$fuels = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\fuels.json" | ConvertFrom-Json).fuels
$harvestRules = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\block_harvest.json" | ConvertFrom-Json).rules
$cropData = Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\crops.json" | ConvertFrom-Json
$crops = @($cropData.crops)
$soilData = Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\soil_moisture.json" | ConvertFrom-Json
$equipmentData = Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\equipment.json" | ConvertFrom-Json
$equipmentSlots = @($equipmentData.slots)
$maps = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\map_profiles.json" | ConvertFrom-Json).maps
$creatures = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\creatures.json" | ConvertFrom-Json).creatures

if ($items.Count -lt 86) { throw "Expected >=86 items, got $($items.Count)" }
if ($recipes.Count -lt 58) { throw "Expected >=58 crafting recipes, got $($recipes.Count)" }
if ($furnaceRecipes.Count -lt 8) { throw "Expected >=8 furnace recipes, got $($furnaceRecipes.Count)" }
if ($fuels.Count -lt 2) { throw "Expected >=2 fuels, got $($fuels.Count)" }
if ($harvestRules.Count -lt 43) { throw "Expected >=43 harvest rules, got $($harvestRules.Count)" }
if ($crops.Count -lt 3) { throw "Expected >=3 crop definitions, got $($crops.Count)" }
if ($equipmentSlots.Count -ne 5) { throw "Expected 5 equipment slots, got $($equipmentSlots.Count)" }
if ($maps.Count -ne 5) { throw "Expected 5 map profiles, got $($maps.Count)" }
$creatureCount = @($creatures.PSObject.Properties).Count
if ($creatureCount -ne 4) { throw "Expected 4 creatures, got $creatureCount" }

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
foreach ($item in $items) {
  if ($ids.ContainsKey($item.id)) { throw "Duplicate item id: $($item.id)" }
  $ids[$item.id] = $true
  if ($item.max_stack -lt 1) { throw "Invalid stack limit: $($item.id)" }
  if ($item.category -in @('tool', 'weapon')) {
    $toolCount += 1
    if ([string]::IsNullOrWhiteSpace([string]$item.tool_type)) { throw "Missing tool_type: $($item.id)" }
    if ($item.tool_type -notin @('pickaxe', 'axe', 'shovel', 'hoe', 'sword')) { throw "Unsupported tool_type $($item.tool_type): $($item.id)" }
    if ([int]$item.max_stack -ne 1) { throw "Durable item must not stack: $($item.id)" }
    if ([int]$item.durability -le 0) { throw "Invalid durability: $($item.id)" }
    if ([int]$item.power -lt 1) { throw "Invalid tool power: $($item.id)" }
    if ([double]$item.mining_speed -le 0) { throw "Invalid mining speed: $($item.id)" }
  }
  if ($item.category -eq 'armor') {
    $armorCount += 1
    if ([int]$item.max_stack -ne 1) { throw "Armor must not stack: $($item.id)" }
    if ([int]$item.durability -le 0) { throw "Invalid armor durability: $($item.id)" }
  }
  if ($null -ne $item.equipment) {
    $equippableCount += 1
    $slotId = [string]$item.equipment.slot
    if (-not $slotAllowed.ContainsKey($slotId)) { throw "Unknown equipment slot '$slotId' for $($item.id)" }
    if ($item.category -notin @($slotAllowed[$slotId])) {
      throw "Category $($item.category) is not allowed in $slotId for $($item.id)"
    }
    if ([int]$item.max_stack -ne 1) { throw "Equippable item must not stack: $($item.id)" }
    foreach ($attributeId in @($item.equipment.attributes.PSObject.Properties.Name)) {
      if ($attributeId -notin $knownAttributes) { throw "Unknown equipment attribute $attributeId for $($item.id)" }
      if ([double]$item.equipment.attributes.$attributeId -eq 0) { throw "Zero equipment attribute $attributeId for $($item.id)" }
    }
  }
}
if ($armorCount -lt 8) { throw "Expected >=8 armor items, got $armorCount" }
if ($equippableCount -lt 13) { throw "Expected >=13 equippable items, got $equippableCount" }
foreach ($requiredItem in @('wheat_seeds','wheat','carrot','potato','baked_potato','water_bucket','bucket','oak_bed','repair_station','glass_pane','prospecting_kit','wooden_shovel','diamond_shovel','wooden_hoe','diamond_hoe')) {
  if (-not $ids.ContainsKey($requiredItem)) { throw "Missing agriculture/tool/rest/repair/exploration item: $requiredItem" }
}

foreach ($recipe in $recipes) {
  if ($recipe.station -eq 'furnace') { throw "Furnace recipe leaked into crafting registry: $($recipe.id)" }
  foreach ($ingredient in $recipe.ingredients.PSObject.Properties.Name) {
    if (-not $ids.ContainsKey($ingredient)) { throw "Unknown ingredient $ingredient in $($recipe.id)" }
  }
  if (-not $ids.ContainsKey($recipe.output.id)) { throw "Unknown output $($recipe.output.id)" }
}
foreach ($recipe in $furnaceRecipes) {
  if (-not $ids.ContainsKey($recipe.input.id)) { throw "Unknown furnace input $($recipe.input.id) in $($recipe.id)" }
  if (-not $ids.ContainsKey($recipe.output.id)) { throw "Unknown furnace output $($recipe.output.id) in $($recipe.id)" }
  if ([double]$recipe.duration_seconds -le 0) { throw "Invalid furnace duration in $($recipe.id)" }
}
foreach ($fuel in $fuels) {
  if (-not $ids.ContainsKey($fuel.id)) { throw "Unknown fuel item $($fuel.id)" }
  if ([double]$fuel.burn_seconds -le 0) { throw "Invalid fuel duration for $($fuel.id)" }
}

$knownBlocks = @(
  'air','grass','dirt','stone','cobblestone','sand','snow','wood','leaves','water','lava',
  'planks','stone_bricks','glass','glass_pane','glass_pane_ns','stone_slab','oak_stairs','coal_ore','iron_ore','gold_ore',
  'diamond_ore','crafting_table','furnace','chest','oak_door','oak_fence','oak_bed','repair_station','ladder','torch','wool','ice','bedrock',
  'farmland','wheat_stage_0','wheat_stage_1','wheat_stage_2','wheat_stage_3','farmland_wet',
  'carrot_stage_0','carrot_stage_1','carrot_stage_2','carrot_stage_3',
  'potato_stage_0','potato_stage_1','potato_stage_2','potato_stage_3',
  'oak_stairs_east','oak_stairs_north','oak_stairs_west'
)
$harvestIds = @{}
foreach ($rule in $harvestRules) {
  if ($harvestIds.ContainsKey($rule.block_id)) { throw "Duplicate harvest rule: $($rule.block_id)" }
  $harvestIds[$rule.block_id] = $true
  if ($rule.block_id -notin $knownBlocks) { throw "Unknown harvest block: $($rule.block_id)" }
  foreach ($field in @('preferred_tool', 'required_tool')) {
    $toolType = [string]$rule.$field
    if (-not [string]::IsNullOrWhiteSpace($toolType) -and $toolType -notin @('pickaxe', 'axe', 'shovel', 'hoe')) {
      throw "Invalid $field '$toolType' for $($rule.block_id)"
    }
  }
  if ($null -ne $rule.minimum_power -and [int]$rule.minimum_power -lt 0) { throw "Invalid minimum power for $($rule.block_id)" }
  if ($null -ne $rule.drop_count -and [int]$rule.drop_count -lt 0) { throw "Invalid drop count for $($rule.block_id)" }
  if (-not [string]::IsNullOrWhiteSpace([string]$rule.drop_item) -and -not $ids.ContainsKey($rule.drop_item)) {
    throw "Unknown harvest drop $($rule.drop_item) for $($rule.block_id)"
  }
  if ($null -ne $rule.wrong_tool_speed_multiplier) {
    $multiplier = [double]$rule.wrong_tool_speed_multiplier
    if ($multiplier -le 0 -or $multiplier -gt 1) { throw "Invalid wrong-tool speed for $($rule.block_id)" }
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
    if ($stageBlock -notin $knownBlocks) { throw "Unknown crop stage block $stageBlock for $cropId" }
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

foreach ($requiredField in @('dry_block','wet_block','water_blocks','horizontal_radius','vertical_radius','manual_hydration_seconds','dry_growth_multiplier','wet_growth_multiplier','refresh_interval_seconds','max_refresh_per_tick')) {
  if ($null -eq $soilData.$requiredField) { throw "Missing soil moisture field: $requiredField" }
}
if ([string]$soilData.dry_block -notin $knownBlocks) { throw "Unknown dry soil block: $($soilData.dry_block)" }
if ([string]$soilData.wet_block -notin $knownBlocks) { throw "Unknown wet soil block: $($soilData.wet_block)" }
if ([string]$soilData.dry_block -eq [string]$soilData.wet_block) { throw 'Dry and wet soil blocks must differ' }
foreach ($waterBlock in @($soilData.water_blocks)) {
  if ($waterBlock -notin $knownBlocks) { throw "Unknown irrigation water block: $waterBlock" }
}
if ([int]$soilData.horizontal_radius -lt 1 -or [int]$soilData.horizontal_radius -gt 8) { throw 'Invalid irrigation horizontal radius' }
if ([int]$soilData.vertical_radius -lt 0 -or [int]$soilData.vertical_radius -gt 3) { throw 'Invalid irrigation vertical radius' }
if ([double]$soilData.manual_hydration_seconds -le 0) { throw 'Invalid manual hydration duration' }
if ([double]$soilData.dry_growth_multiplier -lt 0 -or [double]$soilData.dry_growth_multiplier -gt 1) { throw 'Invalid dry growth multiplier' }
if ([double]$soilData.wet_growth_multiplier -le 0) { throw 'Invalid wet growth multiplier' }
if ([int]$soilData.max_refresh_per_tick -lt 1) { throw 'Invalid soil refresh budget' }

Write-Host "PASS items=$($items.Count) tools=$toolCount armor=$armorCount equippable=$equippableCount equipment_slots=$($equipmentSlots.Count) crafting=$($recipes.Count) furnace=$($furnaceRecipes.Count) fuels=$($fuels.Count) harvest=$($harvestRules.Count) crops=$($crops.Count) soil_radius=$($soilData.horizontal_radius) maps=$($maps.Count) creatures=$creatureCount"
