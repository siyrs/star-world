$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path "$PSScriptRoot\..\.."
$registryPath = Join-Path $projectRoot 'data\world_decoration_profiles.json'
$mapPath = Join-Path $projectRoot 'data\map_profiles.json'
$generatorPath = Join-Path $projectRoot 'src\world\world_generator.gd'
$registryScriptPath = Join-Path $projectRoot 'src\world\world_decoration_registry.gd'
$policyPath = Join-Path $projectRoot 'src\world\world_decoration_policy.gd'
$panelPath = Join-Path $projectRoot 'src\ui\map_selection_panel.gd'
$workflowPath = Join-Path $projectRoot '.github\workflows\world-decoration-poi-tests.yml'
$regressionPath = Join-Path $projectRoot 'tests\qa\world_decoration_registry_regression.gd'
$desktopPath = Join-Path $projectRoot 'tests\qa\world_decoration_desktop_acceptance.gd'

foreach ($path in @(
  $registryPath,
  $mapPath,
  $generatorPath,
  $registryScriptPath,
  $policyPath,
  $panelPath,
  $workflowPath,
  $regressionPath,
  $desktopPath
)) {
  if (-not (Test-Path $path)) { throw "Missing world decoration contract file: $path" }
}

$data = Get-Content -Raw -Encoding UTF8 $registryPath | ConvertFrom-Json
$maps = @((Get-Content -Raw -Encoding UTF8 $mapPath | ConvertFrom-Json).maps)
$profiles = @($data.profiles)
$allowedTypes = @('surface_roll','column_roll','ruin_grid','ruin_debris')
$knownBlocks = @('tall_grass','flower_red','flower_yellow','ruin_pillar','cactus','dead_bush','glow_crystal')

if ([int]$data.schema_version -ne 1) { throw 'World decoration schema_version must remain 1' }
if ([int]$data.max_rules_per_profile -lt 1 -or [int]$data.max_rules_per_profile -gt 16) {
  throw 'World decoration rule budget must be between 1 and 16'
}
if ($profiles.Count -ne $maps.Count) {
  throw "Decoration profile count $($profiles.Count) does not match map count $($maps.Count)"
}

$mapIds = @{}
foreach ($map in $maps) {
  $mapId = [string]$map.id
  if ([string]::IsNullOrWhiteSpace($mapId)) { throw 'Map id is empty' }
  if ($mapIds.ContainsKey($mapId)) { throw "Duplicate map id: $mapId" }
  $mapIds[$mapId] = $true
}

$profileIds = @{}
foreach ($profile in $profiles) {
  $profileId = [string]$profile.id
  if ([string]::IsNullOrWhiteSpace($profileId)) { throw 'Decoration profile id is empty' }
  if ($profileIds.ContainsKey($profileId)) { throw "Duplicate decoration profile: $profileId" }
  if (-not $mapIds.ContainsKey($profileId)) { throw "Decoration profile has no map: $profileId" }
  $profileIds[$profileId] = $true
  if ([string]::IsNullOrWhiteSpace([string]$profile.summary)) {
    throw "Decoration summary is empty: $profileId"
  }
  $rules = @($profile.rules)
  if ($rules.Count -lt 1 -or $rules.Count -gt [int]$data.max_rules_per_profile) {
    throw "Decoration rule count is outside budget for ${profileId}: $($rules.Count)"
  }
  $ruleIds = @{}
  foreach ($rule in $rules) {
    $ruleId = [string]$rule.id
    $ruleType = [string]$rule.type
    $blockId = [string]$rule.block_id
    if ([string]::IsNullOrWhiteSpace($ruleId)) { throw "Rule id is empty in $profileId" }
    if ($ruleIds.ContainsKey($ruleId)) { throw "Duplicate rule '$ruleId' in $profileId" }
    $ruleIds[$ruleId] = $true
    if ($ruleType -notin $allowedTypes) { throw "Unknown rule type '$ruleType' in $profileId" }
    if ($blockId -notin $knownBlocks) { throw "Unknown decoration block '$blockId' in $profileId" }
    if ($ruleType -eq 'surface_roll') {
      $minimum = [int]$rule.minimum_roll
      $maximum = [int]$rule.maximum_roll
      if ($minimum -lt 0 -or $maximum -le $minimum -or $maximum -gt 10000) {
        throw "Invalid surface roll range in ${profileId}/${ruleId}"
      }
    }
    if ($ruleType -eq 'column_roll' -or $ruleType -eq 'ruin_debris') {
      $maximum = [int]$rule.maximum_roll
      if ($maximum -le 0 -or $maximum -gt 10000) {
        throw "Invalid bounded probability in ${profileId}/${ruleId}"
      }
    }
    if ($ruleType -like 'ruin_*') {
      $cellSize = [int]$rule.cell_size
      $siteMinimum = [int]$rule.site_minimum_roll
      $radius = [int]$rule.local_radius
      if ($cellSize -lt 16 -or $cellSize -gt 256) { throw "Invalid POI cell size in ${profileId}/${ruleId}" }
      if ($siteMinimum -lt 0 -or $siteMinimum -ge 10000) { throw "Invalid POI activation threshold in ${profileId}/${ruleId}" }
      if ($radius -lt 1 -or $radius -gt ($cellSize / 2)) { throw "Invalid POI radius in ${profileId}/${ruleId}" }
    }
  }
}

foreach ($mapId in $mapIds.Keys) {
  if (-not $profileIds.ContainsKey($mapId)) { throw "Map has no decoration profile: $mapId" }
}
if (-not $profileIds.ContainsKey([string]$data.default_profile)) {
  throw "Unknown default decoration profile: $($data.default_profile)"
}

$generatorText = Get-Content -Raw -Encoding UTF8 $generatorPath
foreach ($required in @(
  'WorldDecorationRegistryScript',
  'WorldDecorationPolicyScript.resolve_block',
  'get_decoration_profile_snapshot',
  'get_poi_snapshot'
)) {
  if (-not $generatorText.Contains($required)) { throw "World generator is missing '$required'" }
}
foreach ($legacy in @('_cactus_height', '_ruin_site_center', '_ruin_pillar_height', '_ruin_debris_here')) {
  if ($generatorText.Contains("func $legacy")) { throw "Legacy hard-coded decoration helper remains: $legacy" }
}

$panelText = Get-Content -Raw -Encoding UTF8 $panelPath
if (-not $panelText.Contains('get_decoration_summary')) { throw 'Map selection does not expose decoration summary' }
if (-not $panelText.Contains('地表地标')) { throw 'Map selection does not label player-facing POI identity' }

$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
foreach ($required in @(
  'validate_world_decoration_registry.ps1',
  'world_decoration_registry_regression.gd',
  'world_decoration_desktop_acceptance.gd'
)) {
  if (-not $workflowText.Contains($required)) { throw "World decoration workflow is missing '$required'" }
}

Write-Host "PASS world decoration profiles=$($profiles.Count) max_rules=$($data.max_rules_per_profile) default=$($data.default_profile)"
