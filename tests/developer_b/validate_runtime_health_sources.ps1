$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  scheduler = Join-Path $root 'src\machine\machine_runtime_scheduler.gd'
  furnace = Join-Path $root 'src\machine\scalable_furnace_service.gd'
  stonecutter = Join-Path $root 'src\machine\scalable_stonecutter_service.gd'
  automation = Join-Path $root 'src\machine\scalable_machine_automation_service.gd'
  agriculture = Join-Path $root 'src\agriculture\scalable_agriculture_service.gd'
  report = Join-Path $root 'src\diagnostics\runtime_health_report_service.gd'
  regression = Join-Path $root 'tests\qa\runtime_health_source_projection_regression.gd'
  desktop = Join-Path $root 'tests\qa\runtime_health_report_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\runtime-health-report-tests.yml'
  run_all = Join-Path $root 'tests\run_all.ps1'
  contract = Join-Path $root 'docs\RUNTIME_HEALTH_SOURCE_CONTRACT.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_32.md'
}

$text = @{}
foreach ($name in $paths.Keys) {
  $path = $paths[$name]
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing lightweight health source file: $path" }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $path
}

function Assert-Match {
  param([string]$Text, [string]$Pattern, [string]$Message)
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch {
  param([string]$Text, [string]$Pattern, [string]$Message)
  if ($Text -match $Pattern) { throw $Message }
}

function Get-MethodBody {
  param([string]$Text, [string]$MethodName)
  $pattern = '(?ms)^func\s+' + [regex]::Escape($MethodName) + '\s*\([^\n]*\).*?(?=^func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'func\s+get_health_snapshot\s*\(',
  'MAX_DOMAINS\s*:=\s*16',
  'domain_limit',
  'fallback_domain_count',
  'total_health_fallback_count',
  'domain\.has_method\("get_health_snapshot"\)',
  'domain\.call\("get_health_snapshot"\)'
)) {
  Assert-Match $text.scheduler $token "Machine scheduler lost lightweight health contract: $token"
}
$schedulerHealth = Get-MethodBody $text.scheduler 'get_health_snapshot'
Assert-NoMatch $schedulerHealth 'domain_summaries|registered_domains|last_batch|domains\s*:' 'Machine health snapshot must not copy full scheduler dictionaries'

foreach ($name in @('furnace','stonecutter')) {
  $body = Get-MethodBody $text[$name] 'get_health_snapshot'
  foreach ($token in @('_machines\.size\(\)','_activity_index\.size\(\)','schema_version')) {
    Assert-Match $body $token "$name lightweight health snapshot is missing O(1) scalar: $token"
  }
  Assert-NoMatch $body 'super\.get_runtime_snapshot|get_machine_ids|last_runtime_summary|activity_index\s*:' "$name health snapshot must not invoke or expose the heavy runtime snapshot"
}

$automationHealth = Get-MethodBody $text.automation 'get_health_snapshot'
foreach ($token in @('_candidate_order\.size\(\)','max_machines_per_cycle','candidate_order_dirty')) {
  Assert-Match $automationHealth $token "Automation health snapshot is missing bounded scalar: $token"
}
Assert-NoMatch $automationHealth 'last_cycle|transfers|super\.get_runtime_snapshot' 'Automation health snapshot must not copy cycle details'

foreach ($token in @(
  '_health_mature_crop_count',
  '_recount_health_mature_crops',
  '_on_health_crop_stage_changed',
  '_on_health_crop_harvested',
  'func\s+get_health_snapshot\s*\(',
  'world_mutation_batch'
)) {
  Assert-Match $text.agriculture $token "Agriculture health cache is missing contract: $token"
}
$agricultureHealth = Get-MethodBody $text.agriculture 'get_health_snapshot'
Assert-NoMatch $agricultureHealth 'crop_counts|last_atomic_harvest|soil_refresh_cache|get_runtime_snapshot' 'Agriculture health snapshot must not construct heavy dictionaries'

foreach ($token in @(
  '\["get_health_snapshot",\s*"get_snapshot"\]',
  '\["get_health_snapshot",\s*"get_runtime_snapshot"\]',
  'source_methods',
  'preferred_source_count',
  'fallback_source_count',
  'unavailable_source_count',
  'get_source_contract_snapshot'
)) {
  Assert-Match $text.report $token "Runtime health aggregation is missing preferred-source diagnostics: $token"
}

foreach ($phrase in @(
  'machine heavy snapshots are never called by health aggregation',
  'agriculture heavy snapshots are never called by health aggregation',
  'scheduler aggregates the full 4,096-machine capacity from scalar counts',
  'legacy fallback is bounded, visible and counted exactly once',
  'agriculture cache restores exact crop and mature counts',
  'agriculture health snapshot excludes full runtime dictionaries'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Lightweight health regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'production health aggregation uses the dedicated machine source port',
  'production health aggregation uses the dedicated agriculture source port',
  'production health aggregation requires zero source fallback'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Desktop health acceptance is missing assertion: $phrase"
}

foreach ($token in @('validate_runtime_health_sources\.ps1','runtime_health_source_projection_regression\.gd')) {
  Assert-Match $text.workflow $token "Runtime health workflow is missing lightweight source gate: $token"
  Assert-Match $text.run_all $token "Full regression entry point is missing lightweight source gate: $token"
}

foreach ($token in @('专用轻量端口','0 fallback','成熟作物缓存','不构造 `crop_counts`','调用计数')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Runtime health source contract is missing boundary: $token"
}
Assert-Match $text.contract '最多(?:读取)?\s*16 个机器领域' 'Runtime health source contract is missing the bounded 16-domain limit'
foreach ($token in @('完整快照后丢弃','每 0.5 秒','O\(1\)','兼容 fallback','真实桌面')) {
  Assert-Match $text.audit $token "Architecture audit is missing source optimization finding: $token"
}

Write-Host 'PASS runtime_health_sources machine_domains=16 machine_capacity=4096 agriculture=maturity-cache preferred=11 fallback=0 heavy_calls=0 desktop=verified'
