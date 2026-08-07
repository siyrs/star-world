param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$RequirePublisherSignature
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$build = [System.IO.Path]::GetFullPath($BuildDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$output = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$packageName = 'StarWorld-Windows-x86_64.zip'
$checksumName = 'StarWorld-Windows-x86_64.zip.sha256'
$manifestName = 'update-manifest.json'
$signatureName = 'update-manifest.p7s'
$requiredNames = @('StarWorld.exe', 'StarWorld.pck')
$buildPrefix = $build + [System.IO.Path]::DirectorySeparatorChar

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Release version must be stable semantic version, got: $Version" }
if (-not (Test-Path -LiteralPath $build -PathType Container)) { throw "BuildDirectory does not exist: $build" }
if ($output.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory must not be nested inside BuildDirectory.' }
foreach ($name in $requiredNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $build $name) -PathType Leaf)) { throw "Required release file is missing: $name" }
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
$manifestPath = Join-Path $build $manifestName
$signaturePath = Join-Path $build $signatureName

if (-not $RequirePublisherSignature) {
    Remove-Item -Force -LiteralPath $manifestPath -ErrorAction SilentlyContinue
    Remove-Item -Force -LiteralPath $signaturePath -ErrorAction SilentlyContinue
}

$payloadFiles = @(Get-ChildItem -LiteralPath $build -File -Recurse -Force | Where-Object {
    $_.FullName -ne $manifestPath -and $_.FullName -ne $signaturePath
} | Sort-Object FullName)
if ($payloadFiles.Count -lt 2 -or $payloadFiles.Count -gt 64) { throw "Release payload file count must be between 2 and 64, got $($payloadFiles.Count)" }

$actualFiles = [ordered]@{}
foreach ($item in $payloadFiles) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Release payload cannot contain a reparse point: $($item.FullName)" }
    if (($item.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) { throw "Release payload cannot contain a hidden file: $($item.FullName)" }
    $fullPath = [System.IO.Path]::GetFullPath($item.FullName)
    if (-not $fullPath.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Release file escapes BuildDirectory: $fullPath" }
    $relative = $fullPath.Substring($buildPrefix.Length).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains(':') -or $relative.Split('/') -contains '..') { throw "Unsafe release relative path: $relative" }
    $key = $relative.ToLowerInvariant()
    if ($actualFiles.Contains($key)) { throw "Duplicate release path: $relative" }
    $actualFiles[$key] = [ordered]@{
        path = $relative
        size = [long]$item.Length
        sha256 = Get-Sha256 $fullPath
    }
}

if ($RequirePublisherSignature) {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Publisher-signed update manifest is missing.' }
    if (-not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) { throw 'Detached publisher manifest signature is missing.' }
    if ((Get-Item -LiteralPath $signaturePath).Length -le 0 -or (Get-Item -LiteralPath $signaturePath).Length -gt 1048576) { throw 'Detached publisher manifest signature size is invalid.' }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    if ([int]$manifest.schema_version -ne 2 -or [int]$manifest.updater_protocol -ne 2) { throw 'Publisher-signed update manifest must use schema/protocol 2.' }
    if ([string]$manifest.version -ne $Version) { throw 'Publisher-signed update manifest version mismatch.' }
    if ([string]$manifest.platform -ne 'windows-x86_64' -or [string]$manifest.executable -ne 'StarWorld.exe') { throw 'Publisher-signed update manifest platform/executable mismatch.' }
    if ($null -eq $manifest.signature -or [string]$manifest.signature.format -ne 'cms-detached' -or [string]$manifest.signature.digest -ne 'sha256' -or [string]$manifest.signature.path -ne $signatureName) {
        throw 'Publisher-signed update manifest signature declaration is invalid.'
    }
    $manifestFiles = @{}
    foreach ($file in @($manifest.files)) {
        $relative = ([string]$file.path).Replace('\', '/').Trim()
        $key = $relative.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -in @($manifestName, $signatureName) -or $manifestFiles.ContainsKey($key)) { throw "Signed manifest path is invalid or duplicated: $relative" }
        $manifestFiles[$key] = $file
        if (-not $actualFiles.Contains($key)) { throw "Signed manifest references a missing payload file: $relative" }
        $actual = $actualFiles[$key]
        if ([long]$file.size -ne [long]$actual.size) { throw "Signed manifest size mismatch: $relative" }
        if (([string]$file.sha256).ToLowerInvariant() -ne [string]$actual.sha256) { throw "Signed manifest SHA-256 mismatch: $relative" }
    }
    if ($manifestFiles.Count -ne $actualFiles.Count) { throw 'Signed manifest does not cover the exact release payload.' }
    foreach ($key in $actualFiles.Keys) { if (-not $manifestFiles.ContainsKey($key)) { throw "Signed manifest omits payload file: $($actualFiles[$key].path)" } }
} else {
    $files = @($actualFiles.Values)
    $manifest = [ordered]@{
        schema_version = 1
        updater_protocol = 1
        version = $Version
        platform = 'windows-x86_64'
        executable = 'StarWorld.exe'
        generated_at_utc = [DateTime]::UtcNow.ToString('o')
        files = $files
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

$packagePath = Join-Path $output $packageName
$checksumPath = Join-Path $output $checksumName
Remove-Item -Force -LiteralPath $packagePath -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $checksumPath -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $build '*') -DestinationPath $packagePath -CompressionLevel Optimal
$packageHash = Get-Sha256 $packagePath
"$packageHash  $packageName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

Write-Host "UPDATE_PACKAGE=$packagePath"
Write-Host "UPDATE_CHECKSUM=$checksumPath"
Write-Host "UPDATE_SHA256=$packageHash"
Write-Host "UPDATE_PUBLISHER_SIGNED=$([bool]$RequirePublisherSignature)"
