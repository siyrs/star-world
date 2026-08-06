$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$candidateWriter = Join-Path $root 'tests\ci\new_release_candidate_manifest.ps1'
$candidateValidator = Join-Path $root 'tests\ci\validate_release_candidate_manifest.ps1'
$bundleWriter = Join-Path $root 'tests\ci\new_external_qualification_chain_bundle.ps1'
$bundleValidator = Join-Path $root 'tests\ci\validate_external_qualification_chain_bundle.ps1'
$bundleTest = Join-Path $root 'tests\ci\test_external_qualification_chain_bundle.ps1'
$workflow = Join-Path $root '.github\workflows\release-candidate-chain-iteration-61-tests.yml'
$roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_61.md'
$guide = Join-Path $root 'docs\RELEASE_CANDIDATE_CHAIN_OF_CUSTODY.md'
$audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-06_ITERATION_61.md'
$requiredFiles = @($candidateWriter, $candidateValidator, $bundleWriter, $bundleValidator, $bundleTest, $workflow, $roadmap, $guide, $audit)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 61 file missing: $path" }
}

foreach ($path in @($candidateWriter, $candidateValidator, $bundleWriter, $bundleValidator, $bundleTest)) {
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
        if (-not $text.Contains($token)) { throw "Missing Iteration 61 contract token '$token' in $Path" }
    }
}

Assert-ContainsAll $candidateWriter @(
    'star-world-release-candidate-v1',
    'candidate_id',
    'release_qualification.json',
    'export_presets.cfg',
    'Move-Item -LiteralPath $tempPath'
)
Assert-ContainsAll $candidateValidator @(
    'candidate_id does not match the candidate contents',
    'StarWorld.pck beside StarWorld.exe',
    'Assert-RepositoryContractPath',
    'data/release_qualification.json',
    'release qualification policy'
)
Assert-ContainsAll $bundleWriter @(
    'OutputDirectory must be absent or empty to prevent stale evidence',
    'qualification package artifact',
    'star-world-qualification-chain-bundle-v1',
    'Copy-BundleFile',
    'validate_external_qualification_chain_bundle.ps1'
)
Assert-ContainsAll $bundleValidator @(
    'Bundle must not contain symbolic links or reparse points',
    'Bundle contains missing or unexpected files',
    'Unsafe bundle path',
    "-match '(^|/)\.\.(/|$)'",
    'artifact manifest',
    'bundle_id'
)
Assert-ContainsAll $bundleTest @(
    'Evidence tamper',
    'Candidate identity tamper',
    'Unexpected file injection',
    'Bundle path traversal',
    'tamper_cases=4'
)
Assert-ContainsAll $workflow @(
    'Validate release candidate chain contract',
    'Validate strict project import',
    'external_qualification_contract_regression.gd',
    'release-candidate-chain-fixture'
)

$bundleWriterText = Get-Content -LiteralPath $bundleWriter -Raw
if ($bundleWriterText -match 'Compress-Archive') {
    throw 'The canonical evidence chain must remain a directly inspectable directory, not an opaque ZIP-only artifact.'
}

& $bundleTest
Write-Host 'ITERATION 61 RELEASE CANDIDATE CHAIN PASS | manifest=immutable | bundle=portable | artifact-hashes=verified | tamper-cases=4'
