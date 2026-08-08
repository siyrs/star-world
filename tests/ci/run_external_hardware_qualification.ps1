param(
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
$policyHelpers = Join-Path $PSScriptRoot 'qualification_policy_helpers.ps1'
if (-not (Test-Path -LiteralPath $policyHelpers -PathType Leaf)) {
    throw "Qualification policy helpers not found: $policyHelpers"
}
. $policyHelpers
$policyContext = Get-ReleaseQualificationPolicyContext -ProjectRoot $projectFullPath
$policySnapshot = New-HardwareQualificationPolicySnapshot -PolicyContext $policyContext -Tier $Tier
$exeFullPath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckFullPath = [System.IO.Path]::GetFullPath($ReleasePck)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
foreach ($path in @($exeFullPath, $pckFullPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Final package file not found: $path" }
}
$expectedPck = Join-Path (Split-Path -Parent $exeFullPath) 'StarWorld.pck'
if ($pckFullPath -ne [System.IO.Path]::GetFullPath($expectedPck)) {
    throw 'ReleasePck must be StarWorld.pck beside the supplied final executable.'
}
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StringSha256 {
    param([string]$Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Value))
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

$exeHashBefore = Get-Sha256 $exeFullPath
$pckHashBefore = Get-Sha256 $pckFullPath
$startedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$matrixRoot = Join-Path $outputFullPath 'release-journey-matrix'
$matrixRelative = [System.IO.Path]::GetRelativePath($projectFullPath, $matrixRoot)
$matrixTier = if ($ReferenceOnly) { 'hosted-ci-reference' } else { $Tier }
& (Join-Path $projectFullPath 'tests/release/run_windows_export_journey_matrix.ps1') `
    -OutputDirectory $matrixRelative `
    -QualificationTier $matrixTier `
    -Operator $OperatorId `
    -ExistingExecutablePath $exeFullPath

$matrixPath = Join-Path $matrixRoot 'release-journey-matrix.json'
if (-not (Test-Path -LiteralPath $matrixPath -PathType Leaf)) { throw "Release journey matrix missing: $matrixPath" }
$matrix = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json -Depth 30
$profileIds = @($matrix.profiles | ForEach-Object { [string]$_.profile_id } | Sort-Object -Unique)
$requiredProfiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
foreach ($profile in $requiredProfiles) {
    if ($profile -notin $profileIds) { throw "Release journey matrix is missing profile: $profile" }
}
if ($profileIds.Count -ne 5 -or -not [bool]$matrix.assertions.all_profiles_present) {
    throw 'Release journey matrix did not validate exactly five formal profiles.'
}
if (-not [bool]$matrix.exact_existing_package_reused) {
    throw 'Release journey matrix did not reuse the supplied exact final package.'
}
$exeHash = Get-Sha256 $exeFullPath
$pckHash = Get-Sha256 $pckFullPath
if ($exeHash -ne $exeHashBefore -or $pckHash -ne $pckHashBefore) {
    throw 'The supplied final EXE/PCK changed while the fixed-package matrix was running.'
}
if ([string]$matrix.final_executable_sha256 -ne $exeHash -or [string]$matrix.final_pck_sha256 -ne $pckHash) {
    throw 'Release journey matrix hashes do not match the supplied final package.'
}
if ([int]$matrix.assertions.post_spawn_transport_count -ne 0) {
    throw 'Release journey matrix contains forbidden post-spawn transport.'
}
$metricEvaluation = Get-HardwareMetricEvaluation `
    -ProfileRecords @($matrix.profiles) `
    -MetricPolicy $policySnapshot.metrics `
    -RequiredProfiles $requiredProfiles
if (-not [bool]$metricEvaluation.passed) {
    throw "Hardware qualification metric policy failed for $Tier`: $($metricEvaluation.violations -join ' | ')"
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
$machineFingerprint = Get-StringSha256 ($hardwareIdentity | ConvertTo-Json -Depth 5 -Compress)
$completedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$evidence = [ordered]@{
    schema_version = 2
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
    exact_final_package_reused = $true
    qualification_policy = $policySnapshot
    metric_evaluation = $metricEvaluation
    result = 'pass'
    build = [ordered]@{
        executable_path = $exeFullPath
        executable_sha256 = $exeHash
        pck_path = $pckFullPath
        pck_sha256 = $pckHash
    }
    journey_matrix = [ordered]@{
        path = [System.IO.Path]::GetRelativePath($outputFullPath, $matrixPath).Replace('\', '/')
        sha256 = Get-Sha256 $matrixPath
        exact_existing_package_reused = [bool]$matrix.exact_existing_package_reused
        profile_count = $profileIds.Count
        minimum_steps = [int]$matrix.assertions.minimum_steps
        minimum_displacement = [double]$matrix.assertions.minimum_displacement
        minimum_unique_chunks = [int]$matrix.assertions.minimum_unique_chunks
    }
}
$outputPath = Join-Path $outputFullPath "hardware-$Tier.json"
$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding utf8
Write-Host "EXTERNAL HARDWARE QUALIFICATION CAPTURE PASS | tier=$Tier | reference_only=$([bool]$ReferenceOnly) | profiles=$($profileIds.Count) | executable=$exeHash | pck=$pckHash | fingerprint=$machineFingerprint | evidence=$outputPath"
