param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$ProjectRoot = '.',
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
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot executable not found: $Godot" }
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
$matrixRelative = [System.IO.Path]::GetRelativePath($projectFullPath, (Join-Path $outputFullPath 'release-journey-matrix'))
$matrixTier = if ($ReferenceOnly) { 'hosted-ci-reference' } else { $Tier }
& (Join-Path $projectFullPath 'tests/release/run_windows_export_journey_matrix.ps1') `
    -Godot $Godot `
    -OutputDirectory $matrixRelative `
    -QualificationTier $matrixTier `
    -Operator $OperatorId

$matrixRoot = Join-Path $outputFullPath 'release-journey-matrix'
$matrixPath = Join-Path $matrixRoot 'release-journey-matrix.json'
$exeFullPath = Join-Path $matrixRoot 'binary/StarWorld.exe'
$pckFullPath = Join-Path $matrixRoot 'binary/StarWorld.pck'
foreach ($path in @($matrixPath, $exeFullPath, $pckFullPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release journey evidence missing: $path" }
}
$matrix = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json -Depth 20
$profileIds = @($matrix.profiles | ForEach-Object { [string]$_.profile_id } | Sort-Object -Unique)
$requiredProfiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
foreach ($profile in $requiredProfiles) {
    if ($profile -notin $profileIds) { throw "Release journey matrix is missing profile: $profile" }
}
if ($profileIds.Count -ne 5 -or -not [bool]$matrix.assertions.all_profiles_present) {
    throw 'Release journey matrix did not validate exactly five formal profiles.'
}
if ([int]$matrix.assertions.post_spawn_transport_count -ne 0) {
    throw 'Release journey matrix contains forbidden post-spawn transport.'
}

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$gpus = @(Get-CimInstance Win32_VideoController | Sort-Object Name | ForEach-Object { [string]$_.Name })
$physicalDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId | Select-Object -First 1
$driveType = 'ssd'
$storageModel = 'unresolved-storage'
if ($null -ne $physicalDisk) {
    $storageModel = [string]$physicalDisk.FriendlyName
    $media = ([string]$physicalDisk.MediaType).ToLowerInvariant()
    $bus = ([string]$physicalDisk.BusType).ToLowerInvariant()
    if ($media -eq 'hdd') { $driveType = 'hdd' }
    elseif ($bus -eq 'nvme') { $driveType = 'nvme' }
    elseif ($media -eq 'ssd') { $driveType = 'ssd' }
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
    storage = [ordered]@{ drive_type = $driveType; model = $storageModel }
    profiles = @($requiredProfiles)
    started_at_unix = $startedAt
    completed_at_unix = $completedAt
    result = 'pass'
    build = [ordered]@{
        executable_path = [System.IO.Path]::GetRelativePath($outputFullPath, $exeFullPath).Replace('\', '/')
        executable_sha256 = Get-Sha256 -Path $exeFullPath
        pck_path = [System.IO.Path]::GetRelativePath($outputFullPath, $pckFullPath).Replace('\', '/')
        pck_sha256 = Get-Sha256 -Path $pckFullPath
    }
    journey_matrix = [ordered]@{
        path = [System.IO.Path]::GetRelativePath($outputFullPath, $matrixPath).Replace('\', '/')
        sha256 = Get-Sha256 -Path $matrixPath
        profile_count = $profileIds.Count
        minimum_steps = [int]$matrix.assertions.minimum_steps
        minimum_displacement = [double]$matrix.assertions.minimum_displacement
        minimum_unique_chunks = [int]$matrix.assertions.minimum_unique_chunks
    }
}

$outputPath = Join-Path $outputFullPath "hardware-$Tier.json"
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding utf8
Write-Host "EXTERNAL HARDWARE QUALIFICATION CAPTURE PASS | tier=$Tier | reference_only=$([bool]$ReferenceOnly) | profiles=$($profileIds.Count) | fingerprint=$machineFingerprint | evidence=$outputPath"
