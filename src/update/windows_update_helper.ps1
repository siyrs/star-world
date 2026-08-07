param(
    [Parameter(Mandatory = $true)][int]$ParentProcessId,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$ExpectedPackageSha256,
    [Parameter(Mandatory = $true)][string]$InstallDirectory,
    [Parameter(Mandatory = $true)][string]$ExecutableName,
    [Parameter(Mandatory = $true)][string]$TargetVersion,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$TrustValidatorPath,
    [Parameter(Mandatory = $true)][string]$TrustPolicyBase64,
    [string]$LaunchExecutable = '',
    [string]$LaunchArgumentsBase64 = '',
    [int]$WaitForExitSeconds = 120,
    [int]$AckTimeoutSeconds = 45,
    [switch]$AllowUnsignedReference
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
$trustEvidence = $null

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
    if (-not (Test-Path -LiteralPath $TrustValidatorPath -PathType Leaf)) {
        throw 'Current-install updater trust validator is missing.'
    }
    if ([string]::IsNullOrWhiteSpace($TrustPolicyBase64)) {
        throw 'Current-install updater trust policy is missing.'
    }
    $actualPackageHash = Get-Sha256 $PackagePath
    if ($actualPackageHash -ne $ExpectedPackageSha256.ToLowerInvariant()) {
        throw 'Downloaded update package checksum does not match.'
    }

    Remove-Tree $stagingDirectory
    Expand-SafeArchive -ArchivePath $PackagePath -Destination $stagingDirectory
    $manifestPath = Join-Path $stagingDirectory 'update-manifest.json'
    $signaturePath = Join-Path $stagingDirectory 'update-manifest.p7s'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Update manifest is missing from package.'
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    $schemaVersion = [int]$manifest.schema_version
    if ($schemaVersion -ne 1 -and $schemaVersion -ne 2) { throw 'Unsupported update manifest schema.' }
    if (-not $AllowUnsignedReference -and $schemaVersion -ne 2) { throw 'Publisher-signed update manifest schema is required.' }
    if ($schemaVersion -eq 2) {
        if ([int]$manifest.updater_protocol -ne 2) { throw 'Signed updater protocol mismatch.' }
        if ($null -eq $manifest.signature) { throw 'Signed update manifest declaration is missing.' }
        if ([string]$manifest.signature.format -ne 'cms-detached') { throw 'Update manifest signature format mismatch.' }
        if ([string]$manifest.signature.digest -ne 'sha256') { throw 'Update manifest signature digest mismatch.' }
        if ([string]$manifest.signature.path -ne 'update-manifest.p7s') { throw 'Update manifest signature path mismatch.' }
        if (-not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) { throw 'Detached update manifest signature is missing.' }
    }
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
        if ($manifestRelative -eq 'update-manifest.json' -or $manifestRelative -eq 'update-manifest.p7s') {
            throw "Manifest metadata cannot list itself as payload: $manifestRelative"
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
    foreach ($stagedFile in @(Get-ChildItem -LiteralPath $stagingDirectory -File -Recurse -Force)) {
        $fullStagedPath = [System.IO.Path]::GetFullPath($stagedFile.FullName)
        if (-not $fullStagedPath.StartsWith($stageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Staged file escapes staging directory: $fullStagedPath"
        }
        $stagedRelative = $fullStagedPath.Substring($stageRoot.Length).Replace('\', '/')
        if ($stagedRelative -eq 'update-manifest.json') { continue }
        if ($stagedRelative -eq 'update-manifest.p7s' -and $schemaVersion -eq 2) { continue }
        if (-not $manifestPaths.ContainsKey($stagedRelative.ToLowerInvariant())) {
            throw "Archive contains an unlisted payload file: $stagedRelative"
        }
    }

    $stagedExecutable = Join-Path $stagingDirectory $ExecutableName
    if (-not (Test-Path -LiteralPath $stagedExecutable -PathType Leaf)) {
        throw 'Staged executable is missing.'
    }
    if (-not (Test-Path -LiteralPath $installFull -PathType Container)) {
        throw 'Install directory is missing.'
    }

    Write-ResultFile @{
        success = $false
        phase = 'authenticating_publisher'
        target_version = $TargetVersion
    }
    $trustArguments = @{
        ManifestPath = $manifestPath
        SignaturePath = $signaturePath
        ExecutablePath = $stagedExecutable
        TrustPolicyBase64 = $TrustPolicyBase64
    }
    if ($AllowUnsignedReference) { $trustArguments['AllowUnsignedReference'] = $true }
    $trustText = (& $TrustValidatorPath @trustArguments | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($trustText)) { throw 'Updater trust validator returned no evidence.' }
    $trustEvidence = $trustText | ConvertFrom-Json
    if (-not [bool]$trustEvidence.valid) { throw 'Updater publisher trust validation failed.' }
    if (-not $AllowUnsignedReference -and [bool]$trustEvidence.reference_only) {
        throw 'Reference-only updater trust evidence cannot authorize an install.'
    }

    Write-ResultFile @{
        success = $false
        phase = 'switching'
        target_version = $TargetVersion
        staging_path = $stagingDirectory
        backup_path = $backupDirectory
        publisher_authenticated = -not [bool]$trustEvidence.reference_only
        manifest_signer_certificate_sha256 = [string]$trustEvidence.manifest_signer_certificate_sha256
        publisher_certificate_sha256 = [string]$trustEvidence.publisher_certificate_sha256
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
        publisher_authenticated = -not [bool]$trustEvidence.reference_only
        manifest_signer_certificate_sha256 = [string]$trustEvidence.manifest_signer_certificate_sha256
        publisher_certificate_sha256 = [string]$trustEvidence.publisher_certificate_sha256
        trusted_timestamp_present = [bool]$trustEvidence.trusted_timestamp_present
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