$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$workspace = Join-Path $root 'docs\tasks\20260731-v1.3.0-commercial-release-gameplay-polish'
$contractPath = Join-Path $workspace '16-current-status.json'

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "Iteration 65 contract mismatch for ${Name}: expected '$Expected', got '$Actual'" }
}

function Read-WorkspaceFile([string]$RelativePath) {
    $path = Join-Path $workspace $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 65 workspace file missing: $RelativePath" }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $path
}

function Assert-ContainsAll([string]$RelativePath, [string[]]$Tokens) {
    $text = Read-WorkspaceFile $RelativePath
    foreach ($token in $Tokens) {
        if (-not $text.Contains($token)) { throw "Iteration 65 token '$token' missing from $RelativePath" }
    }
}

$requiredRepositoryFiles = @(
    'docs\PRODUCT_ROADMAP_ITERATION_65.md',
    'docs\ARCHITECTURE_AUDIT_2026-08-07_ITERATION_65.md',
    'tests\developer_b\validate_task_workspace_governance_iteration_65.ps1',
    'tests\ci\run_iteration_65_full_regression.ps1',
    '.github\workflows\task-workspace-governance-iteration-65-tests.yml'
)
foreach ($relative in $requiredRepositoryFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 65 file missing: $relative" }
}

if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw 'Iteration 65 canonical status contract is missing.' }
$contract = Get-Content -Raw -Encoding UTF8 -LiteralPath $contractPath | ConvertFrom-Json -Depth 20
Assert-Equal ([int]$contract.schema_version) 1 'schema_version'
Assert-Equal ([string]$contract.task_id) '20260731-v1.3.0-commercial-release-gameplay-polish' 'task_id'
Assert-Equal ([string]$contract.version) 'v1.3.0' 'version'
Assert-Equal ([string]$contract.repository_implementation) 'complete' 'repository_implementation'
Assert-Equal ([string]$contract.repository_qa) 'passed' 'repository_qa'
Assert-Equal ([string]$contract.repository_acceptance) 'accepted' 'repository_acceptance'
Assert-Equal ([string]$contract.repository_delivery) 'delivered' 'repository_delivery'
Assert-Equal ([int]$contract.function_points.planned) 11 'function_points.planned'
Assert-Equal ([int]$contract.function_points.complete) 11 'function_points.complete'
Assert-Equal ([int]$contract.function_points.accepted_repository) 9 'function_points.accepted_repository'
Assert-Equal ([int]$contract.function_points.external_hold) 2 'function_points.external_hold'
Assert-Equal ([int]$contract.open_repository_p0_p1_bugs) 0 'open_repository_p0_p1_bugs'
Assert-Equal ([string]$contract.commercial_release) 'hold' 'commercial_release'
Assert-Equal ([string]$contract.commercial_hold_scope) 'external-qualification-and-production-signing' 'commercial_hold_scope'
if (@($contract.remaining_external_gates).Count -ne 8) { throw 'Iteration 65 external gate inventory must contain exactly eight explicit gates.' }

Assert-ContainsAll '00-index.md' @(
    'Current status: repository-delivered / commercial-hold',
    'Repository function points: 11/11 complete',
    'Open repository P0/P1 bugs: 0',
    'Commercial release: HOLD',
    '16 Current Status Contract'
)
Assert-ContainsAll '05-test-report.md' @(
    'Repository QA decision: passed',
    'Repository P0/P1 blockers: 0',
    'Commercial-release decision: HOLD',
    'Historical snapshot'
)
Assert-ContainsAll '06-bugfix-log.md' @(
    'Remaining repository P0/P1 bugs: 0',
    'Original bugfix loop: closed/superseded by permanent regressions',
    'Historical bugfix evidence'
)
Assert-ContainsAll '07-acceptance-report.md' @(
    'Repository acceptance: accepted',
    'Function points: 11/11 complete',
    'Commercial release: HOLD',
    'External qualification is not fabricated by CI'
)
Assert-ContainsAll '08-delivery-summary.md' @(
    'Repository delivery: delivered',
    'Repository scope: 11/11 function points complete',
    'Commercial release: HOLD',
    'External-only remaining work'
)
Assert-ContainsAll '15-risk-register.md' @(
    'Repository implementation blockers: 0',
    'Commercial release risks remain external',
    'RISK-009',
    'RISK-014'
)

$forbiddenCurrentTokens = @(
    'Current status: in-development',
    '0 commits; 0 complete profile journeys',
    'Remaining open P0/P1 bugs: 7',
    'Open P0/P1 bugs at acceptance: 7',
    'Delivered: no',
    'Accepted: no'
)
foreach ($relative in @('00-index.md', '05-test-report.md', '06-bugfix-log.md', '07-acceptance-report.md', '08-delivery-summary.md')) {
    $text = Read-WorkspaceFile $relative
    foreach ($token in $forbiddenCurrentTokens) {
        if ($text.Contains($token)) { throw "Stale current-state token '$token' remains in $relative" }
    }
}

$statusBoard = Read-WorkspaceFile '09-feature-status-board.md'
for ($i = 1; $i -le 11; $i++) {
    $id = 'FP-{0:D3}' -f $i
    if (-not $statusBoard.Contains("| $id | complete | passed |")) { throw "Feature status board does not prove $id complete and passed." }
}
if (-not $statusBoard.Contains('Commercial release remains **HOLD**')) { throw 'Feature status board lost the commercial HOLD boundary.' }

$readiness = Read-WorkspaceFile '11-readiness-gates.md'
foreach ($token in @(
    'Repository readiness is complete.',
    'Commercial release remains **HOLD**',
    'real certificate pins',
    'physical qualification requirements'
)) {
    if (-not $readiness.Contains($token)) { throw "Readiness gates lost required boundary token '$token'." }
}

$riskText = Read-WorkspaceFile '15-risk-register.md'
foreach ($legacyRisk in 1..8) {
    $id = 'RISK-{0:D3}' -f $legacyRisk
    if (-not $riskText.Contains("| $id |")) { throw "Risk register lost historical risk $id." }
}

$workflow = Get-Content -Raw -Encoding UTF8 (Join-Path $root '.github\workflows\task-workspace-governance-iteration-65-tests.yml')
foreach ($token in @(
    'Validate canonical task workspace state',
    'Run complete repository regression',
    'run_iteration_65_full_regression.ps1',
    'pull_request:',
    'push:'
)) {
    if (-not $workflow.Contains($token)) { throw "Iteration 65 workflow token '$token' is missing." }
}

Write-Host 'ITERATION 65 TASK WORKSPACE GOVERNANCE PASS | canonical-status=true | fp=11/11 | repo-p0-p1=0 | repo-qa=passed | repo-accepted=true | repo-delivered=true | commercial-release=hold | external-gates=8'
