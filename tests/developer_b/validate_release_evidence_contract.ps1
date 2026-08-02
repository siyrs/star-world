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

$traversal = Read-RepoFile 'tests/qa/player_driven_regional_traversal_regression.gd'
$workflow = Read-RepoFile '.github/workflows/release-evidence-contract-tests.yml'
$report = Read-RepoFile 'qa/final-release-report.md'
$matrix = Read-RepoFile 'qa/map-coverage-matrix.md'

Require-Contains $traversal 'Input.action_press(action)' 'Regional traversal must use production input actions'
Require-Contains $traversal 'force_load_chunk' 'Regional traversal must own live collision before movement'
Require-Contains $traversal 'MIN_REGIONS_PER_PROFILE := 6' 'Every profile must retain a six-region minimum'
Require-Contains $traversal 'visited_chunks.size() >= MIN_REGIONS_PER_PROFILE' 'Traversal must prove unique spatial coverage'
Require-Contains $traversal 'CharacterBody3D' 'Traversal must exercise the production physics body'
Require-NotContains $traversal 'force_decision_for_test' 'Player traversal must not substitute a forced domain decision for play'
Require-NotContains $traversal 'complete exploration' 'A regional gate must not claim complete exploration'

Require-Contains $workflow 'player_driven_regional_traversal_regression.gd' 'The regional traversal gate must be wired into GitHub Actions'
Require-Contains $workflow 'validate_release_evidence_contract.ps1' 'The evidence validator must validate itself through CI'
Require-Contains $workflow 'pull_request:' 'The evidence gate must run automatically for relevant pull requests'
Require-Contains $workflow 'reusable-godot-quality-gate.yml' 'The gate must reuse the authoritative Godot runner'

Require-Contains $report '状态：**HOLD' 'The authoritative release report must not claim RELEASE while evidence blockers remain'
Require-Contains $report 'BUG-QA-COVERAGE-001' 'The release report must retain the map-coverage blocker'
Require-Contains $report 'BUG-QA-CONTENT-001' 'The release report must retain the end-to-end content blocker'
Require-Contains $report 'BUG-QA-VISUAL-001' 'The release report must retain the final-export visual blocker'
Require-Contains $report 'BUG-PERF-002' 'The release report must retain the commercial performance blocker'
Require-Contains $report 'E0' 'The release report must define evidence levels'
Require-Contains $report 'E4' 'The release report must define final-export evidence'
Require-NotContains $report '推荐发布（RELEASE）' 'The report must not retain the superseded release recommendation'

Require-Contains $matrix 'E3 玩家区域穿行' 'The map matrix must distinguish player-driven regional evidence'
Require-Contains $matrix '不等于“完整探索”' 'The map matrix must prohibit cross-level evidence claims'
Require-Contains $matrix '| **否** | HOLD |' 'Every currently incomplete map must remain explicitly on hold'
Require-Contains $matrix '内容覆盖纠偏' 'The matrix must separate domain contracts from player journeys'
Require-NotContains $matrix '| ✓ 验收旅程' 'The old generator/service journey must not remain labelled complete exploration'

if ($failures.Count -gt 0) {
    Write-Host 'RELEASE EVIDENCE CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'RELEASE EVIDENCE CONTRACT PASS'
Write-Host '  - five-profile player-driven regional traversal is present'
Write-Host '  - CI wiring is present'
Write-Host '  - release and map reports use E0-E4 evidence levels'
Write-Host '  - unsupported COMPLETE/RELEASE claims are blocked'
exit 0
