param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDirectory = 'build/commercial-desktop-acceptance',
    [int]$TimeoutMilliseconds = 1200000,
    [string[]]$ScriptPaths = @(),
    [switch]$Resume,
    [switch]$FailFast
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 (pwsh) or later is required.'
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runner = Join-Path $projectRoot 'tests\ci\run_godot_desktop_test.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Desktop runner is missing: $runner"
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot 4.7 console executable is required. Pass -Godot <path> or set GODOT_BIN.'
}

$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
$artifactsRoot = Join-Path $outputRoot 'artifacts'
$userdataRoot = Join-Path $outputRoot 'isolated-userdata'
$summaryPath = Join-Path $outputRoot 'desktop-acceptance-summary.json'
New-Item -ItemType Directory -Force -Path $artifactsRoot, $userdataRoot | Out-Null

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-CandidateFingerprint {
    $head = (& git -C $projectRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve Git HEAD.' }
    $diff = ((& git -C $projectRoot diff --no-ext-diff --binary) -join "`n")
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the worktree diff.' }
    $untracked = @(& git -C $projectRoot ls-files --others --exclude-standard | Sort-Object)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate untracked files.' }
    $untrackedFacts = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $untracked) {
        $fullPath = Join-Path $projectRoot $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $untrackedFacts.Add("$relativePath=$((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant())")
        }
    }
    $material = @($head, (Get-Sha256Text -Text $diff)) + $untrackedFacts
    return [ordered]@{
        head = $head
        worktree_sha256 = Get-Sha256Text -Text ($material -join "`n")
        untracked_files = @($untracked)
    }
}

function Write-Summary {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Summary
    )
    $temporaryPath = "$summaryPath.tmp"
    $Summary.updated_at = (Get-Date).ToString('o')
    $Summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $summaryPath -Force
}

if ($ScriptPaths.Count -eq 0) {
    $ScriptPaths = @(
        'res://tests/qa/desktop_acceptance_regression.gd'
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests\qa') -Filter '*_desktop_acceptance.gd' -File |
            Sort-Object Name |
            ForEach-Object { "res://tests/qa/$($_.Name)" }
    )
}
if ($ScriptPaths.Count -eq 0) { throw 'No desktop acceptance scripts were selected.' }

$candidate = Get-CandidateFingerprint
$records = [System.Collections.Generic.List[object]]::new()
if ($Resume -and (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    $previous = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 30
    if ([string]$previous.candidate.head -ne [string]$candidate.head -or
        [string]$previous.candidate.worktree_sha256 -ne [string]$candidate.worktree_sha256) {
        throw 'Resume evidence belongs to a different candidate fingerprint.'
    }
    foreach ($record in @($previous.records)) { $records.Add($record) }
}

$passedNames = @(
    $records |
        Where-Object { [string]$_.status -eq 'passed' } |
        ForEach-Object { [string]$_.script }
)
$startedAt = Get-Date
$summary = [ordered]@{
    schema_version = 1
    evidence_kind = 'fresh-local-commercial-desktop-acceptance'
    started_at = $startedAt.ToString('o')
    updated_at = $startedAt.ToString('o')
    completed_at = $null
    candidate = $candidate
    godot = [System.IO.Path]::GetFullPath($Godot)
    rendering_method = 'gl_compatibility'
    timeout_milliseconds_per_test = $TimeoutMilliseconds
    isolated_user_data = $true
    selected_count = $ScriptPaths.Count
    passed = 0
    failed = 0
    skipped_from_resume = 0
    ok = $false
    records = $records
}

$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
try {
    foreach ($scriptPath in $ScriptPaths) {
        if (($scriptPath -ne 'res://tests/qa/desktop_acceptance_regression.gd') -and
            ($scriptPath -notmatch '^res://tests/qa/[^/]+_desktop_acceptance\.gd$')) {
            throw "Desktop script is outside the allowed QA scope: $scriptPath"
        }
        if ($scriptPath -in $passedNames) {
            $summary.skipped_from_resume++
            continue
        }

        $name = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        $testRoot = Join-Path $artifactsRoot $name
        $testUserData = Join-Path $userdataRoot $name
        $primaryCapture = Join-Path $testRoot "$name.png"
        $runnerLog = Join-Path $testRoot "$name.runner.log"
        New-Item -ItemType Directory -Force -Path $testRoot, $testUserData | Out-Null

        $env:APPDATA = Join-Path $testUserData 'Roaming'
        $env:LOCALAPPDATA = Join-Path $testUserData 'Local'
        New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $status = 'passed'
        $failure = ''
        Write-Host "DESKTOP ACCEPTANCE START | $scriptPath"
        try {
            & $runner `
                -Godot $Godot `
                -ProjectRoot $projectRoot `
                -ScriptPath $scriptPath `
                -OutputPath $primaryCapture `
                -UserDataDirectory $testUserData `
                -TimeoutMilliseconds $TimeoutMilliseconds *>&1 |
                Tee-Object -LiteralPath $runnerLog | Write-Host

            if (-not (Test-Path -LiteralPath $primaryCapture -PathType Leaf) -or
                (Get-Item -LiteralPath $primaryCapture).Length -le 0) {
                throw "Desktop acceptance did not create a non-empty primary capture: $primaryCapture"
            }
        } catch {
            $status = 'failed'
            $failure = $_.Exception.Message
            Write-Host "DESKTOP ACCEPTANCE FAIL | $scriptPath | $failure"
        } finally {
            $watch.Stop()
        }

        $stdoutPath = Join-Path $testRoot "$name.stdout.log"
        $stderrPath = Join-Path $testRoot "$name.stderr.log"
        $records.Add([pscustomobject][ordered]@{
            script = $scriptPath
            status = $status
            duration_seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3)
            capture = [System.IO.Path]::GetRelativePath($outputRoot, $primaryCapture).Replace('\', '/')
            stdout = [System.IO.Path]::GetRelativePath($outputRoot, $stdoutPath).Replace('\', '/')
            stderr = [System.IO.Path]::GetRelativePath($outputRoot, $stderrPath).Replace('\', '/')
            runner_log = [System.IO.Path]::GetRelativePath($outputRoot, $runnerLog).Replace('\', '/')
            isolated_userdata = [System.IO.Path]::GetRelativePath($outputRoot, $testUserData).Replace('\', '/')
            failure = $failure
        })

        $summary.passed = @($records | Where-Object { [string]$_.status -eq 'passed' }).Count
        $summary.failed = @($records | Where-Object { [string]$_.status -eq 'failed' }).Count
        Write-Summary -Summary $summary
        if ($status -eq 'passed') {
            Write-Host "DESKTOP ACCEPTANCE PASS | $scriptPath | seconds=$($watch.Elapsed.TotalSeconds)"
        } elseif ($FailFast) {
            break
        }
    }
} finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
}

$summary.passed = @($records | Where-Object { [string]$_.status -eq 'passed' }).Count
$summary.failed = @($records | Where-Object { [string]$_.status -eq 'failed' }).Count
$summary.completed_at = (Get-Date).ToString('o')
$summary.ok = ($summary.failed -eq 0 -and $summary.passed -eq $summary.selected_count)
Write-Summary -Summary $summary

Write-Host "DESKTOP ACCEPTANCE SUMMARY | passed=$($summary.passed) failed=$($summary.failed) selected=$($summary.selected_count)"
Write-Host "DESKTOP ACCEPTANCE REPORT | $summaryPath"
if (-not $summary.ok) { exit 1 }
