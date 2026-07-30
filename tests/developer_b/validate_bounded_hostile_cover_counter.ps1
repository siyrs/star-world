$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Policy = Join-Path $root 'src\entity\hostile_cover_counter_policy.gd'
  Service = Join-Path $root 'src\entity\hostile_cover_counter_service.gd'
  Lifecycle = Join-Path $root 'src\entity\lifecycle_bound_hostile_cover_counter_service.gd'
  Brute = Join-Path $root 'src\entity\cover_aware_abyss_brute.gd'
  Marksman = Join-Path $root 'src\entity\cover_aware_abyss_marksman.gd'
  Factory = Join-Path $root 'src\entity\creature_factory.gd'
  Overlay = Join-Path $root 'src\ui\hostile_cover_counter_overlay.gd'
  Scene = Join-Path $root 'scenes\ui\service_hub.tscn'
  World = Join-Path $root 'src\world\batched_voxel_world.gd'
  Headless = Join-Path $root 'tests\qa\hostile_cover_counter_regression.gd'
  Desktop = Join-Path $root 'tests\qa\hostile_cover_counter_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-hostile-cover-counter-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_HOSTILE_COVER_COUNTER.md'
  Testing = Join-Path $root 'docs\BOUNDED_HOSTILE_COVER_COUNTER_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-31_ITERATION_57.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_57.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Hostile cover counter file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($token in @(
  'class_name\s+HostileCoverCounterPolicy',
  'MAX_LINE_SAMPLE_STEPS\s*:=\s*64',
  'MAX_BREAK_BLOCKS_PER_ATTACK\s*:=\s*2',
  'MAX_BREAK_BLOCKS_PER_BRUTE\s*:=\s*12',
  'MAX_REPOSITION_PROBES\s*:=\s*6',
  'MAX_REPOSITION_ATTEMPTS_PER_TARGET\s*:=\s*4',
  'REPOSITION_DELAY_SECONDS\s*:=\s*1\.8',
  '"wool"', '"glass_pane"', '"glass_pane_ns"',
  'blocks_projectile_lane', 'reposition_directions'
)) {
  if ($text.Policy -notmatch $token) { throw "Pure hostile cover policy is missing: $token" }
}
if ($text.Policy -match 'extends\s+Node|Timer\.new|Thread\.new|FileAccess|DirAccess|RandomNumberGenerator') {
  throw 'Hostile cover policy must remain pure and deterministic'
}
foreach ($safeBlock in @('stone','planks','oak_door','oak_fence','stone_slab','chest','furnace','stonecutter')) {
  if ($text.Policy -match ('BREAKABLE_COVER_IDS[\s\S]*?"' + [regex]::Escape($safeBlock) + '"')) {
    throw "Permanent block entered the hostile destruction whitelist: $safeBlock"
  }
}

foreach ($token in @(
  'class_name\s+HostileCoverCounterService',
  'MAX_INITIAL_CHILD_SCAN\s*:=\s*64',
  'MAX_BOUND_CREATURES\s*:=\s*32',
  'creature_spawned', 'WeakRef',
  'apply_block_mutations', 'hostile_cover_break',
  'find_marksman_reposition_destination',
  'HostileCoverCounterOverlay'
)) {
  if ($text.Service -notmatch $token) { throw "Bounded hostile cover runtime is missing: $token" }
}
if ($text.Service -match 'Timer\.new|Thread\.new|get_nodes_in_group|NavigationServer|save_world|serialize\s*\(|current_state\s*\[') {
  throw 'Cover counter must reuse existing signals, local probes, world batching and persistence authority'
}
if ($text.Service -notmatch '_is_player_override[\s\S]*block_overrides') {
  throw 'Brute destruction must prove that fragile cover is a player sparse override'
}

foreach ($token in @(
  'class_name\s+LifecycleBoundHostileCoverCounterService',
  'start_world_requested', 'return_to_menu_requested',
  'blocks_damage', 'permanent_cover_blocked',
  '_permanent_cover_blocks_lane'
)) {
  if ($text.Lifecycle -notmatch $token) { throw "Cover lifecycle or permanent-wall protection is missing: $token" }
}
foreach ($token in @(
  'class_name\s+CoverAwareAbyssBruteCreature',
  'blocks_damage', 'cover_blocked_attack_count',
  'super\._commit_attack\(\)'
)) {
  if ($text.Brute -notmatch $token) { throw "Cover-aware brute behavior is missing: $token" }
}
foreach ($token in @(
  'class_name\s+CoverAwareAbyssMarksmanCreature',
  'blocked_lane_seconds', 'reposition_attempt_count',
  'find_marksman_reposition_destination',
  'MAX_REPOSITION_ATTEMPTS_PER_TARGET',
  'super\._choose_direction\(\)'
)) {
  if ($text.Marksman -notmatch $token) { throw "Cover-aware marksman behavior is missing: $token" }
}
if ($text.Brute -match 'set_block\s*\(' -or $text.Marksman -match 'get_nodes_in_group|NavigationServer') {
  throw 'Creature subclasses must remain thin adapters over the shared cover service'
}

if ($text.Factory -notmatch 'abyss_brute.*cover_aware_abyss_brute\.gd' -or $text.Factory -notmatch 'abyss_marksman.*cover_aware_abyss_marksman\.gd') {
  throw 'CreatureFactory must compose both cover-aware elite subclasses'
}
if (($text.Scene | Select-String -Pattern 'HostileCoverCounterService' -AllMatches).Matches.Count -ne 1) {
  throw 'Production scene must install exactly one HostileCoverCounterService'
}
if ($text.Scene -notmatch 'lifecycle_bound_hostile_cover_counter_service\.gd') {
  throw 'Production scene must use the lifecycle-bound cover counter adapter'
}
if ($text.World -notmatch 'func\s+apply_block_mutations' -or $text.World -notmatch 'MAX_BLOCK_MUTATIONS_PER_BATCH\s*:=\s*4096') {
  throw 'Cover destruction must retain the shared bounded mutation batch authority'
}
foreach ($token in @('HostileCoverCounterPanel','临时掩体被突破','深渊射手正在换位','补给等待领取|掩体')) {
  if ($text.Overlay -notmatch $token) { throw "Cover counter HUD is missing: $token" }
}

foreach ($phrase in @(
  'one brute cover attack uses exactly one world mutation batch',
  'permanent stone base cannot be broken by a brute',
  'generated fragile blocks are not mistaken for player temporary cover',
  'brute cannot exceed twelve destroyed blocks per lifetime',
  'blocked marksman finds a bounded lateral firing lane',
  'sixty minute probe work remains linearly bounded',
  'return-to-menu signal releases the cover counter world attachment'
)) {
  if ($text.Headless -notmatch [regex]::Escape($phrase)) { throw "Cover headless regression is missing: $phrase" }
}
foreach ($phrase in @(
  'one real brute attack destroys both temporary cover cells',
  'cover-breaking attack cannot damage the player through the wall',
  'permanent cover also blocks melee damage through the wall',
  'unobstructed brute attack still reaches the production player',
  'blocked production marksman finds one local firing lane',
  'repositioned marksman fires through the shared hostile projectile runtime',
  'cover counter runtime never enters world.json'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Cover desktop acceptance is missing: $phrase" }
}
foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_hostile_cover_counter\.ps1',
  'hostile_cover_counter_regression\.gd',
  'hostile_cover_counter_desktop_acceptance\.gd',
  'hostile-cover-broken\.png',
  'hostile-cover-reposition\.png',
  'hostile-cover-report\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "Cover workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_hostile_cover_counter\.ps1','hostile_cover_counter_regression\.gd')) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing hostile cover gate: $token" }
}
foreach ($concept in @('临时掩体','永久基地','单批次','隔墙伤害','6 个探针','4 次','3600 秒','不进入存档','Windows Release')) {
  if (($text.Contract + $text.Testing + $text.Audit + $text.Roadmap) -notmatch [regex]::Escape($concept)) {
    throw "Hostile cover documentation is missing concept: $concept"
  }
}
Write-Host 'PASS hostile_cover_counter line<=64 break<=2/lifetime<=12 bound<=32 reposition<=6x4 temporary_only batch=single persistence=none'
