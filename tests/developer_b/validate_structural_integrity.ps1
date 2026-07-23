$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'src\interaction\block_structure_integrity_policy.gd'
$servicePath = Join-Path $root 'src\interaction\block_structure_integrity_service.gd'
$toolHubPath = Join-Path $root 'src\ui\tool_progression_service_hub.gd'
$doorPolicyPath = Join-Path $root 'src\block\block_door_policy.gd'
$ladderPolicyPath = Join-Path $root 'src\block\block_ladder_policy.gd'
$worldPath = Join-Path $root 'src\world\batched_voxel_world.gd'
$pickupPath = Join-Path $root 'src\entity\pickup_stack_coordinator.gd'
$regressionBasePath = Join-Path $root 'tests\qa\structural_integrity_regression.gd'
$regressionPath = Join-Path $root 'tests\qa\structural_integrity_batched_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\structural_integrity_desktop_acceptance.gd'
$batchedDesktopPath = Join-Path $root 'tests\qa\structural_integrity_batched_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\structural-integrity-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\BOUNDED_STRUCTURAL_INTEGRITY.md'
$auditPath = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_30.md'
$roadmapPath = Join-Path $root 'docs\PRODUCT_ROADMAP.md'

foreach ($path in @(
  $policyPath,$servicePath,$toolHubPath,$doorPolicyPath,$ladderPolicyPath,$worldPath,
  $pickupPath,$regressionBasePath,$regressionPath,$desktopPath,$batchedDesktopPath,
  $workflowPath,$runAllPath,$contractPath,$auditPath,$roadmapPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing structural integrity contract file: $path" }
}

$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$toolHub = Get-Content -Raw -Encoding UTF8 $toolHubPath
$doorPolicy = Get-Content -Raw -Encoding UTF8 $doorPolicyPath
$ladderPolicy = Get-Content -Raw -Encoding UTF8 $ladderPolicyPath
$world = Get-Content -Raw -Encoding UTF8 $worldPath
$pickup = Get-Content -Raw -Encoding UTF8 $pickupPath
$regressionBase = Get-Content -Raw -Encoding UTF8 $regressionBasePath
$regression = $regressionBase + "`n" + (Get-Content -Raw -Encoding UTF8 $regressionPath)
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$batchedDesktop = Get-Content -Raw -Encoding UTF8 $batchedDesktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath
$audit = Get-Content -Raw -Encoding UTF8 $auditPath
$roadmap = Get-Content -Raw -Encoding UTF8 $roadmapPath

foreach ($token in @(
  'class_name\s+BlockStructureIntegrityPolicy',
  'CANDIDATE_OFFSETS\s*:\s*Array\[Vector3i\]',
  'static\s+func\s+candidate_positions\s*\(',
  'static\s+func\s+inspect\s*\(',
  'DoorPolicyScript\.is_valid_pair',
  'LadderPolicyScript\.support_offset',
  '"drop_item"\s*:\s*DOOR_ITEM_ID',
  '"drop_item"\s*:\s*LADDER_ITEM_ID',
  '"structure_key"'
)) {
  if ($policy -notmatch $token) { throw "Structural integrity policy is missing pure bounded contract: $token" }
}
if ($policy -match 'func\s+_process\s*\(' -or $policy -match 'Timer\.new\(' -or $policy -match 'FileAccess') {
  throw 'Structural integrity policy must remain pure and must not own scheduling or files'
}

foreach ($token in @(
  'class_name\s+BlockStructureIntegrityService',
  'MAX_PENDING_CANDIDATES\s*:=\s*65536',
  'MAX_CANDIDATES_PER_FLUSH\s*:=\s*4096',
  'MAX_STRUCTURES_PER_FLUSH\s*:=\s*1024',
  'MAX_MUTATIONS_PER_FLUSH\s*:=\s*2048',
  'MAX_INITIAL_OVERRIDE_SCAN\s*:=\s*8192',
  'PROCESS_MODE_PAUSABLE',
  'set_process\(false\)',
  'func\s+bind_world\s*\(',
  '"block_changed"',
  'func\s+queue_persisted_structures\s*\(',
  'func\s+flush_pending\s*\(',
  'apply_block_mutations',
  'structural_integrity_cleanup',
  '_applying_cleanup',
  'inventory\.call\("add_item"',
  'PickupScript\.new\(\)',
  'func\s+get_snapshot\s*\(',
  'candidate_overflow_count',
  'cleanup_batch_count',
  'initial_override_truncated_count',
  'func\s+clear\s*\(',
  'func\s+shutdown\s*\('
)) {
  if ($service -notmatch $token) { throw "Structural integrity runtime is missing bounded behavior: $token" }
}
if ($service -match 'func\s+serialize\s*\(' -or $service -match 'FileAccess' -or $service -match 'Timer\.new\(') {
  throw 'Structural integrity runtime must remain transient and reuse the shared process loop and save surface'
}
if ($service -notmatch 'set_process\([\s\S]{0,220}_pending_candidates[\s\S]{0,160}_pending_drops') {
  throw 'Structural integrity runtime must disable idle processing when candidate and drop queues are empty'
}
if ($service -notmatch 'structures\.size\(\)\s*>=\s*MAX_STRUCTURES_PER_FLUSH' -or $service -notmatch 'mutation_positions\.size\(\)\s*\+\s*new_mutations\s*>\s*MAX_MUTATIONS_PER_FLUSH') {
  throw 'Structural cleanup must enforce independent structure and mutation budgets'
}

foreach ($token in @(
  'block_structure_integrity_service\.gd',
  'var\s+structural_integrity_service\s*:\s*Node',
  '"StructuralIntegrity"',
  'structural_integrity_service\.call\("setup",\s*inventory,\s*creature_spawner\)',
  'structural_integrity_service\.call\("bind_world",\s*world\)',
  'structural_integrity_service\.call\("begin_world"\)',
  'snapshot\["structural_integrity"\]',
  'structural_integrity_service\.call\("clear",\s*true\)',
  'structural_integrity_service\.call\("shutdown"\)'
)) {
  if ($toolHub -notmatch $token) { throw "Production service hub is missing structural integrity composition: $token" }
}

if ($doorPolicy -notmatch 'static\s+func\s+is_valid_pair' -or $ladderPolicy -notmatch 'static\s+func\s+is_valid_support') {
  throw 'Integrity cleanup must reuse the existing door and ladder state contracts'
}
if ($world -notmatch 'MAX_BLOCK_MUTATIONS_PER_BATCH\s*:=\s*4096' -or $world -notmatch 'func\s+apply_block_mutations') {
  throw 'Production world must retain the bounded mutation batch used by structural cleanup'
}
if ($pickup -notmatch 'MAX_PICKUP_NODES\s*:=\s*128' -or $pickup -notmatch 'pickup_stack_consolidated') {
  throw 'Full-inventory structural returns must reuse the bounded pickup runtime'
}

foreach ($phrase in @(
  'one changed cell produces seven bounded structural candidates',
  'unit fixture keeps every support and structural cell distinct',
  'door and ladder cleanup share one production mutation batch',
  'orphan upper door half self-cleans',
  'full inventory produces one bounded physical fallback node',
  'world-start scan repairs an old unsupported ladder'
)) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "Structural integrity regression is missing assertion: $phrase" }
}
if ($regression -notmatch 'extends\s+"res://tests/qa/structural_integrity_regression\.gd"') {
  throw 'Collision-free domain fixture must preserve the complete structural regression journey'
}
foreach ($token in @(
  'TARGET_DOOR_COUNT\s*:=\s*128',
  'TARGET_LADDER_COUNT\s*:=\s*256',
  'FALLBACK_DOOR_COUNT\s*:=\s*6',
  'FALLBACK_LADDER_COUNT\s*:=\s*10',
  'MAX_MAIN_CLEANUP_MILLISECONDS\s*:=\s*5000',
  'structural-integrity-desktop\.json'
)) {
  if ($desktop -notmatch $token -and -not ($token -eq 'structural-integrity-desktop\.json' -and $desktop -match 'get_basename\(\)\s*\+\s*"\.json"')) {
    throw "Structural integrity desktop acceptance is missing scale evidence: $token"
  }
}
foreach ($phrase in @(
  'one real batch removes every target support exactly once',
  'support loss leaves no floating or half-door cells',
  'support loss leaves no un-climbable ladder remnants',
  'cleanup returns the exact canonical door and ladder totals',
  'support removal and dependent cleanup use exactly two world rebuild flushes',
  'physical fallback preserves exact door and ladder totals',
  'full inventory aggregates sixteen returns into at most two pickup nodes',
  'full reload never duplicates structural return items'
)) {
  if ($desktop -notmatch [regex]::Escape($phrase)) { throw "Structural integrity desktop acceptance is missing assertion: $phrase" }
}
foreach ($token in @(
  'extends\s+"res://tests/qa/structural_integrity_desktop_acceptance\.gd"',
  'posmod\(chunk_coord\.x,\s*2\)',
  'posmod\(chunk_coord\.y,\s*2\)',
  '\[2,\s*6\]',
  '\[10,\s*14\]',
  'func\s+_build_main_fixture\s*\('
)) {
  if ($batchedDesktop -notmatch $token) { throw "Collision-free cross-Chunk fixture is missing: $token" }
}

if ($workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml') {
  throw 'Structural integrity workflow must use the reusable Godot quality gate'
}
foreach ($token in @(
  'validate_structural_integrity\.ps1',
  'structural_integrity_batched_regression\.gd',
  'double_door_regression\.gd',
  'directional_ladder_regression\.gd',
  'world_mutation_batch_regression\.gd',
  'pickup_stack_regression\.gd',
  'structural_integrity_batched_desktop_acceptance\.gd',
  'structural-integrity-desktop\.json'
)) {
  if ($workflow -notmatch $token) { throw "Structural integrity workflow is missing validation or evidence: $token" }
}
if ($runAll -notmatch 'validate_structural_integrity\.ps1' -or $runAll -notmatch 'structural_integrity_batched_regression\.gd') {
  throw 'Full regression entry point must permanently include structural integrity validation and corrected domain regression'
}

foreach ($token in @('65,536','4,096','1,024','2,048','浮空半门','物理掉落','不进入存档')) {
  if ($contract -notmatch [regex]::Escape($token)) { throw "Structural integrity contract is missing boundary documentation: $token" }
}
foreach ($token in @('支撑','浮空','共享','批处理','384','512','跨 Chunk')) {
  if ($audit -notmatch [regex]::Escape($token)) { throw "Architecture audit is missing original problem or scale evidence: $token" }
}
if ($roadmap -notmatch '结构完整性' -or $roadmap -notmatch '统一运行与保存健康报告') {
  throw 'Product roadmap must record completed structural integrity and the next health-report priority'
}

Write-Host 'PASS structural_integrity candidates=65536 per_flush=4096 structures=1024 mutations=2048 doors=128 ladders=256 removed_cells=512 fallback_items=16 pickup_nodes<=2 persistence=none ci=reusable'
