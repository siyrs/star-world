$ErrorActionPreference = 'Stop'
$items = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\items.json" | ConvertFrom-Json).items
$recipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\recipes.json" | ConvertFrom-Json).recipes
$maps = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\map_profiles.json" | ConvertFrom-Json).maps
$creatures = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\creatures.json" | ConvertFrom-Json).creatures

if ($items.Count -lt 30) { throw "Expected >=30 items, got $($items.Count)" }
if ($recipes.Count -lt 30) { throw "Expected >=30 recipes, got $($recipes.Count)" }
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
  foreach ($ingredient in $recipe.ingredients.PSObject.Properties.Name) {
    if (-not $ids.ContainsKey($ingredient)) { throw "Unknown ingredient $ingredient in $($recipe.id)" }
  }
  if (-not $ids.ContainsKey($recipe.output.id)) { throw "Unknown output $($recipe.output.id)" }
}

Write-Host "PASS items=$($items.Count) recipes=$($recipes.Count) maps=$($maps.Count) creatures=$creatureCount"
