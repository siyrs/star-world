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
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not $Content.Contains($Needle)) {
        $script:failures.Add("$Description (missing: $Needle)")
    }
}

function Require-NotContains {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if ($Content.Contains($Needle)) {
        $script:failures.Add("$Description (forbidden: $Needle)")
    }
}

$cache = Read-RepoFile 'src/world/world_generator_column_cache.gd'
$generator = Read-RepoFile 'src/world/world_generator.gd'
$world = Read-RepoFile 'src/world/voxel_world.gd'
$metrics = Read-RepoFile 'src/core/frame_performance_metrics.gd'
$capture = Read-RepoFile 'tests/qa/performance_scenario_capture.gd'
$cacheRegression = Read-RepoFile 'tests/qa/world_generator_column_cache_regression.gd'
$metricRegression = Read-RepoFile 'tests/qa/frame_performance_metrics_regression.gd'
$workflow = Read-RepoFile '.github/workflows/generator-column-cache-performance-tests.yml'
$performanceDriver = Read-RepoFile 'tests/ci/run_performance_capture.ps1'
$performanceDoc = Read-RepoFile 'qa/performance-baseline.md'

Require-Contains $cache 'DEFAULT_CAPACITY := 8192' 'Column cache must retain an explicit production capacity'
Require-Contains $cache 'MAX_CAPACITY := 32768' 'Column cache capacity must retain a hard maximum'
Require-Contains $cache 'ORDER_COMPACTION_THRESHOLD := 2048' 'FIFO bookkeeping must compact instead of growing forever'
Require-Contains $cache 'while _entries.size() >= capacity' 'Value storage must enforce capacity before insertion'
Require-Contains $cache '_compact_order_if_needed' 'FIFO bookkeeping must have bounded compaction'
Require-Contains $cache '"entry_count"' 'Runtime cache telemetry must expose retained entries'
Require-Contains $cache '"eviction_count"' 'Runtime cache telemetry must expose evictions'
Require-NotContains $cache 'Dictionary[Vector2i' 'Cache must remain compatible with Godot Dictionary syntax'

Require-Contains $generator 'world_generator_column_cache.gd' 'Production generator must install the bounded column cache'
Require-Contains $generator '_compute_surface_height_uncached' 'Height cache must preserve an explicit deterministic uncached implementation'
Require-Contains $generator '_compute_sky_island_strength_uncached' 'Sky cache must preserve an explicit deterministic uncached implementation'
Require-Contains $generator '_surface_height_evaluation_count' 'Height optimization must have observable evaluation telemetry'
Require-Contains $generator '_sky_strength_evaluation_count' 'Sky-island optimization must have observable evaluation telemetry'
Require-Contains $generator 'get_column_cache_stats' 'Generator must expose bounded cache telemetry'
Require-Contains $generator 'set_column_cache_enabled_for_test' 'Regression must compare cached and uncached output in one revision'
Require-Contains $generator '_column_cache.clear(true)' 'Profile/seed configuration must invalidate cached facts'
Require-Contains $world 'generator_column_cache' 'Streaming diagnostics must include generator cache telemetry'

Require-Contains $metrics '_slow_tail_fps' 'One-percent low must use the slowest frame-time tail'
Require-Contains $metrics 'engine_fps_avg_diagnostic' 'Rolling engine FPS must be labelled diagnostic'
Require-Contains $metrics 'frame_budget_miss_60fps_percent' 'Metrics must expose sixty-FPS budget misses'
Require-Contains $metrics 'frame_budget_miss_30fps_percent' 'Metrics must expose thirty-FPS budget misses'
Require-Contains $capture 'FramePerformanceMetricsScript.summarize' 'Scenario capture must use the authoritative frame-time metrics helper'
Require-Contains $capture '"schema_version": 2' 'Performance reports must advertise the corrected metric schema'
Require-Contains $capture 'engine_fps_avg_diagnostic' 'Capture output must retain rolling FPS only as a diagnostic'
Require-Contains $capture 'diagnostics.call("sample_now")' 'Every scenario boundary must own a fresh telemetry sample'
Require-Contains $capture 'generator_column_cache' 'Desktop performance report must retain live cache telemetry'
Require-NotContains $capture '_percentile(fps, 1.0)' 'Rolling FPS percentile must never be labelled one-percent low'
Require-NotContains $capture '"one_percent_low_fps": _percentile(fps' 'Old misleading one-percent low implementation must remain removed'

Require-Contains $cacheRegression 'cached_blocks == uncached_blocks' 'Regression must prove generated block equivalence'
Require-Contains $cacheRegression 'cached_sky_evaluations * 32 <= uncached_sky_evaluations' 'Regression must prove at least thirty-two-fold sky evaluation reduction'
Require-Contains $cacheRegression 'entry count never exceeds the hard bound' 'Regression must exercise capacity eviction'
Require-Contains $cacheRegression 'MAX_HOT_PATH_COLUMN_FOOTPRINT' 'Regression must bound tree-neighbour column probes without assuming exact direct-column count'
Require-Contains $metricRegression 'one-percent low uses the slowest one-percent frame tail' 'Metric regression must lock the corrected definition'
Require-Contains $metricRegression 'rolling engine FPS cannot overwrite real average FPS' 'Metric regression must keep diagnostic FPS separate'

Require-Contains $workflow 'world_generator_column_cache_regression.gd' 'Dedicated cache regression must run in GitHub Actions'
Require-Contains $workflow 'frame_performance_metrics_regression.gd' 'Corrected frame metrics must run in GitHub Actions'
Require-Contains $workflow 'validate_generator_column_cache.ps1' 'Architecture validator must run in GitHub Actions'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Quality gate must reuse the authoritative Godot runner'
Require-Contains $workflow 'pull_request:' 'Quality gate must run automatically for relevant pull requests'
Require-Contains $workflow 'performance-capture:' 'Quality gate must run a real desktop performance journey'
Require-Contains $workflow 'run_performance_capture.ps1' 'Desktop benchmark must use the external-memory driver'
Require-Contains $workflow 'Expected performance schema 2' 'Desktop benchmark must validate the corrected report schema'
Require-Contains $workflow 'generator_column_cache' 'Desktop benchmark must validate production cache telemetry'
Require-Contains $performanceDriver 'working_set_bytes' 'Desktop benchmark must retain external Working Set samples'
Require-Contains $performanceDriver 'private_bytes' 'Desktop benchmark must retain external Private Bytes samples'

$workflowDirectory = Join-Path $repoRoot '.github\workflows'
$temporaryWorkflows = @(
    Get-ChildItem -LiteralPath $workflowDirectory -File -ErrorAction Stop |
        Where-Object { $_.Name -like 'temporary-generator-cache*' }
)
if ($temporaryWorkflows.Count -gt 0) {
    $names = ($temporaryWorkflows | ForEach-Object { $_.Name }) -join ', '
    $failures.Add("Temporary self-modifying generator workflows must not ship: $names")
}

Require-Contains $performanceDoc '旧版 `1% Low FPS` 已废弃' 'Performance baseline must explicitly deprecate the old rolling-FPS metric'
Require-Contains $performanceDoc 'BUG-PERF-METRIC-001' 'Performance measurement defect must remain auditable'
Require-Contains $performanceDoc 'BUG-PERF-COLUMN-001' 'Generator repeated-column hotspot must remain auditable'

if ($failures.Count -gt 0) {
    Write-Host 'GENERATOR COLUMN CACHE / PERFORMANCE METRIC CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'GENERATOR COLUMN CACHE / PERFORMANCE METRIC CONTRACT PASS'
Write-Host '  - repeated X/Z generator facts use bounded deterministic storage'
Write-Host '  - cache output is compared against uncached generation'
Write-Host '  - cache values and FIFO bookkeeping both have hard bounds'
Write-Host '  - one-percent low and average FPS derive from real frame times'
Write-Host '  - rolling engine FPS remains diagnostic only'
Write-Host '  - desktop five-profile capture validates schema and cache telemetry'
Write-Host '  - no temporary self-modifying workflow remains'
exit 0
