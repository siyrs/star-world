$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required = @(
    'data\update_trust_policy.json',
    'src\update\update_trust_policy.gd',
    'src\update\windows_update_trust_validator.ps1',
    'src\update\windows_update_helper.ps1',
    'tools\new_update_manifest.ps1',
    'tools\sign_update_manifest.ps1',
    'tools\publish_signed_update_release.ps1',
    'tests\qa\windows_update_publisher_trust_acceptance.ps1',
    '.github\workflows\publisher-pinned-auto-update-iteration-64-tests.yml',
    'docs\PRODUCT_ROADMAP_ITERATION_64.md',
    'docs\PUBLISHER_PINNED_AUTO_UPDATE.md',
    'docs\ARCHITECTURE_AUDIT_2026-08-07_ITERATION_64.md'
)
foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 64 file missing: $relative" }
}

& (Join-Path $PSScriptRoot 'validate_auto_update.ps1')

function Assert-ContainsAll([string]$RelativePath, [string[]]$Tokens) {
    $path = Join-Path $root $RelativePath
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    foreach ($token in $Tokens) { if (-not $text.Contains($token)) { throw "Iteration 64 token '$token' missing from $RelativePath" } }
}

Assert-ContainsAll 'src\update\update_service.gd' @(
    'TrustPolicy.load_policy()',
    'TrustPolicy.helper_payload(policy)',
    'publisher_manifest_required',
    'test_allow_unsigned_reference_update',
    'publisher_trust_ready'
)
Assert-ContainsAll 'src\update\windows_update_helper.ps1' @(
    "phase = 'authenticating_publisher'",
    'TrustValidatorPath',
    'TrustPolicyBase64',
    'Reference-only updater trust evidence cannot authorize an install.',
    'Move-Item -LiteralPath $installFull -Destination $backupDirectory'
)
Assert-ContainsAll 'src\update\windows_update_trust_validator.ps1' @(
    'SignedCms',
    'CheckSignature',
    'Get-AuthenticodeSignature',
    'TimeStamperCertificate',
    'Detached update manifest signer certificate is not pinned by the current install.',
    'Updated executable publisher certificate is not pinned by the current install.'
)
Assert-ContainsAll 'tests\qa\windows_update_publisher_trust_acceptance.ps1' @(
    'Manifest byte tamper',
    'Detached signature tamper',
    'Wrong manifest signer pin',
    'Wrong publisher pin',
    'Unsigned executable',
    'PCK tamper should fail before installation.'
)
Assert-ContainsAll '.github\workflows\publisher-pinned-auto-update-iteration-64-tests.yml' @(
    'Validate publisher-pinned updater contract',
    'Exercise real publisher-pinned updater cryptography',
    'Exercise reference swap, ACK and rollback',
    'Validate strict project import',
    'Run updater protocol regression'
)
Assert-ContainsAll 'docs\PUBLISHER_PINNED_AUTO_UPDATE.md' @(
    'target package cannot change the pins',
    'Bootstrap',
    'overlap',
    'publish_signed_update_release.ps1',
    'reference-only'
)

$policy = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\update_trust_policy.json') | ConvertFrom-Json -Depth 20
if (@($policy.manifest_signature.trusted_signer_certificate_sha256).Count -ne 0) { throw 'Real manifest signer pins must not be fabricated in the repository default.' }
if (@($policy.executable_authenticode.trusted_publisher_certificate_sha256).Count -ne 0) { throw 'Real publisher pins must not be fabricated in the repository default.' }
if ([int]$policy.max_active_pins -ne 4) { throw 'Updater certificate rotation budget must remain four pins.' }

$publishWorkflow = Get-Content -Raw -Encoding UTF8 (Join-Path $root '.github\workflows\publish-windows-release.yml')
if ($publishWorkflow -match 'contents:\s*write' -or $publishWorkflow -match 'gh release (create|upload)') { throw 'Hosted reference workflow regained unsigned GitHub Release publication capability.' }

Write-Host 'ITERATION 64 PUBLISHER-PINNED AUTO UPDATE PASS | current-install-pins=true | cms-manifest=true | authenticode=true | trusted-timestamp=true | pre-swap=true | rotation-budget=4 | hosted-publish=blocked'
