$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  protected = Join-Path $root 'src\save\protected_save_service.gd'
  lifecycle = Join-Path $root 'src\diagnostics\release_lifecycle_report_service.gd'
  game = Join-Path $root 'src\core\batched_game.gd'
  trash_test = Join-Path $root 'tests\qa\trash_restore_integrity_regression.gd'
  lifecycle_test = Join-Path $root 'tests\qa\release_lifecycle_report_regression.gd'
  campaign = Join-Path $root 'tests\qa\release_integrity_continuous_campaign_regression.gd'
  workflow = Join-Path $root '.github\workflows\release-integrity-iteration-59-tests.yml'
  contract = Join-Path $root 'docs\RELEASE_INTEGRITY_AND_LIFECYCLE.md'
  testing = Join-Path $root 'docs\RELEASE_INTEGRITY_TESTING.md'
  roadmap_iteration = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_59.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-06_ITERATION_59.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  issues = Join-Path $root 'qa\issues-found.md'
  status = Join-Path $root 'docs\tasks\20260731-v1.3.0-commercial-release-gameplay-polish\09-feature-status-board.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}
$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing Iteration 59 release-integrity file: $name $($paths[$name])"
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
  $pattern = '(?ms)^func\s+' + [regex]::Escape($MethodName) + '\s*\(.*?(?=^func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'read_dictionary_validated',
  '_is_valid_world_payload',
  'world_payload_unrecoverable',
  'repair_dictionary',
  '_prepare_trash_restore',
  '_remove_trash_catalog_artifacts',
  'restore_integrity_check_count',
  'restore_repair_success_count',
  'last_restore_source'
)) {
  Assert-Match $text.protected $token "Protected restore lost integrity contract: $token"
}
$restoreBody = Get-MethodBody $text.protected 'restore_trashed_world'
$prepareIndex = $restoreBody.IndexOf('_prepare_trash_restore')
$renameIndex = $restoreBody.IndexOf('DirAccess.rename_absolute')
if ($prepareIndex -lt 0 -or $renameIndex -lt 0 -or $prepareIndex -gt $renameIndex) {
  throw 'Trash payload validation and primary repair must complete before directory promotion'
}
Assert-Match $restoreBody 'world_exists\(world_id\)' 'Restore must preserve the active-world collision guard'

foreach ($token in @(
  'DEFAULT_REPORT_PATH\s*:=\s*"user://diagnostics/release-lifecycle-report\.json"',
  'Performance\.OBJECT_NODE_COUNT',
  'Performance\.OBJECT_RESOURCE_COUNT',
  'Performance\.OBJECT_ORPHAN_NODE_COUNT',
  'Performance\.MEMORY_STATIC',
  'mark_scene_ready',
  'mark_first_world_playable',
  'mark_first_save',
  'begin_quit',
  'complete_quit',
  'AtomicJsonStoreScript'
)) {
  Assert-Match $text.lifecycle $token "Release lifecycle reporter is missing: $token"
}
Assert-NoMatch $text.lifecycle 'block_overrides|serialize_state|collect_state' 'Release lifecycle reporter must not own gameplay payloads'

$readyBody = Get-MethodBody $text.game '_ready'
if ($readyBody.IndexOf('_setup_release_lifecycle_report') -gt $readyBody.IndexOf('super._ready')) {
  throw 'Release lifecycle reporter must be configured before production scene setup'
}
foreach ($token in @(
  'world_started\.connect',
  'save_checkpoint_recorded',
  '_begin_release_quit\(source\)',
  '_complete_release_quit\(false\)',
  '_complete_release_quit\(true\)',
  'finalize_scene_exit'
)) {
  Assert-Match $text.game $token "Batched game lost release lifecycle integration: $token"
}

foreach ($phrase in @(
  'restart detects a valid backup without trusting the corrupted primary',
  'temporary recovery promotes and reloads the exact validated payload',
  'wrong-world candidates are purgeable but never restorable',
  'all-corrupt candidates fail closed and enter bounded diagnostics'
)) {
  Assert-Match $text.trash_test ([regex]::Escape($phrase)) "Trash integrity regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'forced QA mode records the real production scene-ready boundary',
  'release timings retain monotonic scene, playable, save and quit ordering',
  'quit report captures bounded before/after resources and exact deltas',
  'independent lifecycle reporting never mutates a world.json sentinel'
)) {
  Assert-Match $text.lifecycle_test ([regex]::Escape($phrase)) "Lifecycle regression is missing assertion: $phrase"
}

foreach ($token in @(
  'CAMPAIGN_CYCLES\s*:=\s*8',
  'HOSTILES_PER_CYCLE\s*:=\s*3',
  'encounter_reward_service\.gd',
  'bounded_pickup_stack_coordinator\.gd',
  'cached_voxel_chunk\.gd',
  'cached_batched_voxel_world\.gd',
  'block_connection_policy',
  'batched_block_structure_integrity_service'
)) {
  Assert-Match $text.campaign $token "Continuous campaign is missing production boundary: $token"
}
foreach ($phrase in @(
  'campaign records the exact multi-hostile death count',
  'every encounter grants once and every duplicate completion is rejected',
  'each hostile death materializes exactly one physical drop and leaves zero residue',
  'chunk hot return hits exactly twice per cycle inside the fixed cache capacity',
  'structural queue converges after every combat and streaming cycle',
  'campaign teardown releases every hostile, pickup, chunk and structural node'
)) {
  Assert-Match $text.campaign ([regex]::Escape($phrase)) "Continuous campaign is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_release_integrity_iteration_59\.ps1',
  'trash_restore_integrity_regression\.gd',
  'release_lifecycle_report_regression\.gd',
  'release_integrity_continuous_campaign_regression\.gd',
  'graceful_application_quit_regression\.gd',
  'encounter_reward_economy_regression\.gd',
  'connected_block_shapes_regression\.gd',
  'recent_chunk_snapshot_cache_regression\.gd',
  'structural_integrity_batched_regression\.gd'
)) {
  Assert-Match $text.workflow $token "Permanent Iteration 59 workflow is missing: $token"
}
foreach ($token in @('Iteration 59','world_payload_unrecoverable','release-lifecycle-report','E4-H','7,200')) {
  Assert-Match ($text.contract + $text.testing + $text.roadmap_iteration + $text.audit + $text.roadmap + $text.issues + $text.status) ([regex]::Escape($token)) "Iteration 59 documentation is missing boundary: $token"
}
foreach ($token in @(
  'validate_release_integrity_iteration_59\.ps1',
  'trash_restore_integrity_regression\.gd',
  'release_lifecycle_report_regression\.gd',
  'release_integrity_continuous_campaign_regression\.gd'
)) {
  Assert-Match $text.run_all $token "Full regression entry is missing: $token"
}
Assert-NoMatch ($text.lifecycle + $text.campaign) 'Timer\.new|Thread\.new|get_nodes_in_group' 'Iteration 59 must remain event-driven and bounded'
Assert-NoMatch ($text.workflow + $text.run_all) 'iteration_59_apply|iteration-59-bootstrap' 'Temporary bootstrap files must not survive the final tree'

Write-Host 'PASS release_integrity_iteration_59 trash=validated recovery=primary-before-promote lifecycle=scene/world/save/quit campaign=8x3 hot-returns=16 structures=8 release=external-hold'
