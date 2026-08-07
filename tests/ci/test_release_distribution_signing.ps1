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
function Find-TrustedTimestampedFixture {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) { $candidates.Add($pwsh.Source) }
    $candidates.Add((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    $candidates.Add((Join-Path $env:SystemRoot 'System32\notepad.exe'))
    $candidates.Add((Join-Path $env:SystemRoot 'System32\cmd.exe'))
    $observed = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $signature = Get-AuthenticodeSignature -LiteralPath $candidate
        $observed.Add("$candidate=$($signature.Status):timestamp=$($null -ne $signature.TimeStamperCertificate)")
        if ([string]$signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and $null -ne $signature.TimeStamperCertificate) {
            return [pscustomobject]@{ Path = $candidate; Signature = $signature }
        }
    }
    throw "No trusted timestamped Authenticode fixture is available on the Windows runner. Observed: $($observed -join ' | ')"
}

Write-Host 'SIGNING FIXTURE PHASE | reference-promotion'
if (-not (Test-Path -LiteralPath $promotionRoot -PathType Container)) { throw 'Promotion fixture was not materialized by the preceding workflow step.' }
if (-not (Test-Path -LiteralPath $pinPath -PathType Leaf)) { throw 'Promotion pin fixture was not materialized by the preceding workflow step.' }
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -Depth 30
$expectedPinId = [string]$pin.pin_id

$referenceText = (& (Join-Path $PSScriptRoot 'validate_release_distribution_gate.ps1') `
    -PromotionBundleDirectory $promotionRoot `
    -ExpectedPinId $expectedPinId | Out-String).Trim()
$reference = $referenceText | ConvertFrom-Json
if (-not [bool]$reference.valid) { throw 'Reference distribution gate did not validate.' }
if ([bool]$reference.signature_present -or [bool]$reference.release_gate_passed) { throw 'Unsigned reference promotion incorrectly behaved as a signed commercial distribution.' }
if ([bool]$reference.sign_before_qualification_proven) { throw 'Unsigned reference promotion incorrectly proved sign-before-qualification.' }

Write-Host 'SIGNING FIXTURE PHASE | reference-receipt'
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

Write-Host 'SIGNING FIXTURE PHASE | trusted-timestamped-fixture'
Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
$trustedSource = Find-TrustedTimestampedFixture
$trustedFixture = Join-Path $fixtureRoot 'trusted-publisher-fixture.exe'
$tamperedFixture = Join-Path $fixtureRoot 'tampered-publisher-fixture.exe'
$unsignedScript = Join-Path $fixtureRoot 'unsigned-fixture.ps1'
Copy-Item -LiteralPath $trustedSource.Path -Destination $trustedFixture
Copy-Item -LiteralPath $trustedSource.Path -Destination $tamperedFixture
Set-Content -LiteralPath $unsignedScript -Value "Write-Output 'unsigned fixture'" -Encoding utf8

$publisherSha256 = Get-CertificateSha256 $trustedSource.Signature.SignerCertificate
$signatureText = (& (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
    -FilePath $trustedFixture `
    -ExpectedPublisherCertificateSha256 $publisherSha256 `
    -RequireSignature `
    -RequireTrustedTimestamp | Out-String).Trim()
$signatureResult = $signatureText | ConvertFrom-Json
if (-not [bool]$signatureResult.signature_present -or -not [bool]$signatureResult.trusted) { throw 'Trusted publisher fixture signature did not validate.' }
if (-not [bool]$signatureResult.signer.code_signing_eku) { throw 'Trusted signer did not expose the Code Signing EKU.' }
if (-not [bool]$signatureResult.timestamp.present -or -not [bool]$signatureResult.timestamp.timestamp_eku) { throw 'Trusted fixture did not expose a valid timestamp certificate and EKU.' }

Write-Host 'SIGNING FIXTURE PHASE | negative-cases'
Assert-Rejected -Name 'Wrong publisher certificate pin' -Expected 'Publisher certificate SHA-256 mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
        -FilePath $trustedFixture `
        -ExpectedPublisherCertificateSha256 ('f' * 64) `
        -RequireSignature `
        -RequireTrustedTimestamp | Out-Null
}

$bytes = [System.IO.File]::ReadAllBytes($tamperedFixture)
if ($bytes.Length -lt 512) { throw 'Trusted fixture is unexpectedly too small for tamper testing.' }
$offset = [Math]::Min(4096, [Math]::Max(256, [int]($bytes.Length / 3)))
$bytes[$offset] = $bytes[$offset] -bxor 0x01
[System.IO.File]::WriteAllBytes($tamperedFixture, $bytes)
Assert-Rejected -Name 'Tampered signed artifact' -Expected 'not trusted and valid' -Action {
    & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
        -FilePath $tamperedFixture `
        -ExpectedPublisherCertificateSha256 $publisherSha256 `
        -RequireSignature | Out-Null
}
Assert-Rejected -Name 'Unsigned publisher artifact' -Expected 'Publisher Authenticode signature is required' -Action {
    & (Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1') `
        -FilePath $unsignedScript `
        -RequireSignature | Out-Null
}

Write-Host "RELEASE PUBLISHER SIGNING PASS | reference_unsigned=true | trusted_timestamp_fixture=$($trustedSource.Path) | publisher_cert=$publisherSha256 | negative_cases=5 | receipt=$receiptPath"
