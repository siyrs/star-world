param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$build = [System.IO.Path]::GetFullPath($BuildDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$output = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$packageName = 'StarWorld-Windows-x86_64.zip'
$checksumName = 'StarWorld-Windows-x86_64.zip.sha256'
$manifestName = 'update-manifest.json'
$requiredNames = @('StarWorld.exe', 'StarWorld.pck')
$buildPrefix = $build + [System.IO.Path]::DirectorySeparatorChar

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Release version must be stable semantic version, got: $Version"
}
if ($output.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must not be nested inside BuildDirectory.'
}
foreach ($name in $requiredNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $build $name) -PathType Leaf)) {
        throw "Required release file is missing: $name"
    }
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
$manifestPath = Join-Path $build $manifestName
if (Test-Path -LiteralPath $manifestPath) { Remove-Item -Force -LiteralPath $manifestPath }

$releaseFiles = @(Get-ChildItem -LiteralPath $build -File -Recurse | Sort-Object FullName)
if ($releaseFiles.Count -lt 2 -or $releaseFiles.Count -gt 64) {
    throw "Release payload file count must be between 2 and 64, got $($releaseFiles.Count)"
}
$files = @()
foreach ($item in $releaseFiles) {
    $fullPath = [System.IO.Path]::GetFullPath($item.FullName)
    if (-not $fullPath.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release file escapes BuildDirectory: $fullPath"
    }
    $relative = $fullPath.Substring($buildPrefix.Length).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('../') -or $relative.Contains(':')) {
        throw "Unsafe release relative path: $relative"
    }
    $files += [ordered]@{
        path = $relative
        size = [long]$item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath).Hash.ToLowerInvariant()
    }
}

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

$packagePath = Join-Path $output $packageName
$checksumPath = Join-Path $output $checksumName
if (Test-Path -LiteralPath $packagePath) { Remove-Item -Force -LiteralPath $packagePath }
if (Test-Path -LiteralPath $checksumPath) { Remove-Item -Force -LiteralPath $checksumPath }
Compress-Archive -Path (Join-Path $build '*') -DestinationPath $packagePath -CompressionLevel Optimal
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash.ToLowerInvariant()
"$packageHash  $packageName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

Write-Host "UPDATE_PACKAGE=$packagePath"
Write-Host "UPDATE_CHECKSUM=$checksumPath"
Write-Host "UPDATE_SHA256=$packageHash"
