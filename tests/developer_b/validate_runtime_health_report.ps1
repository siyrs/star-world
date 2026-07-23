$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
$servicePath = Join-Path $root 'src\diagnostics\runtime_health_report_service.gd'
$formatterPath = Join-Path $root 'src\diagnostics\runtime_health_report_formatter.gd'
$hubPath = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
$explorationHubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$coordinatorPath = Join-Path $root 'src\diagnostics\runtime_diagnostics_coordinator.gd'
$telemetryPath = Join-Path $root 'src\diagnostics\runtime_telemetry_service.gd'
$healthPath = Join-Path $root 'src\diagnostics\runtime_health_policy.gd'
$overlayPath = Join-Path $root 'src\ui\diagnostics_overlay.gd'
$policyTestPath = Join-Path $root 'tests\qa\runtime_health_report_policy_regression.gd'
$integrationTestPath = Join-Path $root 'tests\qa\runtime_health_report_regression.gd'
$desktopTestPath = Join-Path $root 'tests\qa\runtime_health_report_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\runtime-health-report-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\RUNTIME_HEALTH_REPORT.md'
$auditPath = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_31.md'
$roadmapPath = Join-Path $root 'docs\PRODUCT_ROADMAP.md'

foreach ($path in @(
  $policyPath,$servicePath,$formatterPath,$hubPath,$explorationHubPath,$scenePath,
  $coordinatorPath,$telemetryPath,$healthPath,$overlayPath,$policyTestPath,
  $integrationTestPath,$desktopTestPath,$workflowPath,$runAllPath,$contractPath,
  $auditPath,$roadmapPath
)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing runtime health contract file: $path"
  }
}

$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$formatter = Get-Content -Raw -Encoding UTF8 $formatterPath
$hub = Get-Content -Raw -Encoding UTF8 $hubPath
$explorationHub = Get-Content -Raw -Encoding UTF8 $explorationHubPath
$scene = Get-Content -Raw -Encoding UTF8 $scenePath
$coordinator = Get-Content -Raw -Encoding UTF8 $coordinatorPath
$telemetry = Get-Content -Raw -Encoding UTF8 $telemetryPath
$health = Get-Content -Raw -Encoding UTF8 $healthPath
$overlay = Get-Content -Raw -Encoding UTF8 $overlayPath
$policyTest = Get-Content -Raw -Encoding UTF8 $policyTestPath
$integrationTest = Get-Content -Raw -Encoding UTF8 $integrationTestPath
$desktopTest = Get-Content -Raw -Encoding UTF8 $desktopTestPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath
$audit = Get-Content -Raw -Encoding UTF8 $auditPath
$roadmap = Get-Content -Raw -Encoding UTF8 $roadmapPath

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
  if ($policy -notmatch $token) {
    throw "Runtime health policy is missing bounded projection: $token"
  }
}
if ($policy -match 'extends\s+Node' -or $policy -match 'Timer\.new\(' -or $policy -match 'FileAccess') {
  throw 'Runtime health policy must remain pure and must not own nodes, timers or files'
}
if ($policy -match 'block_overrides' -or $policy -match 'crop_counts' -or $policy -match 'species_counts') {
  throw 'Runtime health policy must not project full domain dictionaries'
}

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
  if ($service -notmatch $token) {
    throw "Runtime health service is missing read-only aggregation: $token"
  }
}
if ($service -match 'func\s+_process\s*\(' -or $service -match 'Timer\.new\(' -or $service -match 'func\s+serialize\s*\(') {
  throw 'Runtime health service must not own another sampling loop or persistence domain'
}
if ($service -match '\.call\("set_' -or $service -match '\.call\("clear"' -or $service -match '\.call\("save_') {
  throw 'Runtime health aggregation must not mutate source domains'
}

foreach ($token in @(
  'class_name\s+RuntimeHealthReportFormatter',
  'F3 运行与保存健康',
  '主要压力',
  '保存会话',
  '目录累计'
)) {
  if ($formatter -notmatch [regex]::Escape($token) -and $formatter -notmatch $token) {
    throw "Runtime health formatter is missing visible output: $token"
  }
}
if ($formatter -match 'extends\s+Node' -or $formatter -match 'FileAccess' -or $formatter -match 'Input\.') {
  throw 'Runtime health formatter must remain a pure presentation function'
}

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
  if ($hub -notmatch $token) {
    throw "Runtime health composition layer is missing behavior: $token"
  }
}
if ($explorationHub -notmatch 'extends\s+"res://src/ui/runtime_health_service_hub\.gd"') {
  throw 'Stable exploration ServiceHub must inherit the runtime health composition layer'
}
if ($scene -notmatch 'exploration_progression_service_hub\.gd' -or $scene -match 'runtime_health_service_hub\.gd') {
  throw 'Production scene must preserve the stable exploration ServiceHub entry point'
}

if ($coordinator -notmatch 'telemetry\.call\([\s\S]{0,240}_service_hub') {
  throw 'Diagnostics coordinator must pass the final ServiceHub into the existing telemetry service'
}
if ($coordinator -notmatch 'func\s+get_runtime_health_snapshot') {
  throw 'Diagnostics coordinator must expose the latest operations projection'
}
foreach ($token in @(
  'p_service_hub',
  '"operations"\s*:\s*_get_runtime_health_snapshot\(\)',
  'func\s+_get_runtime_health_snapshot\s*\(',
  '"version"\s*:\s*3'
)) {
  if ($telemetry -notmatch $token) {
    throw "Telemetry is missing unified operations evidence: $token"
  }
}
if ($health -notmatch 'operations' -or $health -notmatch 'MAX_OPERATION_ISSUES\s*:=\s*8') {
  throw 'Top-level runtime health must include bounded operations severity and issues'
}

foreach ($token in @(
  'runtime_health_report_formatter\.gd',
  'HBoxContainer\.new\(\)',
  '_health_label',
  'get_panel_rect',
  'HealthFormatter\.format',
  'MOUSE_FILTER_IGNORE'
)) {
  if ($overlay -notmatch $token) {
    throw "F3 overlay is missing two-column read-only health display: $token"
  }
}
if ($overlay -match '\.call\("set_' -or $overlay -match '\.call\("save_' -or $overlay -match 'block_overrides') {
  throw 'F3 overlay must never mutate or inspect full domain state'
}

foreach ($phrase in @(
  'report retains exactly the bounded twelve health rows',
  'report identifies one deterministic critical bottleneck',
  'bounded projection excludes',
  'save and catalog evidence survive the whitelist projection'
)) {
  if ($policyTest -notmatch [regex]::Escape($phrase)) {
    throw "Runtime health policy regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'aggregation reads exactly eleven bounded source snapshots',
  'top-level runtime health includes operations severity',
  'a real F3 event opens the combined health surface',
  'failed save is retained as critical operational evidence'
)) {
  if ($integrationTest -notmatch [regex]::Escape($phrase)) {
    throw "Runtime health integration regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'real service-hub save transaction succeeds',
  'missing sidecar triggers real fallback and self-healing repair',
  'catalog self-healing becomes the deterministic primary operational bottleneck',
  'real F3 input opens the unified health report',
  'next catalog scan returns to steady sidecar hits without another fallback'
)) {
  if ($desktopTest -notmatch [regex]::Escape($phrase)) {
    throw "Runtime health desktop acceptance is missing assertion: $phrase"
  }
}

foreach ($token in @(
  'validate_runtime_health_report\.ps1',
  'runtime_health_report_policy_regression\.gd',
  'runtime_health_report_regression\.gd',
  'runtime_health_report_desktop_acceptance\.gd',
  'runtime-health-report-desktop\.json'
)) {
  if ($workflow -notmatch $token) {
    throw "Runtime health workflow is missing validation or evidence: $token"
  }
}
if ($workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml') {
  throw 'Runtime health workflow must use the reusable Godot quality gate'
}
foreach ($token in @(
  'validate_runtime_health_report\.ps1',
  'runtime_health_report_policy_regression\.gd',
  'runtime_health_report_regression\.gd'
)) {
  if ($runAll -notmatch $token) {
    throw "Full regression entry point is missing runtime health coverage: $token"
  }
}

foreach ($token in @(
  '11 个固定来源',
  '最多 12 行、8 条问题',
  '75%',
  '90%',
  '主要瓶颈',
  '最近保存字节与耗时',
  '不进入存档'
)) {
  if ($contract -notmatch [regex]::Escape($token)) {
    throw "Runtime health contract is missing a boundary: $token"
  }
}
foreach ($token in @(
  '平行监控域',
  '第二个 Timer',
  '固定大小',
  '确定',
  '真实验收'
)) {
  if ($audit -notmatch [regex]::Escape($token)) {
    throw "Architecture audit is missing finding or decision: $token"
  }
}
if ($roadmap -notmatch '统一运行与保存健康报告' -or $roadmap -notmatch '长期规模与恢复') {
  throw 'Product roadmap must record completed unified health and the next recovery priority'
}

Write-Host 'PASS runtime_health_report sources=11 rows=12 issues=8 warning=75% critical=90% telemetry=shared save=measured catalog=self-healing ui=readonly entry=exploration-compatible'
