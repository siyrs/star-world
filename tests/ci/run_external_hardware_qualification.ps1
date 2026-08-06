param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][ValidateSet('minimum', 'recommended')][string]$Tier,
    [Parameter(Mandatory = $true)][string]$OperatorId,
    [string]$OutputDirectory = 'build/external-qualification/hardware',
    [switch]$ReferenceOnly,
    [switch]$OperatorAttested
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($OperatorId)) { throw 'OperatorId must not be blank.' }
if (-not $ReferenceOnly -and -not $OperatorAttested) {
    throw 'Real target-hardware evidence requires -OperatorAttested.'
}
if (-not $ReferenceOnly -and $env:GITHUB_ACTIONS -eq 'true') {
    throw 'GitHub-hosted runners cannot create target-hardware qualification evidence.'
}

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$exeFullPath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckFullPath = [System.IO.Path]::GetFullPath($ReleasePck)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
foreach ($path in @($Godot, $exeFullPath, $pckFullPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

$startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$gpus = @(Get-CimInstance Win32_VideoController | Sort-Object Name | ForEach-Object { [string]$_.Name })
$physicalDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId | Select-Object -First 1
$logicalDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$([System.IO.Path]::GetPathRoot($exeFullPath).TrimEnd('\'))'" -ErrorAction SilentlyContinue

$driveType = 'ssd'
$storageModel = 'unknown'
if ($null -ne $physicalDisk) {
    $storageModel = [string]$physicalDisk.FriendlyName
    $media = ([string]$physicalDisk.MediaType).ToLowerInvariant()
    $bus = ([string]$physicalDisk.BusType).ToLowerInvariant()
    if ($media -eq 'hdd') { $driveType = 'hdd' }
    elseif ($bus -eq 'nvme') { $driveType = 'nvme' }
    elseif ($media -eq 'ssd') { $driveType = 'ssd' }
}
if ([string]::IsNullOrWhiteSpace($storageModel) -or $storageModel -eq 'unknown') {
    $storageModel = if ($null -ne $logicalDisk) { "logical-$($logicalDisk.DeviceID)" } else { 'unresolved-storage' }
}

$hardwareIdentity = [ordered]@{
    cpu = [string]$cpu.Name
    gpu = @($gpus)
    ram_bytes = [long]$computer.TotalPhysicalMemory
    os_caption = [string]$os.Caption
    os_version = [string]$os.Version
    storage_model = $storageModel
    storage_type = $driveType
}
$machineFingerprint = Get-StringSha256 -Value ($hardwareIdentity | ConvertTo-Json -Depth 5 -Compress)

$performanceDirectory = Join-Path $outputFullPath 'performance'
& (Join-Path $PSScriptRoot 'run_performance_capture.ps1') `
    -Godot $Godot `
    -ProjectRoot $projectFullPath `
    -OutputDirectory ([System.IO.Path]::GetRelativePath($projectFullPath, $performanceDirectory))

$memoryEvidencePath = Join-Path $performanceDirectory 'perf.memory.json'
$stdoutPath = Join-Path $performanceDirectory 'perf.stdout.log'
$stderrPath = Join-Path $performanceDirectory 'perf.stderr.log'
foreach ($path in @($memoryEvidencePath, $stdoutPath, $stderrPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Performance evidence missing: $path" }
}

$completedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$evidence = [ordered]@{
    schema_version = 1
    tier = $Tier
    evidence_source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }
    reference_only = [bool]$ReferenceOnly
    operator_id = $OperatorId.Trim()
    operator_attested = [bool]$OperatorAttested -and -not [bool]$ReferenceOnly
    machine_fingerprint_sha256 = $machineFingerprint
    cpu = [string]$cpu.Name
    gpu = ($gpus -join ' | ')
    ram_gib = [math]::Round([double]$computer.TotalPhysicalMemory / 1GB, 2)
    os = "$($os.Caption) $($os.Version)"
    storage = [ordered]@{
        drive_type = $driveType
        model = $storageModel
    }
    profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
    started_at_unix = $startedAt
    completed_at_unix = $completedAt
    result = 'pass'
    build = [ordered]@{
        executable_path = [System.IO.Path]::GetFileName($exeFullPath)
        executable_sha256 = Get-Sha256 -Path $exeFullPath
        pck_path = [System.IO.Path]::GetFileName($pckFullPath)
        pck_sha256 = Get-Sha256 -Path $pckFullPath
    }
    performance_evidence = [ordered]@{
        memory_report_sha256 = Get-Sha256 -Path $memoryEvidencePath
        stdout_sha256 = Get-Sha256 -Path $stdoutPath
        stderr_sha256 = Get-Sha256 -Path $stderrPath
    }
}

$outputPath = Join-Path $outputFullPath "hardware-$Tier.json"
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding utf8
Write-Host "EXTERNAL HARDWARE QUALIFICATION CAPTURE PASS | tier=$Tier | reference_only=$([bool]$ReferenceOnly) | fingerprint=$machineFingerprint | evidence=$outputPath"
