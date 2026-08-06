param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$ChainBundleDirectory,
    [Parameter(Mandatory = $true)][string]$ReleaseOwnerId,
    [string]$ReleaseChannel = 'commercial',
    [string]$OutputPath = 'build/external-qualification/release-promotion-pin.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$owner = $ReleaseOwnerId.Trim()
$channel = $ReleaseChannel.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($owner)) { throw 'ReleaseOwnerId must not be blank.' }
if ($owner.Length -gt 128) { throw 'ReleaseOwnerId is too long.' }
if ($channel -cnotmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { throw 'ReleaseChannel contains unsupported characters.' }

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $Path))
}
function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

$chainRoot = Resolve-ProjectPath $ChainBundleDirectory
$outputFullPath = Resolve-ProjectPath $OutputPath
if (-not (Test-Path -LiteralPath $chainRoot -PathType Container)) { throw "Chain bundle directory not found: $chainRoot" }
$chainValidator = Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1'
$chainResultText = (& $chainValidator -ProjectRoot $projectFullPath -BundleDirectory $chainRoot | Out-String).Trim()
$chainResult = $chainResultText | ConvertFrom-Json
if (-not [bool]$chainResult.valid) { throw 'Chain bundle must validate before a promotion pin can be created.' }

$candidate = Get-Content -LiteralPath (Join-Path $chainRoot 'release-candidate.json') -Raw | ConvertFrom-Json -Depth 30
$bundleManifest = Get-Content -LiteralPath (Join-Path $chainRoot 'bundle-manifest.json') -Raw | ConvertFrom-Json -Depth 50
$package = Get-Content -LiteralPath (Join-Path $chainRoot 'qualification-package.json') -Raw | ConvertFrom-Json -Depth 100
$canonical = @(
    'star-world-release-promotion-pin-v1',
    "candidate_id=$($candidate.candidate_id)",
    "bundle_id=$($bundleManifest.bundle_id)",
    "package_id=$($package.package_id)",
    "commit=$($candidate.build.commit_sha)",
    "version=$($candidate.build.version)",
    "exe_sha256=$($candidate.build.executable.sha256)",
    "pck_sha256=$($candidate.build.pck.sha256)",
    "channel=$channel",
    "owner=$owner"
) -join "`n"
$pinId = Get-StringSha256 -Value $canonical
$pin = [ordered]@{
    schema_version = 1
    pin_id = $pinId
    created_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    release_channel = $channel
    release_owner_id = $owner
    candidate_id = [string]$candidate.candidate_id
    bundle_id = [string]$bundleManifest.bundle_id
    package_id = [string]$package.package_id
    commit_sha = [string]$candidate.build.commit_sha
    version = [string]$candidate.build.version
    executable_sha256 = [string]$candidate.build.executable.sha256
    pck_sha256 = [string]$candidate.build.pck.sha256
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$tempPath = "$outputFullPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $pin | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $outputFullPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}
& (Join-Path $PSScriptRoot 'validate_release_promotion_pin.ps1') -PinPath $outputFullPath -ExpectedPinId $pinId | Out-Null
Write-Host "RELEASE PROMOTION PIN PASS | pin=$pinId | candidate=$($candidate.candidate_id) | bundle=$($bundleManifest.bundle_id) | channel=$channel | owner=$owner | output=$outputFullPath"
