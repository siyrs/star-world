param(
    [Parameter(Mandatory = $true)][string]$PromotionBundleDirectory,
    [string]$ExpectedPinId = '',
    [string]$ExpectedPublisherCertificateSha256 = '',
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
if (-not $IsWindows) { throw 'Release distribution validation requires Windows because Authenticode is a Windows trust contract.' }

$promotionRoot = [System.IO.Path]::GetFullPath($PromotionBundleDirectory)
if (-not (Test-Path -LiteralPath $promotionRoot -PathType Container)) { throw "Promotion bundle directory not found: $promotionRoot" }
if ($RequireReleaseGate -and [string]::IsNullOrWhiteSpace($ExpectedPinId)) { throw '-RequireReleaseGate requires an externally retained -ExpectedPinId.' }
if ($RequireReleaseGate -and [string]::IsNullOrWhiteSpace($ExpectedPublisherCertificateSha256)) {
    throw '-RequireReleaseGate requires an externally retained -ExpectedPublisherCertificateSha256.'
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-Field {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}
function Assert-PolicyFlag {
    param([object]$SigningPolicy, [string]$Name)
    if (-not [bool](Get-Field $SigningPolicy $Name $false)) { throw "Release qualification signing policy requires $Name=true." }
}

$promotionValidator = Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1'
$promotionArgs = @{
    PromotionBundleDirectory = $promotionRoot
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPinId)) { $promotionArgs.ExpectedPinId = $ExpectedPinId }
if ($RequireReleaseGate) { $promotionArgs.RequireReleaseGate = $true }
$promotionText = (& $promotionValidator @promotionArgs | Out-String).Trim()
$promotion = $promotionText | ConvertFrom-Json
if (-not [bool]$promotion.valid) { throw 'Promotion bundle must validate before distribution validation.' }

$candidatePath = Join-Path $promotionRoot 'candidate-chain\release-candidate.json'
$exePath = Join-Path $promotionRoot 'candidate-chain\binary\StarWorld.exe'
$policyPath = Join-Path $promotionRoot 'contracts\data\release_qualification.json'
foreach ($path in @($candidatePath, $exePath, $policyPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Distribution validation input is missing: $path" }
}
$candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json -Depth 40
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json -Depth 30
$signingPolicy = Get-Field $policy 'publisher_signing' $null

if ($RequireReleaseGate) {
    if ($null -eq $signingPolicy) { throw 'Release qualification policy is missing publisher_signing.' }
    Assert-PolicyFlag $signingPolicy 'required_for_commercial'
    Assert-PolicyFlag $signingPolicy 'sign_before_qualification'
    Assert-PolicyFlag $signingPolicy 'authenticode_required'
    Assert-PolicyFlag $signingPolicy 'trusted_timestamp_required'
    Assert-PolicyFlag $signingPolicy 'publisher_certificate_sha256_external'
}

$actualExeHash = Get-Sha256 $exePath
$candidateExeHash = ([string]$candidate.build.executable.sha256).ToLowerInvariant()
if ($actualExeHash -ne $candidateExeHash) {
    throw "Distribution executable no longer matches the qualified candidate: expected $candidateExeHash, got $actualExeHash"
}

$signatureValidator = Join-Path $PSScriptRoot 'validate_windows_publisher_signature.ps1'
$signatureArgs = @{ FilePath = $exePath }
if (-not [string]::IsNullOrWhiteSpace($ExpectedPublisherCertificateSha256)) {
    $signatureArgs.ExpectedPublisherCertificateSha256 = $ExpectedPublisherCertificateSha256
    $signatureArgs.RequireSignature = $true
}
if ($RequireReleaseGate) {
    $signatureArgs.RequireSignature = $true
    $signatureArgs.RequireTrustedTimestamp = $true
}
$signatureText = (& $signatureValidator @signatureArgs | Out-String).Trim()
$signature = $signatureText | ConvertFrom-Json

$publisherMatchesExternalPin = -not [string]::IsNullOrWhiteSpace($ExpectedPublisherCertificateSha256) -and 
    [bool]$signature.signature_present -and 
    ([string]$signature.signer.certificate_sha256 -eq $ExpectedPublisherCertificateSha256.Trim().ToLowerInvariant())
$releaseGatePassed = [bool]$promotion.release_gate_passed -and 
    [bool]$signature.signature_present -and 
    [bool]$signature.trusted -and 
    [bool]$signature.timestamp.present -and 
    [bool]$signature.timestamp.timestamp_eku -and 
    $publisherMatchesExternalPin

if ($RequireReleaseGate -and -not $releaseGatePassed) {
    throw 'Distribution release gate did not pass publisher identity, Authenticode trust, trusted timestamp and promotion requirements.'
}

[ordered]@{
    schema_version = 1
    valid = $true
    promotion_id = [string]$promotion.promotion_id
    pin_id = [string]$promotion.pin_id
    candidate_id = [string]$promotion.candidate_id
    chain_bundle_id = [string]$promotion.chain_bundle_id
    package_id = [string]$promotion.package_id
    executable_sha256 = $actualExeHash
    signature_present = [bool]$signature.signature_present
    signature_status = [string]$signature.signature_status
    publisher_certificate_sha256 = if ([bool]$signature.signature_present) { [string]$signature.signer.certificate_sha256 } else { '' }
    publisher_matches_external_pin = $publisherMatchesExternalPin
    trusted_timestamp_present = [bool]$signature.timestamp.present
    timestamp_certificate_sha256 = [string]$signature.timestamp.certificate_sha256
    sign_before_qualification_proven = [bool]$signature.signature_present -and ($actualExeHash -eq $candidateExeHash)
    release_gate_passed = $releaseGatePassed
} | ConvertTo-Json -Depth 8
