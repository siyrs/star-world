$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepoFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $repoRoot ($RelativePath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path)) {
        $script:failures.Add("Missing required file: $RelativePath")
        return ''
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Require-Contains {
    param([string]$Content, [string]$Needle, [string]$Description)
    if (-not $Content.Contains($Needle)) { $script:failures.Add("$Description (missing: $Needle)") }
}

function Require-NotContains {
    param([string]$Content, [string]$Needle, [string]$Description)
    if ($Content.Contains($Needle)) { $script:failures.Add("$Description (forbidden: $Needle)") }
}

$route = Read-RepoFile 'src/diagnostics/production_route_probe.gd'
$smoke = Read-RepoFile 'src/diagnostics/release_smoke_runner.gd'
$runtimePolicy = Read-RepoFile 'src/diagnostics/release_smoke_runtime_policy.gd'
$runtimeScopeRegression = Read-RepoFile 'tests/qa/release_smoke_runtime_health_scope_regression.gd'
$evidenceStateRegression = Read-RepoFile 'tests/qa/release_smoke_evidence_state_regression.gd'
$skyDescentRegression = Read-RepoFile 'tests/qa/sky_islands_cautious_descent_regression.gd'
$soak = Read-RepoFile 'tests/qa/long_soak_journey.gd'
$soakDriver = Read-RepoFile 'tests/ci/run_long_soak.ps1'
$godotInvoker = Read-RepoFile 'tests/ci/Invoke-Godot.ps1'
$smokeDriver = Read-RepoFile 'tests/release/run_windows_export_smoke.ps1'
$matrixDriver = Read-RepoFile 'tests/release/run_windows_export_journey_matrix.ps1'
$hardwareDriver = Read-RepoFile 'tests/release/run_target_hardware_qualification.ps1'
$policyText = Read-RepoFile 'data/release_qualification.json'
$tutorial = Read-RepoFile 'tests/qa/tutorial_placement_desktop_acceptance.gd'
$building = Read-RepoFile 'tests/qa/building_mining_closed_loop_desktop_acceptance.gd'
$workflow = Read-RepoFile '.github/workflows/release-readiness-closure-tests.yml'
$report = Read-RepoFile 'qa/final-release-report.md'
$contentMatrix = Read-RepoFile 'qa/content-journey-matrix.md'
$mapMatrix = Read-RepoFile 'qa/map-coverage-matrix.md'

Require-Contains $route 'class_name ProductionRouteProbe' 'Route pressure must live in an export-safe production script'
Require-Contains $route 'Input.action_press' 'Route execution must use production input actions'
Require-Contains $route 'transport_after_spawn": false' 'Route evidence must declare no post-spawn transport'
Require-Contains $route 'player_transform_writes": 0' 'Route evidence must count direct transform writes'
Require-NotContains $route 'player.global_position =' 'Route probe must never write the player transform'
Require-NotContains $route 'tests/qa/' 'Exported route probe cannot depend on test-only resources'
Require-Contains $route 'DESCENT_APPROACH_SPEED_LIMIT' 'Route probe must cap speed before one-block descents'
Require-Contains $route 'DESCENT_BRAKE_DISTANCE' 'Route probe must brake before a lower ledge'
Require-Contains $route 'cautious_descent' 'Route diagnostics must expose cautious descent coverage'
Require-Contains $skyDescentRegression 'REGRESSION_SEED := 112361' 'The exact failing sky-island seed must remain under regression'
Require-Contains $skyDescentRegression 'cautious one-block descent path' 'Regression must prove the cautious descent path is exercised'

Require-Contains $smoke '--smoke-profile=' 'Release smoke must select every formal map profile'
Require-Contains $smoke '--smoke-seed=' 'Release smoke must record a deterministic seed'
Require-Contains $smoke '--smoke-route-probe' 'Release smoke must expose the production route mode'
Require-Contains $smoke 'FrameMetricsScript.summarize' 'Final executable evidence must use frame-time schema metrics'
Require-Contains $smoke '"version": 4' 'Release smoke report schema must advertise route and performance evidence'
Require-NotContains $smoke 'player.global_position =' 'Release smoke cannot transport the player for soak or screenshots'
Require-Contains $smoke 'RuntimePolicy.is_runtime_critical' 'Release smoke must gate on runtime health rather than global operations capacity'
Require-Contains $runtimePolicy 'runtime_status' 'Runtime health policy must retain the primary full runtime signal'
Require-Contains $runtimePolicy 'sustained_runtime_status' 'Runtime health policy must retain sustained runtime as a compatibility fallback'
Require-Contains $runtimeScopeRegression 'operations-only critical health remains observable' 'Runtime health scope must reject operations-only false positives'
Require-Contains $runtimeScopeRegression 'runtime peak failures remain release-blocking' 'Runtime health scope must not weaken repeated peak-frame protection'
Require-Contains $smoke 'tutorial_hidden_for_evidence' 'Release smoke must publish tutorial-free map evidence state'
Require-Contains $smoke '"experience"' 'Release smoke must carry a completed onboarding domain'
Require-Contains $evidenceStateRegression 'release evidence starts after tutorial completion' 'Tutorial-free release evidence must have a deterministic state regression'

Require-Contains $soak 'RouteProbeScript.new()' 'Long soak must reuse the production route contract'
Require-Contains $soak '"schema_version": 2' 'Long soak must advertise the no-transport schema'
Require-Contains $soak '"post_spawn_transport": false' 'Every soak cycle must record its transport boundary'
Require-NotContains $soak 'player.global_position =' 'Long soak cannot simulate pressure by teleporting the player'
Require-Contains $soakDriver 'Invoke-Godot.ps1' 'Long-soak runner must own fresh-checkout project import'
Require-Contains $soakDriver '--editor --quit' 'Long-soak runner must complete a strict import before execution'
Require-Contains $soak 'minimum-cycles' 'Long soak must enforce a minimum route-cycle contract'
Require-Contains $soak 'required_profile_count' 'Long soak must require every configured profile when enough cycles are requested'
Require-Contains $soakDriver '[int]$MinimumCycles = 5' 'Hosted soak driver must default to five profile cycles'
Require-Contains $godotInvoker '[string]$WorkingDirectory' 'Godot process wrapper must support an explicit project working directory'

Require-Contains $smokeDriver '[switch]$SkipExport' 'Release driver must reuse one verified binary across profiles'
Require-Contains $smokeDriver '--smoke-route-probe' 'Release driver must invoke exported production routes'
Require-Contains $smokeDriver 'player_transform_writes' 'Release driver must reject hidden coordinate mutation'
Require-Contains $matrixDriver "'star_continent'" 'Export matrix must include star_continent'
Require-Contains $matrixDriver "'desert_ruins'" 'Export matrix must include desert_ruins'
Require-Contains $matrixDriver "'frozen_wastes'" 'Export matrix must include frozen_wastes'
Require-Contains $matrixDriver "'sky_islands'" 'Export matrix must include sky_islands'
Require-Contains $matrixDriver "'abyss_world'" 'Export matrix must include abyss_world'
Require-Contains $matrixDriver 'hosted_ci_reference' 'Hosted evidence must be labelled as a reference, not target hardware'
Require-Contains $matrixDriver 'all_tutorial_overlays_hidden' 'Five-profile matrix must reject tutorial-obscured screenshots'

try {
    $policy = $policyText | ConvertFrom-Json
    if ([int]$policy.schema_version -ne 1) { $failures.Add('Qualification policy schema_version must be 1') }
    foreach ($tier in @('minimum', 'recommended')) {
        $entry = $policy.tiers.$tier
        if ($null -eq $entry) { $failures.Add("Qualification policy missing tier: $tier"); continue }
        if ([int]$entry.memory_gib_min -lt 16) { $failures.Add("$tier tier must require at least 16 GiB") }
        if ([double]$entry.metrics.avg_fps_min -le 0) { $failures.Add("$tier tier avg FPS threshold must be positive") }
        if ([double]$entry.metrics.one_percent_low_fps_min -le 0) { $failures.Add("$tier tier 1% low threshold must be positive") }
    }
    if ([int]$policy.soak.duration_seconds_min -ne 7200) { $failures.Add('Strict target-hardware soak must remain 7200 seconds') }
} catch {
    $failures.Add("Qualification policy is invalid JSON: $($_.Exception.Message)")
}
Require-Contains $hardwareDriver "[switch]`$HostedReference" 'Hardware script must distinguish CI mechanism checks from real qualification'
Require-Contains $hardwareDriver 'duration_seconds_min' 'Hardware script must enforce the policy soak duration'
Require-Contains $hardwareDriver '-Operator is required' 'Real qualification must identify its operator'
Require-Contains $hardwareDriver 'target_hardware_candidate' 'Automation may produce a candidate package, not silently approve release'

Require-Contains $tutorial 'mid-tutorial progress joins the authoritative save' 'Tutorial must persist an interrupted real-input journey'
Require-Contains $tutorial 'interrupted tutorial completes a full production reload' 'Tutorial must resume after menu re-entry'
Require-Contains $tutorial 'completed tutorial completes a second full production reload' 'Tutorial completion must survive a separate reload boundary'
Require-Contains $tutorial 'completed reload does not replay tutorial completion feedback' 'Tutorial events must remain idempotent'

Require-Contains $building '_right_click_center()' 'Building success and failure must use real right-click input'
Require-Contains $building '_hold_left_until_removed' 'Mining success must use hold-to-mine production input'
Require-Contains $building 'inventory_full' 'Mining must prove full-inventory atomic failure'
Require-Contains $building 'building and mining world completes a full production reload' 'Building/mining must cross a complete menu reload'
Require-Contains $building 'reload cannot resurrect the mined voxel' 'Mining persistence must prevent resurrection'

Require-Contains $workflow 'permissions:' 'Permanent workflow must declare permissions'
Require-Contains $workflow 'contents: read' 'Permanent workflow must be read-only'
Require-Contains $workflow 'run_windows_export_journey_matrix.ps1' 'Permanent workflow must run the five-profile final executable'
Require-Contains $workflow 'run_long_soak.ps1' 'Permanent workflow must exercise the no-transport soak mechanism'
Require-Contains $workflow 'release_smoke_runtime_health_scope_regression.gd' 'Permanent workflow must guard runtime-versus-operations health scope'
Require-Contains $workflow 'release_smoke_evidence_state_regression.gd' 'Permanent workflow must guard tutorial-free map evidence'
Require-Contains $workflow 'sky_islands_cautious_descent_regression.gd' 'Permanent workflow must retain the exact sky-island descent regression'
Require-Contains $workflow '-MinimumCycles 5' 'Permanent hosted soak must cover all five profiles'
Require-Contains $workflow 'tutorial_placement_desktop_acceptance.gd' 'Permanent workflow must run the cross-session tutorial'
Require-Contains $workflow 'building_mining_closed_loop_desktop_acceptance.gd' 'Permanent workflow must run building/mining closure'
Require-NotContains $workflow 'contents: write' 'Permanent release-readiness workflow cannot write repository contents'

Require-Contains $report '状态：**HOLD' 'Commercial release must remain HOLD until external sign-off exists'
Require-Contains $report 'BUG-QA-COVERAGE-001 — qa-passed' 'PR #100 route evidence must close the stale coverage blocker accurately'
Require-Contains $report 'BUG-QA-CONTENT-001 — qa-passed' 'Completed content journeys must close the stale content blocker accurately'
Require-Contains $report 'BUG-QA-VISUAL-EVIDENCE-001' 'Release report must track tutorial-free final screenshots'
Require-Contains $report 'BUG-QA-SOAK-PROFILE-COVERAGE-001' 'Release report must track five-profile hosted soak coverage'
Require-Contains $report 'BUG-QA-SKY-DESCENT-001' 'Release report must track the sky-island descent edge regression'
Require-Contains $report 'BUG-QA-E4-SIGNOFF-001' 'Independent final-export experience sign-off must remain explicit'
Require-Contains $report 'BUG-PERF-002' 'Target-hardware performance remains a release boundary'
Require-Contains $report 'BUG-SOAK-120-001' 'Strict target-hardware soak remains a release boundary'
Require-Contains $contentMatrix '教程 | **E3 闭环**' 'Content matrix must include the cross-session tutorial closure'
Require-Contains $contentMatrix '建造/采矿 | **E3 闭环**' 'Content matrix must include the building/mining closure'
Require-Contains $mapMatrix '连续正常路线 | **E3 通过**' 'Map matrix must record the PR #100 route result'
Require-Contains $mapMatrix '不等于“完整探索”' 'Map matrix must retain the infinite-world evidence boundary'

if (Test-Path -LiteralPath (Join-Path $repoRoot '.github\workflows\temporary-repository-snapshot.yml')) {
    $failures.Add('Temporary repository snapshot workflow must be removed before final validation')
}

if ($failures.Count -gt 0) {
    Write-Host 'RELEASE READINESS CLOSURE CONTRACT FAIL'
    foreach ($failure in $failures) { Write-Host "  - $failure" }
    exit 1
}

Write-Host 'RELEASE READINESS CLOSURE CONTRACT PASS'
Write-Host '  - fresh-checkout soak imports resources before running'
Write-Host '  - final executable runtime health excludes unrelated operations saturation without weakening peak checks'
Write-Host '  - sky-island one-block descents use bounded production-input braking'
Write-Host '  - final executable route evidence uses production input and no transport'
Write-Host '  - tutorial and building/mining cross full save/menu/reload boundaries'
Write-Host '  - hosted CI and target-hardware qualification evidence remain separated'
Write-Host '  - stale coverage/content blockers are reconciled without claiming commercial release'
exit 0
