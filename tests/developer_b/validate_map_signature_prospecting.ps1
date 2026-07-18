$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$mapData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\map_profiles.json') | ConvertFrom-Json
$itemData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json
$recipeData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json
$prospectingData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\prospecting.json') | ConvertFrom-Json
$journalData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\exploration_journal.json') | ConvertFrom-Json
$rewardData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\exploration_milestone_rewards.json') | ConvertFrom-Json
$resourceData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\resource_distribution.json') | ConvertFrom-Json
$ecologyData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creature_ecology.json') | ConvertFrom-Json
$catalogPath = Join-Path $root 'src\world\map_profile_catalog.gd'

$catalogText = Get-Content -Raw -Encoding UTF8 $catalogPath
$profileListMatch = [regex]::Match($catalogText, '(?s)const\s+PROFILE_IDS[^=]*=\s*\[(.*?)\]')
if (-not $profileListMatch.Success) { throw 'Unable to parse MapProfileCatalog.PROFILE_IDS' }
$catalogIds = @([regex]::Matches($profileListMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$catalogLabels = @{}
$labelMatch = [regex]::Match($catalogText, '(?s)const\s+LABELS\s*:=\s*\{(.*?)\}')
if (-not $labelMatch.Success) { throw 'Unable to parse MapProfileCatalog.LABELS' }
foreach ($match in [regex]::Matches($labelMatch.Groups[1].Value, '"([^"]+)"\s*:\s*"([^"]+)"')) {
  $catalogLabels[$match.Groups[1].Value] = $match.Groups[2].Value
}
$maps = @($mapData.maps)
if ($catalogIds.Count -ne $maps.Count) { throw "MapProfileCatalog count $($catalogIds.Count) does not match map data $($maps.Count)" }
foreach ($map in $maps) {
  $mapId = [string]$map.id
  if ($mapId -notin $catalogIds) { throw "MapProfileCatalog is missing $mapId" }
  if (-not $catalogLabels.ContainsKey($mapId) -or [string]$catalogLabels[$mapId] -ne [string]$map.name) { throw "MapProfileCatalog label mismatch for $mapId" }
}

$itemById = @{}
foreach ($item in @($itemData.items)) { $itemById[[string]$item.id] = $item }
$recipeByOutput = @{}
foreach ($recipe in @($recipeData.recipes)) { $recipeByOutput[[string]$recipe.output.id] = $recipe }
$toolByProfile = @{}
foreach ($tool in @($prospectingData.tools)) {
  $profileId = [string]$tool.required_profile_id
  if (-not [string]::IsNullOrWhiteSpace($profileId)) { $toolByProfile[$profileId] = [string]$tool.item_id }
}
$signatureReward = @($rewardData.rewards | Where-Object { [string]$_.milestone_id -eq 'signature_finding' })
if ($signatureReward.Count -ne 1) { throw "Expected one signature_finding reward, got $($signatureReward.Count)" }
$signatureMilestone = @($journalData.milestones | Where-Object { [string]$_.id -eq 'signature_finding' })
if ($signatureMilestone.Count -ne 1 -or [string]$signatureMilestone[0].kind -ne 'profile_rule') { throw 'Expected one profile-aware signature_finding milestone' }

$densityMinimum = @{}
foreach ($tier in @($prospectingData.density_tiers)) { $densityMinimum[[string]$tier.id] = [double]$tier.min_ratio }
$resourceRatio = @{}
foreach ($profile in @($resourceData.profiles)) {
  $entries = @($profile.entries)
  if ($entries.Count -lt 1) { throw "Resource profile has no entries: $($profile.id)" }
  $resourceRatio[[string]$profile.id] = [double]$entries[-1].cumulative_threshold / 10000.0
}
$ecologyById = @{}
foreach ($profile in @($ecologyData.profiles)) { $ecologyById[[string]$profile.id] = $profile }

$materialByProfile = @{
  star_continent = 'verdant_resonance'
  desert_ruins = 'ruin_sun_glass'
  frozen_wastes = 'frost_heart_crystal'
  sky_islands = 'sky_wind_crystal'
  abyss_world = 'abyss_cinder'
}
$expectedTools = @{
  star_continent = 'verdant_prospecting_kit'
  desert_ruins = 'ruin_prospecting_kit'
  frozen_wastes = 'frost_prospecting_kit'
  sky_islands = 'sky_prospecting_kit'
  abyss_world = 'abyss_prospecting_kit'
}
foreach ($mapId in $catalogIds) {
  $materialId = [string]$materialByProfile[$mapId]
  $toolId = [string]$expectedTools[$mapId]
  if (-not $itemById.ContainsKey($materialId)) { throw "Missing signature material item: $materialId" }
  $material = $itemById[$materialId]
  if ([string]$material.category -ne 'material' -or [int]$material.max_stack -gt 16) { throw "Invalid signature material contract: $materialId" }
  if ($null -ne $material.PSObject.Properties['block_id']) { throw "Signature material must not consume a block numeric id: $materialId" }
  if (-not $itemById.ContainsKey($toolId)) { throw "Missing calibrated prospecting tool: $toolId" }
  $toolItem = $itemById[$toolId]
  if ([string]$toolItem.category -ne 'utility' -or -not [bool]$toolItem.prospecting -or [int]$toolItem.max_stack -ne 1) { throw "Invalid calibrated prospecting tool contract: $toolId" }
  if (-not $toolByProfile.ContainsKey($mapId) -or [string]$toolByProfile[$mapId] -ne $toolId) { throw "Prospecting profile does not map $mapId to $toolId" }
  if (-not $recipeByOutput.ContainsKey($toolId)) { throw "Calibrated tool has no recipe: $toolId" }
  $recipe = $recipeByOutput[$toolId]
  if ([string]$recipe.station -ne 'workbench' -or [int]$recipe.output.count -ne 1) { throw "Invalid calibrated tool recipe: $toolId" }
  $baseIngredient = $recipe.ingredients.PSObject.Properties['prospecting_kit']
  $materialIngredient = $recipe.ingredients.PSObject.Properties[$materialId]
  if ($null -eq $baseIngredient -or [int]$baseIngredient.Value -ne 1 -or $null -eq $materialIngredient -or [int]$materialIngredient.Value -ne 1) {
    throw "Calibrated tool recipe must consume one base kit and one signature material: $toolId"
  }
  $profileBonusProperty = $signatureReward[0].profile_bonus.PSObject.Properties[$mapId]
  if ($null -eq $profileBonusProperty) { throw "Signature reward has no map bonus: $mapId" }
  $bonusItems = @($profileBonusProperty.Value)
  if ($bonusItems.Count -ne 1 -or [string]$bonusItems[0].item_id -ne $materialId -or [int]$bonusItems[0].count -ne 1) { throw "Signature reward does not grant the calibrated recipe material: $mapId" }

  $ruleProperty = $signatureMilestone[0].rules.PSObject.Properties[$mapId]
  if ($null -eq $ruleProperty) { throw "Signature milestone has no rule for $mapId" }
  $rule = $ruleProperty.Value
  $acceptedDensities = @($rule.density_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($acceptedDensities.Count -gt 0) {
    $reachable = $false
    foreach ($densityId in $acceptedDensities) {
      if (-not $densityMinimum.ContainsKey([string]$densityId)) { throw "Unknown density tier in signature rule: $mapId/$densityId" }
      if ([double]$densityMinimum[[string]$densityId] -le [double]$resourceRatio[$mapId]) { $reachable = $true }
    }
    if (-not $reachable) { throw "Signature density rule is unreachable with the production resource ceiling: $mapId max=$($resourceRatio[$mapId])" }
  }
  $acceptedDangers = @($rule.danger_tier_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($acceptedDangers.Count -gt 0) {
    if (-not $ecologyById.ContainsKey($mapId) -or [int]$ecologyById[$mapId].hostile_cap_night -lt 1) { throw "Signature danger rule has no production hostile pressure: $mapId" }
  }
}

Write-Host "PASS map signature catalog maps=$($catalogIds.Count) reachable_rules=$($catalogIds.Count) materials=$($materialByProfile.Count) calibrated_tools=$($toolByProfile.Count)"
