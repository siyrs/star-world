param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ManifestSigningCertificateThumbprint,
    [Parameter(Mandatory = $true)][string]$ExpectedManifestSignerCertificateSha256,
    [Parameter(Mandatory = $true)][string]$ExpectedPublisherCertificateSha256,
    [string]$Repository = 'siyrs/star-world',
    [string]$Tag = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) { throw 'Signed Windows update publication requires Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Signed Windows update publication requires PowerShell 7 or later.' }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must be stable semantic version: $Version" }
if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = "v$Version" }
if ($Tag -ne "v$Version") { throw "Tag/version mismatch: tag=$Tag version=$Version" }
if ($ExpectedManifestSignerCertificateSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'ExpectedManifestSignerCertificateSha256 must be 64 hex characters.' }
if ($ExpectedPublisherCertificateSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'ExpectedPublisherCertificateSha256 must be 64 hex characters.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build = [System.IO.Path]::GetFullPath($BuildDirectory)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $root 'build\signed-release-assets' }
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$exe = Join-Path $build 'StarWorld.exe'
$pck = Join-Path $build 'StarWorld.pck'
$manifest = Join-Path $build 'update-manifest.json'
$signature = Join-Path $build 'update-manifest.p7s'
foreach ($path in @($exe, $pck)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Signed release input is missing: $path" } }

$versionText = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\update\app_version.gd')
if ($versionText -notmatch 'CURRENT_VERSION\s*:=\s*"([0-9]+\.[0-9]+\.[0-9]+)"' -or $Matches[1] -ne $Version) {
    throw 'AppVersion.CURRENT_VERSION must match the publication version.'
}

$git = Get-Command git -ErrorAction Stop
$head = (& $git.Source -C $root rev-parse HEAD).Trim()
$tagCommit = (& $git.Source -C $root rev-parse "$Tag^{commit}" 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tagCommit)) { throw "Release tag does not exist locally: $Tag" }
if ($head -ne $tagCommit) { throw "Publication checkout must be exactly the release tag commit: HEAD=$head tag=$tagCommit" }

Write-Host 'SIGNED UPDATE PHASE | verify-authenticode'
$publisherValidator = Join-Path $root 'tests\ci\validate_windows_publisher_signature.ps1'
& $publisherValidator `
    -FilePath $exe `
    -ExpectedPublisherCertificateSha256 $ExpectedPublisherCertificateSha256 `
    -RequireSignature `
    -RequireTrustedTimestamp | Out-Null

Write-Host 'SIGNED UPDATE PHASE | generate-manifest'
& (Join-Path $root 'tools\new_update_manifest.ps1') -BuildDirectory $build -Version $Version -OutputPath $manifest

Write-Host 'SIGNED UPDATE PHASE | sign-manifest'
& (Join-Path $root 'tools\sign_update_manifest.ps1') `
    -ManifestPath $manifest `
    -OutputPath $signature `
    -CertificateThumbprint $ManifestSigningCertificateThumbprint `
    -ExpectedCertificateSha256 $ExpectedManifestSignerCertificateSha256

Write-Host 'SIGNED UPDATE PHASE | verify-combined-trust'
$policy = [ordered]@{
    schema_version = 1
    max_active_pins = 4
    manifest_signature = [ordered]@{
        required_for_release = $true
        format = 'cms-detached'
        digest = 'sha256'
        code_signing_eku_oid = '1.3.6.1.5.5.7.3.3'
        trusted_signer_certificate_sha256 = @($ExpectedManifestSignerCertificateSha256.ToLowerInvariant())
    }
    executable_authenticode = [ordered]@{
        required_for_release = $true
        require_trusted_timestamp = $true
        code_signing_eku_oid = '1.3.6.1.5.5.7.3.3'
        timestamp_eku_oid = '1.3.6.1.5.5.7.3.8'
        trusted_publisher_certificate_sha256 = @($ExpectedPublisherCertificateSha256.ToLowerInvariant())
    }
}
$policyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($policy | ConvertTo-Json -Depth 8 -Compress)))
$trustText = (& (Join-Path $root 'src\update\windows_update_trust_validator.ps1') `
    -ManifestPath $manifest `
    -SignaturePath $signature `
    -ExecutablePath $exe `
    -TrustPolicyBase64 $policyBase64 | Out-String).Trim()
$trust = $trustText | ConvertFrom-Json
if (-not [bool]$trust.valid -or [bool]$trust.reference_only) { throw 'Combined updater publisher trust verification failed.' }

Write-Host 'SIGNED UPDATE PHASE | package'
& (Join-Path $root 'tools\build_update_release.ps1') `
    -BuildDirectory $build `
    -Version $Version `
    -OutputDirectory $output `
    -RequirePublisherSignature

$package = Join-Path $output 'StarWorld-Windows-x86_64.zip'
$checksum = Join-Path $output 'StarWorld-Windows-x86_64.zip.sha256'
foreach ($path in @($package, $checksum)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Signed release output missing: $path" } }

Write-Host 'SIGNED UPDATE PHASE | publish-github-release'
$gh = Get-Command gh -ErrorAction Stop
& $gh.Source auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated.' }
& $gh.Source release view $Tag --repo $Repository *> $null
if ($LASTEXITCODE -eq 0) {
    & $gh.Source release upload $Tag $package $checksum --clobber --repo $Repository
} else {
    & $gh.Source release create $Tag $package $checksum --generate-notes --title "星的世界 $Tag" --repo $Repository
}
if ($LASTEXITCODE -ne 0) { throw 'GitHub Release publication failed.' }

Write-Host "SIGNED_UPDATE_RELEASE_PUBLISHED | repo=$Repository | tag=$Tag | manifest_signer=$($ExpectedManifestSignerCertificateSha256.ToLowerInvariant()) | publisher=$($ExpectedPublisherCertificateSha256.ToLowerInvariant())"
