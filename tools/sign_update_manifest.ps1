param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$CertificateThumbprint,
    [string]$OutputPath = '',
    [string]$ExpectedCertificateSha256 = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) { throw 'Updater manifest signing requires Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Updater manifest signing requires PowerShell 7 or later.' }
try { Add-Type -AssemblyName System.Security.Cryptography.Pkcs -ErrorAction Stop } catch { }

function Get-CertificateSha256 {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Certificate.RawData))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Test-Eku {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$Oid)
    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) { if ([string]$usage.Value -eq $Oid) { return $true } }
        }
    }
    return $false
}

$manifest = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "Update manifest not found: $manifest" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Split-Path -Parent $manifest) 'update-manifest.p7s' }
$output = [System.IO.Path]::GetFullPath($OutputPath)
$thumbprint = $CertificateThumbprint.Replace(' ', '').Trim().ToUpperInvariant()
$certificatePath = "Cert:\CurrentUser\My\$thumbprint"
if (-not (Test-Path -LiteralPath $certificatePath)) { throw "Manifest signing certificate is not present in CurrentUser\\My: $thumbprint" }
$certificate = Get-Item -LiteralPath $certificatePath
if (-not $certificate.HasPrivateKey) { throw 'Manifest signing certificate does not expose a private key.' }
if (-not (Test-Eku -Certificate $certificate -Oid '1.3.6.1.5.5.7.3.3')) { throw 'Manifest signing certificate is missing the Code Signing EKU.' }
$certificateSha256 = Get-CertificateSha256 $certificate
if (-not [string]::IsNullOrWhiteSpace($ExpectedCertificateSha256) -and $certificateSha256 -ne $ExpectedCertificateSha256.Trim().ToLowerInvariant()) {
    throw "Manifest signing certificate SHA-256 mismatch: expected $($ExpectedCertificateSha256.Trim().ToLowerInvariant()), got $certificateSha256"
}

$manifestBytes = [System.IO.File]::ReadAllBytes($manifest)
$content = [System.Security.Cryptography.Pkcs.ContentInfo]::new($manifestBytes)
$cms = [System.Security.Cryptography.Pkcs.SignedCms]::new($content, $true)
$signer = [System.Security.Cryptography.Pkcs.CmsSigner]::new(
    [System.Security.Cryptography.Pkcs.SubjectIdentifierType]::IssuerAndSerialNumber,
    $certificate
)
$signer.IncludeOption = [System.Security.Cryptography.X509Certificates.X509IncludeOption]::EndCertOnly
$signer.DigestAlgorithm = [System.Security.Cryptography.Oid]::new('2.16.840.1.101.3.4.2.1')
$cms.ComputeSignature($signer)
[System.IO.File]::WriteAllBytes($output, $cms.Encode())

Write-Host "UPDATE_MANIFEST_SIGNATURE=$output"
Write-Host "UPDATE_MANIFEST_SIGNER_CERT_SHA256=$certificateSha256"
