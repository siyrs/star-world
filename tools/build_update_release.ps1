param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$build = [System.IO.Path]::GetFullPath($BuildDirectory)
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$packageName = 'StarWorld-Windows-x86_64.zip'
$requiredNames = @('StarWorld.exe', 'StarWorld.pck')

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Release version must be stable semantic version, got: $Version"
}
foreach ($name in $requiredNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $build $name) -PathType Leaf)) {
        throw "Required release file is missing: $name"
    }
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

$files = @()
foreach ($name in $requiredNames) {
    $path = Join-Path $build $name
    $item = Get-Item -LiteralPath $path
    $files += [ordered]@{
        path = $name
        size = [long]$item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
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
$manifestPath = Join-Path $build 'update-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$packagePath = Join-Path $output $packageName
if (Test-Path -LiteralPath $packagePath) { Remove-Item -Force -LiteralPath $packagePath }
Compress-Archive -Path (Join-Path $build '*') -DestinationPath $packagePath -CompressionLevel Optimal
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash.ToLowerInvariant()
$checksumPath = "$packagePath.sha256"
"$packageHash  $packageName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

Write-Host "UPDATE_PACKAGE=$packagePath"
Write-Host "UPDATE_CHECKSUM=$checksumPath"
Write-Host "UPDATE_SHA256=$packageHash"
