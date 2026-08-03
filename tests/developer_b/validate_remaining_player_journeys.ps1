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

$product = Read-RepoFile 'src/husbandry/reliable_animal_product_service.gd'
$ranchRuntime = Read-RepoFile 'src/husbandry/ranch_runtime_participant.gd'
$ranchRegression = Read-RepoFile 'tests/qa/ranch_product_conservation_regression.gd'
$workflow = Read-RepoFile '.github/workflows/remaining-player-journeys-tests.yml'

Require-Contains $product 'class_name ReliableAnimalProductService' 'Production must expose the reliable product service'
Require-Contains $product 'record["pending_count"] = maxi(' 'Collection must commit the authoritative pending count'
Require-Contains $product 'if not _restoring_pickups:' 'Reloaded pickups must not replay new-product feedback'
Require-Contains $product 'var missing_count := maxi(0, pending - current_count)' 'Active pickups must merge only unmaterialized pending products'
Require-NotContains $product 'record["pending_count"] = 0' 'Pickup materialization must not erase pending product state'
Require-Contains $ranchRuntime 'reliable_animal_product_service.gd' 'Production ranch composition must install reliable persistence'
Require-Contains $ranchRegression 'zero-acceptance collection leaves authoritative product state untouched' 'Domain evidence must cover full-inventory-style zero acceptance'
Require-Contains $ranchRegression 'restoring an existing product does not replay production feedback' 'Domain evidence must cover reload event suppression'
Require-Contains $workflow 'ranch_product_conservation_regression.gd' 'Permanent CI must run product conservation'
Require-Contains $workflow 'permissions:' 'Remaining journey workflow must declare permissions'
Require-Contains $workflow 'contents: read' 'Remaining journey workflow must remain read-only'
Require-Contains $workflow 'pull_request:' 'Remaining journey workflow must run on pull requests'
Require-Contains $workflow 'push:' 'Remaining journey workflow must rerun after merge to master'
Require-Contains $workflow 'cancel-in-progress: true' 'Remaining journey workflow must cancel stale runs'

if ($failures.Count -gt 0) {
    Write-Host 'REMAINING PLAYER JOURNEYS CONTRACT FAIL'
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'REMAINING PLAYER JOURNEYS CONTRACT PASS'
Write-Host '  - ranch products remain authoritative until accepted collection'
Write-Host '  - zero-acceptance, reload and offline materialization are covered'
Write-Host '  - production composition and permanent read-only CI are wired'
exit 0
