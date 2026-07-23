$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'src\save\world_catalog_policy.gd'
$savePath = Join-Path $root 'src\save\save_service.gd'
$cacheWorldPath = Join-Path $root 'src\world\cached_batched_voxel_world.gd'
$worldPath = Join-Path $root 'src\world\persistent_cached_batched_voxel_world.gd'
$gamePath = Join-Path $root 'src\core\batched_game.gd'
$browserPath = Join-Path $root 'src\ui\save_browser_panel.gd'
$regressionPath = Join-Path $root 'tests\qa\world_catalog_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\world_catalog_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\world-catalog-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\WORLD_CATALOG.md'
$auditPath = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_29.md'
$roadmapPath = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
$readmePath = Join-Path $root 'README.md'

foreach ($path in @(
  $policyPath,$savePath,$cacheWorldPath,$worldPath,$gamePath,$browserPath,
  $regressionPath,$desktopPath,$workflowPath,$runAllPath,$contractPath,
  $auditPath,$roadmapPath,$readmePath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing world catalog contract file: $path" }
}

$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$save = Get-Content -Raw -Encoding UTF8 $savePath
$cacheWorld = Get-Content -Raw -Encoding UTF8 $cacheWorldPath
$world = Get-Content -Raw -Encoding UTF8 $worldPath
$game = Get-Content -Raw -Encoding UTF8 $gamePath
$browser = Get-Content -Raw -Encoding UTF8 $browserPath
$regression = Get-Content -Raw -Encoding UTF8 $regressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath
$audit = Get-Content -Raw -Encoding UTF8 $auditPath
$roadmap = Get-Content -Raw -Encoding UTF8 $roadmapPath
$readme = Get-Content -Raw -Encoding UTF8 $readmePath

foreach ($token in @(
  'CATALOG_VERSION\s*:=\s*1',
  'MAX_TEXT_LENGTH\s*:=\s*128',
  'METADATA_FIELDS',
  'static\s+func\s+build_entry\s*\(',
  'static\s+func\s+normalize_entry\s*\(',
  'static\s+func\s+metadata_for_list\s*\(',
  'static\s+func\s+_normalize_metadata\s*\(',
  'expected_save_bytes',
  'catalog_source',
  'map_profile'
)) {
  if ($policy -notmatch $token) { throw "World catalog policy is missing bounded contract: $token" }
}

foreach ($token in @(
  'CATALOG_FILE_NAME\s*:=\s*"catalog\.json"',
  'func\s+list_worlds\s*\(',
  'func\s+get_catalog_diagnostics\s*\(',
  'func\s+reset_catalog_diagnostics\s*\(',
  'func\s+_read_catalog_entry\s*\(',
  'func\s+_write_catalog_entry\s*\(',
  'last_avoided_world_bytes',
  'world_fallback',
  'world\.erase\("loaded_chunks"\)'
)) {
  if ($save -notmatch $token) { throw "Save service is missing world catalog behavior: $token" }
}
if ($save -match 'list_worlds_legacy_full_read') {
  throw 'Production save service must not retain a second full-read world listing API'
}
if ($save -notmatch 'func\s+list_worlds[\s\S]*?_read_catalog_entry[\s\S]*?_read_world_payload') {
  throw 'World listing must attempt the lightweight catalog before authoritative fallback'
}
if ($save -notmatch 'if\s+not\s+_write_catalog_entry[\s\S]*?_catalog_write_failure_count\s*\+=\s*1[\s\S]*?world_saved\.emit') {
  throw 'Derived catalog failure must be diagnostic-only after an authoritative world save'
}

if ($cacheWorld -match 'func\s+serialize\s*\(') {
  throw 'Recent Chunk cache composition must remain transient and must not own persistence'
}
if ($world -notmatch 'extends\s+"res://src/world/cached_batched_voxel_world\.gd"') {
  throw 'Production persistence projection must preserve cached and batched world behavior'
}
$serializeMatch = [regex]::Match($world, 'func\s+serialize\s*\(\)\s*->\s*Dictionary\s*:[\s\S]*?(?=\n\nfunc\s+)')
if (-not $serializeMatch.Success) { throw 'Production world projection must own its sparse persistence surface' }
if ($serializeMatch.Value -notmatch '"block_overrides"\s*:\s*serialize_sparse_overrides\(\)') {
  throw 'Production world serialization must retain sparse block overrides'
}
if ($serializeMatch.Value -match '"loaded_chunks"|recent_chunk_cache|rebuild|pending') {
  throw 'Production world serialization must not construct transient streaming or cache state'
}
if ($game -notmatch 'persistent_cached_batched_voxel_world\.gd') {
  throw 'Production GameScene must compose the sparse persistence projection'
}

foreach ($token in @('save_bytes','func\s+_format_bytes','last_elapsed_milliseconds','已修复')) {
  if ($browser -notmatch $token) { throw "Save browser is missing catalog size or latency UX: $token" }
}

foreach ($phrase in @(
  'catalog policy whitelists required fields and excludes unbounded metadata',
  'fresh world listing reads sidecars without parsing authoritative payloads',
  'missing catalog falls back once and self-heals',
  'corrupt catalog uses authoritative fallback and repairs itself',
  'catalog optimization leaves full world loading unchanged',
  'legacy transient Chunk coordinates are removed during load migration'
)) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "World catalog regression is missing assertion: $phrase" }
}
foreach ($token in @(
  'WORLD_COUNT\s*:=\s*12',
  'OVERRIDES_PER_WORLD\s*:=\s*2048',
  'MAX_CATALOG_BYTES\s*:=\s*4096',
  'MIN_AVOIDED_WORLD_BYTES',
  'world-catalog-desktop\.json'
)) {
  if ($desktop -notmatch $token -and -not ($token -eq 'world-catalog-desktop\.json' -and $desktop -match 'get_basename\(\)\s*\+\s*"\.json"')) {
    throw "World catalog desktop acceptance is missing scale evidence: $token"
  }
}
foreach ($phrase in @(
  'excludes unbounded metadata extensions from the catalog',
  'missing and corrupt sidecars never hide real worlds',
  'steady-state diagnostics account for every avoided benchmark payload byte',
  'real save row shows a human-readable authoritative file size',
  'desktop acceptance resolves the selected row without full world reads',
  'save browser continue button starts the selected full world',
  'full load restores every large-world override after catalog selection'
)) {
  if ($desktop -notmatch [regex]::Escape($phrase)) { throw "World catalog desktop acceptance is missing assertion: $phrase" }
}

if ($workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml') {
  throw 'World catalog workflow must use the reusable Godot quality gate'
}
foreach ($token in @('validate_world_catalog\.ps1','world_catalog_regression\.gd','world_catalog_desktop_acceptance\.gd','world-catalog-desktop\.json')) {
  if ($workflow -notmatch $token) { throw "World catalog workflow is missing validation or evidence: $token" }
}
if ($runAll -notmatch 'validate_world_catalog\.ps1' -or $runAll -notmatch 'world_catalog_regression\.gd') {
  throw 'Full regression entry point must retain world catalog validation and domain regression'
}

foreach ($token in @('world\.json','catalog\.json','派生','自愈','严格白名单','loaded_chunks','避免读取')) {
  if ($contract -notmatch $token) { throw "World catalog contract is missing boundary documentation: $token" }
}
foreach ($token in @('list_worlds','完整 JSON','loaded_chunks','第二权威来源','12 个世界')) {
  if ($audit -notmatch $token) { throw "Architecture audit is missing the original catalog problem or real scale: $token" }
}
if ($roadmap -notmatch '轻量世界目录' -or $roadmap -notmatch '跨 Chunk') {
  throw 'Product roadmap must record the completed catalog and current structural scale priority'
}
if ($roadmap -match '## 下一阶段重点[\s\S]{0,500}### 1\. 双格木门与开关状态') {
  throw 'Product roadmap must not keep already completed double doors as the next milestone'
}
if ($readme -notmatch '轻量世界目录' -or $readme -notmatch '存档大小') {
  throw 'README must expose the faster world browser and save-size feedback'
}

Write-Host 'PASS world_catalog authority=world.json cache=catalog.json whitelist=7 worlds=12 overrides=24576 fallback=self-healing persistence=projection cache=transient ui=size+latency ci=reusable'
