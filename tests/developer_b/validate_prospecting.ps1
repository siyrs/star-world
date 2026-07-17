$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$config = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\prospecting.json') | ConvertFrom-Json
$items = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$recipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json).recipes)

if ([int]$config.schema_version -ne 1) { throw "Unsupported prospecting schema: $($config.schema_version)" }
$toolId = [string]$config.tool_item_id
if ([string]::IsNullOrWhiteSpace($toolId)) { throw 'Prospecting tool_item_id is empty' }
$tool = @($items | Where-Object { [string]$_.id -eq $toolId })
if ($tool.Count -ne 1) { throw "Expected one prospecting tool item, got $($tool.Count)" }
if ([string]$tool[0].category -ne 'utility') { throw 'Prospecting tool must use category=utility' }
if ([int]$tool[0].max_stack -ne 1) { throw 'Prospecting tool must not stack' }
if (-not [bool]$tool[0].prospecting) { throw 'Prospecting tool is missing prospecting=true' }

$recipe = @($recipes | Where-Object { [string]$_.output.id -eq $toolId })
if ($recipe.Count -ne 1) { throw "Expected one prospecting recipe, got $($recipe.Count)" }
if ([string]$recipe[0].station -ne 'workbench') { throw 'Prospecting tool must require the workbench' }
if ([int]$recipe[0].output.count -ne 1) { throw 'Prospecting recipe must output exactly one tool' }
foreach ($ingredient in $recipe[0].ingredients.PSObject.Properties) {
  if ([int]$ingredient.Value -lt 1) { throw "Invalid prospecting ingredient count: $($ingredient.Name)" }
}
foreach ($requiredIngredient in @('iron_ingot','coal','glass','stick')) {
  if ($null -eq $recipe[0].ingredients.$requiredIngredient) {
    throw "Prospecting recipe is missing $requiredIngredient"
  }
}

$horizontalRadius = [int]$config.horizontal_radius
$verticalRadius = [int]$config.vertical_radius
$horizontalStep = [int]$config.horizontal_step
$verticalStep = [int]$config.vertical_step
$maxSamples = [int]$config.max_samples
$minimumGeology = [int]$config.minimum_geology_samples
$maxRecords = [int]$config.max_records
if ($horizontalRadius -lt 1 -or $horizontalRadius -gt 16) { throw 'Invalid prospecting horizontal radius' }
if ($verticalRadius -lt 1 -or $verticalRadius -gt 24) { throw 'Invalid prospecting vertical radius' }
if ($horizontalStep -lt 1 -or $verticalStep -lt 1) { throw 'Invalid prospecting sample step' }
$horizontalSamples = [math]::Floor((2 * $horizontalRadius) / $horizontalStep) + 1
$verticalSamples = [math]::Floor((2 * $verticalRadius) / $verticalStep) + 1
$theoreticalSamples = $horizontalSamples * $horizontalSamples * $verticalSamples
if ($theoreticalSamples -gt $maxSamples) {
  throw "Prospecting theoretical sample count $theoreticalSamples exceeds max_samples $maxSamples"
}
if ($maxSamples -gt 2048) { throw 'Prospecting max_samples exceeds hard safety limit' }
if ($minimumGeology -lt 1 -or $minimumGeology -gt $maxSamples) { throw 'Invalid minimum geology sample count' }
if ([double]$config.cooldown_seconds -lt 0 -or [double]$config.cooldown_seconds -gt 10) { throw 'Invalid prospecting cooldown' }
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
  if ($ratio -le $previousRatio -or $ratio -lt 0 -or $ratio -gt 1) {
    throw 'Prospecting density tiers must be strictly increasing between 0 and 1'
  }
  $previousRatio = $ratio
}
$previousY = -1
foreach ($band in @($config.depth_bands)) {
  $maxY = [int]$band.max_y
  if ($maxY -le $previousY) { throw 'Prospecting depth bands must use increasing max_y values' }
  $previousY = $maxY
}
if ($previousY -lt 63) { throw 'Prospecting depth bands do not cover the full world height' }

Write-Host "PASS prospecting tool=$toolId samples=$theoreticalSamples max_records=$maxRecords ores=$($oreProfiles.Count)"
