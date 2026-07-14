$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..\..'
$attraction = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\animal_attraction.json') | ConvertFrom-Json
$products = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\animal_products.json') | ConvertFrom-Json
$husbandry = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\husbandry.json') | ConvertFrom-Json
$items = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$furnaceRecipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\furnace_recipes.json') | ConvertFrom-Json).recipes)

$itemIds = @{}
foreach ($item in $items) {
  $itemIds[[string]$item.id] = $true
}
$speciesIds = @($husbandry.species.PSObject.Properties.Name)

if ([int]$attraction.schema_version -lt 1) { throw 'Animal attraction schema version is invalid' }
if ([double]$attraction.refresh_seconds -lt 0.05 -or [double]$attraction.refresh_seconds -gt 2.0) {
  throw 'Animal attraction refresh interval is outside the supported budget'
}
if ([double]$attraction.target_timeout_seconds -le [double]$attraction.refresh_seconds) {
  throw 'Animal attraction target timeout must exceed the refresh interval'
}
$attractionSpecies = @($attraction.species.PSObject.Properties)
if ($attractionSpecies.Count -ne 3) { throw "Expected 3 attraction species, got $($attractionSpecies.Count)" }
foreach ($property in $attractionSpecies) {
  $speciesId = [string]$property.Name
  $profile = $property.Value
  if ($speciesId -notin $speciesIds) { throw "Unknown attraction species: $speciesId" }
  if ([double]$profile.follow_radius -le 1.0 -or [double]$profile.follow_radius -gt 32.0) {
    throw "Invalid follow radius for $speciesId"
  }
  if ([double]$profile.stop_distance -le 0.0 -or [double]$profile.stop_distance -ge [double]$profile.follow_radius) {
    throw "Invalid stop distance for $speciesId"
  }
  $feedItem = [string]$husbandry.species.$speciesId.feed_item
  if (-not $itemIds.ContainsKey($feedItem)) { throw "Unknown feed item $feedItem for $speciesId" }
}

if ([int]$products.schema_version -lt 1) { throw 'Animal product schema version is invalid' }
if ([double]$products.update_interval_seconds -le 0.0) { throw 'Animal product update interval must be positive' }
if ([double]$products.max_offline_seconds -lt 0.0 -or [double]$products.max_offline_seconds -gt 86400.0) {
  throw 'Animal product offline budget is invalid'
}
if ([double]$products.pickup_spawn_radius -lt 2.0 -or [double]$products.pickup_spawn_radius -gt 48.0) {
  throw 'Animal product pickup radius is invalid'
}
$productProfiles = @($products.profiles)
if ($productProfiles.Count -lt 1) { throw 'At least one animal product profile is required' }
$profileIds = @{}
$productSpecies = @{}
foreach ($profile in $productProfiles) {
  $profileId = [string]$profile.id
  $speciesId = [string]$profile.species_id
  $productItem = [string]$profile.product_item
  if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'Animal product profile id is empty' }
  if ($profileIds.ContainsKey($profileId)) { throw "Duplicate animal product profile: $profileId" }
  $profileIds[$profileId] = $true
  if ($speciesId -notin $speciesIds) { throw "Unknown animal product species: $speciesId" }
  if ($productSpecies.ContainsKey($speciesId)) { throw "Duplicate animal product species mapping: $speciesId" }
  $productSpecies[$speciesId] = $true
  if (-not $itemIds.ContainsKey($productItem)) { throw "Unknown animal product item: $productItem" }
  if ([double]$profile.interval_seconds -lt 5.0) { throw "Animal product interval is too small: $profileId" }
  if ([int]$profile.max_pending -lt 1 -or [int]$profile.max_pending -gt 64) {
    throw "Animal product pending limit is invalid: $profileId"
  }
}

foreach ($requiredItem in @('egg', 'cooked_egg')) {
  if (-not $itemIds.ContainsKey($requiredItem)) { throw "Missing ranch product item: $requiredItem" }
}
$eggRecipe = $furnaceRecipes | Where-Object { [string]$_.id -eq 'cook_egg' } | Select-Object -First 1
if ($null -eq $eggRecipe) { throw 'Missing cook_egg furnace recipe' }
if ([string]$eggRecipe.input.id -ne 'egg' -or [string]$eggRecipe.output.id -ne 'cooked_egg') {
  throw 'cook_egg recipe has an invalid input or output'
}
if ([double]$eggRecipe.duration_seconds -le 0.0) { throw 'cook_egg duration must be positive' }

Write-Host "PASS ranch attraction_species=$($attractionSpecies.Count) product_profiles=$($productProfiles.Count) egg_recipe=$([string]$eggRecipe.id)"
