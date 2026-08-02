param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$ProjectRoot = '.',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $OutputDirectory = "build/qa-independent-qa003-$stamp"
}

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputDirectory))
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

$runner = Join-Path $projectFullPath 'tests/ci/run_godot_desktop_test.ps1'
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Desktop runner not found: $runner"
}

$results = [System.Collections.Generic.List[object]]::new()

function Invoke-QA003Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$OutputRelativePath,
        [int]$TimeoutMilliseconds = 120000,
        [switch]$AllowMissingCapture
    )

    $startedAt = Get-Date
    $status = 'pass'
    $message = ''
    try {
        & $runner `
            -Godot $Godot `
            -ProjectRoot $projectFullPath `
            -ScriptPath $ScriptPath `
            -OutputPath $OutputRelativePath `
            -TimeoutMilliseconds $TimeoutMilliseconds | Out-Null
    } catch {
        $status = 'fail'
        $message = $_.Exception.Message
    }
    # Regression-style scripts do not produce a screenshot; the runner treats a
    # missing primary capture as failure. For those cases require only that the
    # process itself passed and no fatal Godot log was emitted.
    if ($AllowMissingCapture -and $status -eq 'fail' -and $message -match 'did not create its requested screenshot') {
        $stdoutPath = [System.IO.Path]::ChangeExtension((Join-Path $projectFullPath $OutputRelativePath), '.stdout.log')
        $stderrPath = [System.IO.Path]::ChangeExtension((Join-Path $projectFullPath $OutputRelativePath), '.stderr.log')
        $stdoutPath = $stdoutPath -replace '\.png\.stdout\.log$', '.stdout.log'
        $stderrPath = $stderrPath -replace '\.png\.stderr\.log$', '.stderr.log'
        $fatal = @('SCRIPT ERROR', 'Parse Error', 'ObjectDB instances were leaked', 'Leaked instance:', 'Resources still in use at exit')
        $hits = @()
        foreach ($p in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $p) {
                $hits += @(Select-String -LiteralPath $p -Pattern $fatal -SimpleMatch)
            }
        }
        if ($hits.Count -eq 0) {
            $status = 'pass'
            $message = 'no-capture regression (log-only evidence)'
        } else {
            $message = ($hits | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line)" }) -join "`n"
        }
    }
    $elapsed = [int]((Get-Date) - $startedAt).TotalMilliseconds
    $results.Add([pscustomobject]@{
        case = $Name
        script = $ScriptPath
        output = $OutputRelativePath
        status = $status
        elapsed_ms = $elapsed
        message = $message
    })
    Write-Host "[$status] $Name ($elapsed ms) $ScriptPath"
    if ($status -eq 'fail') {
        Write-Host "  $message"
    }
}

Write-Host "QA-003 independent retest evidence directory: $outputFullPath"

$rel = $OutputDirectory.Replace('\', '/')

Invoke-QA003Case `
    -Name 'ui-design-system' `
    -ScriptPath 'res://tests/qa/ui_design_system_regression.gd' `
    -OutputRelativePath "$rel/ui-design-system.png" `
    -TimeoutMilliseconds 180000 `
    -AllowMissingCapture

Invoke-QA003Case `
    -Name 'ui-layout-1024x576' `
    -ScriptPath 'res://tests/qa/ui_layout_regression.gd' `
    -OutputRelativePath "$rel/ui-layout-1024x576.png" `
    -TimeoutMilliseconds 180000 `
    -AllowMissingCapture

Invoke-QA003Case `
    -Name 'ui-visual-refresh-main' `
    -ScriptPath 'res://tests/qa/ui_visual_refresh_desktop_acceptance.gd' `
    -OutputRelativePath "$rel/ui-visual-refresh-main.png" `
    -TimeoutMilliseconds 180000

Invoke-QA003Case `
    -Name 'ui-accessibility-settings' `
    -ScriptPath 'res://tests/qa/ui_accessibility_desktop_acceptance.gd' `
    -OutputRelativePath "$rel/ui-accessibility-settings.png" `
    -TimeoutMilliseconds 180000

Invoke-QA003Case `
    -Name 'profile-journey-main' `
    -ScriptPath 'res://tests/qa/profile_release_journey_regression.gd' `
    -OutputRelativePath "$rel/profile-journey-main.png" `
    -TimeoutMilliseconds 600000

$report = [pscustomobject]@{
    qa_id = 'QA-003'
    generated_at = (Get-Date).ToString('o')
    godot = $Godot
    project_root = $projectFullPath
    output_directory = $outputFullPath
    cases = $results
    pass_count = @($results | Where-Object { $_.status -eq 'pass' }).Count
    fail_count = @($results | Where-Object { $_.status -eq 'fail' }).Count
}
$reportPath = Join-Path $outputFullPath 'qa003-report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "QA-003 report: $reportPath"

$failed = @($results | Where-Object { $_.status -ne 'pass' })
if ($failed.Count -gt 0) {
    throw "QA-003 failed cases: $($failed.Count)"
}
Write-Host "QA-003 PASS | cases=$($results.Count)"
