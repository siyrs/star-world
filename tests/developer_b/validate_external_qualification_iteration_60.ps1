$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$contractPath = Join-Path $root 'src\diagnostics\external_qualification_contract.gd'
$regressionPath = Join-Path $root 'tests\qa\external_qualification_contract_regression.gd'
$packageValidatorPath = Join-Path $root 'tests\ci\validate_external_qualification_package.ps1'
$hardwareRunnerPath = Join-Path $root 'tests\ci\run_external_hardware_qualification.ps1'
$soakRunnerPath = Join-Path $root 'tests\ci\run_strict_target_hardware_soak.ps1'
$faultRecorderPath = Join-Path $root 'tests\ci\new_external_fault_lab_record.ps1'
$reviewRecorderPath = Join-Path $root 'tests\ci\new_independent_experience_review.ps1'
$assemblerPath = Join-Path $root 'tests\ci\new_external_qualification_package.ps1'
$assemblerTestPath = Join-Path $root 'tests\ci\test_external_qualification_package_assembler.ps1'
$policyHelpersPath = Join-Path $root 'tests\ci\qualification_policy_helpers.ps1'
$policyHelpersTestPath = Join-Path $root 'tests\ci\test_qualification_policy_helpers.ps1'
$releaseSmokeRunnerPath = Join-Path $root 'tests\release\run_windows_export_smoke.ps1'
$releaseSmokeScriptPath = Join-Path $root 'src\diagnostics\release_smoke_runner.gd'
$fixturePath = Join-Path $root 'tests\fixtures\external_qualification\reference-package.json'

$requiredFiles = @(
    $contractPath,
    $regressionPath,
    $packageValidatorPath,
    $hardwareRunnerPath,
    $soakRunnerPath,
    $faultRecorderPath,
    $reviewRecorderPath,
    $assemblerPath,
    $assemblerTestPath,
    $policyHelpersPath,
    $policyHelpersTestPath,
    $releaseSmokeRunnerPath,
    $releaseSmokeScriptPath,
    $fixturePath
)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 60 file missing: $path" }
}

foreach ($path in @(
    $packageValidatorPath,
    $hardwareRunnerPath,
    $soakRunnerPath,
    $faultRecorderPath,
    $reviewRecorderPath,
    $assemblerPath,
    $assemblerTestPath,
    $policyHelpersPath,
    $policyHelpersTestPath,
    $releaseSmokeRunnerPath
)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "PowerShell parse failure in $path`: $((@($parseErrors | ForEach-Object Message) -join ' | '))"
    }
}

function Assert-ContainsAll {
    param([string]$Path, [string[]]$Tokens)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($token in $Tokens) {
        if (-not $text.Contains($token)) { throw "Missing Iteration 60 contract token '$token' in $Path" }
    }
}

Assert-ContainsAll $contractPath @(
    'SCHEMA_VERSION := 2',
    'STRICT_SOAK_SECONDS := 7200',
    'target_hardware',
    'hosted_reference',
    'fixture_contract_complete',
    'release_gate_passed',
    'experiential reviewer must be independent',
    'hardware qualification is missing tier',
    'QUALIFICATION_POLICY_PATH',
    'metric threshold failed',
    'Working Set growth exceeds policy',
    'termination_reason must equal prepared_quit',
    'exact final package reuse',
    'fault lab is missing scenario',
    'release owner must explicitly approve',
    'review commit',
    'strict soak PCK',
    'evidence_source does not match package'
)
Assert-ContainsAll $regressionPath @(
    'fixture evidence never closes the commercial release gate',
    'hosted runner cannot impersonate target hardware',
    'short target soak is rejected',
    'self-review is rejected',
    'all required real fault scenarios are required',
    'E4-H review cannot be rebound to another commit',
    'hardware evidence cannot be mixed from another executable',
    'fault scenarios must retain one operator identity',
    'forged passing performance is recomputed and rejected',
    'scene exit without prepared quit is rejected',
    'strict soak requires ten completed routes'
)
Assert-ContainsAll $packageValidatorPath @(
    '$SchemaVersion = 2',
    'review commit',
    'hardware $tier executable',
    'strict soak PCK',
    'fault $scenarioType PCK',
    'reference_only does not match package',
    'Get-HardwareMetricEvaluationErrors',
    'Get-LifecycleSummaryErrors',
    'rejection-cases=14'
)
Assert-ContainsAll $hardwareRunnerPath @(
    'run_windows_export_journey_matrix.ps1',
    'Release journey matrix did not validate exactly five formal profiles',
    'GitHub-hosted runners cannot create target-hardware qualification evidence',
    'exact_existing_package_reused',
    'operator_attested',
    'executable_sha256',
    'pck_sha256',
    'qualification_policy',
    'metric_evaluation',
    'exact_final_package_reused'
)
Assert-ContainsAll $soakRunnerPath @(
    'soakPolicy.duration_seconds_min',
    'GitHub-hosted runners cannot create target-hardware soak evidence',
    'run_windows_export_smoke.ps1',
    '[System.Diagnostics.Stopwatch]::StartNew()',
    'while ($watch.Elapsed.TotalSeconds -lt $SoakSeconds',
    'Strict soak did not reach wall-clock target',
    'post-spawn transport',
    'minimum_completed_routes',
    'Get-AuthoritativeLifecycleEvidence',
    'authoritative_cycle_lifecycle_count',
    'memoryGrowthPercent'
)
Assert-ContainsAll $releaseSmokeRunnerPath @(
    '--smoke-lifecycle-output=',
    'Get-AuthoritativeLifecycleEvidence',
    'clean authoritative quit'
)
Assert-ContainsAll $releaseSmokeScriptPath @(
    'request_application_quit',
    'release_smoke',
    'authoritative_lifecycle_termination_reason',
    'application_exit_enabled'
)
Assert-ContainsAll $policyHelpersPath @(
    'Get-ReleaseQualificationPolicyContext',
    'Get-HardwareMetricEvaluation',
    'Get-AuthoritativeLifecycleEvidence',
    'prepared_quit'
)
Assert-ContainsAll $policyHelpersTestPath @(
    'assertions=70',
    'scene_exit_without_prepared_quit',
    'minimum_completed_routes',
    'Get-HardwareMetricEvaluation'
)
Assert-ContainsAll $faultRecorderPath @(
    "ValidateSet('hdd', 'antivirus', 'power_loss')",
    "ValidateSet('prepare', 'complete')",
    'GitHub-hosted runners cannot create real HDD, antivirus or power-loss evidence',
    'ReleaseExecutable',
    'ReleasePck',
    'Fault completion must use the exact EXE/PCK captured during prepare',
    'before_world_sha256',
    'after_world_sha256',
    'RecoveryEvidencePath'
)
Assert-ContainsAll $reviewRecorderPath @(
    'The experiential reviewer must be independent from the implementer',
    'IndependentAttestation',
    'E4-H checklist is incomplete',
    'E4-H review has unresolved blockers',
    'executable_sha256'
)
Assert-ContainsAll $assemblerPath @(
    'schema_version = 2',
    'E4-H review commit',
    'hardware $($hardware.tier) executable',
    'fault $($pair.Expected) executable',
    'strict soak executable',
    'build = $review.build',
    'validate_external_qualification_package.ps1',
    '-RequireReleaseGate'
)
Assert-ContainsAll $assemblerTestPath @(
    'EXTERNAL QUALIFICATION ASSEMBLER PASS',
    'Assembler did not bind the final executable and PCK digests',
    'Standalone validator accepted a package with a rebound hardware executable',
    '-ReferenceOnly'
)

$soakText = Get-Content -LiteralPath $soakRunnerPath -Raw
if ($soakText -match 'Start-Sleep\s+-Seconds\s+7200') {
    throw 'Strict soak must execute the final package rather than sleep for 7200 seconds.'
}
if ($soakText -notmatch "star_continent.*desert_ruins.*frozen_wastes.*sky_islands.*abyss_world") {
    throw 'Strict soak must rotate through all five formal profiles.'
}

& $packageValidatorPath
& $policyHelpersTestPath
& $assemblerTestPath

$fixtureOutput = (& $packageValidatorPath -PackagePath $fixturePath | Out-String).Trim()
$fixtureResult = $fixtureOutput | ConvertFrom-Json
if (-not [bool]$fixtureResult.contract_valid) { throw 'Reference fixture is not structurally valid.' }
if ([bool]$fixtureResult.release_gate_passed) { throw 'Reference fixture incorrectly closed the commercial release gate.' }
if ([string]$fixtureResult.status -ne 'fixture_contract_complete') {
    throw "Reference fixture has unexpected status: $($fixtureResult.status)"
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -Depth 100
if ([int]$fixture.schema_version -ne 2) { throw 'Reference fixture must use schema version 2.' }
if (-not [bool]$fixture.reference_only -or -not [bool]$fixture.fixture_mode -or [string]$fixture.evidence_source -ne 'fixture') {
    throw 'Reference fixture must remain explicitly fixture-only and reference-only.'
}
if ($null -ne $fixture.PSObject.Properties['release_owner_attestation']) {
    throw 'Reference fixture must not contain release-owner approval.'
}

Write-Host 'ITERATION 60 EXTERNAL QUALIFICATION CONTRACT PASS | schema=2 | policy=repository-bound | metrics=35-per-tier | lifecycle=authoritative | assembler=bound | fixture=non-qualifying | anti-forgery=validation-time | strict-soak=policy-7200s'
