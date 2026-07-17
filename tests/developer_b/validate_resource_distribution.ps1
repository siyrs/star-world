$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path "$PSScriptRoot\..\.."
$resourcePath = Join-Path $projectRoot 'data\resource_distribution.json'
$mapPath = Join-Path $projectRoot 'data\map_profiles.json'

$resourceData = Get-Content -Raw -Encoding UTF8 $resourcePath | ConvertFrom-Json
$mapData = Get-Content -Raw -Encoding UTF8 $mapPath | ConvertFrom-Json
$profiles = @($resourceData.profiles)
$maps = @($mapData.maps)

if ([int]$resourceData.schema_version -lt 1) { throw 'Resource distribution schema_version must be >= 1' }
if ($profiles.Count -ne $maps.Count) { throw "Resource profile count $($profiles.Count) does not match map count $($maps.Count)" }

$knownBlocks = @('stone','coal_ore','iron_ore','gold_ore','diamond_ore')
$requiredOres = @('diamond_ore','gold_ore','iron_ore','coal_ore')
$mapIds = @{}
foreach ($map in $maps) {
  $mapId = [string]$map.id
  if ([string]::IsNullOrWhiteSpace($mapId)) { throw 'Map profile id is empty' }
  if ($mapIds.ContainsKey($mapId)) { throw "Duplicate map profile: $mapId" }
  $mapIds[$mapId] = $true
}

$profileIds = @{}
foreach ($profile in $profiles) {
  $profileId = [string]$profile.id
  if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'Resource profile id is empty' }
  if ($profileIds.ContainsKey($profileId)) { throw "Duplicate resource profile: $profileId" }
  if (-not $mapIds.ContainsKey($profileId)) { throw "Resource profile has no matching map: $profileId" }
  $profileIds[$profileId] = $true
  if ([string]::IsNullOrWhiteSpace([string]$profile.name)) { throw "Resource profile name is empty: $profileId" }
  if ([string]::IsNullOrWhiteSpace([string]$profile.summary)) { throw "Resource profile summary is empty: $profileId" }
  if ([string]$profile.fallback_block -notin $knownBlocks) { throw "Unknown fallback block for ${profileId}: $($profile.fallback_block)" }

  $entries = @($profile.entries)
  if ($entries.Count -ne $requiredOres.Count) { throw "Expected four resource entries for $profileId, got $($entries.Count)" }
  $entryIds = @{}
  $previousThreshold = 0
  foreach ($entry in $entries) {
    $blockId = [string]$entry.block_id
    if ($blockId -notin $requiredOres) { throw "Unknown resource block '$blockId' for $profileId" }
    if ($entryIds.ContainsKey($blockId)) { throw "Duplicate resource block '$blockId' for $profileId" }
    $entryIds[$blockId] = $true
    $minY = [int]$entry.min_y
    $maxY = [int]$entry.max_y
    $threshold = [int]$entry.cumulative_threshold
    if ($minY -lt 0 -or $maxY -lt $minY -or $maxY -gt 63) { throw "Invalid resource height range for $blockId in $profileId" }
    if ($threshold -le $previousThreshold -or $threshold -ge 10000) { throw "Thresholds must be strictly increasing and below 10000 for $profileId" }
    $previousThreshold = $threshold
  }
  foreach ($requiredOre in $requiredOres) {
    if (-not $entryIds.ContainsKey($requiredOre)) { throw "Missing $requiredOre in resource profile $profileId" }
  }
}

foreach ($mapId in $mapIds.Keys) {
  if (-not $profileIds.ContainsKey($mapId)) { throw "Map has no resource distribution profile: $mapId" }
}
$defaultProfile = [string]$resourceData.default_profile
if (-not $profileIds.ContainsKey($defaultProfile)) { throw "Unknown default resource profile: $defaultProfile" }

Write-Host "PASS resource distributions=$($profiles.Count) maps=$($maps.Count) default=$defaultProfile"
