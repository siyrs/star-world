$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$reusablePath = Join-Path $root '.github\workflows\reusable-godot-quality-gate.yml'
$godotGatePath = Join-Path $root '.github\workflows\godot-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\REUSABLE_GODOT_QUALITY_GATES.md'
$auditPath = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-23_ITERATION_28.md'

$callers = [ordered]@{
  'pickup-shared-runtime-tests.yml' = @('validate_reusable_ci_workflows.ps1','validate_pickup_shared_runtime.ps1','pickup_shared_runtime_regression.gd','pickup_shared_runtime_desktop_acceptance.gd','pickup-shared-runtime-desktop.json')
  'mixed-runtime-endurance-tests.yml' = @('validate_pickup_stacks.ps1','pickup_stack_regression.gd','multi_hostile_danger_batch_regression.gd','mixed_runtime_endurance_desktop_acceptance.gd','mixed-runtime-endurance-desktop.json')
  'recent-chunk-cache-tests.yml' = @('validate_recent_chunk_cache.ps1','recent_chunk_snapshot_cache_regression.gd','adaptive_streaming_regression.gd','recent_chunk_cache_desktop_acceptance.gd','recent-chunk-cache-desktop.json')
  'machine-scale-tests.yml' = @('validate_machine_scale.ps1','machine_scale_runtime_regression.gd','machine_automation_regression.gd','machine_scale_desktop_acceptance.gd','machine-scale-desktop.json')
  'agriculture-scale-tests.yml' = @('validate_agriculture_scale.ps1','agriculture_scale_batch_regression.gd','agriculture_runtime_lifecycle_regression.gd','agriculture_scale_desktop_acceptance.gd','agriculture-scale-desktop.json')
  'world-scale-tests.yml' = @('validate_world_mutation_batch.ps1','world_mutation_batch_regression.gd','connected_block_shapes_regression.gd','world_scale_desktop_acceptance.gd','world-scale-desktop.json')
}

foreach ($path in @($reusablePath,$godotGatePath,$runAllPath,$contractPath,$auditPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Reusable CI contract file is missing: $path" }
}

$reusable = Get-Content -Raw -Encoding UTF8 $reusablePath
$godotGate = Get-Content -Raw -Encoding UTF8 $godotGatePath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath
$audit = Get-Content -Raw -Encoding UTF8 $auditPath

if ($reusable -notmatch 'workflow_call:') { throw 'Reusable Godot gate must be callable through workflow_call' }
foreach ($inputName in @('domain_job_name','domain_timeout_minutes','static_validators','primary_headless_script','domain_scripts','domain_artifact_paths','desktop_script','desktop_output_path','desktop_artifact_paths','retention_days')) {
  $inputPattern = '(?m)^\s{6}' + [regex]::Escape($inputName) + ':'
  if ($reusable -notmatch $inputPattern) { throw "Reusable Godot gate is missing input: $inputName" }
}
foreach ($token in @('actions/checkout@v4','chickensoft-games/setup-godot@v2','tests\\ci\\Invoke-Godot\.ps1','tests\\ci\\run_godot_headless_test\.ps1','tests\\ci\\run_godot_desktop_test\.ps1','actions/upload-artifact@v4','inputs\.desktop_script\s*!=\s*''','if-no-files-found:\s*\$\{\{\s*inputs\.')) {
  if ($reusable -notmatch $token) { throw "Reusable Godot gate is missing awaited runner or artifact contract: $token" }
}
if ($reusable -match '(?m)^\s{2}(pull_request|push):') { throw 'Reusable Godot gate must not trigger independently from its caller workflows' }
$inheritedCredentialPattern = ('se' + 'crets:\s*inherit')
$writePermissionPattern = ('contents:\s*' + 'write')
if ($reusable -match $inheritedCredentialPattern -or $reusable -match $writePermissionPattern) {
  throw 'Reusable domain and desktop gates must remain read-only without inherited credentials'
}

$callerTexts = @{}
foreach ($fileName in $callers.Keys) {
  $path = Join-Path $root ".github\workflows\$fileName"
  if (-not (Test-Path -LiteralPath $path)) { throw "Migrated caller workflow is missing: $fileName" }
  $text = Get-Content -Raw -Encoding UTF8 $path
  $callerTexts[$fileName] = $text
  if ($text -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml') { throw "Workflow must call the reusable Godot gate: $fileName" }
  if ($text -notmatch 'concurrency:' -or $text -notmatch 'cancel-in-progress:\s*true') { throw "Caller must retain per-branch cancellation: $fileName" }
  foreach ($forbidden in @('(?m)^\s+runs-on:','actions/checkout@v4','setup-godot@v2','upload-artifact@v4')) {
    if ($text -match $forbidden) { throw "Caller duplicated reusable implementation token '$forbidden': $fileName" }
  }
  foreach ($required in $callers[$fileName]) {
    if ($text -notmatch [regex]::Escape($required)) { throw "Caller lost declared validation or evidence input '$required': $fileName" }
  }
}

$combinedReusableSurface = $reusable
foreach ($text in $callerTexts.Values) { $combinedReusableSurface += "`n$text" }
$checkoutCount = [regex]::Matches($combinedReusableSurface,'actions/checkout@v4').Count
$setupCount = [regex]::Matches($combinedReusableSurface,'setup-godot@v2').Count
$uploadCount = [regex]::Matches($combinedReusableSurface,'actions/upload-artifact@v4').Count
if ($checkoutCount -ne 2 -or $setupCount -ne 2 -or $uploadCount -ne 2) { throw "Reusable setup/upload implementation drifted: checkout=$checkoutCount setup=$setupCount upload=$uploadCount" }

if ($godotGate -notmatch 'Exported Windows release smoke' -or $godotGate -notmatch 'include-templates:\s*true') { throw 'The authoritative Godot gate must retain real Windows export templates and release smoke' }
if ($godotGate -match 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml') { throw 'The authoritative full desktop matrix and Windows Release gate must remain explicit' }
if ($runAll -notmatch 'validate_reusable_ci_workflows\.ps1') { throw 'Full static regression entry point must include the reusable CI validator' }
if ($contract -notmatch 'workflow_call' -or $contract -notmatch '六个' -or $contract -notmatch 'Windows Release') { throw 'Reusable CI contract must document call boundaries, migration scope, and release authority' }
if ($audit -notmatch 'Checkout' -or $audit -notmatch 'setup-godot' -or $audit -notmatch '重复') { throw 'Architecture audit must record the duplicated workflow implementation problem' }

Write-Host 'PASS reusable_godot_ci callers=6 shared_jobs=2 checkout_impl=2 setup_impl=2 upload_impl=2 release_gate=explicit'
