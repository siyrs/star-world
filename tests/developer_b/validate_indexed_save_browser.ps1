$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  policy = Join-Path $root 'src\ui\save_browser_query_policy.gd'
  policy_regression = Join-Path $root 'tests\qa\save_browser_query_policy_regression.gd'
  browser_regression = Join-Path $root 'tests\qa\indexed_save_browser_regression.gd'
  desktop = Join-Path $root 'tests\qa\indexed_save_browser_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\indexed-save-browser-tests.yml'
  contract = Join-Path $root 'docs\INDEXED_SAVE_BROWSER.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-25_ITERATION_39.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing indexed save browser file: $($paths[$name])"
  }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

function Get-MethodBody([string]$Text, [string]$MethodName) {
  $pattern = '(?ms)^func\s+' + [regex]::Escape($MethodName) + '\s*\([^\n]*\).*?(?=^func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'save_browser_query_policy\.gd',
  '_world_by_id:\s*Dictionary',
  '_filtered_world_ids:\s*Array\[String\]',
  'func\s+apply_query\s*\(',
  'func\s+clear_query\s*\(',
  'func\s+_rebuild_world_index\s*\(',
  'func\s+_rebuild_filtered_world_ids\s*\(',
  'func\s+_clear_hidden_selection\s*\(',
  'LineEdit\.new\(\)',
  'OptionButton\.new\(\)',
  'text_submitted\.connect',
  'item_selected\.connect',
  '搜索名称 / ID / 地图 / Seed',
  '名称 A-Z',
  '存档从大到小',
  '匹配 %d / 共 %d'
)) {
  Assert-Match $text.browser $token "Save browser lost indexed search behavior: $token"
}

$refreshBody = Get-MethodBody $text.browser '_perform_refresh'
Assert-NoMatch $refreshBody 'duplicate\(true\)' 'Refresh must not deep-copy every metadata dictionary'
Assert-Match $refreshBody '_rebuild_world_index\(raw_worlds\)' 'Refresh must rebuild the explicit world-id index'

$indexBody = Get-MethodBody $text.browser '_rebuild_world_index'
Assert-Match $indexBody '_world_by_id\[world_id\]\s*=\s*metadata' 'Index rebuild must retain one direct metadata lookup per stable world id'
Assert-NoMatch $indexBody 'duplicate\(true\)' 'Index rebuild must preserve shallow read-only metadata references'

$lookupBody = Get-MethodBody $text.browser '_metadata_for_world'
Assert-Match $lookupBody '_world_by_id\.get\(' 'Metadata lookup must use the direct id index'
Assert-NoMatch $lookupBody 'for\s+' 'Metadata lookup must not linearly scan every world'
Assert-NoMatch $text.browser 'text_changed\.connect' 'Search must not rescan the full in-memory directory for every keystroke'

foreach ($token in @(
  'MAX_QUERY_LENGTH\s*:=\s*64',
  'MAX_QUERY_TOKENS\s*:=\s*8',
  'SORT_UPDATED_DESC',
  'SORT_NAME_ASC',
  'SORT_SIZE_DESC',
  'seen_world_ids',
  'metadata\.get\("name"',
  'metadata\.get\("id"',
  'metadata\.get\("map_id"',
  'metadata\.get\("seed"',
  'naturalnocasecmp_to',
  'save_bytes',
  'updated_at'
)) {
  Assert-Match $text.policy $token "Query policy lost bounded deterministic behavior: $token"
}
Assert-NoMatch $text.policy 'FileAccess|DirAccess|load_world|list_worlds' 'Pure query policy must never touch storage or services'

foreach ($phrase in @(
  'query normalization trims, lowercases and enforces the sixty-four-character limit',
  'query tokens are unique and capped at eight',
  'default sorting is deterministic newest-first and removes duplicate ids',
  'name search returns all sixty-four matching worlds',
  'map id is searchable without reading world payloads',
  'sort ties always fall back to stable natural world ids'
)) {
  Assert-Match $text.policy_regression ([regex]::Escape($phrase)) "Query policy regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'one authoritative refresh deduplicates and indexes all two hundred fifty-six worlds',
  'indexed page navigation performs zero service or disk scans',
  'search and sort operate only on the in-memory index',
  'filtering a selected world out clears hidden deletion state',
  'typing does not run an unbounded full-directory query per keystroke',
  'index rebuilds never allocate additional UI rows'
)) {
  Assert-Match $text.browser_regression ([regex]::Escape($phrase)) "Indexed browser regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'real browser indexes all two hundred fifty-six worlds',
  'real search and sorting perform zero additional catalog scans',
  'three filtered pages expose every real Gamma world exactly once',
  'real filtering clears selection when the selected row becomes hidden',
  'all real query and sort variants stay inside the in-memory index',
  'steady indexed refresh remains a pure sidecar hit with zero reads and writes'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Indexed browser desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_indexed_save_browser\.ps1',
  'save_browser_query_policy_regression\.gd',
  'indexed_save_browser_regression\.gd',
  'indexed_save_browser_desktop_acceptance\.gd',
  'indexed-save-browser-desktop\.png',
  'indexed-save-browser-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Indexed save browser workflow is missing: $token"
}

foreach ($token in @('浅引用','world_id → metadata','64','8','名称','ID','地图','Seed','256 个世界','Windows Release')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Indexed browser contract is missing: $token"
}
foreach ($token in @('深拷贝','线性扫描','逐键输入','隐藏选择','内存索引','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing indexed-browser finding: $token"
}
Assert-Match $text.roadmap '名称、ID、地图和 Seed' 'Roadmap must record indexed save search fields'
Assert-Match $text.roadmap '最近更新、名称和存档大小' 'Roadmap must record deterministic save sorting'
Assert-Match $text.run_all 'validate_indexed_save_browser\.ps1' 'Full suite is missing indexed-browser static validation'
Assert-Match $text.run_all 'save_browser_query_policy_regression\.gd' 'Full suite is missing query-policy regression'
Assert-Match $text.run_all 'indexed_save_browser_regression\.gd' 'Full suite is missing indexed-browser regression'

Write-Host 'PASS indexed_save_browser worlds=256 rows=24 index=direct query-length=64 query-tokens=8 fields=name-id-map-seed sorts=updated-name-size keystroke-scan=0 page-scan=0 desktop=real release=required'
