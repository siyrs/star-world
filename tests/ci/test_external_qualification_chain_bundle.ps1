$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixtureRoot = Join-Path $root 'build\external-qualification-assembler-fixture'
$bundleRoot = Join-Path $root 'build\release-candidate-chain-fixture'
$assemblerTest = Join-Path $PSScriptRoot 'test_external_qualification_package_assembler.ps1'
& $assemblerTest

$exe = Join-Path $fixtureRoot 'StarWorld.exe'
$pck = Join-Path $fixtureRoot 'StarWorld.pck'
$packagePath = Join-Path $fixtureRoot 'qualification-package.json'
$candidatePath = Join-Path $fixtureRoot 'release-candidate.json'
$reviewPath = Join-Path $fixtureRoot 'review.json'
$minimumPath = Join-Path $fixtureRoot 'hardware-minimum.json'
$recommendedPath = Join-Path $fixtureRoot 'hardware-recommended.json'
$soakPath = Join-Path $fixtureRoot 'strict-soak.json'
$hddPath = Join-Path $fixtureRoot 'fault-hdd.json'
$antivirusPath = Join-Path $fixtureRoot 'fault-antivirus.json'
$powerLossPath = Join-Path $fixtureRoot 'fault-power-loss.json'
$commit = 'a' * 40

& (Join-Path $PSScriptRoot 'new_release_candidate_manifest.ps1') `
    -ProjectRoot $root `
    -CommitSha $commit `
    -Version 'fixture-version' `
    -ReleaseExecutable $exe `
    -ReleasePck $pck `
    -OutputPath $candidatePath

function New-TestBundle {
    Remove-Item -LiteralPath $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'new_external_qualification_chain_bundle.ps1') `
        -ProjectRoot $root `
        -CandidateManifestPath $candidatePath `
        -QualificationPackagePath $packagePath `
        -ReleaseExecutable $exe `
        -ReleasePck $pck `
        -ExperienceReviewPath $reviewPath `
        -MinimumHardwarePath $minimumPath `
        -RecommendedHardwarePath $recommendedPath `
        -StrictSoakPath $soakPath `
        -HddFaultPath $hddPath `
        -AntivirusFaultPath $antivirusPath `
        -PowerLossFaultPath $powerLossPath `
        -OutputDirectory $bundleRoot
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

New-TestBundle
$resultText = (& (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-String).Trim()
$result = $resultText | ConvertFrom-Json
if (-not [bool]$result.valid -or [int]$result.file_count -ne 11) { throw 'Fresh qualification chain bundle did not validate.' }
if ([bool]$result.release_gate_passed) { throw 'Reference chain bundle incorrectly closed the release gate.' }

Add-Content -LiteralPath (Join-Path $bundleRoot 'evidence\hardware-minimum.json') -Value 'tampered'
Assert-Rejected -Name 'Evidence tamper' -Expected 'Bundle file hash mismatch' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
$candidateCopyPath = Join-Path $bundleRoot 'release-candidate.json'
$candidate = Get-Content -LiteralPath $candidateCopyPath -Raw | ConvertFrom-Json -Depth 30
$candidate.candidate_id = 'f' * 64
$candidate | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $candidateCopyPath -Encoding utf8
$manifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 30
$candidateEntry = @($manifest.files | Where-Object { [string]$_.path -eq 'release-candidate.json' })[0]
$candidateEntry.sha256 = (Get-FileHash -LiteralPath $candidateCopyPath -Algorithm SHA256).Hash.ToLowerInvariant()
$candidateEntry.length_bytes = (Get-Item -LiteralPath $candidateCopyPath).Length
$manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Assert-Rejected -Name 'Candidate identity tamper' -Expected 'candidate_id does not match' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
Set-Content -LiteralPath (Join-Path $bundleRoot 'unexpected.txt') -Value 'not part of the evidence chain' -Encoding utf8
Assert-Rejected -Name 'Unexpected file injection' -Expected 'missing or unexpected files' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'bundle-manifest.json') -Raw | ConvertFrom-Json -Depth 30
$manifest.files[0].path = '../escape.json'
$manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $bundleRoot 'bundle-manifest.json') -Encoding utf8
Assert-Rejected -Name 'Bundle path traversal' -Expected 'Unsafe bundle path' -Action {
    & (Join-Path $PSScriptRoot 'validate_external_qualification_chain_bundle.ps1') -ProjectRoot $root -BundleDirectory $bundleRoot | Out-Null
}

New-TestBundle
Write-Host "RELEASE CANDIDATE CHAIN BUNDLE PASS | candidate=$($result.candidate_id) | bundle=$($result.bundle_id) | tamper_cases=4 | output=$bundleRoot"
