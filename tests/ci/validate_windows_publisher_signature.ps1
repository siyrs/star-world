param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string]$ExpectedPublisherCertificateSha256 = '',
    [switch]$RequireSignature,
    [switch]$RequireTrustedTimestamp
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
if (-not $IsWindows) { throw 'Windows Authenticode validation requires Windows.' }

$resolved = [System.IO.Path]::GetFullPath($FilePath)
if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Publisher signature input not found: $resolved" }

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-CertificateSha256 {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Certificate.RawData)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Assert-HexSha256 {
    param([string]$Value, [string]$Label)
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "$Label must be a lowercase 64-character hexadecimal SHA-256 digest." }
}
function Test-CertificateEku {
    param(
        [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)][string]$Oid
    )
    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) {
                if ([string]$usage.Value -eq $Oid) { return $true }
            }
        }
    }
    return $false
}

$expectedPublisher = $ExpectedPublisherCertificateSha256.Trim().ToLowerInvariant()
if (-not [string]::IsNullOrWhiteSpace($expectedPublisher)) { Assert-HexSha256 $expectedPublisher 'ExpectedPublisherCertificateSha256' }
if ($RequireTrustedTimestamp -and -not $RequireSignature) { throw '-RequireTrustedTimestamp requires -RequireSignature.' }

$signature = Get-AuthenticodeSignature -LiteralPath $resolved
$signer = $signature.SignerCertificate
$signaturePresent = $null -ne $signer -and [string]$signature.Status -ne 'NotSigned'
if ($RequireSignature -and -not $signaturePresent) { throw 'Publisher Authenticode signature is required.' }

$signerCertificateSha256 = ''
$signerCodeSigningEku = $false
$timestampPresent = $false
$timestampCertificateSha256 = ''
$timestampEku = $false
$timestampSubject = ''
$timestampIssuer = ''
$timestampThumbprint = ''

if ($signaturePresent) {
    $signerCertificateSha256 = Get-CertificateSha256 $signer
    $signerCodeSigningEku = Test-CertificateEku -Certificate $signer -Oid '1.3.6.1.5.5.7.3.3'
    if (-not $signerCodeSigningEku) { throw 'Publisher certificate does not contain the Code Signing EKU.' }
    if (-not [string]::IsNullOrWhiteSpace($expectedPublisher) -and $signerCertificateSha256 -ne $expectedPublisher) {
        throw "Publisher certificate SHA-256 mismatch: expected $expectedPublisher, got $signerCertificateSha256"
    }
    if ($RequireSignature -and [string]$signature.Status -ne 'Valid') {
        throw "Publisher Authenticode signature is not trusted and valid: status=$($signature.Status)"
    }

    $timestamp = $signature.TimeStamperCertificate
    $timestampPresent = $null -ne $timestamp
    if ($timestampPresent) {
        $timestampCertificateSha256 = Get-CertificateSha256 $timestamp
        $timestampEku = Test-CertificateEku -Certificate $timestamp -Oid '1.3.6.1.5.5.7.3.8'
        $timestampSubject = [string]$timestamp.Subject
        $timestampIssuer = [string]$timestamp.Issuer
        $timestampThumbprint = ([string]$timestamp.Thumbprint).ToLowerInvariant()
    }
    if ($RequireTrustedTimestamp) {
        if (-not $timestampPresent) { throw 'A trusted Authenticode timestamp is required for commercial release.' }
        if (-not $timestampEku) { throw 'Authenticode timestamp certificate does not contain the Time Stamping EKU.' }
        if ([string]$signature.Status -ne 'Valid') { throw "Timestamped publisher signature is not trusted and valid: status=$($signature.Status)" }
    }
} elseif (-not [string]::IsNullOrWhiteSpace($expectedPublisher)) {
    throw 'ExpectedPublisherCertificateSha256 was supplied but the file is unsigned.'
}

[ordered]@{
    schema_version = 1
    valid = $true
    file_sha256 = Get-Sha256 $resolved
    signature_present = $signaturePresent
    signature_status = [string]$signature.Status
    signature_status_message = [string]$signature.StatusMessage
    trusted = $signaturePresent -and ([string]$signature.Status -eq 'Valid')
    signer = if ($signaturePresent) {
        [ordered]@{
            subject = [string]$signer.Subject
            issuer = [string]$signer.Issuer
            thumbprint = ([string]$signer.Thumbprint).ToLowerInvariant()
            certificate_sha256 = $signerCertificateSha256
            code_signing_eku = $signerCodeSigningEku
            not_before_utc = $signer.NotBefore.ToUniversalTime().ToString('o')
            not_after_utc = $signer.NotAfter.ToUniversalTime().ToString('o')
        }
    } else { $null }
    timestamp = [ordered]@{
        present = $timestampPresent
        subject = $timestampSubject
        issuer = $timestampIssuer
        thumbprint = $timestampThumbprint
        certificate_sha256 = $timestampCertificateSha256
        timestamp_eku = $timestampEku
    }
} | ConvertTo-Json -Depth 8
