param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$build = [System.IO.Path]::GetFullPath($BuildDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Release version must be stable semantic version, got: $Version" }
if (-not (Test-Path -LiteralPath $build -PathType Container)) { throw "Build directory is missing: $build" }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $build 'update-manifest.json' }
$output = [System.IO.Path]::GetFullPath($OutputPath)
$signaturePath = Join-Path (Split-Path -Parent $output) 'update-manifest.p7s'
$buildPrefix = $build + [System.IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Update manifest must be written inside BuildDirectory.'
}
foreach ($required in @('StarWorld.exe', 'StarWorld.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $build $required) -PathType Leaf)) { throw "Required release file is missing: $required" }
}

Remove-Item -Force -LiteralPath $output -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $signaturePath -ErrorAction SilentlyContinue
$payloadFiles = @(Get-ChildItem -LiteralPath $build -File -Recurse -Force | Where-Object {
    $_.FullName -ne $output -and $_.FullName -ne $signaturePath
} | Sort-Object FullName)
if ($payloadFiles.Count -lt 2 -or $payloadFiles.Count -gt 64) { throw "Release payload file count must be between 2 and 64, got $($payloadFiles.Count)" }

$files = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($item in $payloadFiles) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Release payload cannot contain a reparse point: $($item.FullName)" }
    $full = [System.IO.Path]::GetFullPath($item.FullName)
    if (-not $full.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Release file escapes BuildDirectory: $full" }
    $relative = $full.Substring($buildPrefix.Length).Replace('\', '/')
    $key = $relative.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains(':') -or $relative.Split('/') -contains '..') { throw "Unsafe release relative path: $relative" }
    if ($seen.ContainsKey($key)) { throw "Duplicate release relative path: $relative" }
    $seen[$key] = $true
    $files.Add([ordered]@{
        path = $relative
        size = [long]$item.Length
        sha256 = Get-Sha256 $full
    })
}

$manifest = [ordered]@{
    schema_version = 2
    updater_protocol = 2
    version = $Version
    platform = 'windows-x86_64'
    executable = 'StarWorld.exe'
    signature = [ordered]@{
        format = 'cms-detached'
        digest = 'sha256'
        path = 'update-manifest.p7s'
    }
    files = @($files)
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $output -Encoding utf8
Write-Host "UPDATE_MANIFEST=$output"
Write-Host "UPDATE_MANIFEST_SHA256=$(Get-Sha256 $output)"
Write-Host "UPDATE_PAYLOAD_FILES=$($payloadFiles.Count)"
