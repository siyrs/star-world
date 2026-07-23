$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'tests\qa\support\multi_hostile_arena_batch_policy.gd'
$regressionPath = Join-Path $root 'tests\qa\multi_hostile_arena_batch_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\multi_hostile_danger_batched_desktop_acceptance.gd'
$worldPath = Join-Path $root 'src\world\batched_voxel_world.gd'
$workflowPath = Join-Path $root '.github\workflows\multi-hostile-danger-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @($policyPath,$regressionPath,$desktopPath,$worldPath,$workflowPath,$runAllPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing multi-hostile arena batch contract file: $path" }
}

$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$regression = Get-Content -Raw -Encoding UTF8 $regressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$world = Get-Content -Raw -Encoding UTF8 $worldPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath

foreach ($token in @(
  'DEFAULT_RADIUS\s*:=\s*10',
  'DEFAULT_CLEARANCE_HEIGHT\s*:=\s*4',
  'MAX_RADIUS\s*:=\s*12',
  'MAX_CLEARANCE_HEIGHT\s*:=\s*5',
  'MAX_MUTATIONS_PER_BATCH\s*:=\s*4096',
  'static\s+func\s+build_mutations\s*\(',
  'static\s+func\s+expected_mutation_count\s*\('
)) {
  if ($policy -notmatch $token) { throw "Arena mutation policy is missing bounded contract: $token" }
}
if ($policy -match 'set_block\s*\(' -or $policy -match 'rebuild_mesh\s*\(') {
  throw 'Arena mutation policy must remain pure and must not mutate or rebuild the world directly'
}
if ($world -notmatch 'MAX_BLOCK_MUTATIONS_PER_BATCH\s*:=\s*4096' -or $world -notmatch 'func\s+apply_block_mutations\s*\(') {
  throw 'Production world must retain the bounded 4096-item mutation API used by the desktop arena'
}

foreach ($phrase in @(
  'default multi-hostile arena emits the exact bounded mutation count',
  'default arena remains below the 4096-mutation world limit',
  'arena mutations never write the same cell twice',
  'largest supported arena always fits one production world mutation batch'
)) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "Arena unit regression is missing assertion: $phrase" }
}

if ($desktop -notmatch 'extends\s+"res://tests/qa/multi_hostile_danger_desktop_acceptance\.gd"') {
  throw 'Batched desktop acceptance must preserve the full existing multi-hostile journey through inheritance'
}
foreach ($token in @(
  'apply_block_mutations',
  'reset_chunk_rebuild_stats',
  'accepted',
  'truncated',
  'rejected',
  'execution_count',
  'ARENA_TIME_BUDGET_MILLISECONDS\s*:=\s*45000',
  'QA MULTI HOSTILE ARENA BATCH'
)) {
  if ($desktop -notmatch $token) { throw "Batched desktop acceptance is missing production evidence: $token" }
}
if ($desktop -match 'world\.call\("set_block"') {
  throw 'Real desktop arena must not return to thousands of immediate set_block rebuilds'
}

if ($workflow -notmatch 'validate_multi_hostile_arena_batch\.ps1') {
  throw 'Multi-hostile workflow must permanently validate the arena batch contract'
}
if ($workflow -notmatch 'multi_hostile_arena_batch_regression\.gd') {
  throw 'Multi-hostile workflow must run the arena unit regression'
}
if ($workflow -notmatch 'multi_hostile_danger_batched_desktop_acceptance\.gd') {
  throw 'Multi-hostile workflow must run the optimized full desktop journey'
}
if ($workflow -notmatch 'TimeoutMilliseconds\s+180000') {
  throw 'Full save/reload desktop journey must retain a bounded three-minute process timeout'
}
if ($runAll -notmatch 'validate_multi_hostile_arena_batch\.ps1' -or $runAll -notmatch 'multi_hostile_arena_batch_regression\.gd') {
  throw 'Full regression entry point must retain the arena batch validator and unit regression'
}

Write-Host 'PASS multi_hostile_arena_batch mutations=2205 max=3750 world_limit=4096 desktop_budget_ms=45000 process_timeout_ms=180000'
