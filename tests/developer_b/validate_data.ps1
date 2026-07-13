$ErrorActionPreference = 'Stop'
$items = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\items.json" | ConvertFrom-Json).items
$recipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\recipes.json" | ConvertFrom-Json).recipes
$furnaceRecipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\furnace_recipes.json" | ConvertFrom-Json).recipes
$fuels = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\fuels.json" | ConvertFrom-Json).fuels
$maps = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\map_profiles.json" | ConvertFrom-Json).maps
$creatures = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\creatures.json" | ConvertFrom-Json).creatures

if ($items.Count -lt 30) { throw "Expected >=30 items, got $($items.Count)" }
if ($recipes.Count -lt 30) { throw "Expected >=30 crafting recipes, got $($recipes.Count)" }
if ($furnaceRecipes.Count -lt 5) { throw "Expected >=5 furnace recipes, got $($furnaceRecipes.Count)" }
if ($fuels.Count -lt 2) { throw "Expected >=2 fuels, got $($fuels.Count)" }
if ($maps.Count -ne 5) { throw "Expected 5 map profiles, got $($maps.Count)" }
$creatureCount = @($creatures.PSObject.Properties).Count
if ($creatureCount -ne 4) { throw "Expected 4 creatures, got $creatureCount" }

$ids = @{}
foreach ($item in $items) {
  if ($ids.ContainsKey($item.id)) { throw "Duplicate item id: $($item.id)" }
  $ids[$item.id] = $true
  if ($item.max_stack -lt 1) { throw "Invalid stack limit: $($item.id)" }
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

Write-Host "PASS items=$($items.Count) crafting=$($recipes.Count) furnace=$($furnaceRecipes.Count) fuels=$($fuels.Count) maps=$($maps.Count) creatures=$creatureCount"
