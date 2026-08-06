param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$CandidateManifestPath,
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $Path))
}
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
function Assert-Hex {
    param([string]$Value, [int]$Length, [string]$Label)
    if ($Value -cnotmatch "^[0-9a-f]{$Length}$") { throw "$Label must be a lowercase $Length-character hexadecimal digest." }
}
function Assert-FileRecord {
    param([object]$Record, [string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label file not found: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ([long]$Record.length_bytes -ne [long]$item.Length) { throw "$Label length does not match the file." }
    $actualHash = Get-Sha256 -Path $Path
    if ([string]$Record.sha256 -ne $actualHash) { throw "$Label SHA-256 does not match the file." }
}

$manifestPath = Resolve-ProjectPath $CandidateManifestPath
$exePath = Resolve-ProjectPath $ReleaseExecutable
$pckPath = Resolve-ProjectPath $ReleasePck
foreach ($path in @($manifestPath, $exePath, $pckPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate validation input not found: $path" }
}
if ([System.IO.Path]::GetFileName($exePath) -ne 'StarWorld.exe') { throw 'ReleaseExecutable must be named StarWorld.exe.' }
$expectedPck = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $exePath) 'StarWorld.pck'))
if ($pckPath -ne $expectedPck) { throw 'ReleasePck must be StarWorld.pck beside StarWorld.exe.' }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 30
if ([int]$manifest.schema_version -ne 1) { throw 'Release candidate schema_version must equal 1.' }
Assert-Hex ([string]$manifest.candidate_id) 64 'candidate_id'
Assert-Hex ([string]$manifest.build.commit_sha) 40 'build.commit_sha'
if ([long]$manifest.created_at_unix -le 0) { throw 'created_at_unix must be positive.' }
if ([string]::IsNullOrWhiteSpace([string]$manifest.build.version)) { throw 'build.version is required.' }

Assert-FileRecord $manifest.build.executable $exePath 'StarWorld.exe'
Assert-FileRecord $manifest.build.pck $pckPath 'StarWorld.pck'
$policyPath = Join-Path $projectFullPath ([string]$manifest.contracts.release_qualification.repository_path)
$projectFilePath = Join-Path $projectFullPath ([string]$manifest.contracts.project.repository_path)
$exportPresetsPath = Join-Path $projectFullPath ([string]$manifest.contracts.export_presets.repository_path)
Assert-FileRecord $manifest.contracts.release_qualification $policyPath 'release qualification policy'
Assert-FileRecord $manifest.contracts.project $projectFilePath 'project.godot'
Assert-FileRecord $manifest.contracts.export_presets $exportPresetsPath 'export_presets.cfg'

$canonical = @(
    'star-world-release-candidate-v1',
    "commit=$($manifest.build.commit_sha)",
    "version=$($manifest.build.version)",
    "exe_sha256=$($manifest.build.executable.sha256)",
    "exe_bytes=$([long]$manifest.build.executable.length_bytes)",
    "pck_sha256=$($manifest.build.pck.sha256)",
    "pck_bytes=$([long]$manifest.build.pck.length_bytes)",
    "policy_sha256=$($manifest.contracts.release_qualification.sha256)",
    "project_sha256=$($manifest.contracts.project.sha256)",
    "export_presets_sha256=$($manifest.contracts.export_presets.sha256)"
) -join "`n"
$expectedCandidateId = Get-StringSha256 -Value $canonical
if ([string]$manifest.candidate_id -ne $expectedCandidateId) {
    throw "candidate_id does not match the candidate contents: expected $expectedCandidateId"
}

$result = [ordered]@{
    schema_version = 1
    valid = $true
    candidate_id = [string]$manifest.candidate_id
    commit_sha = [string]$manifest.build.commit_sha
    executable_sha256 = [string]$manifest.build.executable.sha256
    pck_sha256 = [string]$manifest.build.pck.sha256
}
$result | ConvertTo-Json -Depth 5
