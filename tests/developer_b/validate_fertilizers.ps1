$ErrorActionPreference = 'Stop'

$items = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\items.json" | ConvertFrom-Json).items
$recipes = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\recipes.json" | ConvertFrom-Json).recipes
$crops = (Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\crops.json" | ConvertFrom-Json).crops
$fertilizerData = Get-Content -Raw -Encoding UTF8 "$PSScriptRoot\..\..\data\fertilizers.json" | ConvertFrom-Json
$fertilizers = @($fertilizerData.fertilizers)

$itemIds = @{}
foreach ($item in $items) { $itemIds[[string]$item.id] = $true }
$cropIds = @{}
foreach ($crop in $crops) { $cropIds[[string]$crop.id] = $true }

if ([int]$fertilizerData.schema_version -lt 1) { throw 'Invalid fertilizer schema version' }
if ($fertilizers.Count -lt 1) { throw 'Expected at least one fertilizer profile' }

$profileIds = @{}
$fertilizerItems = @{}
foreach ($profile in $fertilizers) {
  $profileId = [string]$profile.id
  $itemId = [string]$profile.item_id
  if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'Fertilizer profile id is empty' }
  if ([string]::IsNullOrWhiteSpace($itemId)) { throw "Fertilizer item id is empty: $profileId" }
  if ($profileIds.ContainsKey($profileId)) { throw "Duplicate fertilizer profile: $profileId" }
  if ($fertilizerItems.ContainsKey($itemId)) { throw "Duplicate fertilizer item mapping: $itemId" }
  if (-not $itemIds.ContainsKey($itemId)) { throw "Unknown fertilizer item: $itemId" }
  if ([int]$profile.stage_advances -lt 1 -or [int]$profile.stage_advances -gt 3) {
    throw "Invalid fertilizer stage advance: $profileId"
  }
  foreach ($cropId in @($profile.allowed_crops)) {
    if (-not $cropIds.ContainsKey([string]$cropId)) {
      throw "Unknown allowed crop '$cropId' in fertilizer $profileId"
    }
  }
  $profileIds[$profileId] = $true
  $fertilizerItems[$itemId] = $true
}

if (-not $fertilizerItems.ContainsKey('compost')) { throw 'Missing compost fertilizer profile' }
$compostRecipe = @($recipes | Where-Object { $_.id -eq 'compost' })
if ($compostRecipe.Count -ne 1) { throw 'Expected exactly one compost recipe' }
if ([string]$compostRecipe[0].station -ne 'workbench') { throw 'Compost recipe must require the workbench' }
if ([string]$compostRecipe[0].output.id -ne 'compost' -or [int]$compostRecipe[0].output.count -lt 1) {
  throw 'Compost recipe has an invalid output'
}

Write-Host "PASS fertilizers=$($fertilizers.Count) compost_recipe=$($compostRecipe.Count) crops=$($crops.Count)"
