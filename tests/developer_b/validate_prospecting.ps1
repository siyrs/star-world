$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$config = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\prospecting.json') | ConvertFrom-Json
$items = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$recipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json).recipes)
$maps = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\map_profiles.json') | ConvertFrom-Json).maps)

if ([int]$config.schema_version -ne 2) { throw "Unsupported prospecting schema: $($config.schema_version)" }
$defaultToolId = [string]$config.default_tool_item_id
if ([string]::IsNullOrWhiteSpace($defaultToolId)) { throw 'Prospecting default_tool_item_id is empty' }

$itemById = @{}
foreach ($item in $items) { $itemById[[string]$item.id] = $item }
$recipeByOutput = @{}
foreach ($recipe in $recipes) {
  $outputId = [string]$recipe.output.id
  if (-not $recipeByOutput.ContainsKey($outputId)) { $recipeByOutput[$outputId] = @() }
  $recipeByOutput[$outputId] = @($recipeByOutput[$outputId]) + @($recipe)
}
$mapIds = @{}
foreach ($map in $maps) { $mapIds[[string]$map.id] = $true }

$tools = @($config.tools)
if ($tools.Count -ne 6) { throw "Expected six prospecting tools, got $($tools.Count)" }
$toolIds = @{}
$calibrations = @{}
$calibratedProfiles = @{}
foreach ($tool in $tools) {
  $toolId = [string]$tool.item_id
  $calibrationId = [string]$tool.calibration_id
  if ([string]::IsNullOrWhiteSpace($toolId) -or [string]::IsNullOrWhiteSpace($calibrationId)) { throw 'Prospecting tool identity is empty' }
  if ($toolIds.ContainsKey($toolId)) { throw "Duplicate prospecting tool: $toolId" }
  if ($calibrations.ContainsKey($calibrationId)) { throw "Duplicate prospecting calibration: $calibrationId" }
  $toolIds[$toolId] = $true
  $calibrations[$calibrationId] = $true
  if (-not $itemById.ContainsKey($toolId)) { throw "Prospecting tool item is missing: $toolId" }
  $item = $itemById[$toolId]
  if ([string]$item.category -ne 'utility' -or [int]$item.max_stack -ne 1 -or -not [bool]$item.prospecting) {
    throw "Invalid prospecting tool item contract: $toolId"
  }
  $toolRecipes = @($recipeByOutput[$toolId])
  if ($toolRecipes.Count -ne 1) { throw "Expected one recipe for prospecting tool ${toolId}, got $($toolRecipes.Count)" }
  if ([string]$toolRecipes[0].station -ne 'workbench' -or [int]$toolRecipes[0].output.count -ne 1) {
    throw "Prospecting tool recipe must produce one item at a workbench: $toolId"
  }
  $requiredProfile = [string]$tool.required_profile_id
  if (-not [string]::IsNullOrWhiteSpace($requiredProfile)) {
    if (-not $mapIds.ContainsKey($requiredProfile)) { throw "Unknown prospecting calibration profile: $requiredProfile" }
    if ($calibratedProfiles.ContainsKey($requiredProfile)) { throw "Duplicate calibrated prospecting profile: $requiredProfile" }
    $calibratedProfiles[$requiredProfile] = $toolId
    if ($null -eq $toolRecipes[0].ingredients.prospecting_kit) { throw "Calibrated tool must consume the base kit: $toolId" }
  }

  $resolved = @{}
  foreach ($field in @('horizontal_radius','vertical_radius','horizontal_step','vertical_step','max_samples','minimum_geology_samples','cooldown_seconds')) {
    $value = $config.$field
    if ($null -ne $tool.overrides -and $null -ne $tool.overrides.$field) { $value = $tool.overrides.$field }
    $resolved[$field] = $value
  }
  $horizontalRadius = [int]$resolved.horizontal_radius
  $verticalRadius = [int]$resolved.vertical_radius
  $horizontalStep = [int]$resolved.horizontal_step
  $verticalStep = [int]$resolved.vertical_step
  $maxSamples = [int]$resolved.max_samples
  $minimumGeology = [int]$resolved.minimum_geology_samples
  if ($horizontalRadius -lt 1 -or $horizontalRadius -gt 16) { throw "Invalid prospecting horizontal radius: $toolId" }
  if ($verticalRadius -lt 1 -or $verticalRadius -gt 24) { throw "Invalid prospecting vertical radius: $toolId" }
  if ($horizontalStep -lt 1 -or $horizontalStep -gt $horizontalRadius) { throw "Invalid prospecting horizontal step: $toolId" }
  if ($verticalStep -lt 1 -or $verticalStep -gt $verticalRadius) { throw "Invalid prospecting vertical step: $toolId" }
  $horizontalSamples = [math]::Floor((2 * $horizontalRadius) / $horizontalStep) + 1
  $verticalSamples = [math]::Floor((2 * $verticalRadius) / $verticalStep) + 1
  $theoreticalSamples = $horizontalSamples * $horizontalSamples * $verticalSamples
  if ($theoreticalSamples -gt $maxSamples) { throw "Prospecting theoretical sample count $theoreticalSamples exceeds max_samples $maxSamples for $toolId" }
  if ($maxSamples -lt 1 -or $maxSamples -gt 768) { throw "Prospecting max_samples exceeds the calibrated hard limit: $toolId" }
  if ($minimumGeology -lt 1 -or $minimumGeology -gt $maxSamples) { throw "Invalid minimum geology sample count: $toolId" }
  if ([double]$resolved.cooldown_seconds -lt 0 -or [double]$resolved.cooldown_seconds -gt 10) { throw "Invalid prospecting cooldown: $toolId" }
}
if (-not $toolIds.ContainsKey($defaultToolId)) { throw "Default prospecting tool is not registered: $defaultToolId" }
if ($calibratedProfiles.Count -ne $mapIds.Count) { throw "Expected one calibrated tool for every map, got $($calibratedProfiles.Count)" }
foreach ($mapId in $mapIds.Keys) {
  if (-not $calibratedProfiles.ContainsKey($mapId)) { throw "Map has no calibrated prospecting tool: $mapId" }
}

$baseRecipe = @($recipeByOutput[$defaultToolId])
foreach ($requiredIngredient in @('iron_ingot','coal','glass','stick')) {
  if ($null -eq $baseRecipe[0].ingredients.$requiredIngredient) { throw "Base prospecting recipe is missing $requiredIngredient" }
}

$maxRecords = [int]$config.max_records
if ($maxRecords -lt 1 -or $maxRecords -gt 256) { throw 'Invalid prospecting record budget' }
$geology = @($config.geology_blocks)
$oreProfiles = @($config.ore_blocks)
if ($oreProfiles.Count -ne 4) { throw "Expected four ore profiles, got $($oreProfiles.Count)" }
$oreIds = @{}
foreach ($ore in $oreProfiles) {
  $blockId = [string]$ore.block_id
  if ($oreIds.ContainsKey($blockId)) { throw "Duplicate prospecting ore: $blockId" }
  if ($blockId -notin $geology) { throw "Prospecting ore is missing from geology blocks: $blockId" }
  if ([string]::IsNullOrWhiteSpace([string]$ore.label)) { throw "Prospecting ore label is empty: $blockId" }
  $oreIds[$blockId] = $true
}
foreach ($requiredOre in @('coal_ore','iron_ore','gold_ore','diamond_ore')) {
  if (-not $oreIds.ContainsKey($requiredOre)) { throw "Missing prospecting ore profile: $requiredOre" }
}

$previousRatio = -1.0
foreach ($tier in @($config.density_tiers)) {
  $ratio = [double]$tier.min_ratio
  if ($ratio -le $previousRatio -or $ratio -lt 0 -or $ratio -gt 1) { throw 'Prospecting density tiers must be strictly increasing between 0 and 1' }
  $previousRatio = $ratio
}
$previousY = -1
foreach ($band in @($config.depth_bands)) {
  $maxY = [int]$band.max_y
  if ($maxY -le $previousY) { throw 'Prospecting depth bands must use increasing max_y values' }
  $previousY = $maxY
}
if ($previousY -lt 63) { throw 'Prospecting depth bands do not cover the full world height' }

Write-Host "PASS prospecting tools=$($tools.Count) calibrated_maps=$($calibratedProfiles.Count) max_records=$maxRecords ores=$($oreProfiles.Count)"
