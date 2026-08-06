param(
    [Parameter(Mandatory = $true)][string]$PromotionBundleDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedPinId,
    [Parameter(Mandatory = $true)][string]$ReceiverId,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$receiver = $ReceiverId.Trim()
if ([string]::IsNullOrWhiteSpace($receiver)) { throw 'ReceiverId must not be blank.' }
if ($receiver.Length -gt 128) { throw 'ReceiverId is too long.' }
$bundleRoot = [System.IO.Path]::GetFullPath($PromotionBundleDirectory)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw "Promotion bundle not found: $bundleRoot" }
$bundlePrefix = $bundleRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputFullPath.StartsWith($bundlePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Promotion receipt must be written outside the immutable promotion bundle.' }
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

$validator = Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1'
if ($RequireReleaseGate) {
    $resultText = (& $validator -PromotionBundleDirectory $bundleRoot -ExpectedPinId $ExpectedPinId -RequireReleaseGate | Out-String).Trim()
} else {
    $resultText = (& $validator -PromotionBundleDirectory $bundleRoot -ExpectedPinId $ExpectedPinId | Out-String).Trim()
}
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.valid -or -not [bool]$result.identity_pinned -or -not [bool]$result.offline_contract_validation) { throw 'Promotion bundle did not satisfy the receipt validation contract.' }
$validatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$manifestPath = Join-Path $bundleRoot 'promotion-manifest.json'
$validatorHash = Get-Sha256 $validator
$pinValidatorHash = Get-Sha256 (Join-Path $PSScriptRoot 'validate_release_promotion_pin.ps1')
$chainValidatorHash = Get-Sha256 (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1')
$manifestHash = Get-Sha256 $manifestPath
$canonical = @(
    'star-world-release-promotion-receipt-v1',
    "promotion_id=$($result.promotion_id)",
    "pin_id=$($result.pin_id)",
    "candidate_id=$($result.candidate_id)",
    "bundle_id=$($result.chain_bundle_id)",
    "receiver=$receiver",
    "validated_at=$validatedAt",
    "manifest_sha256=$manifestHash",
    "validator_sha256=$validatorHash"
) -join "`n"
$receiptId = Get-StringSha256 -Value $canonical
$receipt = [ordered]@{
    schema_version = 1
    receipt_id = $receiptId
    validated_at_unix = $validatedAt
    receiver_id = $receiver
    promotion_id = [string]$result.promotion_id
    pin_id = [string]$result.pin_id
    candidate_id = [string]$result.candidate_id
    chain_bundle_id = [string]$result.chain_bundle_id
    package_id = [string]$result.package_id
    expected_pin_id = $ExpectedPinId
    offline_contract_validation = [bool]$result.offline_contract_validation
    release_gate_passed = [bool]$result.release_gate_passed
    promotion_manifest_sha256 = $manifestHash
    validators = [ordered]@{
        promotion_bundle_sha256 = $validatorHash
        promotion_pin_sha256 = $pinValidatorHash
        chain_bundle_sha256 = $chainValidatorHash
    }
    result = 'pass'
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$tempPath = "$outputFullPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $outputFullPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}
Write-Host "RELEASE PROMOTION RECEIPT PASS | receipt=$receiptId | promotion=$($result.promotion_id) | pin=$($result.pin_id) | receiver=$receiver | gate=$([bool]$result.release_gate_passed) | output=$outputFullPath"
