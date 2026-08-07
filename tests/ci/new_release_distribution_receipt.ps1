param(
    [Parameter(Mandatory = $true)][string]$PromotionBundleDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedPinId,
    [string]$ExpectedPublisherCertificateSha256 = '',
    [Parameter(Mandatory = $true)][string]$ReceiverId,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$promotionRoot = [System.IO.Path]::GetFullPath($PromotionBundleDirectory)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$receiver = $ReceiverId.Trim()
if ([string]::IsNullOrWhiteSpace($receiver)) { throw 'ReceiverId must not be blank.' }
if ($receiver.Length -gt 128) { throw 'ReceiverId is too long.' }
if (-not (Test-Path -LiteralPath $promotionRoot -PathType Container)) { throw "Promotion bundle directory not found: $promotionRoot" }
$prefix = $promotionRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputFullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $outputFullPath -eq $promotionRoot) {
    throw 'Distribution receipt must be written outside the immutable promotion bundle.'
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

$gateValidator = Join-Path $PSScriptRoot 'validate_release_distribution_gate.ps1'
$signatureValidator = Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1'
$promotionValidator = Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1'
foreach ($validator in @($gateValidator, $signatureValidator, $promotionValidator)) {
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw "Distribution receipt validator is missing: $validator" }
}

$gateArgs = @{
    PromotionBundleDirectory = $promotionRoot
    ExpectedPinId = $ExpectedPinId
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPublisherCertificateSha256)) {
    $gateArgs.ExpectedPublisherCertificateSha256 = $ExpectedPublisherCertificateSha256
}
if ($RequireReleaseGate) { $gateArgs.RequireReleaseGate = $true }
$gateText = (& $gateValidator @gateArgs | Out-String).Trim()
$gate = $gateText | ConvertFrom-Json
if (-not [bool]$gate.valid) { throw 'Distribution gate must validate before writing a receipt.' }

$validatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$promotionManifestPath = Join-Path $promotionRoot 'promotion-manifest.json'
$canonical = @(
    'star-world-release-distribution-receipt-v1',
    "validated_at=$validatedAt",
    "receiver=$receiver",
    "promotion_id=$($gate.promotion_id)",
    "pin_id=$($gate.pin_id)",
    "candidate_id=$($gate.candidate_id)",
    "publisher_certificate_sha256=$($gate.publisher_certificate_sha256)",
    "timestamp_certificate_sha256=$($gate.timestamp_certificate_sha256)",
    "release_gate_passed=$([bool]$gate.release_gate_passed)",
    "promotion_manifest_sha256=$(Get-Sha256 $promotionManifestPath)",
    "distribution_validator_sha256=$(Get-Sha256 $gateValidator)",
    "signature_validator_sha256=$(Get-Sha256 $signatureValidator)",
    "promotion_validator_sha256=$(Get-Sha256 $promotionValidator)"
) -join "`n"
$receiptId = Get-StringSha256 $canonical

$receipt = [ordered]@{
    schema_version = 1
    receipt_id = $receiptId
    validated_at_unix = $validatedAt
    receiver_id = $receiver
    result = 'pass'
    promotion_id = [string]$gate.promotion_id
    pin_id = [string]$gate.pin_id
    candidate_id = [string]$gate.candidate_id
    chain_bundle_id = [string]$gate.chain_bundle_id
    package_id = [string]$gate.package_id
    executable_sha256 = [string]$gate.executable_sha256
    signature_present = [bool]$gate.signature_present
    signature_status = [string]$gate.signature_status
    publisher_certificate_sha256 = [string]$gate.publisher_certificate_sha256
    publisher_matches_external_pin = [bool]$gate.publisher_matches_external_pin
    trusted_timestamp_present = [bool]$gate.trusted_timestamp_present
    timestamp_certificate_sha256 = [string]$gate.timestamp_certificate_sha256
    sign_before_qualification_proven = [bool]$gate.sign_before_qualification_proven
    release_gate_passed = [bool]$gate.release_gate_passed
    promotion_manifest_sha256 = Get-Sha256 $promotionManifestPath
    validators = [ordered]@{
        distribution_gate_sha256 = Get-Sha256 $gateValidator
        publisher_signature_sha256 = Get-Sha256 $signatureValidator
        promotion_bundle_sha256 = Get-Sha256 $promotionValidator
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$tempPath = "$outputFullPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $outputFullPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}
Write-Host "RELEASE DISTRIBUTION RECEIPT PASS | receipt=$receiptId | promotion=$($gate.promotion_id) | pin=$($gate.pin_id) | signature=$($gate.signature_status) | release_gate=$([bool]$gate.release_gate_passed) | output=$outputFullPath"
