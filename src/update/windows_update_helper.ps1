param(
    [Parameter(Mandatory = $true)][int]$ParentProcessId,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$ExpectedPackageSha256,
    [Parameter(Mandatory = $true)][string]$InstallDirectory,
    [Parameter(Mandatory = $true)][string]$ExecutableName,
    [Parameter(Mandatory = $true)][string]$TargetVersion,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [string]$LaunchExecutable = '',
    [string]$LaunchArgumentsBase64 = '',
    [int]$WaitForExitSeconds = 120,
    [int]$AckTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-ResultFile {
    param([hashtable]$Payload)
    $directory = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $temporary = "$ResultPath.tmp"
    $Payload['timestamp_utc'] = [DateTime]::UtcNow.ToString('o')
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -Force -LiteralPath $temporary -Destination $ResultPath
}

function Get-Sha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Remove-Tree {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Expand-SafeArchive {
    param([string]$ArchivePath, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $target = [System.IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Archive entry escapes staging directory: $($entry.FullName)"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Read-LaunchArguments {
    if ([string]::IsNullOrWhiteSpace($LaunchArgumentsBase64)) { return @() }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($LaunchArgumentsBase64))
    $parsed = $json | ConvertFrom-Json
    $result = @()
    foreach ($value in @($parsed)) { $result += [string]$value }
    return $result
}

$installFull = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$parentDirectory = Split-Path -Parent $installFull
$transactionId = [Guid]::NewGuid().ToString('N')
$stagingDirectory = Join-Path $parentDirectory ".starworld-stage-$transactionId"
$backupDirectory = Join-Path $parentDirectory ".starworld-backup-$transactionId"
$ackPath = Join-Path (Split-Path -Parent $ResultPath) "update-ack-$transactionId.json"
$swapped = $false
$launchedProcess = $null

try {
    Write-ResultFile @{
        success = $false
        phase = 'waiting_for_exit'
        target_version = $TargetVersion
    }

    if ($ParentProcessId -gt 0) {
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(5, $WaitForExitSeconds))
        while ([DateTime]::UtcNow -lt $deadline) {
            $process = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
            if ($null -eq $process) { break }
            Start-Sleep -Milliseconds 200
        }
        if ($null -ne (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)) {
            throw 'Application did not exit before update timeout.'
        }
    }

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw 'Downloaded update package is missing.'
    }
    $actualPackageHash = Get-Sha256 $PackagePath
    if ($actualPackageHash -ne $ExpectedPackageSha256.ToLowerInvariant()) {
        throw 'Downloaded update package checksum does not match.'
    }

    Remove-Tree $stagingDirectory
    Expand-SafeArchive -ArchivePath $PackagePath -Destination $stagingDirectory
    $manifestPath = Join-Path $stagingDirectory 'update-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Update manifest is missing from package.'
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    if ([int]$manifest.schema_version -ne 1) { throw 'Unsupported update manifest schema.' }
    if ([string]$manifest.platform -ne 'windows-x86_64') { throw 'Update package platform mismatch.' }
    if ([string]$manifest.version -ne $TargetVersion) { throw 'Update package version mismatch.' }
    if ([string]$manifest.executable -ne $ExecutableName) { throw 'Update executable name mismatch.' }

    $stageRoot = [System.IO.Path]::GetFullPath($stagingDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $manifestPaths = @{}
    foreach ($file in @($manifest.files)) {
        $manifestRelative = ([string]$file.path).Replace('\', '/').Trim()
        $manifestKey = $manifestRelative.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($manifestRelative) -or $manifestPaths.ContainsKey($manifestKey)) {
            throw "Duplicate or empty manifest path: $manifestRelative"
        }
        $relative = $manifestRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $stagingDirectory $relative))
        if (-not $candidate.StartsWith($stageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest path escapes staging directory: $relative"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Manifest file is missing: $relative"
        }
        if ((Get-Item -LiteralPath $candidate).Length -ne [long]$file.size) {
            throw "Manifest file size mismatch: $relative"
        }
        if ((Get-Sha256 $candidate) -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Manifest file checksum mismatch: $relative"
        }
        $manifestPaths[$manifestKey] = $true
    }
    foreach ($stagedFile in @(Get-ChildItem -LiteralPath $stagingDirectory -File -Recurse)) {
        $fullStagedPath = [System.IO.Path]::GetFullPath($stagedFile.FullName)
        if (-not $fullStagedPath.StartsWith($stageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Staged file escapes staging directory: $fullStagedPath"
        }
        $stagedRelative = $fullStagedPath.Substring($stageRoot.Length).Replace('\', '/')
        if ($stagedRelative -eq 'update-manifest.json') { continue }
        if (-not $manifestPaths.ContainsKey($stagedRelative.ToLowerInvariant())) {
            throw "Archive contains an unlisted payload file: $stagedRelative"
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $stagingDirectory $ExecutableName) -PathType Leaf)) {
        throw 'Staged executable is missing.'
    }
    if (-not (Test-Path -LiteralPath $installFull -PathType Container)) {
        throw 'Install directory is missing.'
    }

    Write-ResultFile @{
        success = $false
        phase = 'switching'
        target_version = $TargetVersion
        staging_path = $stagingDirectory
        backup_path = $backupDirectory
    }

    Move-Item -LiteralPath $installFull -Destination $backupDirectory
    Move-Item -LiteralPath $stagingDirectory -Destination $installFull
    $swapped = $true

    $launchPath = if ([string]::IsNullOrWhiteSpace($LaunchExecutable)) {
        Join-Path $installFull $ExecutableName
    } else {
        $LaunchExecutable
    }
    $arguments = @(Read-LaunchArguments)
    $arguments += "--starworld-update-ack=$ackPath"
    $arguments += "--starworld-update-version=$TargetVersion"
    $launchedProcess = Start-Process -FilePath $launchPath -ArgumentList $arguments -WorkingDirectory $installFull -PassThru

    $ackDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(5, $AckTimeoutSeconds))
    $acknowledged = $false
    while ([DateTime]::UtcNow -lt $ackDeadline) {
        if (Test-Path -LiteralPath $ackPath -PathType Leaf) {
            $ack = Get-Content -Raw -Encoding UTF8 -LiteralPath $ackPath | ConvertFrom-Json
            if ([bool]$ack.ok -and [string]$ack.version -eq $TargetVersion) {
                $acknowledged = $true
                break
            }
            throw 'Updated application rejected the update acknowledgement.'
        }
        if ($launchedProcess.HasExited) {
            throw 'Updated application exited before acknowledging startup.'
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $acknowledged) {
        throw 'Updated application did not acknowledge startup.'
    }

    Remove-Tree $backupDirectory
    if (Test-Path -LiteralPath $PackagePath -PathType Leaf) {
        Remove-Item -Force -LiteralPath $PackagePath
    }
    if (Test-Path -LiteralPath $ackPath -PathType Leaf) {
        Remove-Item -Force -LiteralPath $ackPath
    }
    Write-ResultFile @{
        success = $true
        phase = 'completed'
        target_version = $TargetVersion
        launched_pid = $launchedProcess.Id
    }
    exit 0
}
catch {
    $failure = $_.Exception.Message
    if ($null -ne $launchedProcess -and -not $launchedProcess.HasExited) {
        Stop-Process -Id $launchedProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($swapped) {
        Remove-Tree $installFull
        if (Test-Path -LiteralPath $backupDirectory -PathType Container) {
            Move-Item -LiteralPath $backupDirectory -Destination $installFull
        }
    }
    Remove-Tree $stagingDirectory
    if (Test-Path -LiteralPath $ackPath -PathType Leaf) {
        Remove-Item -Force -LiteralPath $ackPath
    }
    Write-ResultFile @{
        success = $false
        phase = 'failed'
        target_version = $TargetVersion
        error = $failure
        rolled_back = $swapped
    }
    exit 1
}
