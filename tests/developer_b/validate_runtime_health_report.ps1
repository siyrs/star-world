$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."

function Assert-FileExists {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing runtime health contract file: $Path"
  }
}

function Assert-Matches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -match $Pattern) { throw $Message }
}

function Read-ContractText {
  param([Parameter(Mandatory = $true)][string]$Path)
  Assert-FileExists -Path $Path
  return Get-Content -Raw -Encoding UTF8 $Path
}

$paths = [ordered]@{
  policy = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  service = Join-Path $root 'src\diagnostics\runtime_health_report_service.gd'
  formatter = Join-Path $root 'src\diagnostics\runtime_health_report_formatter.gd'
  hub = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
  exploration_hub = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
  scene = Join-Path $root 'scenes\ui\service_hub.tscn'
  coordinator = Join-Path $root 'src\diagnostics\runtime_diagnostics_coordinator.gd'
  telemetry = Join-Path $root 'src\diagnostics\runtime_telemetry_service.gd'
  health = Join-Path $root 'src\diagnostics\runtime_health_policy.gd'
  overlay = Join-Path $root 'src\ui\diagnostics_overlay.gd'
  policy_test = Join-Path $root 'tests\qa\runtime_health_report_policy_regression.gd'
  integration_test = Join-Path $root 'tests\qa\runtime_health_report_regression.gd'
  desktop_test = Join-Path $root 'tests\qa\runtime_health_report_desktop_acceptance.gd'
  soak_test = Join-Path $root 'tests\qa\runtime_soak_regression.gd'
  workflow = Join-Path $root '.github\workflows\runtime-health-report-tests.yml'
  run_all = Join-Path $root 'tests\run_all.ps1'
  contract = Join-Path $root 'docs\RUNTIME_HEALTH_REPORT.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_31.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
}

$text = @{}
foreach ($name in $paths.Keys) {
  $text[$name] = Read-ContractText -Path $paths[$name]
}

foreach ($token in @(
  'class_name\s+RuntimeHealthReportPolicy',
  'MAX_ROWS\s*:=\s*12',
  'MAX_ISSUES\s*:=\s*8',
  'WARNING_USAGE_RATIO\s*:=\s*0\.75',
  'CRITICAL_USAGE_RATIO\s*:=\s*0\.90',
  'streaming_pending',
  'streaming_loaded',
  'machine_domains',
  'agriculture',
  'husbandry',
  'ranch',
  'ecology',
  'pickups',
  'structural_integrity',
  'catalog',
  'save',
  'candidate_queue_budget',
  'primary_bottleneck',
  '_project_save',
  '_project_catalog'
)) {
  Assert-Matches $text.policy $token "Runtime health policy is missing bounded projection: $token"
}
Assert-NotMatches $text.policy 'extends\s+Node|Timer\.new\(|FileAccess' 'Runtime health policy must remain a pure read-only evaluator'
Assert-NotMatches $text.policy 'block_overrides|crop_counts|species_counts' 'Runtime health policy must not project full domain dictionaries'

foreach ($token in @(
  'class_name\s+RuntimeHealthReportService',
  'func\s+record_save_result\s*\(',
  'func\s+get_snapshot\s*\(',
  'get_streaming_stats',
  'get_runtime_snapshot',
  'get_ecology_snapshot',
  'get_catalog_diagnostics',
  '_world_file_size',
  'save_recovered',
  'source_count'
)) {
  Assert-Matches $text.service $token "Runtime health service is missing read-only aggregation: $token"
}
Assert-NotMatches $text.service 'func\s+_process\s*\(|Timer\.new\(|func\s+serialize\s*\(' 'Runtime health service must not own a sampling loop or persistence domain'
Assert-NotMatches $text.service '\.call\("set_|\.call\("clear"|\.call\("save_' 'Runtime health aggregation must not mutate source domains'

foreach ($token in @('class_name\s+RuntimeHealthReportFormatter','F3 运行与保存健康','主要压力','保存会话','目录累计')) {
  Assert-Matches $text.formatter $token "Runtime health formatter is missing visible output: $token"
}
Assert-NotMatches $text.formatter 'extends\s+Node|FileAccess|Input\.' 'Runtime health formatter must remain a pure presentation helper'

foreach ($token in @(
  'class_name\s+RuntimeHealthServiceHub',
  'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"',
  'RuntimeHealthReportServiceScript\.new\(\),\s*"RuntimeHealthReport"',
  'func\s+save_current\s*\(',
  'super\.save_current',
  'record_save_result',
  'func\s+get_runtime_health_snapshot\s*\(',
  'detach_runtime',
  'shutdown'
)) {
  Assert-Matches $text.hub $token "Runtime health composition layer is missing behavior: $token"
}
Assert-Matches $text.exploration_hub 'extends\s+"res://src/ui/runtime_health_service_hub\.gd"' 'Stable exploration ServiceHub must inherit the runtime health composition layer'
Assert-Matches $text.scene 'exploration_progression_service_hub\.gd' 'Production scene must preserve the stable exploration ServiceHub entry point'
Assert-NotMatches $text.scene 'runtime_health_service_hub\.gd' 'Production scene must not bypass the stable exploration ServiceHub entry point'

Assert-Matches $text.coordinator 'telemetry\.call\([\s\S]{0,240}_service_hub' 'Diagnostics coordinator must pass the final ServiceHub into telemetry'
Assert-Matches $text.coordinator 'func\s+get_runtime_health_snapshot' 'Diagnostics coordinator must expose the operations projection'
foreach ($token in @('p_service_hub','"operations"\s*:\s*_get_runtime_health_snapshot\(\)','func\s+_get_runtime_health_snapshot\s*\(','"version"\s*:\s*3')) {
  Assert-Matches $text.telemetry $token "Telemetry is missing unified operations evidence: $token"
}

foreach ($token in @(
  'MAX_OPERATION_ISSUES\s*:=\s*8',
  'runtime_severity',
  'runtime_status',
  'sustained_runtime_severity',
  'sustained_runtime_status',
  'runtime_components',
  'average_frame',
  'peak_frame',
  'stutters',
  'pending_chunks',
  'memory',
  'nodes',
  'operations_severity',
  'operations_status',
  'maxi\(runtime_severity,\s*operations_severity\)'
)) {
  Assert-Matches $text.health $token "Top-level runtime health is missing split component evidence: $token"
}

foreach ($token in @('runtime_health_report_formatter\.gd','HBoxContainer\.new\(\)','_health_label','get_panel_rect','HealthFormatter\.format','MOUSE_FILTER_IGNORE')) {
  Assert-Matches $text.overlay $token "F3 overlay is missing the two-column read-only health display: $token"
}
Assert-NotMatches $text.overlay '\.call\("set_|\.call\("save_|block_overrides' 'F3 overlay must never mutate or inspect full domain state'

foreach ($token in @('MAX_ROWS','MAX_ISSUES','primary_bottleneck','bounded projection excludes','save and catalog evidence survive the whitelist projection')) {
  Assert-Matches $text.policy_test ([regex]::Escape($token)) "Runtime health policy regression is missing coverage: $token"
}
foreach ($token in @(
  'aggregation reads exactly eleven bounded source snapshots',
  'top-level runtime health includes operations severity',
  'runtime and operations severity remain independently observable',
  'a real F3 event opens the combined health surface',
  'failed save is retained as critical operational evidence'
)) {
  Assert-Matches $text.integration_test ([regex]::Escape($token)) "Runtime health integration regression is missing coverage: $token"
}
foreach ($token in @(
  'real service-hub save transaction succeeds',
  'missing sidecar triggers real fallback and self-healing repair',
  'catalog self-healing becomes the deterministic primary operational bottleneck',
  'real F3 input opens the unified health report',
  'next catalog scan returns to steady sidecar hits without another fallback'
)) {
  Assert-Matches $text.desktop_test ([regex]::Escape($token)) "Runtime health desktop acceptance is missing coverage: $token"
}
foreach ($token in @(
  'sustained_runtime_critical_samples',
  'sustained_runtime_severity',
  'runtime_components',
  'runtime health recovers after bounded travel pressure',
  'QA RUNTIME SOAK SAMPLE',
  'QA RUNTIME SOAK CYCLE'
)) {
  Assert-Matches $text.soak_test ([regex]::Escape($token)) "Runtime soak is missing sustained component diagnostics: $token"
}
Assert-Matches $text.soak_test 'sustained_runtime_critical_samples\s*<=\s*2' 'Runtime soak must gate sustained component pressure with a bounded allowance'
Assert-Matches $text.soak_test 'last_runtime_severity\s*<\s*2' 'Runtime soak must prove recovery by the final sample'

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_runtime_health_report\.ps1',
  'runtime_soak_regression\.gd',
  'runtime_health_report_policy_regression\.gd',
  'runtime_health_report_regression\.gd',
  'runtime_health_report_desktop_acceptance\.gd',
  'runtime-health-soak\.stdout\.log',
  'runtime-health-report-desktop\.json'
)) {
  Assert-Matches $text.workflow $token "Runtime health workflow is missing validation or evidence: $token"
}
foreach ($token in @('validate_runtime_health_report\.ps1','runtime_health_report_policy_regression\.gd','runtime_health_report_regression\.gd','runtime_soak_regression\.gd')) {
  Assert-Matches $text.run_all $token "Full regression entry point is missing runtime health coverage: $token"
}

foreach ($token in @('11 个固定来源','最多 12 行、8 条问题','75%','90%','运行分量','运营分量','主要瓶颈','最近保存字节与耗时','不进入存档')) {
  Assert-Matches $text.contract ([regex]::Escape($token)) "Runtime health contract is missing a boundary: $token"
}
foreach ($token in @('平行监控域','第二个 Timer','固定大小','运行分量','运营分量','确定','真实验收','兼容接口')) {
  Assert-Matches $text.audit ([regex]::Escape($token)) "Architecture audit is missing a finding or decision: $token"
}
Assert-Matches $text.roadmap '统一运行与保存健康报告' 'Product roadmap must record the completed unified health report'
Assert-Matches $text.roadmap '长期规模与恢复' 'Product roadmap must retain the next recovery priority'

Write-Host 'PASS runtime_health_report sources=11 rows=12 issues=8 warning=75% critical=90% runtime=componentized sustained=separate operations=split telemetry=shared save=measured catalog=self-healing ui=readonly entry=exploration-compatible'
