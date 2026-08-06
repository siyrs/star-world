param(
    [Parameter(Mandatory = $true)][string]$ReviewerId,
    [Parameter(Mandatory = $true)][string]$ImplementerId,
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$ExecutableSha256,
    [Parameter(Mandatory = $true)][string]$PckSha256,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string[]]$Blockers = @(),
    [switch]$FreshInstall,
    [switch]$NewWorld,
    [switch]$SaveReload,
    [switch]$FiveProfiles,
    [switch]$InputAndUi,
    [switch]$QuitAndRestart,
    [switch]$IndependentAttestation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$reviewer = $ReviewerId.Trim()
$implementer = $ImplementerId.Trim()
if ([string]::IsNullOrWhiteSpace($reviewer) -or [string]::IsNullOrWhiteSpace($implementer)) {
    throw 'ReviewerId and ImplementerId must not be blank.'
}
if ($reviewer -eq $implementer) { throw 'The experiential reviewer must be independent from the implementer.' }
if (-not $IndependentAttestation) { throw 'Independent review requires -IndependentAttestation.' }
if ($CommitSha -cnotmatch '^[0-9a-f]{40}$') { throw 'CommitSha must be a 40-character lowercase hexadecimal SHA.' }
if ($ExecutableSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'ExecutableSha256 must be a lowercase SHA-256 digest.' }
if ($PckSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'PckSha256 must be a lowercase SHA-256 digest.' }

$checks = [ordered]@{
    fresh_install = [bool]$FreshInstall
    new_world = [bool]$NewWorld
    save_reload = [bool]$SaveReload
    five_profiles = [bool]$FiveProfiles
    input_and_ui = [bool]$InputAndUi
    quit_and_restart = [bool]$QuitAndRestart
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value } | ForEach-Object Key)
if ($failedChecks.Count -gt 0) { throw "E4-H checklist is incomplete: $($failedChecks -join ', ')" }
if ($Blockers.Count -gt 0) { throw "E4-H review has unresolved blockers: $($Blockers -join ' | ')" }

$record = [ordered]@{
    schema_version = 2
    evidence_class = 'e4_h_independent_experience_review'
    reviewer_id = $reviewer
    implementer_id = $implementer
    independent = $true
    signed_at_unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    build = [ordered]@{
        commit_sha = $CommitSha
        executable_sha256 = $ExecutableSha256
        pck_sha256 = $PckSha256
    }
    checklist = $checks
    blockers = @()
    result = 'pass'
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) | Out-Null
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
Write-Host "E4-H INDEPENDENT REVIEW RECORDED | schema=2 | reviewer=$reviewer | commit=$CommitSha | evidence=$resolvedOutput"
