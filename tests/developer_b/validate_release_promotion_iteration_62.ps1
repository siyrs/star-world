$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pinWriter = Join-Path $root 'tests\ci\new_release_promotion_pin.ps1'
$pinValidator = Join-Path $root 'tests\ci\validate_release_promotion_pin.ps1'
$bundleWriter = Join-Path $root 'tests\ci\new_release_promotion_bundle.ps1'
$bundleValidator = Join-Path $root 'tests\ci\validate_release_promotion_bundle.ps1'
$receiptWriter = Join-Path $root 'tests\ci\new_release_promotion_receipt.ps1'
$bundleTest = Join-Path $root 'tests\ci\test_release_promotion_bundle.ps1'
$workflow = Join-Path $root '.github\workflows\release-promotion-iteration-62-tests.yml'
$roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_62.md'
$guide = Join-Path $root 'docs\RELEASE_PROMOTION_OFFLINE_VALIDATION.md'
$audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-07_ITERATION_62.md'
$requiredFiles = @($pinWriter, $pinValidator, $bundleWriter, $bundleValidator, $receiptWriter, $bundleTest, $workflow, $roadmap, $guide, $audit)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 62 file missing: $path" }
}
foreach ($path in @($pinWriter, $pinValidator, $bundleWriter, $bundleValidator, $receiptWriter, $bundleTest)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "PowerShell parse failure in $path`: $((@($parseErrors | ForEach-Object Message) -join ' | '))" }
}
function Assert-ContainsAll {
    param([string]$Path, [string[]]$Tokens)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($token in $Tokens) {
        if (-not $text.Contains($token)) { throw "Missing Iteration 62 contract token '$token' in $Path" }
    }
}
Assert-ContainsAll $pinWriter @('star-world-release-promotion-pin-v1', 'release_owner_id', 'bundle_id', 'ReleaseOwnerId must match the real qualification package owner', 'validate_release_promotion_pin.ps1')
Assert-ContainsAll $pinValidator @('Expected promotion pin mismatch', 'pin_id does not match the promotion identity', 'release_channel contains unsupported characters', 'release_owner_id must contain 1-128 characters')
Assert-ContainsAll $bundleWriter @('contracts/data/release_qualification.json', 'candidate-chain', 'OutputDirectory must be absent or empty to prevent stale promotion evidence', 'star-world-release-promotion-bundle-v1')
Assert-ContainsAll $bundleValidator @('-RequireReleaseGate requires an externally retained -ExpectedPinId', 'offline_contract_validation', 'Unsafe promotion path', 'Promotion bundle contains missing or unexpected physical files', 'star-world-promotion-contracts-', 'promotion release owner')
Assert-ContainsAll $receiptWriter @('outside the immutable promotion bundle', 'promotion_manifest_sha256', 'validators', 'RELEASE PROMOTION RECEIPT PASS')
Assert-ContainsAll $bundleTest @('checkout drift must not be trusted by promotion validation', 'checkout_drift=pass', 'Contract snapshot tamper', 'Wrong expected promotion pin', 'Hidden promotion file injection', 'Promotion identity tamper', 'negative_cases=8')
Assert-ContainsAll $workflow @('Validate offline release promotion contract', 'Validate strict project import', 'external_qualification_contract_regression.gd', 'release-promotion-bundle-fixture')

$bundleWriterText = Get-Content -LiteralPath $bundleWriter -Raw
if ($bundleWriterText -match 'Compress-Archive') { throw 'Promotion bundle must remain directly inspectable and must not use an opaque ZIP as the canonical source of truth.' }
& $bundleTest
Write-Host 'ITERATION 62 RELEASE PROMOTION PASS | offline-contracts=true | checkout-drift=true | external-pin=true | owner-attestation-bound=true | immutable-receipt=true | negative-cases=8'
