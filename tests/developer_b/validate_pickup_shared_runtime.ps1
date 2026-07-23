$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Pickup = Join-Path $root 'src\entity\item_pickup.gd'
  Coordinator = Join-Path $root 'src\entity\pickup_stack_coordinator.gd'
  Bounded = Join-Path $root 'src\entity\bounded_pickup_stack_coordinator.gd'
  Resources = Join-Path $root 'src\entity\pickup_visual_resource_cache.gd'
  Regression = Join-Path $root 'tests\qa\pickup_shared_runtime_regression.gd'
  Desktop = Join-Path $root 'tests\qa\pickup_shared_runtime_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\pickup-shared-runtime-tests.yml'
  Reusable = Join-Path $root '.github\workflows\reusable-godot-quality-gate.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\SHARED_PICKUP_RUNTIME.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_27.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Shared pickup runtime file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($constant in @('MAX_RUNTIME_NODES\s*:=\s*128','MAX_RUNTIME_DELTA_SECONDS\s*:=\s*0\.25')) {
  if ($text.Coordinator -notmatch $constant) { throw "Missing shared pickup runtime budget: $constant" }
}
if ($text.Coordinator -notmatch 'process_mode\s*=\s*Node\.PROCESS_MODE_PAUSABLE') {
  throw 'Shared pickup runtime must explicitly pause with the world simulation'
}
if ($text.Coordinator -notmatch 'func\s+_process\s*\([^)]*\)[\s\S]{0,180}advance_shared_runtime') {
  throw 'Pickup coordinator must own the single production process callback'
}
foreach ($method in @('advance_shared_runtime','_register_runtime_pickup','_unregister_runtime_pickup','_update_runtime_processing')) {
  if ($text.Coordinator -notmatch "func\s+$method\s*\(") { throw "Pickup coordinator is missing runtime method: $method" }
}
if ($text.Coordinator -notmatch 'child_entered_tree' -or $text.Coordinator -notmatch 'child_exiting_tree') {
  throw 'Shared runtime membership must remain event-maintained by the existing spawner'
}
if ($text.Coordinator -match 'Timer\.new\(' -or $text.Coordinator -match 'func\s+serialize\s*\(' -or $text.Coordinator -match 'FileAccess') {
  throw 'Shared pickup runtime must not add another timer, persistence owner, or file'
}
if ($text.Coordinator -notmatch 'individual_process_count' -or $text.Coordinator -notmatch 'runtime_advance_count' -or $text.Coordinator -notmatch 'expired_pickup_count') {
  throw 'Shared pickup runtime diagnostics must expose process elimination, work, and expiry'
}
if ($text.Bounded -notmatch 'super\._on_spawner_child_exiting') {
  throw 'Pressure-aware coordinator must preserve shared runtime unregistration'
}
foreach ($method in @('configure_shared_runtime','release_shared_runtime','advance_runtime','get_visual_root','get_visual_offset','get_visual_resource_ids')) {
  if ($text.Pickup -notmatch "func\s+$method\s*\(") { throw "ItemPickup is missing shared runtime port: $method" }
}
if ($text.Pickup -notmatch 'process_mode\s*=\s*Node\.PROCESS_MODE_PAUSABLE') {
  throw 'Standalone pickup fallback must also respect real simulation pause'
}
if ($text.Pickup -notmatch '_shared_runtime_managed' -or $text.Pickup -notmatch 'set_process\(false\)') {
  throw 'Production coordinator must be able to disable individual pickup processing'
}
if ($text.Pickup -notmatch 'PickupVisual' -or $text.Pickup -notmatch '_visual_root\.position') {
  throw 'Pickup bobbing must move a visual child instead of the Area3D anchor'
}
if ($text.Pickup -match 'position\.y\s*\+=') {
  throw 'Pickup runtime must not accumulate bobbing directly into the collision anchor'
}
if ($text.Pickup -notmatch 'pickup_visual_resource_cache\.gd') {
  throw 'Pickup visuals must use the bounded shared resource cache'
}
if ($text.Resources -notmatch 'MAX_MATERIALS\s*:=\s*256') {
  throw 'Pickup material cache must have a hard 256-entry budget'
}
foreach ($method in @('get_box_mesh','get_collision_shape','get_material','get_stats','reset_stats')) {
  if ($text.Resources -notmatch "static\s+func\s+$method\s*\(") { throw "Pickup visual cache is missing: $method" }
}
if ($text.Resources -notmatch 'material_overflow_count') {
  throw 'Pickup visual cache must expose bounded fallback diagnostics'
}
foreach ($phrase in @(
  'one shared pickup runtime step advances both production pickup nodes',
  'pickup bobbing never moves the Area3D collision anchors',
  'real SceneTree pause freezes pickup lifetime and visual runtime',
  'one hundred twenty-eight production pickups still use zero individual process callbacks',
  'shared lifetime expiration removes all expired pickup nodes exactly once'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) { throw "Shared pickup runtime regression is missing assertion: $phrase" }
}
foreach ($phrase in @(
  'production shared runtime tracks one hundred twenty-eight physical pickups',
  'one pausable coordinator replaces all individual pickup process callbacks',
  'production simulation pause freezes pickup visuals and lifetime',
  'one hundred twenty-eight same-color pickups share one mesh, shape, and material',
  'new world session does not restore transient pickups or shared runtime counters'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Shared pickup runtime desktop acceptance is missing assertion: $phrase" }
}
if ($text.Workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml' -or $text.Workflow -notmatch 'pickup_shared_runtime_regression\.gd' -or $text.Workflow -notmatch 'pickup_shared_runtime_desktop_acceptance\.gd') {
  throw 'Shared pickup runtime caller must declare domain and real desktop acceptance through the reusable gate'
}
if ($text.Reusable -notmatch 'tests\\ci\\run_godot_headless_test\.ps1' -or $text.Reusable -notmatch 'tests\\ci\\run_godot_desktop_test\.ps1') {
  throw 'Reusable Godot gate must own awaited captured headless and desktop execution'
}
if ($text.Workflow -notmatch 'pickup-shared-runtime-desktop\.json' -or $text.Workflow -notmatch 'pickup-shared-runtime-regression\.stdout\.log') {
  throw 'Shared pickup runtime caller must retain machine-readable and captured log evidence declarations'
}
if ($text.RunAll -notmatch 'validate_pickup_shared_runtime\.ps1' -or $text.RunAll -notmatch 'pickup_shared_runtime_regression\.gd') {
  throw 'Full regression entry point must permanently include shared pickup runtime tests'
}
if ($text.Contract -notmatch '128' -or $text.Contract -notmatch 'PROCESS_MODE_PAUSABLE' -or $text.Contract -notmatch '碰撞锚点') {
  throw 'Shared pickup runtime contract must document budget, pause, and stable anchors'
}
if ($text.Audit -notmatch '128' -or $text.Audit -notmatch '_process' -or $text.Audit -notmatch '资源') {
  throw 'Architecture audit must record per-node process and resource allocation problems'
}

Write-Host 'PASS pickup_shared_runtime processes=1 nodes=128 delta=0.25 resources=shared materials=256 anchors=stable pause=pausable persistence=none ci=reusable'
