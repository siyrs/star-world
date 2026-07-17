$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$ecology = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creature_ecology.json') | ConvertFrom-Json
$danger = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\exploration_danger.json') | ConvertFrom-Json
$maps = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\map_profiles.json') | ConvertFrom-Json).maps)
$creatures = (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creatures.json') | ConvertFrom-Json).creatures

if ([int]$ecology.schema_version -ne 1) { throw 'Creature ecology schema_version must be 1' }
$profiles = @($ecology.profiles)
if ($profiles.Count -ne $maps.Count) { throw "Ecology profile count $($profiles.Count) does not match maps $($maps.Count)" }
$knownSpecies = @($creatures.PSObject.Properties.Name)
$mapIds = @{}
foreach ($map in $maps) { $mapIds[[string]$map.id] = $true }
$profileIds = @{}
foreach ($profile in $profiles) {
  $id = [string]$profile.id
  if ([string]::IsNullOrWhiteSpace($id)) { throw 'Ecology profile id is empty' }
  if ($profileIds.ContainsKey($id)) { throw "Duplicate ecology profile: $id" }
  if (-not $mapIds.ContainsKey($id)) { throw "Ecology profile has no map: $id" }
  $profileIds[$id] = $true
  if ([double]$profile.spawn_interval_seconds -lt 1 -or [double]$profile.spawn_interval_seconds -gt 30) { throw "Invalid spawn interval: $id" }
  if ([int]$profile.passive_cap -lt 0 -or [int]$profile.hostile_cap_day -lt 0 -or [int]$profile.hostile_cap_night -lt [int]$profile.hostile_cap_day) { throw "Invalid ecology caps: $id" }
  if ([int]$profile.danger_base -lt 0 -or [int]$profile.danger_base -gt 60) { throw "Invalid danger base: $id" }
  foreach ($phase in @('day','dawn','dusk','night')) {
    $chance = [double]$profile.hostile_chance.$phase
    if ($chance -lt 0 -or $chance -gt 1) { throw "Invalid hostile chance $phase for $id" }
  }
  foreach ($category in @('passive_species','hostile_species')) {
    $seen = @{}
    foreach ($entry in @($profile.$category)) {
      $speciesId = [string]$entry.id
      if ($speciesId -notin $knownSpecies) { throw "Unknown species $speciesId in ${id}:$category" }
      if ($seen.ContainsKey($speciesId)) { throw "Duplicate species $speciesId in ${id}:$category" }
      if ([int]$entry.weight -le 0) { throw "Invalid species weight $speciesId in $id" }
      $seen[$speciesId] = $true
    }
  }
}
foreach ($mapId in $mapIds.Keys) { if (-not $profileIds.ContainsKey($mapId)) { throw "Map has no ecology profile: $mapId" } }
if (-not $profileIds.ContainsKey([string]$ecology.default_profile)) { throw 'Unknown default ecology profile' }
$abyss = $profiles | Where-Object { $_.id -eq 'abyss_world' }
if ([int]$abyss.hostile_cap_day -lt 1) { throw 'Abyss must keep daytime hostile pressure' }
$sky = $profiles | Where-Object { $_.id -eq 'sky_islands' }
$skyChicken = @($sky.passive_species | Where-Object { $_.id -eq 'chicken' })[0]
if ([int]$skyChicken.weight -lt 4) { throw 'Sky islands must strongly prefer chickens' }

if ([int]$danger.schema_version -ne 1) { throw 'Exploration danger schema_version must be 1' }
foreach ($field in @('assessment_interval_seconds','horizontal_radius','vertical_radius','horizontal_step','vertical_step','max_samples','hostile_radius')) {
  if ($null -eq $danger.$field) { throw "Missing danger field: $field" }
}
$horizontalCount = [math]::Ceiling((([int]$danger.horizontal_radius * 2) + 1) / [double][int]$danger.horizontal_step)
$verticalCount = [math]::Ceiling((([int]$danger.vertical_radius * 2) + 1) / [double][int]$danger.vertical_step)
$theoretical = [int]($horizontalCount * $horizontalCount * $verticalCount)
if ($theoretical -gt [int]$danger.max_samples) { throw "Danger sampling exceeds budget: $theoretical > $($danger.max_samples)" }
if ([int]$danger.max_samples -gt 512) { throw 'Danger sampling hard cap must remain <= 512' }
$previousY = -1
foreach ($entry in @($danger.depth_scores)) {
  if ([int]$entry.max_y -le $previousY) { throw 'Danger depth scores are not ordered' }
  $previousY = [int]$entry.max_y
}
if ($previousY -lt 63) { throw 'Danger depth scores do not cover Y63' }
$previousScore = -1
$tierIds = @{}
foreach ($tier in @($danger.tiers)) {
  $id = [string]$tier.id
  if ($tierIds.ContainsKey($id)) { throw "Duplicate danger tier: $id" }
  if ([int]$tier.max_score -le $previousScore) { throw 'Danger tiers are not ordered' }
  $tierIds[$id] = $true
  $previousScore = [int]$tier.max_score
}
if ($previousScore -lt 100) { throw 'Danger tiers do not cover score 100' }
foreach ($required in @('safe','guarded','dangerous','severe')) { if (-not $tierIds.ContainsKey($required)) { throw "Missing danger tier: $required" } }

Write-Host "PASS ecology_profiles=$($profiles.Count) species=$($knownSpecies.Count) danger_samples=$theoretical tiers=$($tierIds.Count)"
