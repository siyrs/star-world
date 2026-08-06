param(
    [string]$ProjectRoot = '.',
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ReleaseExecutable,
    [Parameter(Mandatory = $true)][string]$ReleasePck,
    [string]$PolicyPath = 'data/release_qualification.json',
    [string]$ProjectFilePath = 'project.godot',
    [string]$ExportPresetsPath = 'export_presets.cfg',
    [string]$OutputPath = 'build/external-qualification/release-candidate.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
if ($CommitSha -cnotmatch '^[0-9a-f]{40}$') { throw 'CommitSha must be a 40-character lowercase hexadecimal SHA.' }
$versionText = $Version.Trim()
if ([string]::IsNullOrWhiteSpace($versionText)) { throw 'Version must not be blank.' }
if ($versionText.Length -gt 128) { throw 'Version is too long.' }

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
function New-FileRecord {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        file_name = $item.Name
        length_bytes = [long]$item.Length
        sha256 = Get-Sha256 -Path $Path
    }
}

$exePath = Resolve-ProjectPath $ReleaseExecutable
$pckPath = Resolve-ProjectPath $ReleasePck
$policyFullPath = Resolve-ProjectPath $PolicyPath
$projectFileFullPath = Resolve-ProjectPath $ProjectFilePath
$exportPresetsFullPath = Resolve-ProjectPath $ExportPresetsPath
$outputFullPath = Resolve-ProjectPath $OutputPath
foreach ($path in @($exePath, $pckPath, $policyFullPath, $projectFileFullPath, $exportPresetsFullPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release candidate input not found: $path" }
}
if ([System.IO.Path]::GetFileName($exePath) -ne 'StarWorld.exe') {
    throw 'ReleaseExecutable must be named StarWorld.exe.'
}
$expectedPck = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $exePath) 'StarWorld.pck'))
if ($pckPath -ne $expectedPck) { throw 'ReleasePck must be StarWorld.pck beside StarWorld.exe.' }

$exe = New-FileRecord -Path $exePath
$pck = New-FileRecord -Path $pckPath
$policy = New-FileRecord -Path $policyFullPath
$projectFile = New-FileRecord -Path $projectFileFullPath
$exportPresets = New-FileRecord -Path $exportPresetsFullPath
$canonical = @(
    'star-world-release-candidate-v1',
    "commit=$CommitSha",
    "version=$versionText",
    "exe_sha256=$($exe.sha256)",
    "exe_bytes=$($exe.length_bytes)",
    "pck_sha256=$($pck.sha256)",
    "pck_bytes=$($pck.length_bytes)",
    "policy_sha256=$($policy.sha256)",
    "project_sha256=$($projectFile.sha256)",
    "export_presets_sha256=$($exportPresets.sha256)"
) -join "`n"
$candidateId = Get-StringSha256 -Value $canonical

$manifest = [ordered]@{
    schema_version = 1
    candidate_id = $candidateId
    created_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    product = 'Star World'
    platform = 'Windows x86_64'
    build = [ordered]@{
        commit_sha = $CommitSha
        version = $versionText
        executable = $exe
        pck = $pck
    }
    contracts = [ordered]@{
        release_qualification = [ordered]@{
            repository_path = 'data/release_qualification.json'
            length_bytes = $policy.length_bytes
            sha256 = $policy.sha256
        }
        project = [ordered]@{
            repository_path = 'project.godot'
            length_bytes = $projectFile.length_bytes
            sha256 = $projectFile.sha256
        }
        export_presets = [ordered]@{
            repository_path = 'export_presets.cfg'
            length_bytes = $exportPresets.length_bytes
            sha256 = $exportPresets.sha256
        }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$tempPath = "$outputFullPath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $outputFullPath -Force
} finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

$validator = Join-Path $PSScriptRoot 'validate_release_candidate_manifest.ps1'
if (Test-Path -LiteralPath $validator -PathType Leaf) {
    & $validator `
        -ProjectRoot $projectFullPath `
        -CandidateManifestPath $outputFullPath `
        -ReleaseExecutable $exePath `
        -ReleasePck $pckPath | Out-Null
}
Write-Host "RELEASE CANDIDATE MANIFEST PASS | candidate=$candidateId | commit=$CommitSha | executable=$($exe.sha256) | pck=$($pck.sha256) | output=$outputFullPath"
