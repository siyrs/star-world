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

$policy = Read-RepoFile 'src/entity/hostile_cover_counter_policy.gd'
$service = Read-RepoFile 'src/entity/hostile_cover_counter_service.gd'
$brute = Read-RepoFile 'src/entity/cover_aware_abyss_brute.gd'
$marksman = Read-RepoFile 'src/entity/cover_aware_abyss_marksman.gd'
$factory = Read-RepoFile 'src/entity/creature_factory.gd'
$hubScene = Read-RepoFile 'scenes/ui/service_hub.tscn'
$regression = Read-RepoFile 'tests/qa/hostile_cover_counter_v2_regression.gd'
$workflow = Read-RepoFile '.github/workflows/bounded-hostile-cover-counter-v2-tests.yml'

Require-Contains $policy 'MAX_LINE_SAMPLE_STEPS := 64' 'Line-of-sight work must retain a hard cap'
Require-Contains $policy 'MAX_BREAK_BLOCKS_PER_ATTACK := 2' 'Per-attack destruction must retain a hard cap'
Require-Contains $policy 'MAX_BREAK_BLOCKS_PER_BRUTE := 12' 'Per-brute destruction must retain a lifetime cap'
Require-Contains $policy 'MAX_REPOSITION_PROBES := 6' 'Marksman search must retain a probe cap'
Require-Contains $policy 'MAX_REPOSITION_ATTEMPTS_PER_TARGET := 4' 'Marksman search must retain a per-target attempt cap'
Require-Contains $policy 'const WALK_HAZARD_IDS' 'Projectile and movement semantics must remain separated'
Require-Contains $policy '"water"' 'Water must remain an explicit walking hazard'
Require-Contains $policy '"lava"' 'Lava must remain an explicit walking hazard'
Require-Contains $policy 'BlockRegistryScript.is_solid' 'Cover collision must reuse the authoritative block registry'
Require-NotContains $policy '"stone",' 'Permanent stone must never enter the breakable cover allowlist'
Require-NotContains $policy '"planks",' 'Permanent planks must never enter the breakable cover allowlist'

Require-Contains $service '"blocks_damage": true' 'Every blocked cover result must explicitly prevent same-frame damage'
Require-Contains $service '"brute_break_budget_exhausted"' 'Budget exhaustion must remain a first-class result'
Require-Contains $service '"mutation_failed"' 'World mutation failure must remain a first-class result'
Require-Contains $service '_is_player_override' 'Generated terrain must not be mistaken for player temporary cover'
Require-Contains $service '_ground_route_safe' 'Marksman repositioning must validate its whole route'
Require-Contains $service '_column_has_walk_hazard' 'Unsafe columns must have explicit production telemetry'
Require-Contains $service '_resolve_local_ground' 'Cave combat must use local ground instead of global top-surface teleporting'
Require-Contains $service 'MAX_BOUND_CREATURES := 32' 'Runtime hostile bindings must remain bounded'
Require-Contains $service 'MAX_ROUTE_GROUND_SAMPLES := 12' 'Ground-route work must remain bounded'
Require-Contains $service 'PolicyScript.blocks_walk_lane' 'Reposition lanes must use hazard-aware movement semantics'
Require-NotContains $service 'resolve_ground_position' 'Cover counter must not jump marksmen to the highest global terrain surface'

Require-Contains $brute 'bool(result.get("blocks_damage", false))' 'Production brute must consume attacks blocked by cover'
Require-Contains $brute 'super._commit_attack()' 'Clear lanes must preserve the existing production melee attack'
Require-Contains $marksman 'find_marksman_reposition_destination' 'Cover-aware marksman must request a bounded safe destination'
Require-Contains $marksman '_cover_destination_active = true' 'Marksman must move through the existing destination contract'
Require-NotContains $marksman 'global_position = destination' 'Marksman may not teleport to a firing lane'

Require-Contains $factory 'cover_aware_abyss_brute.gd' 'Factory must compose cover-aware brute in production'
Require-Contains $factory 'cover_aware_abyss_marksman.gd' 'Factory must compose cover-aware marksman in production'
Require-Contains $hubScene 'HostileCoverCounterService' 'Production service hub must install the cover counter'

Require-Contains $regression 'production brute cannot damage through permanent wall' 'Regression must verify actual player damage, not only wall state'
Require-Contains $regression 'production brute cannot damage through cover after lifetime budget exhaustion' 'Regression must lock the historical budget bypass'
Require-Contains $regression 'production brute cannot damage through cover when mutation fails' 'Regression must lock the historical mutation bypass'
Require-Contains $regression 'scan never destroys temporary cover behind permanent wall' 'Regression must lock permanent-wall scan ordering'
Require-Contains $regression 'fully hazardous ring yields no unsafe reposition' 'Regression must reject unsafe fallback movement'
Require-Contains $regression 'sixty-minute simulation' 'Regression must exercise long-session budget behavior'

Require-Contains $workflow 'hostile_cover_counter_v2_regression.gd' 'Dedicated regression must run in GitHub Actions'
Require-Contains $workflow 'validate_hostile_cover_counter_v2.ps1' 'Architecture validator must run in GitHub Actions'
Require-Contains $workflow 'pull_request:' 'Quality gate must run automatically for relevant pull requests'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'Quality gate must reuse the authoritative Godot runner'

if ($failures.Count -gt 0) {
    Write-Host 'HOSTILE COVER COUNTER V2 CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'HOSTILE COVER COUNTER V2 CONTRACT PASS'
Write-Host '  - temporary-cover destruction is explicit and bounded'
Write-Host '  - permanent/generated cover blocks same-frame damage'
Write-Host '  - budget and mutation failures cannot fall through to melee'
Write-Host '  - marksman repositioning rejects hazards and teleportation'
Write-Host '  - production composition, regression and CI wiring are present'
exit 0
