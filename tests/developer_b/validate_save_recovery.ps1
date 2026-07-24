$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  store = Join-Path $root 'src\save\atomic_json_store.gd'
  save = Join-Path $root 'src\save\save_service.gd'
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  health_service = Join-Path $root 'src\diagnostics\runtime_health_report_service.gd'
  health_policy = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  formatter = Join-Path $root 'src\diagnostics\runtime_health_report_formatter.gd'
  regression = Join-Path $root 'tests\qa\save_recovery_regression.gd'
  desktop = Join-Path $root 'tests\qa\save_recovery_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\save-recovery-tests.yml'
  run_all = Join-Path $root 'tests\run_all.ps1'
  contract = Join-Path $root 'docs\SELF_HEALING_SAVE_RECOVERY.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_33.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
}

$text = @{}
foreach ($name in $paths.Keys) {
  $path = $paths[$name]
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing save recovery contract file: $path"
  }
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
  $pattern = '(?ms)^(?:static\s+)?func\s+' + [regex]::Escape($MethodName) + '\s*\([^\n]*\).*?(?=^(?:static\s+)?func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'RECOVERY_SUFFIX\s*:=\s*"\.recover"',
  'DISPLACED_SUFFIX\s*:=\s*"\.corrupt"',
  'MAX_REJECTED_SOURCES\s*:=\s*3',
  'func\s+read_dictionary_validated\s*\(',
  'func\s+repair_dictionary\s*\(',
  'validator\.call\(data\)',
  'rejected_sources',
  'repair_attempted',
  'repair_success',
  'candidate_bytes'
)) {
  Assert-Match $text.store $token "Atomic JSON store lost validated recovery contract: $token"
}
$repairBody = Get-MethodBody $text.store '_repair_text'
Assert-Match $repairBody 'rename_absolute\(absolute_path, displaced_path\)' 'Recovery must displace a corrupt primary before promotion'
Assert-Match $repairBody 'rename_absolute\(recovery_path, absolute_path\)' 'Recovery must promote a separately validated staging file'
Assert-Match $repairBody '_remove_if_exists\(temporary_path\)' 'Successful recovery must remove stale temporary files'
Assert-NoMatch $repairBody 'BACKUP_SUFFIX|backup_path|\.bak' 'Recovery promotion must never delete or overwrite the valid backup candidate'

foreach ($token in @(
  'read_dictionary_validated',
  'Callable\(self,\s*"_is_valid_world_payload"\)\.bind\(world_id\)',
  'func\s+_read_world_result\s*\(',
  'func\s+_is_valid_world_payload\s*\(',
  'func\s+get_recovery_diagnostics\s*\(',
  'func\s+reset_recovery_diagnostics\s*\(',
  'repair_success_count',
  'repair_failure_count',
  'primary_rejection_count',
  'last_rejected_sources',
  'primary_ready'
)) {
  Assert-Match $text.save $token "SaveService lost self-healing recovery behavior: $token"
}
$listBody = Get-MethodBody $text.save 'list_worlds'
Assert-Match $listBody 'var\s+primary_ready\s*:=\s*bool\(world_read\.get\("primary_ready",\s*false\)\)' 'Catalog scan must derive authoritative-primary readiness from the recovery result'
Assert-Match $listBody 'if\s+primary_ready\s*:[\s\S]*_write_catalog_entry' 'Catalog repair must remain gated on a healthy authoritative primary'
$validatorBody = Get-MethodBody $text.save '_is_valid_world_payload'
foreach ($token in @('raw_metadata','raw_player','raw_world','block_overrides','stored_world_id')) {
  Assert-Match $validatorBody $token "World recovery validator is missing core structural check: $token"
}
Assert-NoMatch $validatorBody 'agriculture|husbandry|machines|exploration' 'World recovery validator must remain backward-compatible instead of requiring every modern domain'

foreach ($token in @('已自愈 %d 个存档','主文件修复失败 %d','get_recovery_diagnostics')) {
  Assert-Match $text.browser ([regex]::Escape($token)) "Save browser is missing visible recovery evidence: $token"
}
foreach ($token in @('get_recovery_diagnostics','repair_success_count','repair_failure_count','last_recovery_source','last_recovery_elapsed_milliseconds')) {
  Assert-Match $text.health_service $token "Runtime health service is missing save repair aggregation: $token"
}
foreach ($token in @('repair_success_count','repair_failure_count','last_recovery_source','last_recovery_elapsed_milliseconds')) {
  Assert-Match $text.health_policy $token "Runtime health policy is missing bounded save repair projection: $token"
}
Assert-NoMatch $text.health_policy 'get_recovery_diagnostics|save_service\.call' 'Pure runtime health policy must not reach back into SaveService'
Assert-Match $text.health_policy '主文件重建失败' 'F3 health must treat a failed primary repair as critical'
Assert-Match $text.health_policy '恢复并重建主存档' 'F3 health must surface successful self-healing'
Assert-Match $text.formatter '主文件修复 %d / 失败 %d' 'F3 formatter must display primary repair totals'

foreach ($phrase in @(
  'structurally invalid primary falls back to backup',
  'recovery promotion preserves the valid backup',
  'valid temporary generation wins before the older backup',
  'catalog rebuild occurs only after the authoritative primary is healthy',
  'next catalog scan is a pure sidecar hit without another authoritative read',
  'F3 health treats an unrepaired authoritative primary as critical'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Save recovery regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'save browser visibly reports authoritative and catalog self-healing',
  'desktop recovery identifies the backup and rejected primary',
  'desktop repair preserves the valid backup file',
  'continue button starts the recovered production world',
  'continue does not repeat recovery after authoritative repair',
  'F3 visibly reports successful authoritative save repair'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Save recovery desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_save_recovery\.ps1',
  'save_recovery_regression\.gd',
  'save_recovery_desktop_acceptance\.gd',
  'save-recovery-desktop-health\.png',
  'save-recovery-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Save recovery workflow is missing validation or evidence: $token"
}
foreach ($token in @('validate_save_recovery\.ps1','save_recovery_regression\.gd')) {
  Assert-Match $text.run_all $token "Full regression entry point is missing save recovery coverage: $token"
}
foreach ($token in @('语义损坏','有效备份','恢复暂存','保留 `.bak`','目录只在主文件','0 次重复恢复','固定大小诊断')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Save recovery contract is missing boundary: $token"
}
foreach ($token in @('可解析但无效','覆盖唯一有效备份','恢复后目录','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing recovery finding: $token"
}
Assert-Match $text.roadmap 'SELF_HEALING_SAVE_RECOVERY\.md' 'Product roadmap must link the save recovery contract'
Assert-Match $text.roadmap '原子重建主文件' 'Product roadmap must record authoritative save repair'

Write-Host 'PASS save_recovery semantic-validation=on temporary-first=on backup-preserved=on primary-repair=atomic catalog-after-primary=on repeated-recovery=0 diagnostics=bounded desktop=real release=required'
