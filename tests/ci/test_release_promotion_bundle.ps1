$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$chainRoot = Join-Path $root 'build\release-candidate-chain-fixture'
$pinSourceRoot = Join-Path $root 'build\release-promotion-pin-fixture'
$pinPath = Join-Path $pinSourceRoot 'promotion-pin.json'
$promotionRoot = Join-Path $root 'build\release-promotion-bundle-fixture'
$receiptRoot = Join-Path $root 'build\release-promotion-receipts'
$receiptPath = Join-Path $receiptRoot 'receiver-a.json'

& (Join-Path $PSScriptRoot 'test_external_qualification_chain_bundle.ps1')
Remove-Item -LiteralPath $pinSourceRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $pinSourceRoot | Out-Null
& (Join-Path $PSScriptRoot 'new_release_promotion_pin.ps1') `
    -ProjectRoot $root `
    -ChainBundleDirectory $chainRoot `
    -ReleaseOwnerId 'fixture-release-owner' `
    -ReleaseChannel 'commercial-fixture' `
    -OutputPath $pinPath
$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -Depth 30
$expectedPinId = [string]$pin.pin_id

function Write-Json {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function New-TestPromotionBundle {
    Remove-Item -LiteralPath $promotionRoot -Recurse -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'new_release_promotion_bundle.ps1') `
        -ProjectRoot $root `
        -ChainBundleDirectory $chainRoot `
        -PromotionPinPath $pinPath `
        -OutputDirectory $promotionRoot
}
function Assert-Rejected {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Expected, [Parameter(Mandatory = $true)][string]$Name)
    $rejected = $false
    try { & $Action } catch {
        $rejected = $_.Exception.Message.Contains($Expected)
        if (-not $rejected) { throw "$Name failed for the wrong reason: $($_.Exception.Message)" }
    }
    if (-not $rejected) { throw "$Name was not rejected." }
}

New-TestPromotionBundle
$resultText = (& (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-String).Trim()
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.valid -or -not [bool]$result.offline_contract_validation -or -not [bool]$result.identity_pinned) { throw 'Fresh promotion bundle did not validate with the external pin.' }
if ([int]$result.file_count -ne 24) { throw "Promotion bundle payload count drifted: $($result.file_count)" }
if ([bool]$result.release_gate_passed) { throw 'Reference promotion bundle incorrectly closed the release gate.' }
Remove-Item -LiteralPath $receiptRoot -Recurse -Force -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot 'new_release_promotion_receipt.ps1') `
    -PromotionBundleDirectory $promotionRoot `
    -ExpectedPinId $expectedPinId `
    -ReceiverId 'fixture-receiver-a' `
    -OutputPath $receiptPath
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 30
if ([string]$receipt.result -ne 'pass' -or [string]$receipt.pin_id -ne $expectedPinId -or -not [bool]$receipt.offline_contract_validation) { throw 'Promotion receipt did not retain validated identity.' }

New-TestPromotionBundle
Add-Content -LiteralPath (Join-Path $promotionRoot 'contracts\project.godot') -Value '# tampered contract snapshot'
Assert-Rejected -Name 'Contract snapshot tamper' -Expected 'Promotion file hash mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
Add-Content -LiteralPath (Join-Path $promotionRoot 'candidate-chain\evidence\hardware-minimum.json') -Value 'tampered nested evidence'
Assert-Rejected -Name 'Nested chain tamper' -Expected 'Promotion file hash mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
Assert-Rejected -Name 'Wrong expected promotion pin' -Expected 'Expected promotion pin mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId ('f' * 64) | Out-Null
}

New-TestPromotionBundle
Set-Content -LiteralPath (Join-Path $promotionRoot 'unexpected.txt') -Value 'unexpected promotion payload' -Encoding utf8
Assert-Rejected -Name 'Visible promotion file injection' -Expected 'missing or unexpected physical files' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
$hiddenPath = Join-Path $promotionRoot 'hidden-unexpected.txt'
Set-Content -LiteralPath $hiddenPath -Value 'hidden promotion payload' -Encoding utf8
$item = Get-Item -LiteralPath $hiddenPath
$item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
Assert-Rejected -Name 'Hidden promotion file injection' -Expected 'missing or unexpected physical files' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
$manifestPath = Join-Path $promotionRoot 'promotion-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
$manifest.files[0].path = '../escape.json'
Write-Json $manifestPath $manifest
Assert-Rejected -Name 'Promotion path traversal' -Expected 'Unsafe promotion path' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
$manifest = Get-Content -LiteralPath (Join-Path $promotionRoot 'promotion-manifest.json') -Raw | ConvertFrom-Json -Depth 100
$manifest.promotion_id = 'f' * 64
Write-Json (Join-Path $promotionRoot 'promotion-manifest.json') $manifest
Assert-Rejected -Name 'Promotion identity tamper' -Expected 'promotion_id mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_release_promotion_bundle.ps1') -PromotionBundleDirectory $promotionRoot -ExpectedPinId $expectedPinId | Out-Null
}

New-TestPromotionBundle
Assert-Rejected -Name 'Receipt mutation inside immutable bundle' -Expected 'outside the immutable promotion bundle' -Action {
    & (Join-Path $PSScriptRoot 'new_release_promotion_receipt.ps1') `
        -PromotionBundleDirectory $promotionRoot `
        -ExpectedPinId $expectedPinId `
        -ReceiverId 'bad-receiver' `
        -OutputPath (Join-Path $promotionRoot 'receipt.json')
}

New-TestPromotionBundle
Write-Host "RELEASE PROMOTION BUNDLE PASS | promotion=$($result.promotion_id) | pin=$expectedPinId | files=24 | negative_cases=8 | receipt=$receiptPath"
