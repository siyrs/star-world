$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$signatureValidator = Join-Path $root 'tests\ci\validate_windows_publisher_signature.ps1'
$distributionGate = Join-Path $root 'tests\ci\validate_release_distribution_gate.ps1'
$receiptWriter = Join-Path $root 'tests\ci\new_release_distribution_receipt.ps1'
$distributionTest = Join-Path $root 'tests\ci\test_release_distribution_signing.ps1'
$workflow = Join-Path $root '.github\workflows\release-publisher-signing-iteration-63-tests.yml'
$policyPath = Join-Path $root 'data\release_qualification.json'
$roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_63.md'
$guide = Join-Path $root 'docs\RELEASE_PUBLISHER_SIGNING_GATE.md'
$audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-07_ITERATION_63.md'
$required = @($signatureValidator, $distributionGate, $receiptWriter, $distributionTest, $workflow, $policyPath, $roadmap, $guide, $audit)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 63 file missing: $path" }
}
foreach ($path in @($signatureValidator, $distributionGate, $receiptWriter, $distributionTest)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "PowerShell parse failure in $path`: $((@($parseErrors | ForEach-Object Message) -join ' | '))" }
}
function Assert-ContainsAll {
    param([string]$Path, [string[]]$Tokens)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($token in $Tokens) {
        if (-not $text.Contains($token)) { throw "Missing Iteration 63 contract token '$token' in $Path" }
    }
}
Assert-ContainsAll $signatureValidator @('Get-AuthenticodeSignature', 'ExpectedPublisherCertificateSha256', 'Code Signing EKU', 'trusted Authenticode timestamp', 'Time Stamping EKU')
Assert-ContainsAll $distributionGate @('sign_before_qualification', 'post_qualification_signing_forbidden', 'ExpectedPublisherCertificateSha256', 'sign_before_qualification_proven', 'not_required_reference', 'validate_release_promotion_bundle.ps1', 'validate_windows_publisher_signature.ps1')
Assert-ContainsAll $receiptWriter @('outside the immutable promotion bundle', 'publisher_certificate_sha256', 'timestamp_certificate_sha256', 'distribution_gate_sha256')
Assert-ContainsAll $distributionTest @('Find-TrustedTimestampedFixture', 'Wrong publisher certificate pin', 'Tampered signed artifact', 'Unsigned publisher artifact', 'negative_cases=5')
Assert-ContainsAll $workflow @('Validate publisher signing static contract', 'Materialize promotion reference fixture', 'Exercise Authenticode and distribution gate', 'Validate strict project import')

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -Depth 30
$signing = $policy.publisher_signing
if ($null -eq $signing) { throw 'release_qualification.json is missing publisher_signing.' }
foreach ($name in @('required_for_commercial', 'sign_before_qualification', 'post_qualification_signing_forbidden', 'authenticode_required', 'trusted_timestamp_required', 'publisher_certificate_sha256_external', 'distribution_receipt_external')) {
    if (-not [bool]$signing.$name) { throw "publisher_signing.$name must be true." }
}
if ([string]$signing.code_signing_eku_oid -ne '1.3.6.1.5.5.7.3.3') { throw 'Code Signing EKU OID drifted.' }
if ([string]$signing.timestamp_eku_oid -ne '1.3.6.1.5.5.7.3.8') { throw 'Time Stamping EKU OID drifted.' }

Write-Host 'ITERATION 63 PUBLISHER SIGNING STATIC PASS | sign-before-qualification=true | external-publisher-pin=true | authenticode=true | trusted-timestamp=required'
