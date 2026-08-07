param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$SignaturePath,
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$TrustPolicyBase64,
    [switch]$AllowUnsignedReference
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-ByteSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-Sha256Text {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[0-9a-fA-F]{64}$'
}

function Get-PinList {
    param([object]$Section, [string]$PropertyName, [int]$MaxPins)
    if ($null -eq $Section) { throw "Updater trust section is missing for $PropertyName." }
    $property = $Section.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { throw "Updater trust pin list is missing: $PropertyName" }
    $pins = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($raw in @($property.Value)) {
        $pin = ([string]$raw).Trim().ToLowerInvariant()
        if (-not (Test-Sha256Text $pin)) { throw "Updater trust pin is invalid: $PropertyName" }
        if (-not $seen.ContainsKey($pin)) {
            $seen[$pin] = $true
            $pins.Add($pin)
        }
    }
    if ($pins.Count -gt $MaxPins) { throw "Updater trust pin budget exceeded: $PropertyName" }
    return @($pins)
}

function Test-CertificateEku {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$RequiredOid)
    if ($null -eq $Certificate -or [string]::IsNullOrWhiteSpace($RequiredOid)) { return $false }
    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($oid in $extension.EnhancedKeyUsages) {
                if ([string]$oid.Value -eq $RequiredOid) { return $true }
            }
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Update manifest is missing for trust validation.' }
if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { throw 'Update executable is missing for trust validation.' }
if ([string]::IsNullOrWhiteSpace($TrustPolicyBase64)) { throw 'Updater trust policy payload is missing.' }

$policyJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TrustPolicyBase64))
$policy = $policyJson | ConvertFrom-Json
if ([int]$policy.schema_version -ne 1) { throw 'Unsupported updater trust policy schema.' }
$maxPins = [Math]::Min(8, [Math]::Max(1, [int]$policy.max_active_pins))
$manifestPolicy = $policy.manifest_signature
$executablePolicy = $policy.executable_authenticode
$manifestPins = @(Get-PinList -Section $manifestPolicy -PropertyName 'trusted_signer_certificate_sha256' -MaxPins $maxPins)
$publisherPins = @(Get-PinList -Section $executablePolicy -PropertyName 'trusted_publisher_certificate_sha256' -MaxPins $maxPins)

if ($AllowUnsignedReference) {
    [ordered]@{
        schema_version = 1
        valid = $true
        reference_only = $true
        manifest_signature_present = (Test-Path -LiteralPath $SignaturePath -PathType Leaf)
        manifest_signer_certificate_sha256 = ''
        publisher_signature_present = $false
        publisher_certificate_sha256 = ''
        trusted_timestamp_present = $false
    } | ConvertTo-Json -Depth 6
    return
}

if ([bool]$manifestPolicy.required_for_release -and $manifestPins.Count -eq 0) {
    throw 'Updater manifest signer trust is not configured.'
}
if ([bool]$executablePolicy.required_for_release -and $publisherPins.Count -eq 0) {
    throw 'Updater publisher trust is not configured.'
}
if ([string]$manifestPolicy.format -ne 'cms-detached' -or [string]$manifestPolicy.digest -ne 'sha256') {
    throw 'Unsupported updater manifest signature algorithm.'
}
if (-not (Test-Path -LiteralPath $SignaturePath -PathType Leaf)) {
    throw 'Detached publisher signature is missing from update package.'
}

$manifestBytes = [System.IO.File]::ReadAllBytes($ManifestPath)
$signatureBytes = [System.IO.File]::ReadAllBytes($SignaturePath)
$contentInfo = [System.Security.Cryptography.Pkcs.ContentInfo]::new($manifestBytes)
$cms = [System.Security.Cryptography.Pkcs.SignedCms]::new($contentInfo, $true)
$cms.Decode($signatureBytes)
$cms.CheckSignature($true)
if ($cms.SignerInfos.Count -ne 1) { throw 'Detached update manifest must have exactly one signer.' }
$manifestSigner = $cms.SignerInfos[0].Certificate
if ($null -eq $manifestSigner) { throw 'Detached update manifest signer certificate is missing.' }
$manifestSignerSha256 = Get-ByteSha256 -Bytes $manifestSigner.RawData
if ($manifestPins -notcontains $manifestSignerSha256) { throw 'Detached update manifest signer certificate is not pinned by the current install.' }
if (-not (Test-CertificateEku -Certificate $manifestSigner -RequiredOid ([string]$manifestPolicy.code_signing_eku_oid))) {
    throw 'Detached update manifest signer is missing the Code Signing EKU.'
}

$authenticode = Get-AuthenticodeSignature -LiteralPath $ExecutablePath
if ([string]$authenticode.Status -ne 'Valid') {
    throw "Updated executable Authenticode status is not Valid: $($authenticode.Status)"
}
$publisherCertificate = $authenticode.SignerCertificate
if ($null -eq $publisherCertificate) { throw 'Updated executable signer certificate is missing.' }
$publisherSha256 = Get-ByteSha256 -Bytes $publisherCertificate.RawData
if ($publisherPins -notcontains $publisherSha256) { throw 'Updated executable publisher certificate is not pinned by the current install.' }
if (-not (Test-CertificateEku -Certificate $publisherCertificate -RequiredOid ([string]$executablePolicy.code_signing_eku_oid))) {
    throw 'Updated executable signer is missing the Code Signing EKU.'
}

$timestampCertificate = $authenticode.TimeStamperCertificate
$timestampPresent = $null -ne $timestampCertificate
$timestampSha256 = ''
$timestampEku = $false
if ($timestampPresent) {
    $timestampSha256 = Get-ByteSha256 -Bytes $timestampCertificate.RawData
    $timestampEku = Test-CertificateEku -Certificate $timestampCertificate -RequiredOid ([string]$executablePolicy.timestamp_eku_oid)
}
if ([bool]$executablePolicy.require_trusted_timestamp -and -not $timestampPresent) {
    throw 'Updated executable is missing a trusted Authenticode timestamp.'
}
if ([bool]$executablePolicy.require_trusted_timestamp -and -not $timestampEku) {
    throw 'Updated executable timestamp certificate is missing the Time Stamping EKU.'
}

[ordered]@{
    schema_version = 1
    valid = $true
    reference_only = $false
    manifest_signature_present = $true
    manifest_signer_certificate_sha256 = $manifestSignerSha256
    publisher_signature_present = $true
    publisher_certificate_sha256 = $publisherSha256
    trusted_timestamp_present = $timestampPresent
    timestamp_certificate_sha256 = $timestampSha256
    timestamp_eku = $timestampEku
} | ConvertTo-Json -Depth 6
