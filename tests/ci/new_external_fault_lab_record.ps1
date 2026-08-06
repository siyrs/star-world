param(
    [Parameter(Mandatory = $true)][ValidateSet('hdd', 'antivirus', 'power_loss')][string]$Scenario,
    [Parameter(Mandatory = $true)][ValidateSet('prepare', 'complete')][string]$Phase,
    [Parameter(Mandatory = $true)][string]$WorldJsonPath,
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [Parameter(Mandatory = $true)][string]$OperatorId,
    [Parameter(Mandatory = $true)][string]$RecordPath,
    [string]$RecoveryEvidencePath = '',
    [switch]$ReferenceOnly,
    [switch]$AttestedReal,
    [switch]$InterruptionObserved,
    [switch]$RecoveryVerified,
    [switch]$WorldIntegrityVerified
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($OperatorId)) { throw 'OperatorId must not be blank.' }
if (-not $ReferenceOnly -and -not $AttestedReal) { throw 'Real fault-lab evidence requires -AttestedReal.' }
if (-not $ReferenceOnly -and $env:GITHUB_ACTIONS -eq 'true') {
    throw 'GitHub-hosted runners cannot create real HDD, antivirus or power-loss evidence.'
}

$worldPath = [System.IO.Path]::GetFullPath($WorldJsonPath)
$exePath = [System.IO.Path]::GetFullPath($ReleaseExecutable)
$pckPath = [System.IO.Path]::GetFullPath($ReleasePck)
$recordFullPath = [System.IO.Path]::GetFullPath($RecordPath)
foreach ($path in @($worldPath, $exePath, $pckPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required fault-lab input not found: $path" }
}
$expectedPck = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $exePath) 'StarWorld.pck'))
if ($pckPath -ne $expectedPck) { throw 'ReleasePck must be StarWorld.pck beside the supplied final executable.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $recordFullPath) | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-WorldIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    $worldId = [string]$payload.metadata.id
    if ([string]::IsNullOrWhiteSpace($worldId)) { throw "World metadata.id is missing: $Path" }
    return $worldId
}

$exeHash = Get-Sha256 -Path $exePath
$pckHash = Get-Sha256 -Path $pckPath

if ($Phase -eq 'prepare') {
    if (Test-Path -LiteralPath $recordFullPath) {
        throw "Fault record already exists; use -Phase complete or choose a new path: $recordFullPath"
    }
    $worldId = Read-WorldIdentity -Path $worldPath
    $record = [ordered]@{
        schema_version = 1
        type = $Scenario
        phase = 'prepared'
        evidence_source = if ($ReferenceOnly) { 'hosted_reference' } else { 'target_hardware' }
        reference_only = [bool]$ReferenceOnly
        operator_id = $OperatorId.Trim()
        attested_real = [bool]$AttestedReal -and -not [bool]$ReferenceOnly
        prepared_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        world_id = $worldId
        before_world_sha256 = Get-Sha256 -Path $worldPath
        build = [ordered]@{
            executable_sha256 = $exeHash
            pck_sha256 = $pckHash
        }
        interruption_observed = $false
        recovery_verified = $false
        world_integrity_verified = $false
        result = 'pending'
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordFullPath -Encoding utf8
    Write-Host "FAULT LAB PREPARED | scenario=$Scenario | world=$worldId | executable=$exeHash | pck=$pckHash | record=$recordFullPath"
    Write-Host 'Perform the real external interruption now, restart the machine/application, then run -Phase complete with the same EXE/PCK.'
    return
}

if (-not (Test-Path -LiteralPath $recordFullPath -PathType Leaf)) {
    throw "Prepared fault record not found: $recordFullPath"
}
if ([string]::IsNullOrWhiteSpace($RecoveryEvidencePath)) {
    throw '-RecoveryEvidencePath is required when completing a fault-lab record.'
}
$recoveryPath = [System.IO.Path]::GetFullPath($RecoveryEvidencePath)
if (-not (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) { throw "Recovery evidence not found: $recoveryPath" }
if (-not $InterruptionObserved -or -not $RecoveryVerified -or -not $WorldIntegrityVerified) {
    throw 'Completion requires -InterruptionObserved, -RecoveryVerified and -WorldIntegrityVerified.'
}

$record = Get-Content -LiteralPath $recordFullPath -Raw | ConvertFrom-Json -Depth 20
if ([string]$record.type -ne $Scenario -or [string]$record.phase -ne 'prepared') {
    throw 'Fault record does not match the requested scenario or is not in prepared state.'
}
if ([string]$record.operator_id -ne $OperatorId.Trim()) {
    throw 'Fault record operator does not match the completing operator.'
}
if ([string]$record.build.executable_sha256 -ne $exeHash -or [string]$record.build.pck_sha256 -ne $pckHash) {
    throw 'Fault completion must use the exact EXE/PCK captured during prepare.'
}
$worldId = Read-WorldIdentity -Path $worldPath
if ($worldId -ne [string]$record.world_id) {
    throw "Recovered world identity changed: expected $($record.world_id), got $worldId"
}

$completed = [ordered]@{
    schema_version = 1
    type = $Scenario
    phase = 'completed'
    evidence_source = [string]$record.evidence_source
    reference_only = [bool]$record.reference_only
    operator_id = [string]$record.operator_id
    attested_real = [bool]$record.attested_real
    prepared_at_unix = [long]$record.prepared_at_unix
    completed_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    world_id = $worldId
    before_world_sha256 = [string]$record.before_world_sha256
    after_world_sha256 = Get-Sha256 -Path $worldPath
    recovery_evidence_sha256 = Get-Sha256 -Path $recoveryPath
    build = [ordered]@{
        executable_sha256 = $exeHash
        pck_sha256 = $pckHash
    }
    interruption_observed = $true
    recovery_verified = $true
    world_integrity_verified = $true
    result = 'pass'
}
$completed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordFullPath -Encoding utf8
Write-Host "FAULT LAB COMPLETE | scenario=$Scenario | world=$worldId | before=$($completed.before_world_sha256) | after=$($completed.after_world_sha256) | executable=$exeHash | pck=$pckHash | record=$recordFullPath"
