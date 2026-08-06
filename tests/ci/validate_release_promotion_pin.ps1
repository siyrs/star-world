param(
    [Parameter(Mandatory = $true)][string]$PinPath,
    [string]$ExpectedPinId = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$pinFullPath = [System.IO.Path]::GetFullPath($PinPath)
if (-not (Test-Path -LiteralPath $pinFullPath -PathType Leaf)) { throw "Promotion pin not found: $pinFullPath" }
function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Assert-Hex {
    param([string]$Value, [int]$Length, [string]$Label)
    if ($Value -cnotmatch "^[0-9a-f]{$Length}$") { throw "$Label must be a lowercase $Length-character hexadecimal value." }
}

$pin = Get-Content -LiteralPath $pinFullPath -Raw | ConvertFrom-Json -Depth 30
if ([int]$pin.schema_version -ne 1) { throw 'Promotion pin schema_version must equal 1.' }
Assert-Hex ([string]$pin.pin_id) 64 'pin_id'
Assert-Hex ([string]$pin.candidate_id) 64 'candidate_id'
Assert-Hex ([string]$pin.bundle_id) 64 'bundle_id'
Assert-Hex ([string]$pin.commit_sha) 40 'commit_sha'
Assert-Hex ([string]$pin.executable_sha256) 64 'executable_sha256'
Assert-Hex ([string]$pin.pck_sha256) 64 'pck_sha256'
if ([long]$pin.created_at_unix -le 0) { throw 'Promotion pin created_at_unix must be positive.' }
$channel = ([string]$pin.release_channel).Trim()
$owner = ([string]$pin.release_owner_id).Trim()
if ($channel -cnotmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { throw 'release_channel contains unsupported characters.' }
if ([string]::IsNullOrWhiteSpace($owner) -or $owner.Length -gt 128) { throw 'release_owner_id must contain 1-128 characters.' }
foreach ($pair in @(
    @{ Label = 'package_id'; Value = [string]$pin.package_id },
    @{ Label = 'version'; Value = [string]$pin.version }
)) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) { throw "$($pair.Label) must not be blank." }
}
$canonical = @(
    'star-world-release-promotion-pin-v1',
    "candidate_id=$($pin.candidate_id)",
    "bundle_id=$($pin.bundle_id)",
    "package_id=$($pin.package_id)",
    "commit=$($pin.commit_sha)",
    "version=$($pin.version)",
    "exe_sha256=$($pin.executable_sha256)",
    "pck_sha256=$($pin.pck_sha256)",
    "channel=$channel",
    "owner=$owner"
) -join "`n"
$expected = Get-StringSha256 -Value $canonical
if ([string]$pin.pin_id -ne $expected) { throw "pin_id does not match the promotion identity: expected $expected" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedPinId)) {
    Assert-Hex $ExpectedPinId 64 'ExpectedPinId'
    if ([string]$pin.pin_id -ne $ExpectedPinId) { throw "Expected promotion pin mismatch: expected $ExpectedPinId, got $($pin.pin_id)" }
}
[ordered]@{
    schema_version = 1
    valid = $true
    pin_id = [string]$pin.pin_id
    candidate_id = [string]$pin.candidate_id
    bundle_id = [string]$pin.bundle_id
    commit_sha = [string]$pin.commit_sha
    version = [string]$pin.version
} | ConvertTo-Json -Depth 5
