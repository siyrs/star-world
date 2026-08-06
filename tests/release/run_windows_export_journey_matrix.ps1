param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDirectory = 'build/release-journey-matrix',
    [int]$RunnerTimeoutMilliseconds = 1200000,
    [int]$Seed = 112358,
    [ValidateSet('hosted-ci-reference', 'minimum', 'recommended')]
    [string]$QualificationTier = 'hosted-ci-reference',
    [string]$Operator = '',
    [string]$ExistingExecutablePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 (pwsh) or later is required.' }
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputDirectory))
$binaryDirectory = Join-Path $outputRoot 'binary'
$profilesDirectory = Join-Path $outputRoot 'profiles'
$summaryPath = Join-Path $outputRoot 'release-journey-matrix.json'
New-Item -ItemType Directory -Force -Path $binaryDirectory, $profilesDirectory | Out-Null

if ($QualificationTier -ne 'hosted-ci-reference' -and [string]::IsNullOrWhiteSpace($Operator)) {
    throw '-Operator is required for minimum/recommended hardware evidence.'
}
$profiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$reuseExisting = -not [string]::IsNullOrWhiteSpace($ExistingExecutablePath)
if ($reuseExisting) {
    $executable = [System.IO.Path]::GetFullPath($ExistingExecutablePath)
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Existing executable not found: $executable" }
    $pckPath = Join-Path (Split-Path -Parent $executable) 'StarWorld.pck'
    if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) { throw "Existing PCK not found beside executable: $pckPath" }
} else {
    $executable = Join-Path $binaryDirectory 'StarWorld.exe'
    $pckPath = Join-Path $binaryDirectory 'StarWorld.pck'
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-SafeCimValue {
    param([string]$ClassName, [string]$PropertyName)
    try {
        return @(Get-CimInstance $ClassName -ErrorAction Stop | ForEach-Object { $_.$PropertyName } | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    } catch { return @() }
}
function Get-HardwareSnapshot {
    $totalMemory = 0L
    try { $totalMemory = [long](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1).TotalPhysicalMemory } catch {}
    return [ordered]@{
        captured_at = (Get-Date).ToString('o')
        os = Get-SafeCimValue Win32_OperatingSystem Caption
        os_version = Get-SafeCimValue Win32_OperatingSystem Version
        cpu = Get-SafeCimValue Win32_Processor Name
        gpu = Get-SafeCimValue Win32_VideoController Name
        gpu_driver = Get-SafeCimValue Win32_VideoController DriverVersion
        physical_memory_gib = if ($totalMemory -gt 0) { [math]::Round($totalMemory / 1GB, 1) } else { 0 }
        github_actions = [bool]($env:GITHUB_ACTIONS -eq 'true')
        runner_name = [string]$env:RUNNER_NAME
        runner_os = [string]$env:RUNNER_OS
        runner_arch = [string]$env:RUNNER_ARCH
    }
}

$records = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $profiles.Count; $index++) {
    $profile = $profiles[$index]
    $profileOutput = if ($index -eq 0) { $binaryDirectory } else { Join-Path $profilesDirectory $profile }
    New-Item -ItemType Directory -Force -Path $profileOutput | Out-Null
    $arguments = @{
        OutputDirectory = $profileOutput
        RunnerTimeoutMilliseconds = $RunnerTimeoutMilliseconds
        ProfileId = $profile
        Seed = $Seed
        RouteProbe = $true
    }
    if ($reuseExisting -or $index -gt 0) {
        $arguments['SkipExport'] = $true
        $arguments['ExecutablePath'] = $executable
    } else {
        $arguments['Godot'] = $Godot
    }
    & (Join-Path $PSScriptRoot 'run_windows_export_smoke.ps1') @arguments

    $reportPath = Join-Path $profileOutput 'release-smoke.json'
    $memoryPath = Join-Path $profileOutput 'release-smoke.memory.json'
    $screenshotPath = Join-Path $profileOutput 'release-smoke.png'
    foreach ($path in @($reportPath, $memoryPath, $screenshotPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing route evidence for $profile`: $path" }
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 30
    $memory = Get-Content -LiteralPath $memoryPath -Raw | ConvertFrom-Json -Depth 30
    if (-not [bool]$report.ok -or -not [bool]$report.route.ok) { throw "Exported route failed for $profile" }
    if ((Get-Item $screenshotPath).Length -le 0) { throw "Exported route screenshot is empty for $profile" }
    $records.Add([pscustomobject][ordered]@{
        profile_id = $profile
        seed = $Seed
        checks = [int]$report.checks
        world_start_ms = [int]$report.world_start_ms
        planned_steps = [int]$report.route.planned_steps
        successful_steps = [int]$report.route.successful_steps
        horizontal_displacement = [double]$report.route.horizontal_displacement
        unique_chunks = [int]$report.route.unique_chunks
        maximum_single_fall = [double]$report.route.maximum_single_fall
        transport_after_spawn = [bool]$report.route.transport_after_spawn
        player_transform_writes = [int]$report.route.player_transform_writes
        tutorial_hidden_for_evidence = [bool]$report.tutorial_hidden_for_evidence
        visual_ok = [bool]$report.visual.ok
        avg_fps = [double]$report.soak.frame_metrics.avg_fps
        one_percent_low_fps = [double]$report.soak.frame_metrics.one_percent_low_fps
        frame_ms_p95 = [double]$report.soak.frame_metrics.frame_ms_p95
        frame_ms_p99 = [double]$report.soak.frame_metrics.frame_ms_p99
        frame_budget_miss_30fps_percent = [double]$report.soak.frame_metrics.frame_budget_miss_30fps_percent
        screenshot = [System.IO.Path]::GetRelativePath($outputRoot, $screenshotPath).Replace('\', '/')
        report = [System.IO.Path]::GetRelativePath($outputRoot, $reportPath).Replace('\', '/')
        working_set_p95_mib = [double]$memory.working_set_mib.p95_mib
        private_bytes_p95_mib = [double]$memory.private_bytes_mib.p95_mib
    })
}

if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or -not (Test-Path -LiteralPath $pckPath -PathType Leaf)) {
    throw 'The final executable or PCK disappeared during the route matrix.'
}
$summary = [ordered]@{
    schema_version = 2
    evidence_class = if ($QualificationTier -eq 'hosted-ci-reference') { 'hosted_ci_reference' } else { 'target_hardware_candidate' }
    qualification_tier = $QualificationTier
    operator = $Operator
    generated_at = (Get-Date).ToString('o')
    seed = $Seed
    exact_existing_package_reused = $reuseExisting
    single_package_reused_across_profiles = $true
    final_executable = [System.IO.Path]::GetFileName($executable)
    final_executable_sha256 = Get-Sha256 $executable
    final_pck = [System.IO.Path]::GetFileName($pckPath)
    final_pck_sha256 = Get-Sha256 $pckPath
    hardware = Get-HardwareSnapshot
    profiles = @($records)
    assertions = [ordered]@{
        profile_count = $records.Count
        all_profiles_present = $records.Count -eq 5
        minimum_steps = [int](($records | Measure-Object successful_steps -Minimum).Minimum)
        minimum_displacement = [math]::Round([double](($records | Measure-Object horizontal_displacement -Minimum).Minimum), 3)
        minimum_unique_chunks = [int](($records | Measure-Object unique_chunks -Minimum).Minimum)
        post_spawn_transport_count = @($records | Where-Object { $_.transport_after_spawn -or $_.player_transform_writes -ne 0 }).Count
        all_visual_checks_passed = @($records | Where-Object { -not $_.visual_ok }).Count -eq 0
        all_tutorial_overlays_hidden = @($records | Where-Object { -not $_.tutorial_hidden_for_evidence }).Count -eq 0
    }
}
if (-not $summary.assertions.all_profiles_present) { throw 'Five-profile export matrix is incomplete.' }
if ($summary.assertions.minimum_steps -lt 20) { throw 'At least one exported route completed fewer than 20 steps.' }
if ($summary.assertions.minimum_displacement -lt 14.0) { throw 'At least one exported route travelled less than 14 metres.' }
if ($summary.assertions.minimum_unique_chunks -lt 2) { throw 'At least one exported route did not cross two chunks.' }
if ($summary.assertions.post_spawn_transport_count -ne 0) { throw 'Exported route matrix contains forbidden post-spawn transport.' }
if (-not $summary.assertions.all_visual_checks_passed) { throw 'At least one exported screenshot failed visual acceptance.' }
if (-not $summary.assertions.all_tutorial_overlays_hidden) { throw 'At least one exported map screenshot is still obscured by onboarding.' }
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "WINDOWS EXPORT JOURNEY MATRIX PASS | profiles=$($records.Count) | exact_existing_package=$reuseExisting | executable=$($summary.final_executable_sha256) | pck=$($summary.final_pck_sha256) | evidence=$summaryPath"
if ($QualificationTier -eq 'hosted-ci-reference') { Write-Host 'NOTE: hosted CI reference evidence is not target-hardware sign-off.' }
