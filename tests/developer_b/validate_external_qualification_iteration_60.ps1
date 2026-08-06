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
    $fixturePath
)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 60 file missing: $path" }
}

# Every PowerShell utility must parse independently before any semantic check.
foreach ($path in @(
    $packageValidatorPath,
    $hardwareRunnerPath,
    $soakRunnerPath,
    $faultRecorderPath,
    $reviewRecorderPath,
    $assemblerPath
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
    'STRICT_SOAK_SECONDS := 7200',
    'target_hardware',
    'hosted_reference',
    'fixture_contract_complete',
    'release_gate_passed',
    'experiential reviewer must be independent',
    'hardware qualification is missing tier',
    'target-hardware soak must run for at least 7200 seconds',
    'fault lab is missing scenario',
    'release owner must explicitly approve'
)
Assert-ContainsAll $regressionPath @(
    'fixture evidence never closes the commercial release gate',
    'hosted runner cannot impersonate target hardware',
    'short target soak is rejected',
    'self-review is rejected',
    'all required real fault scenarios are required'
)
Assert-ContainsAll $hardwareRunnerPath @(
    'run_windows_export_journey_matrix.ps1',
    'Release journey matrix did not validate exactly five formal profiles',
    'GitHub-hosted runners cannot create target-hardware qualification evidence',
    'operator_attested',
    'executable_sha256',
    'pck_sha256'
)
Assert-ContainsAll $soakRunnerPath @(
    'Commercial target-hardware soak cannot be shorter than 7200 seconds',
    'GitHub-hosted runners cannot create target-hardware soak evidence',
    'run_windows_export_smoke.ps1',
    '[System.Diagnostics.Stopwatch]::StartNew()',
    'while ($watch.Elapsed.TotalSeconds -lt $SoakSeconds',
    'Strict soak did not reach wall-clock target',
    'post-spawn transport'
)
Assert-ContainsAll $faultRecorderPath @(
    "ValidateSet('hdd', 'antivirus', 'power_loss')",
    "ValidateSet('prepare', 'complete')",
    'GitHub-hosted runners cannot create real HDD, antivirus or power-loss evidence',
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
    'E4-H review commit',
    'hardware $($hardware.tier) executable',
    'strict soak executable',
    'A target-hardware package cannot include reference-only',
    'validate_external_qualification_package.ps1',
    '-RequireReleaseGate'
)

$soakText = Get-Content -LiteralPath $soakRunnerPath -Raw
if ($soakText -match 'Start-Sleep\s+-Seconds\s+7200') {
    throw 'Strict soak must execute the final package rather than sleep for 7200 seconds.'
}
if ($soakText -notmatch "star_continent.*desert_ruins.*frozen_wastes.*sky_islands.*abyss_world") {
    throw 'Strict soak must rotate through all five formal profiles.'
}

# Run the implementation-independent PowerShell validator self-test.
& $packageValidatorPath

# The retained fixture must be structurally complete but provably non-qualifying.
$fixtureOutput = (& $packageValidatorPath -PackagePath $fixturePath | Out-String).Trim()
$fixtureResult = $fixtureOutput | ConvertFrom-Json
if (-not [bool]$fixtureResult.contract_valid) { throw 'Reference fixture is not structurally valid.' }
if ([bool]$fixtureResult.release_gate_passed) { throw 'Reference fixture incorrectly closed the commercial release gate.' }
if ([string]$fixtureResult.status -ne 'fixture_contract_complete') {
    throw "Reference fixture has unexpected status: $($fixtureResult.status)"
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -Depth 100
if (-not [bool]$fixture.reference_only -or -not [bool]$fixture.fixture_mode -or [string]$fixture.evidence_source -ne 'fixture') {
    throw 'Reference fixture must remain explicitly fixture-only and reference-only.'
}
if ($null -ne $fixture.PSObject.Properties['release_owner_attestation']) {
    throw 'Reference fixture must not contain release-owner approval.'
}

Write-Host 'ITERATION 60 EXTERNAL QUALIFICATION CONTRACT PASS | powershell=6 | fixture=non-qualifying | anti-forgery=enabled | strict-soak=7200s'
