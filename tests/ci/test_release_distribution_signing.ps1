$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) { throw 'Publisher signing regression requires Windows.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$promotionRoot = Join-Path $root 'build\release-promotion-bundle-fixture'
$pinPath = Join-Path $root 'build\release-promotion-pin-fixture\promotion-pin.json'
$fixtureRoot = Join-Path $root 'build\release-distribution-signing-fixture'
$receiptRoot = Join-Path $root 'build\release-distribution-receipts'
$receiptPath = Join-Path $receiptRoot 'receiver-a.json'

function Get-CertificateSha256 {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Certificate.RawData)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Assert-Rejected {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $rejected = $false
    try { & $Action } catch {
        $rejected = $_.Exception.Message.Contains($Expected)
        if (-not $rejected) { throw "$Name failed for the wrong reason: $($_.Exception.Message)" }
    }
    if (-not $rejected) { throw "$Name was not rejected." }
}

& (Join-Path $PSScriptRoot 'test_release_promotion_bundle.ps1')
if (-not (Test-Path -LiteralPath $promotionRoot -PathType Container)) { throw 'Promotion fixture was not materialized.' }
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -Depth 30
$expectedPinId = [string]$pin.pin_id

$referenceText = (& (Join-Path $PSScriptRoot 'validate_release_distribution_gate.ps1') `
    -PromotionBundleDirectory $promotionRoot `
    -ExpectedPinId $expectedPinId | Out-String).Trim()
$reference = $referenceText | ConvertFrom-Json
if (-not [bool]$reference.valid) { throw 'Reference distribution gate did not validate.' }
if ([bool]$reference.signature_present -or [bool]$reference.release_gate_passed) {
    throw 'Unsigned reference promotion incorrectly behaved as a signed commercial distribution.'
}
if ([bool]$reference.sign_before_qualification_proven) {
    throw 'Unsigned reference promotion incorrectly proved sign-before-qualification.'
}

Remove-Item -LiteralPath $receiptRoot -Recurse -Force -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot 'new_release_distribution_receipt.ps1') `
    -PromotionBundleDirectory $promotionRoot `
    -ExpectedPinId $expectedPinId `
    -ReceiverId 'fixture-receiver-a' `
    -OutputPath $receiptPath
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 30
if ([string]$receipt.result -ne 'pass' -or [bool]$receipt.release_gate_passed -or [bool]$receipt.signature_present) {
    throw 'Reference distribution receipt did not preserve the unsigned reference boundary.'
}
Assert-Rejected -Name 'Receipt mutation inside promotion bundle' -Expected 'outside the immutable promotion bundle' -Action {
    & (Join-Path $PSScriptRoot 'new_release_distribution_receipt.ps1') `
        -PromotionBundleDirectory $promotionRoot `
        -ExpectedPinId $expectedPinId `
        -ReceiverId 'bad-receiver' `
        -OutputPath (Join-Path $promotionRoot 'distribution-receipt.json')
}
Assert-Rejected -Name 'Commercial gate without publisher pin' -Expected 'ExpectedPublisherCertificateSha256' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_distribution_gate.ps1') `
        -PromotionBundleDirectory $promotionRoot `
        -ExpectedPinId $expectedPinId `
        -RequireReleaseGate | Out-Null
}

Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$signedScript = Join-Path $fixtureRoot 'publisher-fixture.ps1'
$unsignedScript = Join-Path $fixtureRoot 'unsigned-fixture.ps1'
$certificatePath = Join-Path $fixtureRoot 'publisher-fixture.cer'
Set-Content -LiteralPath $signedScript -Value "Write-Output 'Star World publisher signing fixture'" -Encoding utf8
Set-Content -LiteralPath $unsignedScript -Value "Write-Output 'unsigned fixture'" -Encoding utf8

$certificate = $null
$rootCertificate = $null
$publisherCertificate = $null
try {
    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject 'CN=Star World Fixture Publisher' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddDays(2)
    Export-Certificate -Cert $certificate -FilePath $certificatePath | Out-Null
    $rootCertificate = Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\CurrentUser\Root'
    $publisherCertificate = Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher'
    $signature = Set-AuthenticodeSignature -FilePath $signedScript -Certificate $certificate -HashAlgorithm SHA256
    if ([string]$signature.Status -ne 'Valid') {
        throw "Fixture Authenticode signing did not become trusted: status=$($signature.Status) message=$($signature.StatusMessage)"
    }

    $publisherSha256 = Get-CertificateSha256 $certificate
    $signatureText = (& (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
        -FilePath $signedScript `
        -ExpectedPublisherCertificateSha256 $publisherSha256 `
        -RequireSignature | Out-String).Trim()
    $signatureResult = $signatureText | ConvertFrom-Json
    if (-not [bool]$signatureResult.signature_present -or -not [bool]$signatureResult.trusted) {
        throw 'Trusted publisher fixture signature did not validate.'
    }
    if (-not [bool]$signatureResult.signer.code_signing_eku) { throw 'Fixture signer did not expose the Code Signing EKU.' }
    if ([bool]$signatureResult.timestamp.present) { throw 'Local fixture unexpectedly contains a trusted external timestamp.' }

    Assert-Rejected -Name 'Wrong publisher certificate pin' -Expected 'Publisher certificate SHA-256 mismatch' -Action {
        & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
            -FilePath $signedScript `
            -ExpectedPublisherCertificateSha256 ('f' * 64) `
            -RequireSignature | Out-Null
    }
    Assert-Rejected -Name 'Missing trusted timestamp' -Expected 'trusted Authenticode timestamp' -Action {
        & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
            -FilePath $signedScript `
            -ExpectedPublisherCertificateSha256 $publisherSha256 `
            -RequireSignature `
            -RequireTrustedTimestamp | Out-Null
    }
    Assert-Rejected -Name 'Unsigned publisher artifact' -Expected 'Publisher Authenticode signature is required' -Action {
        & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
            -FilePath $unsignedScript `
            -RequireSignature | Out-Null
    }
} finally {
    foreach ($storePath in @(
        if ($null -ne $certificate) { "Cert:\CurrentUser\My\$($certificate.Thumbprint)" },
        if ($null -ne $rootCertificate) { "Cert:\CurrentUser\Root\$($certificate.Thumbprint)" },
        if ($null -ne $publisherCertificate) { "Cert:\CurrentUser\TrustedPublisher\$($certificate.Thumbprint)" }
    )) {
        if ($storePath -and (Test-Path -LiteralPath $storePath)) { Remove-Item -LiteralPath $storePath -Force }
    }
}

Write-Host "RELEASE PUBLISHER SIGNING PASS | reference_unsigned=true | signed_fixture=trusted | timestamp_fixture=external-only | negative_cases=5 | receipt=$receiptPath"
