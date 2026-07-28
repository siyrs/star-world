$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path "$PSScriptRoot\..\.."
$generatorPath = Join-Path $projectRoot 'src\world\world_generator.gd'
$dataPath = Join-Path $projectRoot 'data\world_decoration_profiles.json'
$regressionPath = Join-Path $projectRoot 'tests\qa\world_decoration_hot_path_regression.gd'
$workflowPath = Join-Path $projectRoot '.github\workflows\world-decoration-poi-tests.yml'

foreach ($path in @($generatorPath, $dataPath, $regressionPath, $workflowPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing world-decoration hot-path contract file: $path"
  }
}

$data = Get-Content -Raw -Encoding UTF8 $dataPath | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) {
  throw 'World decoration production schema must remain exactly version 1'
}
if ([int]$data.max_rules_per_profile -ne 16) {
  throw 'World decoration production rule budget must remain exactly 16'
}

$generatorText = Get-Content -Raw -Encoding UTF8 $generatorPath
foreach ($required in @(
  'var _decoration_profile: Dictionary = {}',
  'var _decoration_tree_exclusion_density := 0',
  'var _decoration_profile_refresh_count := 0',
  'func _refresh_decoration_profile() -> void:',
  'snapshot["profile_refresh_count"]',
  'snapshot["cached_rule_count"]'
)) {
  if (-not $generatorText.Contains($required)) {
    throw "World generator is missing cached-decoration contract: $required"
  }
}

$configureMatch = [regex]::Match(
  $generatorText,
  '(?s)func configure\(.*?(?=\r?\nfunc normalize_profile_id)'
)
if (-not $configureMatch.Success -or -not $configureMatch.Value.Contains('_refresh_decoration_profile()')) {
  throw 'World generator configure() must refresh the normalized decoration profile once'
}

$hotPathMatch = [regex]::Match(
  $generatorText,
  '(?s)func _get_decoration_block\(.*?(?=\r?\nfunc _hash_roll)'
)
if (-not $hotPathMatch.Success) {
  throw 'Unable to locate _get_decoration_block hot path'
}
if ($hotPathMatch.Value.Contains('world_decorations.get_profile')) {
  throw 'Decoration block hot path must not deep-copy registry profiles'
}
if (-not $hotPathMatch.Value.Contains('_decoration_profile')) {
  throw 'Decoration block hot path must consume the configured profile cache'
}

$poiMatch = [regex]::Match(
  $generatorText,
  '(?s)func get_poi_snapshot\(.*?(?=\r?\nfunc get_block)'
)
if (-not $poiMatch.Success) {
  throw 'Unable to locate get_poi_snapshot()'
}
if ($poiMatch.Value.Contains('world_decorations.get_profile')) {
  throw 'POI snapshot hot path must not deep-copy registry profiles'
}
if (-not $poiMatch.Value.Contains('_decoration_profile')) {
  throw 'POI snapshot must consume the configured profile cache'
}

$regressionText = Get-Content -Raw -Encoding UTF8 $regressionPath
foreach ($required in @(
  'profile_refresh_count',
  'cached_rule_count',
  'thousands of block and POI queries reuse one cached profile',
  'switching map profiles refreshes the cache once and only once'
)) {
  if (-not $regressionText.Contains($required)) {
    throw "Hot-path regression is missing contract: $required"
  }
}

$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
foreach ($required in @(
  'validate_world_decoration_hot_path.ps1',
  'world_decoration_hot_path_regression.gd',
  'world_decoration_registry_regression.gd'
)) {
  if (-not $workflowText.Contains($required)) {
    throw "World decoration workflow is missing hot-path contract: $required"
  }
}

Write-Host 'PASS world decoration hot path uses one configured cache and exact schema/rule budgets'
